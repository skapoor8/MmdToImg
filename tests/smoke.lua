-- Run from the plugin directory: nvim --headless -u NONE -l tests/smoke.lua
vim.opt.runtimepath:prepend(vim.uv.cwd())
local plugin = require("mmdtoimg")
local temp = vim.fn.tempname()
vim.fn.mkdir(temp .. "/node_modules", "p")
vim.fn.writefile({ "flowchart LR", "A[Source] --> B[Image]" }, temp .. "/example.mmd")
vim.fn.writefile({ "invalid mermaid" }, temp .. "/node_modules/ignored.mmd")
local notices = {}
vim.notify = function(message)
	notices[#notices + 1] = message
end
local ok, err = pcall(function()
	plugin.setup({ auto_render = false, puppeteer_config = vim.env.MMD_TO_IMG_PUPPETEER_CONFIG })
	local done, failure = false, nil
	plugin.render_all(temp, function(render_err, count)
		failure = render_err
		assert(count == 1, "Excluded directory was scanned")
		done = true
	end)
	assert(
		vim.wait(120000, function()
			return done
		end),
		"Render timed out"
	)
	assert(not failure, failure)
	local svg = table.concat(vim.fn.readfile(temp .. "/example.svg"), "\n")
	assert(svg:find("prefers%-color%-scheme: dark"))
	for _, theme in ipairs({ "light", "dark" }) do
		vim.o.background = theme
		local cached = assert(plugin.resolve(temp .. "/README.md", "example.svg"))
		assert(vim.uv.fs_realpath(cached) == vim.uv.fs_realpath(temp .. "/example." .. theme .. ".png"))
	end
	assert(plugin.resolve(temp .. "/README.md", "missing.svg") == nil)
	assert(plugin.resolve(temp .. "/README.md", "https://example.com/image.png") == nil)
	local calls, saved_path = 0, nil
	local original = plugin.render
	plugin.render = function(path)
		calls, saved_path = calls + 1, path
	end
	plugin.setup({ auto_render = true })
	plugin.setup({ auto_render = true })
	vim.cmd.edit(temp .. "/example.mmd")
	vim.cmd.write()
	assert(calls == 1 and saved_path == temp .. "/example.mmd", "Save handler must run once")
	plugin.render = original
	plugin.setup({ auto_render = false, command = temp .. "/missing-mmdc" })
	done = false
	plugin.render(temp .. "/example.mmd", function(render_err)
		assert(render_err, "Missing CLI must fail")
		done = true
	end)
	assert(
		vim.wait(5000, function()
			return done
		end),
		"Failure callback timed out"
	)
	assert(table.concat(vim.fn.readfile(temp .. "/example.svg"), "\n") == svg, "Failure replaced the existing SVG")
end)
vim.fn.delete(temp, "rf")
assert(ok, err)
print("MmdToImg smoke tests passed: render, themes, directory exclusions, save hook, and failure preservation")
