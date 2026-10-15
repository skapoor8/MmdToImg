local M = {}

-- Mermaid uses IDs outside the root SVG too (actors, markers, accessibility).
local function layer(svg, theme)
	local ids = {}
	for quote, id in svg:gmatch("%sid=([\"'])(.-)%1") do
		ids[id] = id == "my-svg" and "diagram-" .. theme or "diagram-" .. theme .. "-" .. id
	end
	svg = svg:gsub("(%sid=)([\"'])(.-)%2", function(prefix, quote, id)
		return prefix .. quote .. ids[id] .. quote
	end)
	svg = svg:gsub("([%w:_-]+)=([\"'])(.-)%2", function(name, quote, value)
		if name == "href" or name == "xlink:href" then
			local id = value:match("^#(.*)$")
			if ids[id] then
				value = "#" .. ids[id]
			end
		elseif name == "aria-labelledby" or name == "aria-describedby" then
			value = value:gsub("%S+", function(id)
				return ids[id] or id
			end)
		end
		return name .. "=" .. quote .. value .. quote
	end)
	svg = svg:gsub("url%(%s*([\"']?)#(.-)%1%s*%)", function(quote, id)
		return "url(" .. quote .. "#" .. (ids[id] or id) .. quote .. ")"
	end)
	svg = svg:gsub("(<style[^>]*>)(.-)(</style>)", function(open, css, close)
		-- Rewrite selectors without changing hex color declarations.
		css = css:gsub("([^{}]+){", function(selectors)
			return selectors:gsub("#([%w_-]+)", function(id)
				return "#" .. (ids[id] or id)
			end) .. "{"
		end)
		return open .. css .. close
	end)
	return svg:gsub("<svg%s", '<svg height="100%%" ', 1)
end

function M.combine(light, dark)
	local viewbox = assert(light:match('viewBox="([^"]+)"'), "Missing SVG viewBox")
	assert(dark:match('viewBox="([^"]+)"') == viewbox, "Theme layouts must have the same viewBox")
	local dimensions = vim.split(viewbox, "%s+", { trimempty = true })
	return ('<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="%s" width="%s" height="%s">\n'):format(
		viewbox,
		dimensions[3],
		dimensions[4]
	) .. "<style>\n#diagram-dark { display: none; }\n@media (prefers-color-scheme: dark) {\n#diagram-light { display: none; }\n#diagram-dark { display: inline; }\n}\n</style>\n" .. layer(
		light,
		"light"
	) .. "\n" .. layer(dark, "dark") .. "\n</svg>\n"
end
return M
