local M = {}
local uv = vim.uv
local plugin_dir = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))
local options = { command = "mmdc", auto_render = true, snacks = true, scale = 2, timeout = 120000 }
local pending, queue, active = {}, {}, false

local function read(path)
	return table.concat(vim.fn.readfile(path), "\n")
end

-- Namespace each render so Mermaid's SVG IDs and styles cannot collide.
local function combine(light, dark)
	local viewbox = assert(light:match('viewBox="([^"]+)"'), "Missing SVG viewBox")
	assert(dark:match('viewBox="([^"]+)"') == viewbox, "Theme layouts must have the same viewBox")
	local dimensions = vim.split(viewbox, "%s+", { trimempty = true })
	local function layer(svg, theme)
		return svg:gsub("my%-svg", "diagram-" .. theme):gsub("<svg%s", '<svg height="100%%" ', 1)
	end
	return ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="%s" width="%s" height="%s">\n'):format(
		viewbox,
		dimensions[3],
		dimensions[4]
	) .. "<style>\n#diagram-dark { display: none; }\n@media (prefers-color-scheme: dark) {\n#diagram-light { display: none; }\n#diagram-dark { display: inline; }\n}\n</style>\n" .. layer(
		light,
		"light"
	) .. "\n" .. layer(dark, "dark") .. "\n</svg>\n"
end

function M.refresh()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if
			vim.api.nvim_buf_is_loaded(buf)
			and vim.bo[buf].filetype == "markdown"
			and vim.b[buf].snacks_image_attached
		then
			vim.api.nvim_exec_autocmds("WinScrolled", { buffer = buf, modeline = false })
		end
	end
end

-- Resolve SVG links to themed PNGs, and invalidate Snacks' cache after changes.
function M.resolve(file, src)
	if src:match("^%a[%w+.-]*://") or not src:lower():match("%.[ps][nv]g$") then
		return
	end
	local path = vim.fs.normalize(src:sub(1, 1) == "/" and src or vim.fs.dirname(file) .. "/" .. src)
	local stem = path:match("^(.*)%.light%.png$") or path:match("^(.*)%.dark%.png$") or path:match("^(.*)%.svg$")
	if stem then
		local themed = stem .. "." .. vim.o.background .. ".png"
		if uv.fs_stat(themed) then
			path = themed
		end
	end
	local stat = uv.fs_stat(path)
	if not stat or stat.type ~= "file" then
		return
	end
	local cache = vim.fn.stdpath("cache") .. "/mmdtoimg"
	local version = vim.fn.sha256(path .. stat.mtime.sec .. stat.mtime.nsec .. stat.size):sub(1, 12)
	local cached = cache .. "/" .. version .. "-" .. vim.fs.basename(path)
	if not uv.fs_stat(cached) then
		vim.fn.mkdir(cache, "p")
		local ok = uv.fs_symlink(path, cached)
		if not ok then
			return path
		end
	end
	return cached
end

-- Attach after Snacks loads without requiring it for users who do not install it.
local snacks_resolver
function M.attach_snacks()
	local snacks = package.loaded["snacks"]
	if not options.snacks or not snacks or not snacks.did_setup then
		return
	end
	snacks.config.image.enabled = true
	local image = snacks.image
	image.config.enabled = true
	image.config.doc.enabled = true
	if image.config.resolve ~= snacks_resolver or not snacks_resolver then
		local previous = image.config.resolve
		snacks_resolver = function(file, src)
			local resolved = previous and previous(file, src) or nil
			return M.resolve(file, resolved or src) or resolved
		end
		image.config.resolve = snacks_resolver
		snacks.config.image.resolve = snacks_resolver
	end
	image.setup()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "markdown" then
			image.doc.attach(buf)
		end
	end
end

local run_next
local function render(job, finish)
	local temp = vim.fn.tempname()
	vim.fn.mkdir(temp, "p")
	local base = job.path:gsub("%.mmd$", "")
	local commands = {}
	for _, theme in ipairs({ "light", "dark" }) do
		for _, ext in ipairs({ "png", "svg" }) do
			local args = {
				options.command,
				"-i",
				job.path,
				"-o",
				temp .. "/" .. theme .. "." .. ext,
				"-c",
				options[theme .. "_config"] or plugin_dir .. "/themes/" .. theme .. ".json",
				"-b",
				theme == "light" and "white" or "#0f172a",
			}
			if options.puppeteer_config then
				vim.list_extend(args, { "-p", options.puppeteer_config })
			end
			if ext == "png" then
				vim.list_extend(args, { "-s", tostring(options.scale) })
			end
			commands[#commands + 1] = args
		end
	end
	local function done(err)
		vim.fn.delete(temp, "rf")
		if err then
			vim.notify("MmdToImg: " .. err, vim.log.levels.ERROR)
		else
			M.refresh()
		end
		finish(err)
	end
	local function step(index)
		if index > #commands then
			local ok, err = pcall(function()
				vim.fn.writefile(
					vim.split(combine(read(temp .. "/light.svg"), read(temp .. "/dark.svg")), "\n"),
					temp .. "/combined.svg"
				)
				for _, output in ipairs({
					{ "light.png", ".light.png" },
					{ "dark.png", ".dark.png" },
					{ "combined.svg", ".svg" },
				}) do
					local destination = base .. output[2]
					local staged = destination .. ".mmdtoimg-tmp"
					assert(uv.fs_copyfile(temp .. "/" .. output[1], staged))
					local renamed, rename_err = uv.fs_rename(staged, destination)
					if not renamed then
						uv.fs_unlink(staged)
						error(rename_err)
					end
				end
			end)
			done(not ok and tostring(err) or nil)
			return
		end
		local ok, err = pcall(vim.system, commands[index], { text = true, timeout = options.timeout }, function(result)
			vim.schedule(function()
				if result.code ~= 0 then
					done(
						(result.stderr ~= "" and result.stderr or result.stdout or "Mermaid failed")
							.. " (exit "
							.. result.code
							.. ")"
					)
				else
					step(index + 1)
				end
			end)
		end)
		if not ok then
			done(tostring(err))
		end
	end
	step(1)
end

run_next = function()
	if active or #queue == 0 then
		return
	end
	active = true
	local job = table.remove(queue, 1)
	pending[job.path] = nil
	render(job, function(err)
		active = false
		for _, callback in ipairs(job.callbacks) do
			local ok, callback_err = pcall(callback, err)
			if not ok then
				vim.notify("MmdToImg: " .. tostring(callback_err), vim.log.levels.ERROR)
			end
		end
		run_next()
	end)
end

function M.render(path, callback)
	path = vim.fs.normalize(vim.fn.fnamemodify(path or vim.api.nvim_buf_get_name(0), ":p"))
	if not path:match("%.mmd$") or vim.fn.filereadable(path) ~= 1 then
		error("MmdToImg requires an existing .mmd file: " .. path)
	end
	local job = pending[path]
	if not job then
		job = { path = path, callbacks = {} }
		pending[path] = job
		queue[#queue + 1] = job
	end
	if callback then
		job.callbacks[#job.callbacks + 1] = callback
	end
	run_next()
end

function M.render_all(dir, callback)
	dir = vim.fn.fnamemodify(dir or vim.fs.root(0, ".git") or uv.cwd(), ":p")
	local files = {}
	local excluded = { [".git"] = true, node_modules = true, target = true, [".cache"] = true }
	local function scan(path)
		for name, kind in vim.fs.dir(path) do
			local child = path .. "/" .. name
			if kind == "directory" and not excluded[name] then
				scan(child)
			elseif kind == "file" and name:match("%.mmd$") then
				files[#files + 1] = child
			end
		end
	end
	scan(dir)
	table.sort(files)
	local remaining, failures = #files, {}
	if remaining == 0 then
		if callback then
			callback(nil, 0)
		end
		return
	end
	for _, file in ipairs(files) do
		M.render(file, function(err)
			if err then
				failures[#failures + 1] = file .. ": " .. err
			end
			remaining = remaining - 1
			if remaining == 0 and callback then
				callback(#failures > 0 and table.concat(failures, "\n") or nil, #files)
			end
		end)
	end
end

function M.setup(opts)
	options = vim.tbl_extend("force", options, opts or {})
	vim.api.nvim_create_user_command("MmdToImg", function(args)
		M.render(args.args ~= "" and args.args or nil)
	end, { nargs = "?", complete = "file", force = true })
	vim.api.nvim_create_user_command("MmdToImgAll", function(args)
		M.render_all(args.args ~= "" and args.args or nil, function(err, count)
			if not err then
				vim.notify("MmdToImg: rendered " .. count .. " diagrams")
			end
		end)
	end, { nargs = "?", complete = "dir", force = true })
	local group = vim.api.nvim_create_augroup("MmdToImg", { clear = true })
	if options.auto_render then
		vim.api.nvim_create_autocmd("BufWritePost", {
			group = group,
			pattern = "*.mmd",
			callback = function(ev)
				M.render(ev.file)
			end,
		})
	end
	vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "ColorScheme", "VimEnter" }, {
		group = group,
		callback = function()
			M.attach_snacks()
			M.refresh()
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = { "LazyLoad", "VeryLazy" },
		callback = M.attach_snacks,
	})
	M.attach_snacks()
	vim.api.nvim_create_autocmd("OptionSet", {
		group = group,
		pattern = "background",
		callback = function()
			vim.schedule(M.refresh)
		end,
	})
end

return M
