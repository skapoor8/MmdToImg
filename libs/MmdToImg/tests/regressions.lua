local plugin = require("mmdtoimg")
local uv = vim.uv
local temp = vim.fn.tempname()
vim.fn.mkdir(temp, "p")
local original_system, original_notify = vim.system, vim.notify
vim.notify = function() end
local source = temp .. "/diagram.mmd"
vim.fn.writefile({ "OLD" }, source)
local inputs = {}
local fixture =
	[[<svg id="my-svg" viewBox="0 0 10 10" aria-labelledby="title desc"><title id="title">Title</title><desc id="desc">Desc</desc><style>#my-svg #actor0 { fill: #abcdef; }</style><defs><marker id="marker0"/></defs><g id="actor0" marker-end="url(#marker0)"><use href="#actor0"/><use xlink:href="#actor0"/></g></svg>]]
vim.system = function(args, _, callback)
	inputs[#inputs + 1] = table.concat(vim.fn.readfile(args[3]), "\n")
	local config = vim.json.decode(table.concat(vim.fn.readfile(args[7]), "\n"))
	assert(config.theme == "base")
	vim.fn.writefile({ args[5]:match("%.svg$") and fixture or inputs[#inputs] }, args[5])
	if #inputs == 1 then
		vim.fn.writefile({ "NEW" }, source)
	end
	callback({ code = 0, stdout = "", stderr = "" })
end
local ok, err = pcall(function()
	plugin.setup({ snacks = false, auto_render = false, command = "fixture", theme = "default" })
	local done = false
	plugin.render(source, function(failure)
		assert(not failure, failure)
		done = true
	end)
	assert(vim.wait(2000, function()
		return done
	end))
	assert(#inputs == 4)
	for _, input in ipairs(inputs) do
		assert(input == "OLD", "All variants must read one source snapshot")
	end
	local svg = table.concat(vim.fn.readfile(temp .. "/diagram.svg"), "\n")
	local ids = {}
	for id in svg:gmatch(' id="([^"]+)"') do
		assert(not ids[id], "Duplicate SVG ID: " .. id)
		ids[id] = true
	end
	for _, theme in ipairs({ "light", "dark" }) do
		local prefix = "diagram-" .. theme
		assert(svg:find('aria-labelledby="' .. prefix .. "-title " .. prefix .. '-desc"', 1, true))
		assert(svg:find("url(#" .. prefix .. "-marker0)", 1, true))
		assert(svg:find('href="#' .. prefix .. '-actor0"', 1, true))
		assert(svg:find("#" .. prefix .. " #" .. prefix .. "-actor0 { fill: #abcdef;", 1, true))
	end
	-- Fail both staging and publication; the entire previous set must survive.
	local publish = require("mmdtoimg.outputs").publish
	local staging = temp .. "/staging"
	vim.fn.mkdir(staging, "p")
	for _, file in ipairs({ "light.png", "dark.png", "combined.svg" }) do
		vim.fn.writefile({ "REPLACEMENT" }, staging .. "/" .. file)
	end
	local function contents()
		local result = {}
		for _, suffix in ipairs({ ".light.png", ".dark.png", ".svg" }) do
			result[#result + 1] = vim.fn.readfile(temp .. "/diagram" .. suffix)
		end
		return result
	end
	local previous = contents()
	local copy = uv.fs_copyfile
	uv.fs_copyfile = function(from, to)
		if from == staging .. "/dark.png" then
			return nil, "injected staging failure"
		end
		return copy(from, to)
	end
	local published = pcall(publish, staging, temp .. "/diagram")
	uv.fs_copyfile = copy
	assert(not published and vim.deep_equal(previous, contents()), "Staging failure changed existing outputs")
	local rename = uv.fs_rename
	uv.fs_rename = function(from, to)
		if to == temp .. "/diagram.dark.png" and not from:find("backup", 1, true) then
			return nil, "injected rename failure"
		end
		return rename(from, to)
	end
	published = pcall(publish, staging, temp .. "/diagram")
	uv.fs_rename = rename
	assert(not published and vim.deep_equal(previous, contents()), "Publication failure did not roll back")
	-- Newly created outputs must also disappear on rollback.
	local fresh = temp .. "/fresh"
	uv.fs_rename = function(from, to)
		if to == fresh .. ".dark.png" then
			return nil, "injected rename failure"
		end
		return rename(from, to)
	end
	published = pcall(publish, staging, fresh)
	uv.fs_rename = rename
	assert(not published and not uv.fs_stat(fresh .. ".light.png"), "Rollback left a newly created output")
	for name in vim.fs.dir(temp) do
		assert(not name:find("mmdtoimg", 1, true), "Staging or backup file leaked")
	end
	-- A source removed while queued must fail without wedging the queue.
	local queued = temp .. "/queued.mmd"
	vim.fn.writefile({ "QUEUED" }, queued)
	local completed, failed = 0, false
	plugin.render(source, function(failure)
		assert(not failure)
		completed = completed + 1
	end)
	plugin.render(queued, function(failure)
		failed = failure ~= nil
		completed = completed + 1
	end)
	plugin.render(source, function(failure)
		assert(not failure)
		completed = completed + 1
	end)
	vim.fn.delete(queued)
	assert(vim.wait(2000, function()
		return completed == 3
	end))
	assert(failed, "Missing queued source must report an error")
end)
vim.system, vim.notify = original_system, original_notify
plugin.setup({ command = "mmdc", snacks = true })
vim.fn.delete(temp, "rf")
assert(ok, err)
print("Regression tests passed: source snapshot, SVG references, output rollback, queue recovery")
