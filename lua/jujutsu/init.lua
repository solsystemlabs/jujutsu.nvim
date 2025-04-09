local M = {}
-- Track the buffer ID
M.log_buf = nil
-- Track if the window is already open
M.is_window_open = false

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
					vim.api.nvim_buf_set_keymap(new_buf, 'n', 'q', ':q<CR>', { noremap = true, silent = true })
				end
			})
		end
	else
		print("No change ID found on this line")
	end
end

-- Function to check if the log window exists and is valid
local function is_log_window_valid()
	-- Check if buffer exists and is valid
	if M.log_buf and vim.api.nvim_buf_is_valid(M.log_buf) then
		-- Check if buffer is loaded in any window
		local windows = vim.api.nvim_list_wins()
		for _, win in ipairs(windows) do
			if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == M.log_buf then
				return true
			end
		end
	end
	return false
end

function M.setup()
	vim.keymap.set('n', '<leader>l', function()
		-- Check if window is already open
		if is_log_window_valid() then
			-- Window already exists, do nothing
			vim.api.nvim_echo({ { "Jujutsu log window already open", "WarningMsg" } }, false, {})
			return
		end

		-- Create a split window
		vim.cmd("botright vsplit")
		-- Create a new scratch buffer
		local buf = vim.api.nvim_create_buf(false, true)
		-- Set the buffer in the current window
		vim.api.nvim_win_set_buf(vim.api.nvim_get_current_win(), buf)
		-- Save the buffer ID
		M.log_buf = buf
		-- Set window title/header
		vim.cmd("file JJ\\ Log\\ Viewer")
		-- Set window width
		vim.cmd("vertical resize 80")
		-- Run jj log in terminal to preserve colors
		vim.fn.termopen("jj log", {
			on_exit = function()
				-- Switch to normal mode
				vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, true, true), 'n', true)
				-- Set buffer as read-only AFTER terminal exits
				vim.bo[buf].modifiable = false
				vim.bo[buf].readonly = true
				-- Set keymaps
				vim.api.nvim_buf_set_keymap(buf, 'n', 'e', ':lua require("jujutsu").edit_change()<CR>',
					{ noremap = true, silent = true })
				vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':q<CR>', { noremap = true, silent = true })
			end
		})
	end)
end

M.edit_change = edit_change
return M
