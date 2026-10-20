local scroll = require("mmdtoimg.scroll")
local original_buf = vim.api.nvim_get_current_buf()
local original_height = vim.api.nvim_win_get_height(0)
local saved = {
	conceallevel = vim.wo.conceallevel,
	concealcursor = vim.wo.concealcursor,
	smoothscroll = vim.wo.smoothscroll,
	scrolloff = vim.wo.scrolloff,
}
vim.cmd.enew()
local buf = vim.api.nvim_get_current_buf()
local ns = vim.api.nvim_create_namespace("mmdtoimg.scroll.test")
local ok, err = pcall(function()
	-- Guard setup must be scoped and must preserve mappings configured by users.
	vim.keymap.set("n", "<C-y>", "k", { buffer = buf })
	vim.b[buf].snacks_scroll = true
	scroll.attach(buf)
	assert(vim.fn.maparg("<C-y>", "n") == "k", "User scrolling mappings must be preserved")
	if vim.fn.has("nvim-0.11.4") == 1 then
		assert(vim.b[buf].snacks_scroll == false, "Animated native scrolling must not bypass the guard")
	end
	scroll.detach(buf)
	assert(vim.b[buf].snacks_scroll == true)
	assert(vim.fn.maparg("<C-y>", "n") == "k")
	vim.keymap.del("n", "<C-y>", { buffer = buf })
	scroll.attach(buf)
	if vim.fn.has("nvim-0.11.4") == 1 then
		assert(type(vim.fn.maparg("<C-y>", "n", false, true).callback) == "function")
		assert(type(vim.fn.maparg("<ScrollWheelUp>", "n", false, true).callback) == "function")
		local native = scroll.up
		local counts = {}
		scroll.up = function(_, count)
			counts[#counts + 1] = count
		end
		vim.fn.maparg("<C-y>", "n", false, true).callback()
		vim.fn.maparg("<ScrollWheelUp>", "n", false, true).callback()
		scroll.up = native
		assert(
			counts[1] == 1 and counts[2] == (tonumber(vim.o.mousescroll:match("ver:(%d+)")) or 3),
			"Key and mouse mappings must retain their native scroll amounts"
		)
	end
	scroll.detach(buf)
	assert(vim.fn.maparg("<C-y>", "n") == "" and vim.fn.maparg("<ScrollWheelUp>", "n") == "")
	if vim.fn.has("nvim-0.11.4") == 0 then
		return
	end
	vim.cmd("resize 12")
	vim.wo.conceallevel, vim.wo.concealcursor, vim.wo.scrolloff = 3, "n", 0
	for _, above in ipairs({ false, true }) do
		for _, smooth in ipairs({ false, true }) do
			vim.wo.smoothscroll = smooth
			vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
			local lines = {}
			for i = 1, 40 do
				lines[#lines + 1] = ""
				lines[#lines + 1] = "paragraph " .. i
			end
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
			for row = 1, #lines - 2, 2 do
				vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { end_row = row, conceal_lines = "" })
				local virtual = {}
				for i = 1, row % 3 + 1 do
					virtual[i] = { { "image row " .. i } }
				end
				vim.api.nvim_buf_set_extmark(
					buf,
					ns,
					above and row + 1 or row - 1,
					0,
					{ virt_lines = virtual, virt_lines_above = above }
				)
			end
			vim.cmd("normal! G")
			vim.cmd.redraw()
			for _ = 1, 300 do
				if vim.fn.line("w0") == 1 then
					break
				end
				local before = vim.fn.winsaveview()
				scroll.up(vim.api.nvim_get_current_win(), 1)
				-- Full redraw reproduces the worst form of the upstream bug.
				vim.cmd("redraw!")
				local after = vim.fn.winsaveview()
				assert(
					after.topline < before.topline
						or (after.topline == before.topline and after.topfill > before.topfill),
					"Scrolling stalled or moved down: " .. vim.inspect({ before = before, after = after })
				)
			end
			assert(vim.fn.line("w0") == 1, "Guarded scrolling must get past concealed and virtual rows to the top")
		end
	end
end)
scroll.detach(buf)
vim.api.nvim_buf_delete(buf, { force = true })
if vim.api.nvim_buf_is_valid(original_buf) then
	vim.api.nvim_set_current_buf(original_buf)
end
vim.api.nvim_win_set_height(0, original_height)
for name, value in pairs(saved) do
	vim.wo[name] = value
end
assert(ok, err)
print("Scroll tests passed: concealed/virtual rows, upward progress, smoothscroll, mapping preservation, cleanup")
