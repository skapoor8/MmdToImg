-- Custom source visibility (including a render-markdown bridge) overrides modes.
local inline = require("mmdtoimg.inline")
local original_mode = vim.api.nvim_get_mode
local mode, policy = "n", nil
local active, created = {}, 0
local paths = {}
local opts = { command = "mmdc", scale = 2, snacks = true, inline_mermaid = true }
local root = vim.uv.cwd()
local backend = {
	doc = {
		find = function(_, cb)
			cb({})
		end,
	},
	placement = {
		new = function(_, _, config)
			local row = config.pos[1]
			created = created + 1
			active[row] = (active[row] or 0) + 1
			local closed = false
			return {
				close = function()
					if not closed then
						active[row] = active[row] - 1
						closed = true
					end
				end,
			}
		end,
	},
}
local fake = {
	render = function(path, cb)
		local base = path:gsub("%.mmd$", "")
		paths[base] = true
		for _, variant in ipairs({ "light", "dark" }) do
			vim.fn.writefile({ "fixture" }, base .. "." .. variant .. ".png")
		end
		cb()
	end,
}
vim.cmd.enew()
local buf = vim.api.nvim_get_current_buf()
vim.bo[buf].filetype = "markdown"
local unique = vim.fn.tempname()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
	"```mermaid",
	"A[" .. unique .. "] --> B",
	"```",
	"",
	"```mermaid",
	"C[" .. unique .. "] --> D",
	"```",
})
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.api.nvim_get_mode = function()
	return { mode = mode }
end
local calls = 0
opts.inline_source_visible = function(target, first, last)
	assert(
		target == buf and ((first == 1 and last == 3) or (first == 5 and last == 7)),
		"Policy needs the correct buffer and inclusive fence range"
	)
	calls = calls + 1
	if type(policy) == "table" then
		return policy[first]
	end
	return policy
end
local ok, err = pcall(function()
	inline.setup(fake, opts, root, backend)
	inline.update(buf)
	assert(active[2] == 1 and active[6] == 1, "nil policy must fall back to normal-mode previews")
	policy = true
	vim.api.nvim_exec_autocmds("CursorMoved", { buffer = buf })
	assert(active[2] == 0 and active[6] == 0, "Policy must reveal source even in normal mode")
	policy = false
	mode = "i"
	vim.api.nvim_exec_autocmds("ModeChanged", { pattern = "n:i" })
	assert(active[2] == 1 and active[6] == 1, "Explicit false must allow previews even in Insert mode")
	policy = nil
	vim.api.nvim_exec_autocmds("CursorMovedI", { buffer = buf })
	assert(active[2] == 0 and active[6] == 1, "nil must fall back to Insert mode for the block under the cursor")
	mode = "n"
	policy = { [1] = true, [5] = false }
	vim.api.nvim_exec_autocmds("ModeChanged", { pattern = "i:n" })
	assert(active[2] == 0 and active[6] == 1, "Each block must follow its own policy result")
	local count = created
	inline.update(buf)
	assert(created == count, "Unchanged visibility must preserve the other block's placement")
	assert(calls > 0)
end)
inline.stop()
vim.api.nvim_get_mode = original_mode
vim.api.nvim_buf_delete(buf, { force = true })
for base in pairs(paths) do
	for _, suffix in ipairs({ ".mmd", ".light.png", ".dark.png", ".svg" }) do
		vim.fn.delete(base .. suffix)
	end
end
assert(ok, err)
print("Visibility policy tests passed: normal/insert overrides, per-block ranges, nil fallback, stable refresh")
