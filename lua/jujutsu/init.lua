local M = {}
-- Track the buffer ID
M.log_buf = nil
-- Track the window ID that contains the log buffer
M.log_win = nil
-- Track the status buffer and window IDs
M.status_buf = nil
M.status_win = nil

-- Helper function to extract a change ID from a line
local function extract_change_id(line)
	if not line then return nil end

	-- Look for an email address and get the word before it (which should be the change ID)
	local id = line:match("([a-z]+)%s+[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+%.[a-zA-Z0-9-.]+")

	-- Check if it's a valid 8-letter change ID
	if id and #id == 8 then
		return id
	end

	return nil
end

-- Helper function to set keymaps for log buffer
local function setup_log_buffer_keymaps(buf)
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
	vim.api.nvim_buf_set_keymap(buf, 'n', 's', ':lua require("jujutsu").show_status()<CR>',
		{ noremap = true, silent = true })
	-- Add new mappings for enhanced log features
	vim.api.nvim_buf_set_keymap(buf, 'n', 'l', ':lua require("jujutsu").set_log_limit()<CR>',
		{ noremap = true, silent = true, desc = "Set log entry limit" })
	vim.api.nvim_buf_set_keymap(buf, 'n', 'r', ':lua require("jujutsu").set_revset_filter()<CR>',
		{ noremap = true, silent = true, desc = "Set revset filter" })
	vim.api.nvim_buf_set_keymap(buf, 'n', 'f', ':lua require("jujutsu").search_in_log()<CR>',
		{ noremap = true, silent = true, desc = "Search in log" })
	vim.api.nvim_buf_set_keymap(buf, 'n', 'T', ':lua require("jujutsu").change_log_template()<CR>',
		{ noremap = true, silent = true, desc = "Change log template" })
end

-- Helper function to set keymaps for status buffer
local function setup_status_buffer_keymaps(buf)
	vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':lua require("jujutsu").close_status_window()<CR>',
		{ noremap = true, silent = true })
	vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':lua require("jujutsu").close_status_window()<CR>',
		{ noremap = true, silent = true })
	vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', ':lua require("jujutsu").close_status_window()<CR>',
		{ noremap = true, silent = true })
	vim.api.nvim_buf_set_keymap(buf, 'n', 'r', ':lua require("jujutsu").refresh_status()<CR>',
		{ noremap = true, silent = true })
end

-- Store the current log settings
M.log_settings = {
	limit = "",        -- "" means no limit
	revset = "",       -- "" means default revset
	template = "",     -- "" means default template
	search_pattern = "" -- "" means no search pattern
}

-- Helper function to refresh log buffer with jj log and the current settings
local function refresh_log_buffer(win_id)
	-- Create a new buffer for log output
	local new_buf = vim.api.nvim_create_buf(false, true)

	-- Set the new buffer in the window
	vim.api.nvim_win_set_buf(win_id, new_buf)

	-- Update the global buffer reference
	M.log_buf = new_buf

	-- Build the command with any specified options
	local cmd = "jj log"

	-- Add revset if specified
	if M.log_settings.revset ~= "" then
		cmd = cmd .. " -r " .. vim.fn.shellescape(M.log_settings.revset)
	end

	-- Add limit if specified
	if M.log_settings.limit ~= "" then
		cmd = cmd .. " -n " .. M.log_settings.limit
	end

	-- Add template if specified
	if M.log_settings.template ~= "" then
		cmd = cmd .. " -T " .. vim.fn.shellescape(M.log_settings.template)
	end

	-- Add search pattern if specified (using diff_contains)
	if M.log_settings.search_pattern ~= "" then
		-- If we already have a revset, we need to combine them
		if M.log_settings.revset ~= "" then
			cmd = cmd ..
					" -r " ..
					vim.fn.shellescape("(" ..
						M.log_settings.revset .. ") & diff_contains(" .. vim.fn.shellescape(M.log_settings.search_pattern) .. ")")
		else
			cmd = cmd ..
					" -r " .. vim.fn.shellescape("diff_contains(" .. vim.fn.shellescape(M.log_settings.search_pattern) .. ")")
		end
	end

	-- Run the terminal in the new buffer
	vim.fn.termopen(cmd, {
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
			setup_log_buffer_keymaps(new_buf)
		end
	})
end

-- Find the next line with a change ID
local function find_next_change_line(direction)
	local current_line = vim.api.nvim_win_get_cursor(0)[1]
	local line_count = vim.api.nvim_buf_line_count(0)
	local found_line = nil

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

-- Function to show status in a floating window
local function show_status()
	-- Close existing status window if it exists
	if M.status_win and vim.api.nvim_win_is_valid(M.status_win) then
		vim.api.nvim_win_close(M.status_win, true)
		M.status_win = nil
		M.status_buf = nil
		return
	end

	-- Create a new scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	M.status_buf = buf

	-- Set buffer name/title
	vim.api.nvim_buf_set_name(buf, "JJ Status")

	-- Calculate window size and position - made smaller
	local width = math.floor(vim.o.columns * 0.6) -- Reduced from 0.8
	local height = math.floor(vim.o.lines * 0.5) -- Reduced from 0.8
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	-- Create floating window
	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = "rounded"
	}

	M.status_win = vim.api.nvim_open_win(buf, true, win_opts)

	-- Run jj st in a terminal
	vim.fn.termopen("jj st", {
		on_exit = function()
			-- Check if window still exists
			if not vim.api.nvim_win_is_valid(M.status_win) then
				return
			end
			-- Switch to normal mode
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, true, true), 'n', true)
			-- Set buffer as read-only
			vim.bo[buf].modifiable = false
			vim.bo[buf].readonly = true
			-- Set keymaps
			setup_status_buffer_keymaps(buf)
		end
	})
end

-- Function to close the status window
local function close_status_window()
	if M.status_win and vim.api.nvim_win_is_valid(M.status_win) then
		vim.api.nvim_win_close(M.status_win, true)
		M.status_win = nil
		M.status_buf = nil
	end
end

-- Function to refresh the status window
local function refresh_status()
	if M.status_win and vim.api.nvim_win_is_valid(M.status_win) then
		-- Remember the window ID
		local win_id = M.status_win
		-- Create a new buffer
		local new_buf = vim.api.nvim_create_buf(false, true)
		-- Set the buffer in the window
		vim.api.nvim_win_set_buf(win_id, new_buf)
		-- Update the buffer reference
		M.status_buf = new_buf
		-- Run jj st again
		vim.fn.termopen("jj st", {
			on_exit = function()
				-- Check if window still exists
				if not vim.api.nvim_win_is_valid(win_id) then
					return
				end
				-- Switch to normal mode
				vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, true, true), 'n', true)
				-- Set buffer as read-only
				vim.bo[new_buf].modifiable = false
				vim.bo[new_buf].readonly = true
				-- Set keymaps
				setup_status_buffer_keymaps(new_buf)
			end
		})
	else
		-- If window doesn't exist, create a new one
		show_status()
	end
end

-- Execute a jj command and refresh log if necessary
local function execute_jj_command(command, change_id, success_message, refresh_log)
	-- Run the command
	local result = vim.fn.system(command)

	-- Show success message if provided
	if success_message then
		vim.api.nvim_echo({ { success_message, "Normal" } }, false, {})
	end

	-- Refresh the log content if requested and we're in the log buffer
	if refresh_log and M.log_win and vim.api.nvim_win_is_valid(M.log_win) then
		refresh_log_buffer(M.log_win)
	end
end

-- Function to edit change with jj edit command
local function edit_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = extract_change_id(line)

	if change_id then
		execute_jj_command(
			"jj edit " .. change_id,
			change_id,
			"Applied edit to change " .. change_id,
			true
		)
	else
		print("No change ID found on this line")
	end
end

-- Function to abandon a change
local function abandon_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = extract_change_id(line)

	if change_id then
		-- Ask for confirmation before abandoning
		vim.ui.select(
			{ "Yes", "No" },
			{
				prompt = "Are you sure you want to abandon change " .. change_id .. "?",
			},
			function(choice)
				if choice == "Yes" then
					execute_jj_command(
						"jj abandon " .. change_id,
						change_id,
						"Abandoned change " .. change_id,
						true
					)
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
	local change_id = extract_change_id(line)

	if change_id then
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
					execute_jj_command(
						cmd,
						change_id,
						"Updated description for change " .. change_id,
						true
					)
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
	local change_id = extract_change_id(line)

	local prompt_text = change_id
			and "Description for new change based on " .. change_id .. ": "
			or "Description for new change: "

	vim.ui.input(
		{
			prompt = prompt_text,
			default = "",
			completion = "file", -- This gives a decent sized input box
		},
		function(input)
			-- If user didn't provide description, use empty string
			local description = input or ""

			-- Run the new command, optionally with a description
			local cmd
			if change_id then
				if description ~= "" then
					cmd = "jj new " .. change_id .. " -m " .. vim.fn.shellescape(description)
				else
					cmd = "jj new " .. change_id
				end
				execute_jj_command(
					cmd,
					change_id,
					"Created new change based on " .. change_id,
					true
				)
			else
				if description ~= "" then
					cmd = "jj new -m " .. vim.fn.shellescape(description)
				else
					cmd = "jj new"
				end
				execute_jj_command(
					cmd,
					nil,
					"Created new change",
					true
				)
			end
		end
	)
end

-- *** New Functions for Enhanced Log Features ***

-- Function to set the log limit
function M.set_log_limit()
	vim.ui.input(
		{
			prompt = "Enter log limit (leave blank for no limit): ",
			default = M.log_settings.limit,
		},
		function(input)
			if input == nil then
				-- User cancelled
				return
			end

			-- Update the limit
			M.log_settings.limit = input

			-- Refresh the log if it's open
			if M.log_win and vim.api.nvim_win_is_valid(M.log_win) then
				refresh_log_buffer(M.log_win)
			end

			-- Show feedback message
			if input == "" then
				vim.api.nvim_echo({ { "Log limit cleared", "Normal" } }, false, {})
			else
				vim.api.nvim_echo({ { "Log limit set to " .. input .. " entries", "Normal" } }, false, {})
			end
		end
	)
end

-- Common revset templates to choose from
local revset_templates = {
	{ name = "Default",                    value = "" },
	{ name = "All commits",                value = "::" },
	{ name = "Current change ancestors",   value = "::@" },
	{ name = "Current change descendants", value = "@::" },
	{ name = "Recent commits (last 10)",   value = "::@ & arg:1",                 description = "Ancestors of @ limited to 10" },
	{ name = "Current branch only",        value = "(master..@):: | (master..@)-" },
	{ name = "Modified files",             value = "file:",                       description = "Uses files() function to filter by path" },
	{ name = "Custom revset",              value = "CUSTOM" }
}

-- Function to set a revset filter
function M.set_revset_filter()
	-- Extract the names for the select menu
	local options = {}
	for _, template in ipairs(revset_templates) do
		table.insert(options, template.name)
	end

	vim.ui.select(
		options,
		{
			prompt = "Select a revset filter:",
		},
		function(choice)
			if not choice then
				-- User cancelled
				return
			end

			-- Find the selected template
			local selected
			for _, template in ipairs(revset_templates) do
				if template.name == choice then
					selected = template
					break
				end
			end

			-- Handle custom revset
			if selected.value == "CUSTOM" then
				vim.ui.input(
					{
						prompt = "Enter custom revset: ",
						default = M.log_settings.revset,
					},
					function(input)
						if input then
							M.log_settings.revset = input
							vim.api.nvim_echo({ { "Custom revset set to: " .. input, "Normal" } }, false, {})

							-- Refresh the log if it's open
							if M.log_win and vim.api.nvim_win_is_valid(M.log_win) then
								refresh_log_buffer(M.log_win)
							end
						end
					end
				)
				return
			end

			-- Handle recent commits with a limit
			if selected.value:find("arg:") then
				vim.ui.input(
					{
						prompt = "Enter number of commits to show: ",
						default = "10",
					},
					function(input)
						if input and tonumber(input) then
							local revset = selected.value:gsub("arg:1", tonumber(input))
							M.log_settings.revset = revset
							vim.api.nvim_echo({ { "Revset set to show " .. input .. " recent commits", "Normal" } }, false, {})

							-- Refresh the log if it's open
							if M.log_win and vim.api.nvim_win_is_valid(M.log_win) then
								refresh_log_buffer(M.log_win)
							end
						else
							vim.api.nvim_echo({ { "Invalid number, revset not changed", "WarningMsg" } }, false, {})
						end
					end
				)
				return
			end

			-- Handle file: revset with a path
			if selected.value == "file:" then
				vim.ui.input(
					{
						prompt = "Enter file path (leave blank for current file): ",
						default = "",
					},
					function(input)
						local path
						if input == "" then
							-- Use current buffer's file path
							path = vim.fn.expand("%:p")
							if path == "" then
								vim.api.nvim_echo({ { "No file in current buffer", "WarningMsg" } }, false, {})
								return
							end

							-- Get relative path to repo root
							local repo_root = vim.fn.system("jj root"):gsub("%s+$", "")
							path = path:gsub(repo_root .. "/", "")
						else
							path = input
						end

						-- Use the files() function correctly
						-- The files() function filters commits that modify the given path
						-- It handles directories and file paths properly, matching subdirectories too
						M.log_settings.revset = "files(" .. vim.fn.shellescape(path) .. ")"
						vim.api.nvim_echo({ { "Revset set to show commits affecting: " .. path, "Normal" } }, false, {})

						-- Refresh the log if it's open
						if M.log_win and vim.api.nvim_win_is_valid(M.log_win) then
							refresh_log_buffer(M.log_win)
						end
					end
				)
				return
			end

			-- Standard revset
			M.log_settings.revset = selected.value

			-- Show message
			if selected.value == "" then
				vim.api.nvim_echo({ { "Using default revset", "Normal" } }, false, {})
			else
				vim.api.nvim_echo({ { "Revset set to: " .. selected.value, "Normal" } }, false, {})
			end

			-- Refresh the log if it's open
			if M.log_win and vim.api.nvim_win_is_valid(M.log_win) then
				refresh_log_buffer(M.log_win)
			end
		end
	)
end

-- Function to search in log
function M.search_in_log()
	vim.ui.input(
		{
			prompt = "Search for text in log (diff_contains): ",
			default = M.log_settings.search_pattern,
		},
		function(input)
			if input == nil then
				-- User cancelled
				return
			end

			M.log_settings.search_pattern = input

			-- Show message
			if input == "" then
				vim.api.nvim_echo({ { "Search pattern cleared", "Normal" } }, false, {})
			else
				vim.api.nvim_echo({ { "Searching for: " .. input, "Normal" } }, false, {})
			end

			-- Refresh the log if it's open
			if M.log_win and vim.api.nvim_win_is_valid(M.log_win) then
				refresh_log_buffer(M.log_win)
			end
		end
	)
end

-- Template options
local template_options = {
	{ name = "Default",  value = "" },
	{ name = "Detailed", value = "builtin_log_detailed" },
	{ name = "Oneline",  value = "separate(' ', change_id.shortest(8), description.first_line())" },
	{ name = "Full",     value = "separate('\n', change_id, author, description)" },
	{ name = "Custom",   value = "CUSTOM" }
}

-- Function to change log template
function M.change_log_template()
	-- Extract the names for the select menu
	local options = {}
	for _, template in ipairs(template_options) do
		table.insert(options, template.name)
	end

	vim.ui.select(
		options,
		{
			prompt = "Select a log template:",
		},
		function(choice)
			if not choice then
				-- User cancelled
				return
			end

			-- Find the selected template
			local selected
			for _, template in ipairs(template_options) do
				if template.name == choice then
					selected = template
					break
				end
			end

			-- Handle custom template
			if selected.value == "CUSTOM" then
				vim.ui.input(
					{
						prompt = "Enter custom template: ",
						default = M.log_settings.template,
					},
					function(input)
						if input then
							M.log_settings.template = input
							vim.api.nvim_echo({ { "Custom template set", "Normal" } }, false, {})

							-- Refresh the log if it's open
							if M.log_win and vim.api.nvim_win_is_valid(M.log_win) then
								refresh_log_buffer(M.log_win)
							end
						end
					end
				)
				return
			end

			-- Standard template
			M.log_settings.template = selected.value

			-- Show message
			if selected.value == "" then
				vim.api.nvim_echo({ { "Using default template", "Normal" } }, false, {})
			else
				vim.api.nvim_echo({ { "Template set to: " .. selected.name, "Normal" } }, false, {})
			end

			-- Refresh the log if it's open
			if M.log_win and vim.api.nvim_win_is_valid(M.log_win) then
				refresh_log_buffer(M.log_win)
			end
		end
	)
end

-- Reset log settings to default
function M.reset_log_settings()
	M.log_settings = {
		limit = "",
		revset = "",
		template = "",
		search_pattern = ""
	}

	vim.api.nvim_echo({ { "Log settings reset to default", "Normal" } }, false, {})

	-- Refresh the log if it's open
	if M.log_win and vim.api.nvim_win_is_valid(M.log_win) then
		refresh_log_buffer(M.log_win)
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

	-- Run jj log with current settings
	refresh_log_buffer(M.log_win)
end

function M.setup()
	-- Changed to use 'j' namespace for global hotkeys
	vim.keymap.set('n', '<leader>jl', function()
		M.toggle_log_window()
	end)

	-- Added global mapping for showing status
	vim.keymap.set('n', '<leader>js', function()
		M.show_status()
	end)

	-- Add a mapping for resetting log settings
	vim.keymap.set('n', '<leader>jr', function()
		M.reset_log_settings()
	end)

	-- Add mapping for advanced log options
	vim.keymap.set('n', '<leader>jo', function()
		vim.ui.select(
			{
				"Set Limit",
				"Set Revset Filter",
				"Search in Log",
				"Change Template",
				"Reset Settings"
			},
			{
				prompt = "Select a log option:",
			},
			function(choice)
				if choice == "Set Limit" then
					M.set_log_limit()
				elseif choice == "Set Revset Filter" then
					M.set_revset_filter()
				elseif choice == "Search in Log" then
					M.search_in_log()
				elseif choice == "Change Template" then
					M.change_log_template()
				elseif choice == "Reset Settings" then
					M.reset_log_settings()
				end
			end
		)
	end)
end

M.edit_change = edit_change
M.describe_change = describe_change
M.new_change = new_change
M.abandon_change = abandon_change
M.show_status = show_status
M.close_status_window = close_status_window
M.refresh_status = refresh_status
return M
