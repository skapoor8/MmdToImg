local M = {}
local guards = {}
local up = string.char(25)

local function above(after, before)
	if after.topline ~= before.topline then
		return after.topline < before.topline
	end
	if after.topfill ~= before.topfill then
		return after.topfill > before.topfill
	end
	return after.skipcol < before.skipcol
end

local function redraw(win)
	-- Validate the view before testing progress; concealed rows can defer correction.
	if vim.api.nvim__redraw then
		vim.api.nvim__redraw({ win = win, valid = false })
	end
	vim.cmd.redraw()
end

-- Neovim #42317: scrolling up across conceal_lines + virt_lines can loop.
-- Retry only a failed step, moving the cursor up so cursor correction cannot
-- push the viewport back down. Ordinary scrolling keeps its native behavior.
function M.up(win, count)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	vim.api.nvim_win_call(win, function()
		for _ = 1, count do
			local before = vim.fn.winsaveview()
			vim.cmd.normal({ up, bang = true })
			redraw(win)
			if not above(vim.fn.winsaveview(), before) then
				if before.topline == 1 then
					vim.fn.winrestview(before)
					break
				end
				local advanced = false
				for distance = 1, vim.api.nvim_win_get_height(win) do
					vim.fn.winrestview(before)
					vim.cmd.normal({ tostring(distance) .. "k", bang = true })
					vim.cmd.normal({ up, bang = true })
					redraw(win)
					if above(vim.fn.winsaveview(), before) then
						advanced = true
						break
					end
				end
				if not advanced then
					vim.fn.winrestview(before)
					break
				end
			end
		end
	end)
end

function M.attach(buf)
	if guards[buf] or vim.fn.has("nvim-0.11.4") == 0 then
		return
	end
	local guard = { scroll = vim.b[buf].snacks_scroll, mappings = {} }
	guards[buf] = guard
	-- Animation replays native CTRL-Y and would bypass the guarded key mappings.
	vim.b[buf].snacks_scroll = false
	for _, key in ipairs({ "<C-y>", "<ScrollWheelUp>" }) do
		local existing = vim.api.nvim_buf_call(buf, function()
			return vim.fn.maparg(key, "n", false, true)
		end)
		-- Keep explicitly configured user mappings intact.
		if vim.tbl_isempty(existing) then
			local callback = function()
				local win, count = vim.api.nvim_get_current_win(), vim.v.count1
				if key == "<ScrollWheelUp>" then
					local mouse = vim.fn.getmousepos()
					if mouse.winid ~= 0 and vim.api.nvim_win_is_valid(mouse.winid) then
						win = mouse.winid
					end
					count = count * (tonumber(vim.o.mousescroll:match("ver:(%d+)")) or 3)
				end
				M.up(win, count)
			end
			guard.mappings[key] = callback
			vim.keymap.set(
				"n",
				key,
				callback,
				{ buffer = buf, desc = "MmdToImg: scroll past concealed image rows", silent = true }
			)
		end
	end
end

function M.detach(buf)
	local guard = guards[buf]
	guards[buf] = nil
	if not guard or not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	if vim.b[buf].snacks_scroll == false then
		vim.b[buf].snacks_scroll = guard.scroll
	end
	for key, callback in pairs(guard.mappings) do
		local current = vim.api.nvim_buf_call(buf, function()
			return vim.fn.maparg(key, "n", false, true)
		end)
		if current.callback == callback then
			vim.keymap.del("n", key, { buffer = buf })
		end
	end
end
return M
