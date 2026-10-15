local M = {}
local states = {}
local enabled = false
local plugin, options, plugin_dir, image
local original_find, wrapped_find
local rendering = {}
local generation = 0
local attached = false
local fences_ns = vim.api.nvim_create_namespace("mmdtoimg.fences")

-- Parse fences without requiring Treesitter, and ignore examples inside other fences.
function M.blocks(lines)
	local blocks, fence, list_indent = {}, nil, nil
	for row, line in ipairs(lines) do
		-- A fence indented as list content belongs to Snacks, not this replacement.
		if not fence then
			local spaces = #(line:match("^ *") or "")
			if list_indent and line:find("%S") and spaces < list_indent then
				list_indent = nil
			end
			local leading, marker = line:match("^( *)([-+*]%s+)")
			if not marker then
				leading, marker = line:match("^( *)(%d+[.)]%s+)")
			end
			if marker then
				list_indent = list_indent or (#leading + #marker)
			end
		end
		local indent, marker, info = line:match("^( *)([`~]+)(.*)$")
		if
			marker
			and not list_indent
			and #indent <= 3
			and #marker >= 3
			and not marker:find("[^" .. marker:sub(1, 1) .. "]")
		then
			if not fence then
				fence = { first = row, marker = marker, mermaid = vim.trim(info) == "mermaid", indent = #indent }
			elseif marker:sub(1, 1) == fence.marker:sub(1, 1) and #marker >= #fence.marker and vim.trim(info) == "" then
				if fence.mermaid then
					local content = {}
					for i = fence.first + 1, row - 1 do
						content[#content + 1] = lines[i]:gsub("^" .. string.rep(" ", fence.indent), "", 1)
					end
					blocks[#blocks + 1] = { first = fence.first, last = row, content = table.concat(content, "\n") }
				end
				fence = nil
			end
		end
	end
	return blocks
end

local function settings()
	return plugin.settings and plugin.settings() or require("mmdtoimg.theme").snapshot(options, plugin_dir)
end

function M.key(content, snapshot)
	return require("mmdtoimg.theme").key(content, snapshot or settings())
end

function M.bounds(buf)
	local width, height = 80, 40
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		local info = vim.fn.getwininfo(win)[1]
		-- Reserve sign/number columns and margins; Snacks fits the PNG proportionally.
		width = math.min(width, info.width - info.textoff - 2)
		height = math.min(height, info.height - 4)
	end
	return math.max(1, width), math.max(1, height)
end

local function clear(buf)
	require("mmdtoimg.scroll").detach(buf)
	local state = states[buf]
	if state then
		for _, placement in ipairs(state.placements) do
			placement:close()
		end
		for win, saved in pairs(state.windows) do
			if vim.api.nvim_win_is_valid(win) then
				if vim.wo[win].conceallevel == saved.applied_level then
					vim.wo[win].conceallevel = saved.level
				end
				if vim.wo[win].concealcursor == saved.applied_cursor then
					vim.wo[win].concealcursor = saved.cursor
				end
			end
		end
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_clear_namespace(buf, fences_ns, 0, -1)
		end
	end
	states[buf] = nil
end

local function editing(buf, blocks)
	local hidden = {}
	local current = vim.api.nvim_get_current_buf() == buf
	local row = current and vim.api.nvim_win_get_cursor(0)[1] or -1
	local mode = vim.api.nvim_get_mode().mode
	for index, block in ipairs(blocks) do
		local policy = options.inline_source_visible
		local reveal
		if type(policy) == "function" then
			reveal = policy(buf, block.first, block.last)
		end
		if reveal == nil then
			reveal = current
				and (mode:sub(1, 1) == "i" or mode:sub(1, 1) == "R")
				and row >= block.first
				and row <= block.last
		end
		if reveal then
			hidden[index] = true
		end
	end
	return hidden
end

function M.visibility(buf)
	local state = states[buf]
	if state and not vim.deep_equal(editing(buf, state.blocks), state.editing) then
		-- Remove placements entirely when editing, including any concealed lines.
		M.update(buf)
	end
end

function M.update(buf)
	if not enabled then
		return
	end
	if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
		return
	end
	if not options.inline_mermaid or not options.snacks or vim.bo[buf].filetype ~= "markdown" then
		clear(buf)
		return
	end
	local wins = vim.fn.win_findbuf(buf)
	if #wins == 0 then
		clear(buf)
		return
	end
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local tick = vim.api.nvim_buf_get_changedtick(buf)
	local previous = states[buf]
	local blocks = previous and previous.tick == tick and previous.blocks or M.blocks(lines)
	local visible_source = editing(buf, blocks)
	local ok, snapshot = pcall(settings)
	if not ok then
		vim.notify("MmdToImg: " .. tostring(snapshot), vim.log.levels.ERROR)
		return
	end
	local width, height = M.bounds(buf)
	local signature = vim.inspect({ tick, wins, width, height, visible_source, vim.o.background, M.key("", snapshot) })
	-- Keep extmarks and virtual rows stable while scrolling or revisiting a buffer.
	if previous and not previous.failed and previous.signature == signature then
		return
	end
	clear(buf)
	local state =
		{ placements = {}, windows = {}, blocks = blocks, editing = visible_source, tick = tick, signature = signature }
	states[buf] = state
	for index, block in ipairs(blocks) do
		if block.last > block.first + 1 then
			local key = M.key(block.content, snapshot)
			local dir = vim.fn.stdpath("cache") .. "/mmdtoimg/inline"
			vim.fn.mkdir(dir, "p")
			local base = dir .. "/" .. key
			local theme = vim.o.background
			local function display(err)
				if err and states[buf] == state then
					state.failed = true
				end
				if err or states[buf] ~= state or not vim.api.nvim_buf_is_valid(buf) or state.editing[index] then
					return
				end
				if tick ~= vim.api.nvim_buf_get_changedtick(buf) or theme ~= vim.o.background then
					return
				end
				require("mmdtoimg.scroll").attach(buf)
				-- Conceal must remain active on the cursor line in normal mode.
				-- Restore the user's window settings when source editing resumes or we detach.
				for _, win in ipairs(vim.fn.win_findbuf(buf)) do
					if not state.windows[win] then
						local level, cursor = vim.wo[win].conceallevel, vim.wo[win].concealcursor
						local applied_level = math.max(2, level)
						local applied_cursor = cursor:find("n", 1, true) and cursor or cursor .. "n"
						state.windows[win] = {
							level = level,
							cursor = cursor,
							applied_level = applied_level,
							applied_cursor = applied_cursor,
						}
						vim.wo[win].conceallevel, vim.wo[win].concealcursor = applied_level, applied_cursor
					end
				end
				for _, row in ipairs({ block.first, block.last }) do
					vim.api.nvim_buf_set_extmark(buf, fences_ns, row - 1, 0, { end_col = #lines[row], conceal = "" })
				end
				local width, height = M.bounds(buf)
				local placement = image.placement.new(buf, base .. "." .. theme .. ".png", {
					pos = { block.first + 1, 0 },
					-- Fence delimiters may have conceal_lines from Markdown highlighting.
					-- Anchor and reserve image rows on visible content instead.
					range = { block.first + 1, 0, block.last - 1, #lines[block.last - 1] },
					inline = true,
					conceal = true,
					type = "chart",
					max_width = width,
					max_height = height,
				})
				state.placements[#state.placements + 1] = placement
			end
			if vim.fn.filereadable(base .. ".light.png") == 1 and vim.fn.filereadable(base .. ".dark.png") == 1 then
				display()
			else
				if vim.fn.filereadable(base .. ".mmd") == 0 then
					vim.fn.writefile(vim.split(block.content, "\n"), base .. ".mmd")
				end
				if rendering[base] then
					rendering[base][#rendering[base] + 1] = display
				else
					rendering[base] = { display }
					plugin.render(base .. ".mmd", function(err)
						local callbacks = rendering[base] or {}
						rendering[base] = nil
						for _, callback in ipairs(callbacks) do
							callback(err)
						end
					end, snapshot)
				end
			end
		end
	end
end

function M.stop()
	enabled = false
	attached = false
	generation = generation + 1
	pcall(vim.api.nvim_del_augroup_by_name, "MmdToImgInline")
	for buf in pairs(states) do
		clear(buf)
	end
	if image and image.doc.find == wrapped_find then
		image.doc.find = original_find
	end
end

local function update()
	generation = generation + 1
	local current = generation
	vim.defer_fn(function()
		if not enabled or current ~= generation then
			return
		end
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			M.update(buf)
		end
	end, 150)
end

local function owns(buf, match)
	if
		not options.inline_mermaid
		or not options.snacks
		or not vim.api.nvim_buf_is_valid(buf)
		or not vim.api.nvim_buf_is_loaded(buf)
		or vim.bo[buf].filetype ~= "markdown"
		or match.lang ~= "mermaid"
		or match.type ~= "chart"
		or not match.range
	then
		return false
	end
	for _, block in ipairs(M.blocks(vim.api.nvim_buf_get_lines(buf, 0, -1, false))) do
		if block.last > block.first + 1 and match.range[1] >= block.first and match.range[3] <= block.last then
			return true
		end
	end
	return false
end

function M.setup(renderer, opts, root, backend)
	if image ~= backend then
		M.stop()
	end
	plugin, options, plugin_dir, image = renderer, opts, root, backend
	if not opts.inline_mermaid or not opts.snacks then
		M.stop()
		return
	end
	enabled = true
	-- Keep Snacks previews for blocks and document types this module cannot handle.
	if image.doc.find ~= wrapped_find then
		original_find = image.doc.find
		local previous = original_find
		wrapped_find = function(buf, callback, find_opts)
			return previous(buf, function(matches)
				callback(vim.tbl_filter(function(match)
					return not owns(buf, match)
				end, matches))
			end, find_opts)
		end
		image.doc.find = wrapped_find
	end
	if attached then
		update()
		return
	end
	attached = true
	local group = vim.api.nvim_create_augroup("MmdToImgInline", { clear = true })
	vim.api.nvim_create_autocmd({
		"BufEnter",
		"BufWinEnter",
		"FileType",
		"TextChanged",
		"TextChangedI",
		"BufWritePost",
		"WinResized",
		"ColorScheme",
	}, { group = group, callback = update })
	vim.api.nvim_create_autocmd("OptionSet", { group = group, pattern = "background", callback = update })
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "ModeChanged" }, {
		group = group,
		callback = function()
			M.visibility(vim.api.nvim_get_current_buf())
		end,
	})
	vim.api.nvim_create_autocmd({ "BufWipeout", "BufWinLeave" }, {
		group = group,
		callback = function(ev)
			clear(ev.buf)
			update()
		end,
	})
	update()
end

return M
