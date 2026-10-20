local theme = require("mmdtoimg.theme")
local root = vim.uv.cwd()
local background = vim.o.background
local groups = { "Normal", "Function", "Comment", "String", "Type", "DiagnosticWarn" }
local saved = {}
for _, name in ipairs(groups) do
	saved[name] = vim.api.nvim_get_hl(0, { name = name })
end
local temp = vim.fn.tempname()
local ok, err = pcall(function()
	vim.o.background = "dark"
	local defaults = theme.snapshot({ theme = "default", command = "mmdc", scale = 2 }, root)
	for _, name in ipairs(groups) do
		vim.api.nvim_set_hl(0, name, {})
	end
	local fallback = theme.snapshot({ theme = "nvim", command = "mmdc", scale = 2 }, root)
	assert(
		vim.deep_equal(fallback.themes, defaults.themes),
		"Missing highlights must retain the complete bundled palette"
	)
	assert(fallback.themes.dark.background == defaults.themes.dark.background)
	assert(
		fallback.themes.dark.config.themeVariables.primaryTextColor
			== defaults.themes.dark.config.themeVariables.primaryTextColor
	)
	vim.api.nvim_set_hl(0, "Normal", { fg = "#d0d0d0", bg = "#102030" })
	vim.api.nvim_set_hl(0, "Function", { fg = "#abcdef" })
	vim.api.nvim_set_hl(0, "String", { link = "Function" })
	local settings = theme.snapshot({ theme = "nvim", command = "mmdc", scale = 2 }, root)
	local v = settings.themes.dark.config.themeVariables
	assert(v.background == "#102030" and v.primaryTextColor == "#d0d0d0" and v.primaryBorderColor == "#abcdef")
	assert(settings.themes.dark.background == "#102030", "CLI canvas must match Normal background")
	assert(vim.deep_equal(settings.themes.light, defaults.themes.light), "Opposite variant must use bundled fallback")
	local css = settings.themes.dark.config.themeCSS
	assert(
		not css:find("#064e3b", 1, true) and css:find("stroke: #abcdef", 1, true),
		"Bundled CSS must not override editor colors"
	)
	local key = theme.key("A --> B", settings)
	assert(key == theme.key("A --> B", theme.snapshot({ theme = "nvim", command = "mmdc", scale = 2 }, root)))
	vim.api.nvim_set_hl(0, "Normal", { fg = "#eeeeee" }) -- transparent background
	local changed = theme.snapshot({ theme = "nvim", command = "mmdc", scale = 2 }, root)
	assert(theme.key("A --> B", changed) ~= key, "Highlight changes must invalidate inline cache")
	assert(changed.themes.dark.background == "#0f172a", "Transparent themes need an opaque fallback")
	vim.fn.writefile({ '{"theme":"forest","themeVariables":{"background":"#334455"}}' }, temp)
	local custom = theme.snapshot({ theme = "nvim", dark_config = temp }, root)
	assert(
		custom.themes.dark.config.theme == "forest" and custom.themes.dark.background == "#334455",
		"Explicit config must take precedence"
	)
	vim.o.background = "light"
	vim.api.nvim_set_hl(0, "Normal", { fg = "#102030", bg = "#f0f0f0" })
	local light = theme.snapshot({ theme = "nvim" }, root)
	assert(light.themes.light.background == "#f0f0f0")
	assert(vim.deep_equal(light.themes.dark, defaults.themes.dark))
end)
vim.o.background = background
for _, name in ipairs(groups) do
	vim.api.nvim_set_hl(0, name, saved[name])
end
vim.fn.delete(temp)
assert(ok, err)
print(
	"Theme tests passed: editor highlights, linked groups, missing colors, transparency, variants, custom configs, cache invalidation"
)
