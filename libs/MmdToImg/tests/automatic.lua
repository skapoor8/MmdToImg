-- Exercise the public setup and editor events: no render/update command calls.
local plugin = require("mmdtoimg")
local inline = require("mmdtoimg.inline")
local original_snacks = package.loaded.snacks
local original_render, original_mode, original_update = plugin.render, vim.api.nvim_get_mode, inline.update
local paths, placements = {}, {}
local active, renders, updates = 0, 0, 0
local backend = {
	config = { doc = {} },
	setup = function() end,
	doc = {
		attach = function() end,
		find = function(_, cb)
			cb({})
		end,
	},
	placement = {
		new = function(_, src)
			active = active + 1
			placements[#placements + 1] = src
			local closed = false
			return {
				close = function()
					if not closed then
						active = active - 1
						closed = true
					end
				end,
			}
		end,
	},
}
package.loaded.snacks = { did_setup = true, config = { image = {} }, image = backend }
plugin.render = function(path, cb, settings)
	renders = renders + 1
	assert(settings.themes, "Cache key and rendering must share a settings snapshot")
	local base = path:gsub("%.mmd$", "")
	paths[base] = true
	for _, variant in ipairs({ "light", "dark" }) do
		vim.fn.writefile({ "fixture" }, base .. "." .. variant .. ".png")
	end
	cb()
end
local buf
local saved_background = vim.o.background
local saved_level, saved_cursor = vim.wo.conceallevel, vim.wo.concealcursor
vim.wo.conceallevel, vim.wo.concealcursor = 0, ""
local ok, err = pcall(function()
	plugin.setup({ auto_render = false, snacks = true, inline_mermaid = true, theme = "nvim" })
	vim.cmd.enew()
	buf = vim.api.nvim_get_current_buf()
	local source = { "```mermaid", "flowchart LR", "A[" .. vim.fn.tempname() .. "] --> B", "```" }
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
	vim.api.nvim_win_set_cursor(0, { 2, 0 })
	vim.bo[buf].filetype = "markdown"
	assert(
		vim.wait(2000, function()
			return active == 1
		end),
		"Opening Markdown must automatically replace a fence in normal mode, even with cursor inside"
	)
	assert(renders == 1 and vim.api.nvim_get_mode().mode == "n")
	assert(
		vim.wo.conceallevel == 2 and vim.wo.concealcursor == "n",
		"Normal-mode replacement must work with default conceal settings"
	)
	local fence_ns = vim.api.nvim_create_namespace("mmdtoimg.fences")
	assert(
		#vim.api.nvim_buf_get_extmarks(buf, fence_ns, 0, -1, {}) == 2,
		"Fence delimiters must be concealed without Treesitter"
	)
	assert(vim.deep_equal(source, vim.api.nvim_buf_get_lines(buf, 0, -1, false)))
	inline.update = function(target)
		if target == buf then
			updates = updates + 1
		end
		return original_update(target)
	end
	local placement_count = #placements
	plugin.attach_snacks()
	plugin.attach_snacks()
	plugin.attach_snacks()
	assert(vim.wait(1000, function()
		return updates > 0
	end))
	vim.wait(200, function()
		return false
	end)
	assert(updates == 1, "Repeated attachment must coalesce into one deferred update")
	assert(#placements == placement_count, "Unchanged refreshes must preserve placements and virtual rows")
	vim.api.nvim_get_mode = function()
		return { mode = "i" }
	end
	vim.api.nvim_exec_autocmds("ModeChanged", { pattern = "n:i" })
	assert(active == 0, "Insert mode must expose the source")
	assert(vim.wo.conceallevel == 0 and vim.wo.concealcursor == "", "Editing must restore window settings")
	assert(#vim.api.nvim_buf_get_extmarks(buf, fence_ns, 0, -1, {}) == 0, "Editing must reveal fence delimiters")
	vim.api.nvim_get_mode = original_mode
	vim.api.nvim_exec_autocmds("ModeChanged", { pattern = "i:n" })
	assert(active == 1, "Returning to normal mode must restore the preview without a command")
	source[3] = source[3] .. " --> C"
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
	local count = renders
	vim.api.nvim_exec_autocmds("TextChanged", { buffer = buf })
	assert(
		vim.wait(2000, function()
			return renders > count and active == 1
		end),
		"Edits must automatically refresh previews"
	)
	count = renders
	local normal = vim.api.nvim_get_hl(0, { name = "Normal" })
	vim.api.nvim_set_hl(0, "Normal", { fg = "#abcdef", bg = "#102030" })
	vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "test" })
	assert(
		vim.wait(2000, function()
			return renders > count and active == 1
		end),
		"Colorscheme changes must automatically refresh previews"
	)
	vim.api.nvim_set_hl(0, "Normal", normal)
	count = renders
	vim.o.background = vim.o.background == "dark" and "light" or "dark"
	vim.api.nvim_exec_autocmds("OptionSet", { pattern = "background" })
	assert(
		vim.wait(2000, function()
			return renders > count and active == 1
		end),
		"Background changes must automatically refresh previews"
	)
	assert(
		placements[#placements]:match("%." .. vim.o.background .. "%.png$"),
		"Preview must select the new background variant"
	)
	plugin.setup({ inline_mermaid = false })
	assert(active == 0, "Opt-out must remove inline placements")
	assert(vim.wo.conceallevel == 0 and vim.wo.concealcursor == "", "Opt-out must restore conceal settings")
	updates = 0
	inline.setup(plugin, { snacks = true, inline_mermaid = true }, vim.uv.cwd(), backend)
	inline.stop()
	vim.wait(250, function()
		return false
	end)
	assert(updates == 0, "Stopping must invalidate pending updates")
end)
inline.stop()
vim.o.background = saved_background
vim.wo.conceallevel, vim.wo.concealcursor = saved_level, saved_cursor
plugin.render, vim.api.nvim_get_mode, inline.update = original_render, original_mode, original_update
package.loaded.snacks = original_snacks
plugin.setup({ auto_render = false, snacks = true, inline_mermaid = true, theme = "default" })
if buf and vim.api.nvim_buf_is_valid(buf) then
	vim.api.nvim_buf_delete(buf, { force = true })
end
for base in pairs(paths) do
	for _, suffix in ipairs({ ".mmd", ".light.png", ".dark.png", ".svg" }) do
		vim.fn.delete(base .. suffix)
	end
end
assert(ok, err)
print("Automatic inline tests passed: open, filetype, normal/insert mode, edits, colorscheme, debounce, opt-out")
