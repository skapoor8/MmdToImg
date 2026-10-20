for _, dir in ipairs({ "lua", "tests" }) do
	for _, path in
		ipairs(vim.fs.find(function(name)
			return name:match("%.lua$") ~= nil
		end, { path = dir, type = "file", limit = math.huge }))
	do
		assert(loadfile(path))
	end
end
print("Lua syntax checks passed")
