local inline = require("mmdtoimg.inline")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
local blocks = inline.blocks({
	"````markdown",
	"```mermaid",
	"A --> B",
	"```",
	"````",
	"~~~mermaid",
	"flowchart LR",
	"A --> B",
	"~~~~",
	"```mermaid",
	"unclosed",
})
assert(#blocks == 1 and blocks[1].first == 6 and blocks[1].last == 9)
assert(blocks[1].content == "flowchart LR\nA --> B")
assert(#inline.blocks({ "- item", "  ```mermaid", "  A --> B", "  ```" }) == 0, "List fences belong to Snacks")
assert(#inline.blocks({ "> ```mermaid", "> A --> B", "> ```" }) == 0)
assert(#inline.blocks({ "- item", "  ```mermaid", "  A --> B", "  ```", "", "```mermaid", "A --> B", "```" }) == 1)
assert(#inline.blocks({ "   ```mermaid", "   A --> B", "   ```" }) == 1, "Indented top-level fences must work")
local calls, placements, matches = {}, {}, {}
local closed = 0
local backend = {
	doc = {
		find = function(_, cb)
			cb(matches)
		end,
	},
	placement = {
		new = function(_, src, opts)
			local p = {
				src = src,
				opts = opts,
				close = function()
					closed = closed + 1
				end,
				hide = function() end,
				show = function() end,
			}
			placements[#placements + 1] = p
			return p
		end,
	},
}
local opts = { command = "mmdc", scale = 2, snacks = true, inline_mermaid = true }
local root = vim.uv.cwd()
local callbacks = {}
local fake = {
	render = function(path, cb)
		calls[#calls + 1] = path
		callbacks[#callbacks + 1] = cb
	end,
}
inline.setup(fake, opts, root, backend)
local source = { "# Diagram", "", "```mermaid", "flowchart LR", "A --> B", "```", "after" }
vim.cmd.enew()
local buf = vim.api.nvim_get_current_buf()
vim.bo[buf].filetype = "markdown"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, source)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
inline.update(buf)
assert(#calls == 1)
local base = calls[1]:gsub("%.mmd$", "")
callbacks[1]()
assert(placements[1].opts.pos[1] == 4, "Image must anchor below the concealed opening fence")
assert(placements[1].opts.range[1] == 4 and placements[1].opts.range[3] == 5, "Image range must exclude both fences")
assert(#placements == 1 and placements[1].src == base .. "." .. vim.o.background .. ".png")
local width, height = inline.bounds(buf)
assert(placements[1].opts.max_width == width and placements[1].opts.max_height == height)
assert(
	width
		<= vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].width
			- vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff
			- 2
)
assert(vim.deep_equal(source, vim.api.nvim_buf_get_lines(buf, 0, -1, false)))
vim.api.nvim_win_set_cursor(0, { 4, 0 })
inline.visibility(buf)
assert(closed == 0, "Normal-mode movement must preserve the Mermaid image")
local get_mode = vim.api.nvim_get_mode
vim.api.nvim_get_mode = function()
	return { mode = "i" }
end
vim.api.nvim_win_set_cursor(0, { 4, 0 })
inline.visibility(buf)
assert(closed > 0, "Entering the fence must remove the image and all concealment")
callbacks[#callbacks]()
assert(#placements == 1, "Editing the fence must show source, not an image")
vim.api.nvim_get_mode = get_mode
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local key = inline.key("flowchart LR\nA --> B")
opts.scale = 3
assert(inline.key("flowchart LR\nA --> B") ~= key, "Renderer changes must invalidate cache")
opts.scale = 2
matches = { { lang = "mermaid", type = "chart", range = { 3, 0, 6, 3 } }, { lang = "markdown", type = "image" } }
backend.doc.find(buf, function(result)
	assert(#result == 1 and result[1].type == "image")
end)
opts.inline_mermaid = false
backend.doc.find(buf, function(result)
	assert(#result == 2)
end)
inline.update(buf)
callbacks[1]()
assert(#placements == 1, "Stale callbacks must not replace updated buffer")
opts.inline_mermaid = true
matches = { { lang = "mermaid", type = "chart", range = { 9, 0, 11, 3 } } }
backend.doc.find(buf, function(result)
	assert(#result == 1, "Unowned Mermaid matches must reach Snacks")
end)
vim.bo[buf].filetype = "org"
matches[1].range = { 3, 0, 6, 3 }
backend.doc.find(buf, function(result)
	assert(#result == 1, "Other filetypes must retain Snacks previews")
end)
inline.stop()
vim.fn.delete(base .. ".mmd")
vim.fn.delete(temp, "rf")
print("Custom inline tests passed: fences, rendering, cache keys, bounds, source preservation")
