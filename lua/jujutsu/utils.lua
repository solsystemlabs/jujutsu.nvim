-- jujutsu.nvim - Utils module
-- Utility functions for the jujutsu.nvim plugin

local M = {}
local api = vim.api
local fn = vim.fn

-- Execute a system command and get result
function M.system_result(cmd, cwd)
	cwd = cwd or fn.getcwd()

	local output = {
		stdout = "",
		stderr = "",
		exit_code = 0
	}

	-- Use jobstart for async execution
	local stdout_data = {}
	local stderr_data = {}

	local jobid = fn.jobstart(cmd, {
		cwd = cwd,
		on_stdout = function(_, data, _)
			if data then
				vim.list_extend(stdout_data, data)
			end
		end,
		on_stderr = function(_, data, _)
			if data then
				vim.list_extend(stderr_data, data)
			end
		end,
		on_exit = function(_, code, _)
			output.exit_code = code
		end,
		stdout_buffered = true,
		stderr_buffered = true,
	})

	-- Wait for the job to finish
	fn.jobwait({ jobid })

	-- Process the output
	output.stdout = table.concat(stdout_data, "\n")
	output.stderr = table.concat(stderr_data, "\n")

	return output
end

-- Parse diff output into hunks
function M.parse_diff(diff_text)
	if not diff_text or diff_text == "" then
		return {}
	end

	local hunks = {}
	local current_hunk = nil
	local line_num = 0

	-- Simple parser for git-style diff output
	for line in diff_text:gmatch("[^\r\n]+") do
		-- Find hunk headers
		local start_a, count_a, start_b, count_b = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")

		if start_a then
			if current_hunk then
				table.insert(hunks, current_hunk)
			end

			start_a = tonumber(start_a) or 0
			count_a = tonumber(count_a) or 1
			start_b = tonumber(start_b) or 0
			count_b = tonumber(count_b) or 1

			current_hunk = {
				start = start_b,
				count = count_b,
				removed = count_a,
				added = count_b,
				finish = start_b + count_b - 1,
				type = 'change'
			}

			-- Determine hunk type
			if count_a == 0 then
				current_hunk.type = 'add'
			elseif count_b == 0 then
				current_hunk.type = 'remove'
			end

			line_num = start_b
		elseif current_hunk then
			-- Track line numbers for more accurate hunk ranges
			if line:sub(1, 1) == '+' then
				line_num = line_num + 1
			elseif line:sub(1, 1) == '-' then
				-- Don't increment line number for removed lines
			else
				line_num = line_num + 1
			end
		end
	end

	-- Add the last hunk
	if current_hunk then
		table.insert(hunks, current_hunk)
	end

	return hunks
end

-- Show text in a split buffer
function M.show_in_split(text, filetype)
	-- Create a new split
	vim.cmd('botright new')

	local bufnr = api.nvim_get_current_buf()

	-- Set buffer content
	api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(text, '\n'))

	-- Set buffer options
	vim.bo[bufnr].buftype = 'nofile'
	vim.bo[bufnr].bufhidden = 'wipe'
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].modifiable = false

	-- Set filetype for syntax highlighting
	if filetype then
		vim.bo[bufnr].filetype = filetype
	end

	-- Add key mapping to close the buffer
	vim.keymap.set('n', 'q', ':bdelete<CR>', { buffer = bufnr, noremap = true, silent = true })

	return bufnr
end

-- Display an error message
function M.error(msg)
	vim.notify(msg, vim.log.levels.ERROR)
end

-- Read the contents of a file
function M.read_file(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end

	local content = file:read("*all")
	file:close()

	return content
end

-- Write content to a file
function M.write_file(path, content)
	local file = io.open(path, "w")
	if not file then
		return false
	end

	file:write(content)
	file:close()

	return true
end

-- Extract the change ID from jujutsu output
function M.extract_change_id(output)
	-- Look for patterns like "Working copy : abcdefgh 12345678"
	local change_id = output:match("Working copy %s*: (%w+)")
	return change_id
end

-- Safely escape a string for shell usage
function M.shell_escape(str)
	if str == nil then
		return ""
	end

	-- Basic shell escaping
	str = string.gsub(str, "([%^%$%(%)%%%.%[%]%*%+%-%?])", "\\%1")
	str = string.gsub(str, '"', '\\"')

	return str
end

-- Get the root directory of the jujutsu repository
function M.get_jujutsu_root()
	local cwd = fn.getcwd()
	local result = M.system_result({ "jj", "workspace", "root" }, cwd)

	if result.exit_code == 0 then
		return vim.trim(result.stdout)
	end

	return nil
end

-- Convert a buffer path to a path relative to the repo root
function M.buf_to_repo_path(bufnr)
	bufnr = bufnr or api.nvim_get_current_buf()
	local abs_path = api.nvim_buf_get_name(bufnr)

	local repo_root = M.get_jujutsu_root()
	if not repo_root or abs_path == '' then
		return nil
	end

	-- Get relative path
	if vim.startswith(abs_path, repo_root) then
		return abs_path:sub(#repo_root + 2) -- +2 to account for path separator
	end

	return abs_path
end

-- Run a jujutsu command and return the result
function M.jujutsu_command(cmd, args, cwd)
	if type(cmd) == "string" then
		cmd = { cmd }
	end

	-- Add jj at the beginning if not already there
	if cmd[1] ~= "jj" then
		table.insert(cmd, 1, "jj")
	end

	-- Add arguments if provided
	if args then
		for _, arg in ipairs(args) do
			table.insert(cmd, arg)
		end
	end

	return M.system_result(cmd, cwd)
end

return M
