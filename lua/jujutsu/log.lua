-- lua/jujutsu/log.lua
-- Log window management, keymaps, and advanced features

local Log = {}

local Utils = require("jujutsu.utils")

-- Reference to the main module's state (set via init)
local M_ref = nil

-- Common revset templates to choose from
local revset_templates = {
	{ name = "Default",                    value = "" },
	{ name = "All commits",                value = "::" },
	{ name = "Current change ancestors",   value = "::@" },
	{ name = "Current change descendants", value = "@::" },
	{ name = "Recent commits (last 10)",   value = "::@ & limit(arg:1)",      description = "Ancestors of @ limited to 10" }, -- Corrected revset using limit()
	{ name = "Current branch only",        value = "(main..@):: | (main..@)-" },
	{ name = "Modified files",             value = "file:",                   description = "Uses files() function to filter by path" },
	{ name = "Custom revset",              value = "CUSTOM" }
}

-- Template options
local template_options = {
	{ name = "Default",  value = "" },
	{ name = "Detailed", value = "builtin_log_detailed" },
	{ name = "Oneline",  value = "separate(' ', change_id.shortest(8), description.first_line())" },
	{ name = "Full",     value = "separate('\\n', change_id, author, description)" }, -- Escaped newline
	{ name = "Custom",   value = "CUSTOM" }
}

-- Helper function to set keymaps for log buffer
local function setup_log_buffer_keymaps(buf)
	vim.api.nvim_buf_set_keymap(buf, 'n', 'e', ':lua require("jujutsu").edit_change()<CR>',
		{ noremap = true, silent = true, desc = "Edit current change" })
	vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':lua require("jujutsu").toggle_log_window()<CR>',
		{ noremap = true, silent = true, desc = "Close log window" })
	vim.api.nvim_buf_set_keymap(buf, 'n', 'j', ':lua require("jujutsu").jump_next_change()<CR>',
		{ noremap = true, silent = true, desc = "Jump to next change" })
	vim.api.nvim_buf_set_keymap(buf, 'n', 'k', ':lua require("jujutsu").jump_prev_change()<CR>',
		{ noremap = true, silent = true, desc = "Jump to previous change" })
	vim.api.nvim_buf_set_keymap(buf, 'n', 'd', ':lua require("jujutsu").describe_change()<CR>',
		{ noremap = true, silent = true, desc = "Edit change description" })
	vim.api.nvim_buf_set_keymap(buf, 'n', 'n', ':lua require("jujutsu").new_change()<CR>',
		{ noremap = true, silent = true, desc = "Create new change" })
	vim.api.nvim_buf_set_keymap(buf, 'n', 'a', ':lua require("jujutsu").abandon_change()<CR>',
		{ noremap = true, silent = true, desc = "Abandon change" })
	vim.api.nvim_buf_set_keymap(buf, 'n', 's', ':lua require("jujutsu").show_status()<CR>',
		{ noremap = true, silent = true, desc = "Show status" })
	-- Add new mappings for enhanced log features
	vim.api.nvim_buf_set_keymap(buf, 'n', 'l', ':lua require("jujutsu").set_log_limit()<CR>',
		{ noremap = true, silent = true, desc = "Set log entry limit" })
	vim.api.nvim_buf_set_keymap(buf, 'n', 'r', ':lua require("jujutsu").set_revset_filter()<CR>',
		{ noremap = true, silent = true, desc = "Set revset filter" })
	vim.api.nvim_buf_set_keymap(buf, 'n', 'f', ':lua require("jujutsu").search_in_log()<CR>',
		{ noremap = true, silent = true, desc = "Search in log" })
	vim.api.nvim_buf_set_keymap(buf, 'n', 'T', ':lua require("jujutsu").change_log_template()<CR>',
		{ noremap = true, silent = true, desc = "Change log template" })
	-- Add commit command mapping
	vim.api.nvim_buf_set_keymap(buf, 'n', 'c', ':lua require("jujutsu").commit_change()<CR>',
		{ noremap = true, silent = true, desc = "Commit current change" })
end

-- Helper function to refresh log buffer with jj log and the current settings
-- Assumes M_ref.log_win is valid when called
function Log.refresh_log_buffer()
	local win_id = M_ref.log_win
	-- Added validity check at the start for robustness
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		vim.api.nvim_echo({ { "Error: Log.refresh_log_buffer called with invalid win_id", "ErrorMsg" } }, true, {})
		-- Clear state if it matches the invalid window
		if M_ref.log_win == win_id then
			M_ref.log_win = nil; M_ref.log_buf = nil
		end
		return
	end

	-- Create the buffer that will hold the log content
	local new_buf = vim.api.nvim_create_buf(false, true) -- false=not listed, true=scratch

	-- *** ADDED/MODIFIED LINES START ***
	-- Set the name directly on the buffer object
	vim.api.nvim_buf_set_name(new_buf, "JJ Log Viewer")

	-- Set useful options for a log buffer
	vim.bo[new_buf].buftype = "nofile" -- Not related to a file on disk
	vim.bo[new_buf].bufhidden = "hide" -- Unload buffer when hidden (avoids multiple listed buffers)
	vim.bo[new_buf].swapfile = false  -- No swap file needed
	-- Set filetype for potential syntax highlighting if desired (optional)
	-- vim.bo[new_buf].filetype = "git" -- or a custom 'jjlog' filetype
	-- *** ADDED/MODIFIED LINES END ***

	-- Set this newly named buffer into the target window
	vim.api.nvim_win_set_buf(win_id, new_buf)
	-- Update the state AFTER successfully setting the buffer
	M_ref.log_buf = new_buf

	-- Build the command parts...
	local cmd_parts = { "jj", "log" }
	local revset_parts = {}
	-- ... (rest of command building logic is unchanged) ...
	if M_ref.log_settings.revset ~= "" then table.insert(revset_parts, "(" .. M_ref.log_settings.revset .. ")") end
	if M_ref.log_settings.search_pattern ~= "" then
		table.insert(revset_parts,
			"diff_contains(" .. vim.fn.shellescape(M_ref.log_settings.search_pattern) .. ")")
	end
	if #revset_parts > 0 then
		table.insert(cmd_parts, "-r"); table.insert(cmd_parts, vim.fn.shellescape(table.concat(revset_parts, " & ")))
	end
	local limit_num = tonumber(M_ref.log_settings.limit)
	if limit_num and limit_num > 0 then
		table.insert(cmd_parts, "-n"); table.insert(cmd_parts, M_ref.log_settings.limit)
	end
	if M_ref.log_settings.template ~= "" then
		table.insert(cmd_parts, "-T"); table.insert(cmd_parts, vim.fn.shellescape(M_ref.log_settings.template))
	end
	local final_cmd = table.concat(cmd_parts, " ")


	-- Run the terminal command in the buffer
	vim.fn.termopen(final_cmd, {
		on_exit = function()
			-- Check if window (win_id) and buffer (new_buf) are still valid
			if not vim.api.nvim_win_is_valid(win_id) then
				if M_ref.log_win == win_id then
					M_ref.log_win = nil; M_ref.log_buf = nil
				end
				return
			end
			if not vim.api.nvim_buf_is_valid(new_buf) then
				if M_ref.log_buf == new_buf then M_ref.log_buf = nil end -- Clear state if buffer changed/deleted
				return
			end

			-- Terminal finished, set buffer to read-only etc.
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, true, true), 'n', true)
			-- Options need to be set on the specific buffer 'new_buf'
			vim.bo[new_buf].modifiable = false
			vim.bo[new_buf].readonly = true
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
			if Utils.extract_change_id(line) then
				found_line = i
				break
			end
		end

		-- Wrap around to the beginning if no match found
		if not found_line then
			for i = 1, current_line - 1 do
				local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
				if Utils.extract_change_id(line) then
					found_line = i
					break
				end
			end
		end
	else -- direction == "prev"
		-- Search upward from current line
		for i = current_line - 1, 1, -1 do
			local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
			if Utils.extract_change_id(line) then
				found_line = i
				break
			end
		end

		-- Wrap around to the end if no match found
		if not found_line then
			for i = line_count, current_line + 1, -1 do
				local line = vim.api.nvim_buf_get_lines(0, i - 1, i, false)[1]
				if Utils.extract_change_id(line) then
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

-- Function to set the log limit
function Log.set_log_limit()
	vim.ui.input(
		{
			prompt = "Enter log limit (leave blank for no limit): ",
			default = M_ref.log_settings.limit,
		},
		function(input)
			if input == nil then
				-- User cancelled
				return
			end

			-- Validate input is empty or a number
			if input ~= "" and not tonumber(input) then
				vim.api.nvim_echo({ { "Invalid limit: Must be a number or blank.", "ErrorMsg" } }, false, {})
				return
			end

			-- Update the limit
			M_ref.log_settings.limit = input

			-- Refresh the log if it's open
			if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then
				Log.refresh_log_buffer()
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

-- Function to set a revset filter
function Log.set_revset_filter()
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

			if not selected then return end -- Should not happen

			-- Handle custom revset
			if selected.value == "CUSTOM" then
				vim.ui.input(
					{
						prompt = "Enter custom revset: ",
						default = M_ref.log_settings.revset,
					},
					function(input)
						if input ~= nil then -- Allow empty string to clear custom
							M_ref.log_settings.revset = input
							vim.api.nvim_echo({ { "Custom revset set to: " .. (input == "" and "<empty>" or input), "Normal" } }, false,
								{})

							-- Refresh the log if it's open
							if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then
								Log.refresh_log_buffer()
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
						if input and tonumber(input) and tonumber(input) > 0 then
							local revset = selected.value:gsub("arg:1", tonumber(input))
							M_ref.log_settings.revset = revset
							vim.api.nvim_echo({ { "Revset set to show " .. input .. " recent commits", "Normal" } }, false, {})

							-- Refresh the log if it's open
							if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then
								Log.refresh_log_buffer()
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
						completion = "file",
					},
					function(input)
						if input == nil then return end -- Cancelled

						local path
						if input == "" then
							-- Use current buffer's file path
							path = vim.fn.expand("%:p")
							if path == "" then
								vim.api.nvim_echo({ { "No file in current buffer", "WarningMsg" } }, false, {})
								return
							end

							-- Get relative path to repo root
							local repo_root_cmd = vim.fn.system({ "jj", "root" })
							if vim.v.shell_error ~= 0 then
								vim.api.nvim_echo({ { "Failed to get jj repo root", "ErrorMsg" } }, false, {})
								return
							end
							local repo_root = repo_root_cmd:gsub("%s+$", "") -- Trim trailing newline
							-- Make sure paths use forward slashes for consistency
							path = path:gsub("\\", "/")
							repo_root = repo_root:gsub("\\", "/")
							path = path:gsub(repo_root .. "/", "")
						else
							path = input
						end

						-- Use the files() function correctly
						M_ref.log_settings.revset = "files(" .. vim.fn.shellescape(path) .. ")"
						vim.api.nvim_echo({ { "Revset set to show commits affecting: " .. path, "Normal" } }, false, {})

						-- Refresh the log if it's open
						if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then
							Log.refresh_log_buffer()
						end
					end
				)
				return
			end

			-- Standard revset
			M_ref.log_settings.revset = selected.value

			-- Show message
			if selected.value == "" then
				vim.api.nvim_echo({ { "Using default revset", "Normal" } }, false, {})
			else
				vim.api.nvim_echo({ { "Revset set to: " .. selected.name, "Normal" } }, false, {}) -- Use name for clarity
			end

			-- Refresh the log if it's open
			if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then
				Log.refresh_log_buffer()
			end
		end
	)
end

-- Function to search in log
function Log.search_in_log()
	vim.ui.input(
		{
			prompt = "Search for text in log (diff_contains): ",
			default = M_ref.log_settings.search_pattern,
		},
		function(input)
			if input == nil then
				-- User cancelled
				return
			end

			M_ref.log_settings.search_pattern = input

			-- Show message
			if input == "" then
				vim.api.nvim_echo({ { "Search pattern cleared", "Normal" } }, false, {})
			else
				vim.api.nvim_echo({ { "Searching for: " .. input, "Normal" } }, false, {})
			end

			-- Refresh the log if it's open
			if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then
				Log.refresh_log_buffer()
			end
		end
	)
end

-- Function to change log template
function Log.change_log_template()
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

			if not selected then return end

			-- Handle custom template
			if selected.value == "CUSTOM" then
				vim.ui.input(
					{
						prompt = "Enter custom template: ",
						default = M_ref.log_settings.template,
					},
					function(input)
						if input ~= nil then -- Allow empty to clear
							M_ref.log_settings.template = input
							vim.api.nvim_echo({ { "Custom template set", "Normal" } }, false, {})

							-- Refresh the log if it's open
							if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then
								Log.refresh_log_buffer()
							end
						end
					end
				)
				return
			end

			-- Standard template
			M_ref.log_settings.template = selected.value

			-- Show message
			if selected.value == "" then
				vim.api.nvim_echo({ { "Using default template", "Normal" } }, false, {})
			else
				vim.api.nvim_echo({ { "Template set to: " .. selected.name, "Normal" } }, false, {})
			end

			-- Refresh the log if it's open
			if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then
				Log.refresh_log_buffer()
			end
		end
	)
end

-- Reset log settings to default
function Log.reset_log_settings()
	M_ref.log_settings = {
		limit = "",
		revset = "",
		template = "",
		search_pattern = ""
	}

	vim.api.nvim_echo({ { "Log settings reset to default", "Normal" } }, false, {})

	-- Refresh the log if it's open
	if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then
		Log.refresh_log_buffer()
	end
end

function Log.jump_next_change()
	find_next_change_line("next")
end

function Log.jump_prev_change()
	find_next_change_line("prev")
end

function Log.toggle_log_window()
	-- Check if window is already open and valid
	if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then
		-- Close the window
		vim.api.nvim_win_close(M_ref.log_win, true)
		-- Clear state
		M_ref.log_win = nil
		M_ref.log_buf = nil
		-- Note: The buffer might still exist if bufhidden=hide, but won't cause E95
		return
	end

	-- Create a new vertical split window
	vim.cmd("botright vsplit")
	M_ref.log_win = vim.api.nvim_get_current_win() -- Get the new window's ID

	-- Check if window creation failed
	if not M_ref.log_win or not vim.api.nvim_win_is_valid(M_ref.log_win) then
		vim.api.nvim_echo({ { "Failed to create split window.", "ErrorMsg" } }, true, {})
		M_ref.log_win = nil -- Reset state
		return
	end

	-- *** REMOVED THIS LINE ***
	-- vim.cmd("file JJ\\ Log\\ Viewer") -- This caused the E95 error

	-- Set window options if needed (like size)
	vim.cmd("vertical resize 80")

	-- Call refresh_log_buffer, which will now:
	-- 1. Create the actual content buffer
	-- 2. Set its name to "JJ Log Viewer" using nvim_buf_set_name
	-- 3. Set the buffer into the window M_ref.log_win
	-- 4. Update M_ref.log_buf
	-- 5. Run termopen
	Log.refresh_log_buffer()
end

-- Initialize the module with a reference to the main state
function Log.init(main_module_ref)
	M_ref = main_module_ref
end

return Log
