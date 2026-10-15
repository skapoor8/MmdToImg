local M = {}
local uv = vim.uv

-- Stage and back up the complete set before replacing any destination.
function M.publish(temp, base)
	local outputs = {}
	local token = vim.fn.sha256(vim.fn.tempname()):sub(1, 16)
	local ok, err = pcall(function()
		for _, output in ipairs({
			{ "light.png", ".light.png" },
			{ "dark.png", ".dark.png" },
			{ "combined.svg", ".svg" },
		}) do
			local destination = base .. output[2]
			local entry = {
				destination = destination,
				staged = destination .. ".mmdtoimg-" .. token,
				backup = destination .. ".mmdtoimg-backup-" .. token,
			}
			outputs[#outputs + 1] = entry
			assert(uv.fs_copyfile(temp .. "/" .. output[1], entry.staged))
			local stat, stat_err, code = uv.fs_stat(destination)
			assert(stat or code == "ENOENT", stat_err)
			if stat then
				assert(stat.type == "file", "Output is not a file: " .. destination)
				assert(uv.fs_copyfile(destination, entry.backup))
				entry.existed = true
			end
		end
		for _, entry in ipairs(outputs) do
			assert(uv.fs_rename(entry.staged, entry.destination))
			entry.published = true
		end
	end)
	local recovery = {}
	for _, entry in ipairs(outputs) do
		if not ok and entry.published then
			local restored, restore_err
			if entry.existed then
				restored, restore_err = uv.fs_rename(entry.backup, entry.destination)
			else
				restored, restore_err = uv.fs_unlink(entry.destination)
			end
			if not restored then
				recovery[#recovery + 1] = tostring(restore_err) .. "; backup retained at " .. entry.backup
				entry.keep_backup = true
			end
		end
		uv.fs_unlink(entry.staged)
		if not entry.keep_backup then
			uv.fs_unlink(entry.backup)
		end
	end
	if not ok then
		error(tostring(err) .. (#recovery > 0 and "\n" .. table.concat(recovery, "\n") or ""))
	end
end
return M
