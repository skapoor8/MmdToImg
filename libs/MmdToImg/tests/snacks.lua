-- Exercise optional integration and startup order without requiring Snacks in CI.
local plugin = require("mmdtoimg")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
vim.fn.writefile({ "image fixture" }, temp .. "/diagram.dark.png")
local original = package.loaded.snacks
local saved_resolve = plugin.resolve
local setups, resolver_calls = 0, 0
local custom = function(_, src)
	resolver_calls = resolver_calls + 1
	if src == "virtual://diagram" then
		return temp .. "/diagram.svg"
	end
	if src == "https://example.com/image.png" then
		return "https://example.com/custom.png"
	end
end
local image = {
	config = { enabled = false, doc = { enabled = false }, resolve = custom },
	setup = function()
		setups = setups + 1
	end,
	doc = {
		attach = function() end,
		find = function(_, callback)
			callback({})
		end,
	},
}
local snacks = { did_setup = false, config = { image = {} }, image = image }
local ok, err = pcall(function()
	package.loaded.snacks = snacks
	plugin.setup()
	assert(image.config.resolve == custom, "Integration must wait until Snacks setup completes")
	snacks.did_setup = true
	vim.o.background = "dark"
	plugin.attach_snacks()
	assert(image.config.enabled and image.config.doc.enabled and setups == 1)
	local wrapper = image.config.resolve
	plugin.attach_snacks()
	assert(image.config.resolve == wrapper, "Repeated attachment must not wrap the resolver twice")
	local cached = assert(wrapper(temp .. "/README.md", "virtual://diagram"))
	assert(vim.uv.fs_realpath(cached) == vim.uv.fs_realpath(temp .. "/diagram.dark.png"))
	assert(wrapper(temp .. "/README.md", "https://example.com/image.png") == "https://example.com/custom.png")
	assert(resolver_calls == 2, "Custom resolver must run exactly once per request")
	image.config.resolve = custom
	plugin.setup({ snacks = false })
	plugin.attach_snacks()
	assert(image.config.resolve == custom, "Opt-out must leave resolver untouched")
	package.loaded.snacks = nil
	plugin.setup({ snacks = true })
	assert(package.loaded.snacks == nil, "Snacks must remain optional")
end)
-- Synthetic image refreshes must not notify global scroll listeners.
local refresh_buf = vim.api.nvim_create_buf(false, true)
vim.bo[refresh_buf].filetype = "markdown"
vim.b[refresh_buf].snacks_image_attached = true
local image_refreshes, scroll_refreshes = 0, 0
local refresh_group = vim.api.nvim_create_augroup("snacks.image.inline." .. refresh_buf, { clear = true })
local scroll_group = vim.api.nvim_create_augroup("MmdToImgScrollTest", { clear = true })
vim.api.nvim_create_autocmd("WinScrolled", {
	group = refresh_group,
	buffer = refresh_buf,
	callback = function()
		image_refreshes = image_refreshes + 1
	end,
})
vim.api.nvim_create_autocmd("WinScrolled", {
	group = scroll_group,
	callback = function()
		scroll_refreshes = scroll_refreshes + 1
	end,
})
plugin.refresh()
assert(image_refreshes == 1 and scroll_refreshes == 0, "Image refresh must not trigger scroll animations")
vim.api.nvim_del_augroup_by_id(refresh_group)
vim.api.nvim_del_augroup_by_id(scroll_group)
vim.api.nvim_buf_delete(refresh_buf, { force = true })
package.loaded.snacks = original
plugin.resolve = saved_resolve
vim.fn.delete(temp, "rf")
assert(ok, err)
print("Automatic Snacks integration tests passed")
