local M = {}

local function read(path)
	return table.concat(vim.fn.readfile(path), "\n")
end

local function color(group, field, fallback)
	local hl = vim.api.nvim_get_hl(0, { name = group, link = false, create = false })
	return hl[field] and string.format("#%06x", hl[field]) or fallback
end

local function blend(fg, bg)
	local rgb = {}
	for offset = 2, 6, 2 do
		rgb[#rgb + 1] = string.format(
			"%02x",
			math.floor(
				tonumber(fg:sub(offset, offset + 1), 16) * 0.15 + tonumber(bg:sub(offset, offset + 1), 16) * 0.85 + 0.5
			)
		)
	end
	return "#" .. table.concat(rgb)
end

local function from_editor(config)
	local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false, create = false })
	if not normal.fg and not normal.bg then
		return
	end
	local v = config.themeVariables
	local fg = color("Normal", "fg", v.primaryTextColor)
	local bg = color("Normal", "bg", v.background)
	local border = color("Function", "fg", v.primaryBorderColor)
	local line = color("Comment", "fg", v.lineColor)
	v.background, v.primaryTextColor, v.textColor = bg, fg, fg
	v.primaryColor, v.primaryBorderColor = blend(border, bg), border
	v.secondaryColor, v.tertiaryColor = bg, blend(border, bg)
	v.secondaryTextColor, v.tertiaryTextColor = fg, fg
	v.lineColor, v.clusterBorder = line, line
	v.clusterBkg, v.edgeLabelBackground = bg, bg
	v.noteBkgColor, v.noteTextColor, v.noteBorderColor = blend(border, bg), fg, border
	-- Keep geometry and typography, replacing the bundled CSS color overrides.
	config.themeCSS = config.themeCSS:gsub("[%w-]+:%s*#[%x]+%s*!?[%w]*%s*;", "")
	local css = { config.themeCSS, ".edgeLabel { color: " .. fg .. "; } .cluster-label span { color: " .. fg .. "; }" }
	for _, item in ipairs({
		{ "frontend", "String" },
		{ "runtime", "Function" },
		{ "library", "Type" },
		{ "source", "Comment" },
		{ "tool", "DiagnosticWarn" },
		{ "artifact", "String" },
	}) do
		local accent = color(item[2], "fg", border)
		css[#css + 1] = (".node.%s rect { fill: %s; stroke: %s; } .node.%s .nodeLabel { color: %s; }"):format(
			item[1],
			blend(accent, bg),
			accent,
			item[1],
			fg
		)
	end
	config.themeCSS = table.concat(css, "\n")
end

-- One immutable settings snapshot is shared by the cache key and render job.
function M.snapshot(options, root)
	local settings = vim.deepcopy(options)
	settings.themes = {}
	for _, variant in ipairs({ "light", "dark" }) do
		local custom = options[variant .. "_config"]
		local config = vim.json.decode(read(custom or root .. "/themes/" .. variant .. ".json"))
		if not custom and options.theme == "nvim" and variant == vim.o.background then
			from_editor(config)
		end
		settings.themes[variant] = {
			config = config,
			background = (config.themeVariables or {}).background or (variant == "light" and "#ffffff" or "#0f172a"),
		}
	end
	if options.puppeteer_config then
		settings.puppeteer = read(options.puppeteer_config)
	end
	return settings
end

function M.key(content, settings)
	-- vim.inspect sorts table keys, unlike JSON object serialization.
	return vim.fn.sha256(vim.inspect({
		content = content,
		command = settings.command,
		scale = settings.scale,
		themes = settings.themes,
		puppeteer = settings.puppeteer,
		version = "inline-v3",
	}))
end
return M
