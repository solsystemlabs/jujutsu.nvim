local M = {}
-- Track the buffer ID
M.log_buf = nil
-- Track the window ID that contains the log buffer
M.log_win = nil

-- Find the next line with a change ID
local function find_next_change_line(direction)
	local current_line = vim.api.nvim_win_get_cursor(0)[1]
	local line_count = vim.api.nvim_buf_line_count(0)
	local found_line = nil

	-- Function to check if a line has a valid change ID
	local function has_change_id(line)
		if not line then return false end

		-- Split the line by spaces
		local parts = {}
		for part in line:gmatch("%S+") do
			table.insert(parts, part)
		end

		-- Check if the second part is an 8-letter change ID
		return #parts >= 2 and parts[2]:match("^%a+$") and #parts[2] == 8
	end

	if direction == "next" then
		-- Search downward from current line
		for i = current_line + 1, line_count do
			local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
			if has_change_id(line) then
				found_line = i
				break
			end
		end

		-- Wrap around to the beginning if no match found
		if not found_line then
			for i = 1, current_line - 1 do
				local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
				if has_change_id(line) then
					found_line = i
					break
				end
			end
		end
	else -- direction == "prev"
		-- Search upward from current line
		for i = current_line - 1, 1, -1 do
			local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
			if has_change_id(line) then
				found_line = i
				break
			end
		end

		-- Wrap around to the end if no match found
		if not found_line then
			for i = line_count, current_line + 1, -1 do
				local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
				if has_change_id(line) then
					found_line = i
					break
				end
			end
		end
	end

	if found_line then
		vim.api.nvim_win_set_cursor(0, { found_line, 0 })
	end
end

local function edit_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = nil

	-- Split the line by spaces and check the second element
	local parts = {}
	for part in line:gmatch("%S+") do
		table.insert(parts, part)
	end

	-- Check if we have at least 2 elements and the second looks like a jj change ID
	-- (typically 8 lowercase letters with no numbers)
	if #parts >= 2 and parts[2]:match("^%a+$") and #parts[2] == 8 then
		change_id = parts[2]
	end

	-- If we didn't find it in the expected position, try to find any 8-letter word
	if not change_id then
		for _, part in ipairs(parts) do
			if part:match("^%a+$") and #part == 8 then
				change_id = part
				break
			end
		end
	end

	if change_id then
		-- Remember the current buffer and window
		local current_buf = vim.api.nvim_get_current_buf()
		local current_win = vim.api.nvim_get_current_win()

		-- Run the edit command silently using system() instead of !
		local result = vim.fn.system("jj edit " .. change_id)

		-- Optionally display a message about what happened
		vim.api.nvim_echo({ { "Applied edit to change " .. change_id, "Normal" } }, false, {})

		-- Refresh the log content
		if current_buf == M.log_buf then
			-- Create a new buffer for log output (to avoid terminal reuse errors)
			local new_buf = vim.api.nvim_create_buf(false, true) -- Make sure it's empty and scratch
			-- Set the new buffer in the current window
			vim.api.nvim_win_set_buf(current_win, new_buf)
			-- Update the global buffer reference
			M.log_buf = new_buf
			-- Run the terminal in the new buffer
			vim.fn.termopen("jj log", {
				on_exit = function()
					-- Switch to normal mode
					vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, true, true), 'n', true)
					-- Set buffer as read-only AFTER terminal exits
					vim.bo[new_buf].modifiable = false
					vim.bo[new_buf].readonly = true
					-- Set keymaps
					vim.api.nvim_buf_set_keymap(new_buf, 'n', 'e', ':lua require("jujutsu").edit_change()<CR>',
						{ noremap = true, silent = true })
					vim.api.nvim_buf_set_keymap(new_buf, 'n', 'q', ':lua require("jujutsu").toggle_log_window()<CR>',
						{ noremap = true, silent = true })
					vim.api.nvim_buf_set_keymap(new_buf, 'n', 'j', ':lua require("jujutsu").jump_next_change()<CR>',
						{ noremap = true, silent = true })
					vim.api.nvim_buf_set_keymap(new_buf, 'n', 'k', ':lua require("jujutsu").jump_prev_change()<CR>',
						{ noremap = true, silent = true })
				end
			})
		end
	else
		print("No change ID found on this line")
	end
end

function M.jump_next_change()
	find_next_change_line("next")
end

function M.jump_prev_change()
	find_next_change_line("prev")
end

-- Track the window ID that contains the log buffer
M.log_win = nil

function M.toggle_log_window()
	-- Check if log window exists and is valid
	if M.log_win and vim.api.nvim_win_is_valid(M.log_win) then
		-- Close the window
		vim.api.nvim_win_close(M.log_win, true)
		M.log_win = nil
		M.log_buf = nil
		return
	end

	-- Create a split window
	vim.cmd("botright vsplit")
	-- Remember the window ID
	M.log_win = vim.api.nvim_get_current_win()
	-- Create a new scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	-- Set the buffer in the current window
	vim.api.nvim_win_set_buf(M.log_win, buf)
	-- Save the buffer ID
	M.log_buf = buf
	-- Set window title/header
	vim.cmd("file JJ\\ Log\\ Viewer")
	-- Set window width
	vim.cmd("vertical resize 80")
	-- Run jj log in terminal to preserve colors
	vim.fn.termopen("jj log", {
		on_exit = function()
			-- Check if window still exists
			if not vim.api.nvim_win_is_valid(M.log_win) then
				return
			end
			-- Switch to normal mode
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, true, true), 'n', true)
			-- Set buffer as read-only AFTER terminal exits
			vim.bo[buf].modifiable = false
			vim.bo[buf].readonly = true
			-- Set keymaps
			vim.api.nvim_buf_set_keymap(buf, 'n', 'e', ':lua require("jujutsu").edit_change()<CR>',
				{ noremap = true, silent = true })
			vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':lua require("jujutsu").toggle_log_window()<CR>',
				{ noremap = true, silent = true })
			vim.api.nvim_buf_set_keymap(buf, 'n', 'j', ':lua require("jujutsu").jump_next_change()<CR>',
				{ noremap = true, silent = true })
			vim.api.nvim_buf_set_keymap(buf, 'n', 'k', ':lua require("jujutsu").jump_prev_change()<CR>',
				{ noremap = true, silent = true })
		end
	})
end

function M.setup()
	vim.keymap.set('n', '<leader>l', function()
		M.toggle_log_window()
	end)
end

M.edit_change = edit_change
return M
