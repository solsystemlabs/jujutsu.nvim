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

	-- Function to extract a change ID from a line, if it exists
	local function extract_change_id(line)
		if not line then return nil end

		-- Look for an email address and get the word before it (which should be the change ID)
		-- Pattern to match: word followed by email
		local id = line:match("([a-z]+)%s+[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+%.[a-zA-Z0-9-.]+")

		-- Check if it's a valid 8-letter change ID
		if id and #id == 8 then
			return id
		end

		return nil
	end

	if direction == "next" then
		-- Search downward from current line
		for i = current_line + 1, line_count do
			local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
			if extract_change_id(line) then
				found_line = i
				break
			end
		end

		-- Wrap around to the beginning if no match found
		if not found_line then
			for i = 1, current_line - 1 do
				local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
				if extract_change_id(line) then
					found_line = i
					break
				end
			end
		end
	else -- direction == "prev"
		-- Search upward from current line
		for i = current_line - 1, 1, -1 do
			local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
			if extract_change_id(line) then
				found_line = i
				break
			end
		end

		-- Wrap around to the end if no match found
		if not found_line then
			for i = line_count, current_line + 1, -1 do
				local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
				if extract_change_id(line) then
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

-- Function to edit change with jj edit command
local function edit_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = nil

	-- Look for an email address and get the word before it (which should be the change ID)
	change_id = line:match("([a-z]+)%s+[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+%.[a-zA-Z0-9-.]+")

	-- Check if it's a valid 8-letter change ID
	if change_id and #change_id ~= 8 then
		change_id = nil
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
					vim.api.nvim_buf_set_keymap(new_buf, 'n', 'd', ':lua require("jujutsu").describe_change()<CR>',
						{ noremap = true, silent = true })
					vim.api.nvim_buf_set_keymap(new_buf, 'n', 'n', ':lua require("jujutsu").new_change()<CR>',
						{ noremap = true, silent = true })
					vim.api.nvim_buf_set_keymap(new_buf, 'n', 'a', ':lua require("jujutsu").abandon_change()<CR>',
						{ noremap = true, silent = true })
				end
			})
		end
	else
		print("No change ID found on this line")
	end
end

-- Function to abandon a change
local function abandon_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = nil

	-- Look for an email address and get the word before it (which should be the change ID)
	change_id = line:match("([a-z]+)%s+[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+%.[a-zA-Z0-9-.]+")

	-- Check if it's a valid 8-letter change ID
	if change_id and #change_id ~= 8 then
		change_id = nil
	end

	if change_id then
		-- Remember the current buffer and window
		local current_buf = vim.api.nvim_get_current_buf()
		local current_win = vim.api.nvim_get_current_win()

		-- Ask for confirmation before abandoning
		vim.ui.select(
			{ "Yes", "No" },
			{
				prompt = "Are you sure you want to abandon change " .. change_id .. "?",
			},
			function(choice)
				if choice == "Yes" then
					-- Run the abandon command
					local result = vim.fn.system("jj abandon " .. change_id)

					-- Show success message
					vim.api.nvim_echo({ { "Abandoned change " .. change_id, "Normal" } }, false, {})

					-- Refresh the log content if we're in the log buffer
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
								vim.api.nvim_buf_set_keymap(new_buf, 'n', 'd', ':lua require("jujutsu").describe_change()<CR>',
									{ noremap = true, silent = true })
								vim.api.nvim_buf_set_keymap(new_buf, 'n', 'n', ':lua require("jujutsu").new_change()<CR>',
									{ noremap = true, silent = true })
								vim.api.nvim_buf_set_keymap(new_buf, 'n', 'a', ':lua require("jujutsu").abandon_change()<CR>',
									{ noremap = true, silent = true })
							end
						})
					end
				end
			end
		)
	else
		print("No change ID found on this line")
	end
end

-- Function to add or edit change description
local function describe_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = nil

	-- Look for an email address and get the word before it (which should be the change ID)
	change_id = line:match("([a-z]+)%s+[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+%.[a-zA-Z0-9-.]+")

	-- Check if it's a valid 8-letter change ID
	if change_id and #change_id ~= 8 then
		change_id = nil
	end

	if change_id then
		-- Remember the current buffer and window
		local current_buf = vim.api.nvim_get_current_buf()
		local current_win = vim.api.nvim_get_current_win()

		-- Use a plain format to get just the raw description text without any formatting
		local description = vim.fn.system("jj log -r " .. change_id .. " --no-graph -T 'description'")

		-- Trim whitespace
		description = description:gsub("^%s*(.-)%s*$", "%1")

		-- Replace newlines with spaces to avoid the error with snacks.nvim
		description = description:gsub("\n", " ")

		-- Use vim.ui.input() for simple input at the bottom of the screen
		vim.ui.input(
			{
				prompt = "Description for " .. change_id .. ": ",
				default = description,
				completion = "file", -- This gives a decent sized input box
			},
			function(input)
				if input then -- If not cancelled (ESC)
					-- Run the describe command
					local cmd = "jj describe " .. change_id .. " -m " .. vim.fn.shellescape(input)
					local result = vim.fn.system(cmd)

					-- Show success message
					vim.api.nvim_echo({ { "Updated description for change " .. change_id, "Normal" } }, false, {})

					-- Refresh the log content if we're in the log buffer
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
								vim.api.nvim_buf_set_keymap(new_buf, 'n', 'd', ':lua require("jujutsu").describe_change()<CR>',
									{ noremap = true, silent = true })
								vim.api.nvim_buf_set_keymap(new_buf, 'n', 'n', ':lua require("jujutsu").new_change()<CR>',
									{ noremap = true, silent = true })
								vim.api.nvim_buf_set_keymap(new_buf, 'n', 'a', ':lua require("jujutsu").abandon_change()<CR>',
									{ noremap = true, silent = true })
							end
						})
					end
				else
					-- Show cancel message if the user pressed ESC
					vim.api.nvim_echo({ { "Description edit cancelled", "Normal" } }, false, {})
				end
			end
		)
	else
		print("No change ID found on this line")
	end
end

-- Function to create a new change
local function new_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = nil

	-- Look for an email address and get the word before it (which should be the change ID)
	change_id = line:match("([a-z]+)%s+[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+%.[a-zA-Z0-9-.]+")

	-- Check if it's a valid 8-letter change ID
	if change_id and #change_id ~= 8 then
		change_id = nil
	end

	if change_id then
		-- Remember the current buffer and window
		local current_buf = vim.api.nvim_get_current_buf()
		local current_win = vim.api.nvim_get_current_win()

		-- Ask user for a description for the new change
		vim.ui.input(
			{
				prompt = "Description for new change based on " .. change_id .. ": ",
				default = "",
				completion = "file", -- This gives a decent sized input box
			},
			function(input)
				-- If user didn't provide description, use empty string
				local description = input or ""

				-- Run the new command, optionally with a description
				local cmd
				if description ~= "" then
					cmd = "jj new " .. change_id .. " -m " .. vim.fn.shellescape(description)
				else
					cmd = "jj new " .. change_id
				end

				local result = vim.fn.system(cmd)

				-- Show success message
				vim.api.nvim_echo({ { "Created new change based on " .. change_id, "Normal" } }, false, {})

				-- Refresh the log content if we're in the log buffer
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
							vim.api.nvim_buf_set_keymap(new_buf, 'n', 'd', ':lua require("jujutsu").describe_change()<CR>',
								{ noremap = true, silent = true })
							vim.api.nvim_buf_set_keymap(new_buf, 'n', 'n', ':lua require("jujutsu").new_change()<CR>',
								{ noremap = true, silent = true })
							vim.api.nvim_buf_set_keymap(new_buf, 'n', 'a', ':lua require("jujutsu").abandon_change()<CR>',
								{ noremap = true, silent = true })
						end
					})
				end
			end
		)
	else
		-- If no change ID was found on the current line, create a new change based on the working copy
		vim.ui.input(
			{
				prompt = "Description for new change: ",
				default = "",
				completion = "file", -- This gives a decent sized input box
			},
			function(input)
				-- If user didn't provide description, use empty string
				local description = input or ""

				-- Run the new command, optionally with a description
				local cmd
				if description ~= "" then
					cmd = "jj new -m " .. vim.fn.shellescape(description)
				else
					cmd = "jj new"
				end

				local result = vim.fn.system(cmd)

				-- Show success message
				vim.api.nvim_echo({ { "Created new change", "Normal" } }, false, {})

				-- Refresh the log window if needed
				if M.log_buf and vim.api.nvim_buf_is_valid(M.log_buf) then
					-- Remember the window ID
					local win_id = M.log_win
					if win_id and vim.api.nvim_win_is_valid(win_id) then
						-- Create a new buffer for log output
						local new_buf = vim.api.nvim_create_buf(false, true)
						-- Set the new buffer in the window
						vim.api.nvim_win_set_buf(win_id, new_buf)
						-- Update the global buffer reference
						M.log_buf = new_buf
						-- Run the terminal in the new buffer
						vim.fn.termopen("jj log", {
							on_exit = function()
								-- Check if window still exists
								if not vim.api.nvim_win_is_valid(win_id) then
									return
								end
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
								vim.api.nvim_buf_set_keymap(new_buf, 'n', 'd', ':lua require("jujutsu").describe_change()<CR>',
									{ noremap = true, silent = true })
								vim.api.nvim_buf_set_keymap(new_buf, 'n', 'n', ':lua require("jujutsu").new_change()<CR>',
									{ noremap = true, silent = true })
								vim.api.nvim_buf_set_keymap(new_buf, 'n', 'a', ':lua require("jujutsu").abandon_change()<CR>',
									{ noremap = true, silent = true })
							end
						})
					end
				end
			end
		)
	end
end

function M.jump_next_change()
	find_next_change_line("next")
end

function M.jump_prev_change()
	find_next_change_line("prev")
end

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
			vim.api.nvim_buf_set_keymap(buf, 'n', 'd', ':lua require("jujutsu").describe_change()<CR>',
				{ noremap = true, silent = true })
			vim.api.nvim_buf_set_keymap(buf, 'n', 'n', ':lua require("jujutsu").new_change()<CR>',
				{ noremap = true, silent = true })
			vim.api.nvim_buf_set_keymap(buf, 'n', 'a', ':lua require("jujutsu").abandon_change()<CR>',
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
M.describe_change = describe_change
M.new_change = new_change
M.abandon_change = abandon_change
return M
