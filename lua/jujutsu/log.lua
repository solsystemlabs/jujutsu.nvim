-- lua/jujutsu/log.lua
-- Log window management, keymaps, and advanced features

local Log = {}

local Utils = require("jujutsu.utils")
-- Reference to the main module's state (set via init)
---@class JujutsuMainRef
---@field log_win number|nil
---@field log_buf number|nil
---@field status_win number|nil
---@field status_buf number|nil
---@field refresh_log function|nil
---@field log_settings table
local M_ref = nil
Log.help_win_id = nil -- For the help window

-- Define the keymaps specific to the log window for the help display
local log_keymaps_info = {
	{ key = "?",  desc = "Toggle keymap help" },
	{ key = "q",  desc = "Close log window" },
	{ key = "j",  desc = "Jump to next change" },
	{ key = "k",  desc = "Jump to previous change" },
	{ key = "e",  desc = "Edit current change (jj edit)" },
	{ key = "d",  desc = "Edit change description (jj describe)" },
	{ key = "n",  desc = "Create new change (jj new)" },
	{ key = "a",  desc = "Abandon change (jj abandon)" },
	{ key = "c",  desc = "Commit current change (jj commit)" },
	{ key = "s",  desc = "Show status window (jj st)" },
	{ key = "l",  desc = "Set log entry limit (-n)" },
	{ key = "r",  desc = "Set revset filter (-r)" },
	{ key = "f",  desc = "Search in log (diff_contains)" },
	{ key = "T",  desc = "Change log template (-T)" },
	{ key = "bc", desc = "[B]ookmark [C]reate at current change" },
	{ key = "bd", desc = "[B]ookmark [D]elete..." },
	{ key = "bm", desc = "[B]ookmark [M]ove (set) to current change" },
	{ key = "p",  desc = "Push changes (jj git push)" },
	{ key = "rb", desc = "[R]e[B]ase change" },
	{ key = "Vsp", desc = "[S]plit change" },
}

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

-- Function to close the help window (if open)
function Log.close_help_window()
	if Log.help_win_id and vim.api.nvim_win_is_valid(Log.help_win_id) then vim.api.nvim_win_close(Log.help_win_id, true) end
	Log.help_win_id = nil
end

-- Function to toggle the help window display
function Log.toggle_help_window()
	if Log.help_win_id and vim.api.nvim_win_is_valid(Log.help_win_id) then
		Log.close_help_window(); return
	end
	local help_content = { " Jujutsu Log Keymaps ", "-----------------------" }
	local max_key_len = 0
	for _, map_info in ipairs(log_keymaps_info) do max_key_len = math.max(max_key_len, #map_info.key) end
	for _, map_info in ipairs(log_keymaps_info) do
		local key_padding = string.rep(" ", max_key_len - #map_info.key)
		table.insert(help_content, string.format("  %s%s : %s", map_info.key, key_padding, map_info.desc))
	end
	table.insert(help_content, "-----------------------"); table.insert(help_content,
		" Press 'q' or '<Esc>' to close this help window.")
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, help_content)
	vim.api.nvim_buf_set_option(buf, 'readonly', true); vim.api.nvim_buf_set_option(buf, 'modifiable', false)
	vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile'); vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe'); vim.api
			.nvim_buf_set_option(buf, 'swapfile', false)
	local content_width = 0; for _, line in ipairs(help_content) do
		content_width = math.max(content_width,
			vim.fn.strdisplaywidth(line))
	end
	local width = math.max(40, math.min(content_width + 4, vim.o.columns - 4)); local height = math.min(#help_content,
		vim.o.lines - 4)
	local row = math.floor((vim.o.lines - height) / 2); local col = math.floor((vim.o.columns - width) / 2)
	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		row = row,
		col = col,
		style = "minimal",
		border =
		"rounded"
	}
	local win_id = vim.api.nvim_open_win(buf, true, win_opts)
	if not win_id or not vim.api.nvim_win_is_valid(win_id) then
		vim.api.nvim_echo({ { "Failed to open help window.", "ErrorMsg" } }, true, {}); vim.api.nvim_buf_delete(buf,
			{ force = true }); return
	end
	Log.help_win_id = win_id
	local keymap_opts = { noremap = true, silent = true, buffer = buf }
	vim.keymap.set('n', 'q', ':lua require("jujutsu.log").close_help_window()<CR>', keymap_opts)
	vim.keymap.set('n', '<Esc>', ':lua require("jujutsu.log").close_help_window()<CR>', keymap_opts)
end

-- Helper function to set keymaps for log buffer
local function setup_log_buffer_keymaps(buf)
	local opts = { noremap = true, silent = true }
	local function map(key, cmd, desc)
		vim.api.nvim_buf_set_keymap(buf, 'n', key, cmd,
			vim.tbl_extend('keep', { desc = desc }, opts))
	end

	-- Apply mappings
	map('?', ':lua require("jujutsu.log").toggle_help_window()<CR>', "Toggle keymap help")
	map('q', ':lua require("jujutsu").toggle_log_window()<CR>', "Close log window")
	map('j', ':lua require("jujutsu").jump_next_change()<CR>', "Jump to next change")
	map('k', ':lua require("jujutsu").jump_prev_change()<CR>', "Jump to previous change")
	map('e', ':lua require("jujutsu").edit_change()<CR>', "Edit current change")
	map('d', ':lua require("jujutsu").describe_change()<CR>', "Edit change description")
	map('n', ':lua require("jujutsu").new_change()<CR>', "Create new change")
	map('a', ':lua require("jujutsu").abandon_change()<CR>', "Abandon change")
	map('s', ':lua require("jujutsu").show_status()<CR>', "Show status")
	map('l', ':lua require("jujutsu").set_log_limit()<CR>', "Set log entry limit")
	map('r', ':lua require("jujutsu").set_revset_filter()<CR>', "Set revset filter")
	map('f', ':lua require("jujutsu").search_in_log()<CR>', "Search in log")
	map('T', ':lua require("jujutsu").change_log_template()<CR>', "Change log template")
	map('c', ':lua require("jujutsu").commit_change()<CR>', "Commit current change")
	map('bc', ':lua require("jujutsu").create_bookmark()<CR>', "[B]ookmark [C]reate at current change")
	map('bd', ':lua require("jujutsu").delete_bookmark()<CR>', "[B]ookmark [D]elete...")
	map('bm', ':lua require("jujutsu").move_bookmark()<CR>', "[B]ookmark [M]ove (set) to current change")
	map('p', ':lua require("jujutsu").git_push()<CR>', "Push changes (jj git push)")
	map('rb', ':lua require("jujutsu").rebase_change()<CR>', "[R]e[B]ase change")
	map('SVsp', ':lua require("jujutsu").split_change()<CR>', "[S]plit change")
end

-- Helper function to refresh log buffer with jj log and the current settings
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

	-- Set the name directly on the buffer object
	vim.api.nvim_buf_set_name(new_buf, "JJ Log Viewer")

	-- Set useful options for a log buffer
	vim.bo[new_buf].buftype = "nofile" -- Not related to a file on disk
	vim.bo[new_buf].bufhidden = "hide" -- Unload buffer when hidden (avoids multiple listed buffers)
	vim.bo[new_buf].swapfile = false  -- No swap file needed
	-- Set filetype for potential syntax highlighting if desired (optional)
	-- vim.bo[new_buf].filetype = "git" -- or a custom 'jjlog' filetype

	-- Set this newly named buffer into the target window
	vim.api.nvim_win_set_buf(win_id, new_buf)
	-- Update the state AFTER successfully setting the buffer
	M_ref.log_buf = new_buf

	-- Build the command parts...
	local cmd_parts = { "jj", "log" }
	local revset_parts = {}
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
			-- Use the buffer ID stored in M_ref, as it's the definitive one after setting
			local current_log_buf = M_ref.log_buf
			if not current_log_buf or not vim.api.nvim_buf_is_valid(current_log_buf) then
				-- If the buffer we intended to use is gone, clear state
				if M_ref.log_buf == current_log_buf then M_ref.log_buf = nil end
				return
			end

			-- Terminal finished, set buffer to read-only etc.
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, true, true), 'n', true)
			-- Options need to be set on the specific buffer 'current_log_buf'
			vim.bo[current_log_buf].modifiable = false
			vim.bo[current_log_buf].readonly = true
			setup_log_buffer_keymaps(current_log_buf)
		end
	})
end

-- Find the next line with a change ID
local function find_next_change_line(direction)
	local cursor_pos = vim.api.nvim_win_get_cursor(0) -- Returns {row, col} table
	if not cursor_pos then return end                -- Should not happen in a valid window
	local current_line = cursor_pos[1]
	local line_count = vim.api.nvim_buf_line_count(0)
	local found_line = nil

	-- Loop logic...
	if direction == "next" then
		for i = current_line + 1, line_count do
			local lines = vim.api.nvim_buf_get_lines(0, i - 1, i, false) -- Returns list
			if lines and #lines > 0 and Utils.extract_change_id(lines[1]) then
				found_line = i
				break
			end
		end
		if not found_line then
			for i = 1, current_line - 1 do
				local lines = vim.api.nvim_buf_get_lines(0, i - 1, i, false)
				if lines and #lines > 0 and Utils.extract_change_id(lines[1]) then
					found_line = i
					break
				end
			end
		end
	else -- direction == "prev"
		for i = current_line - 1, 1, -1 do
			local lines = vim.api.nvim_buf_get_lines(0, i - 1, i, false)
			if lines and #lines > 0 and Utils.extract_change_id(lines[1]) then
				found_line = i
				break
			end
		end
		if not found_line then
			for i = line_count, current_line + 1, -1 do
				local lines = vim.api.nvim_buf_get_lines(0, i - 1, i, false)
				if lines and #lines > 0 and Utils.extract_change_id(lines[1]) then
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
			-- Check if user cancelled (input is nil)
			if input == nil then
				vim.api.nvim_echo({ { "Set limit cancelled.", "Normal" } }, false, {})
				return
			end

			-- Validate input is empty or a number
			local limit_num = tonumber(input)
			if input ~= "" and not limit_num then
				vim.api.nvim_echo({ { "Invalid limit: Must be a number or blank.", "ErrorMsg" } }, false, {})
				return
			end
			-- Optional: Check if positive? The jj command might handle negatives.
			-- if limit_num and limit_num <= 0 then ... end

			M_ref.log_settings.limit = input -- Store the original string input

			if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then
				Log.refresh_log_buffer()
			end

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
			-- Check if user cancelled (choice is nil)
			if not choice then
				vim.api.nvim_echo({ { "Set revset cancelled.", "Normal" } }, false, {})
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

			-- Should always find a match if choice is not nil, but check defensively
			if not selected then
				vim.api.nvim_echo({ { "Internal error: Could not find selected revset.", "ErrorMsg" } }, true, {})
				return
			end

			-- Handle custom revset
			if selected.value == "CUSTOM" then
				vim.ui.input(
					{
						prompt = "Enter custom revset: ",
						default = M_ref.log_settings.revset,
					},
					function(input)
						-- Check for cancellation
						if input ~= nil then
							M_ref.log_settings.revset = input
							vim.api.nvim_echo({ { "Custom revset set to: " .. (input == "" and "<empty>" or input), "Normal" } }, false,
								{})

							-- Refresh the log if it's open
							if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then Log.refresh_log_buffer() end
						else
							vim.api.nvim_echo({ { "Custom revset cancelled.", "Normal" } }, false, {})
						end
					end
				)
				return -- Exit after starting input UI
			end

			-- Handle recent commits with a limit
			if selected.value:find("arg:") then
				vim.ui.input(
					{
						prompt = "Enter number of commits to show: ",
						default = "10",
					},
					function(input)
						-- Check for cancellation
						if input == nil then
							vim.api.nvim_echo({ { "Recent commits count cancelled.", "Normal" } }, false, {})
							return
						end
						local num = tonumber(input)
						if num and num > 0 then -- Ensure it's a positive number
							local revset = selected.value:gsub("arg:1", num)
							M_ref.log_settings.revset = revset
							vim.api.nvim_echo({ { "Revset set to show " .. input .. " recent commits", "Normal" } }, false, {})

							-- Refresh the log if it's open
							if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then Log.refresh_log_buffer() end
						else
							vim.api.nvim_echo({ { "Invalid number, revset not changed", "WarningMsg" } }, false, {})
						end
					end
				)
				return -- Exit after starting input UI
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
						-- Check for cancellation
						if input == nil then
							vim.api.nvim_echo({ { "File path input cancelled.", "Normal" } }, false, {})
							return
						end

						local path
						if input == "" then
							-- Use current buffer's file path
							path = vim.fn.expand("%:p")
							if path == "" then
								vim.api.nvim_echo({ { "No file in current buffer", "WarningMsg" } }, false, {})
								return
							end

							-- Get relative path to repo root safely
							local repo_root_cmd_out = vim.fn.system({ "jj", "root" })
							if vim.v.shell_error ~= 0 then
								vim.api.nvim_echo({ { "Failed to get jj repo root. Is jj installed and in a jj repo?", "ErrorMsg" } },
									true, {})
								return
							end
							local repo_root = repo_root_cmd_out:gsub("%s+$", "") -- Trim trailing newline/space
							if repo_root == "" then
								vim.api.nvim_echo({ { "Failed to determine jj repo root.", "ErrorMsg" } }, true, {})
								return
							end
							-- Make sure paths use forward slashes for consistency
							path = path:gsub("\\", "/")
							repo_root = repo_root:gsub("\\", "/")
							-- Ensure trailing slash on repo_root for correct substitution
							if not repo_root:find("/$") then repo_root = repo_root .. "/" end
							path = path:gsub(repo_root, "", 1) -- Use gsub with count 1 for safety
						else
							path = input
						end

						-- Use the files() function correctly
						M_ref.log_settings.revset = "files(" .. vim.fn.shellescape(path) .. ")"
						vim.api.nvim_echo({ { "Revset set to show commits affecting: " .. path, "Normal" } }, false, {})

						-- Refresh the log if it's open
						if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then Log.refresh_log_buffer() end
					end
				)
				return -- Exit after starting input UI
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
			if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then Log.refresh_log_buffer() end
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
			-- Check for cancellation
			if input == nil then
				vim.api.nvim_echo({ { "Search cancelled.", "Normal" } }, false, {})
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
			if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then Log.refresh_log_buffer() end
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
			-- Check for cancellation
			if not choice then
				vim.api.nvim_echo({ { "Change template cancelled.", "Normal" } }, false, {})
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

			if not selected then return end -- Should not happen

			-- Handle custom template
			if selected.value == "CUSTOM" then
				vim.ui.input(
					{
						prompt = "Enter custom template: ",
						default = M_ref.log_settings.template,
					},
					function(input)
						-- Check for cancellation
						if input ~= nil then
							M_ref.log_settings.template = input
							vim.api.nvim_echo({ { "Custom template set", "Normal" } }, false, {})

							-- Refresh the log if it's open
							if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then Log.refresh_log_buffer() end
						else
							vim.api.nvim_echo({ { "Custom template cancelled.", "Normal" } }, false, {})
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
			if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then Log.refresh_log_buffer() end
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
	if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then Log.refresh_log_buffer() end
end

function Log.jump_next_change() find_next_change_line("next") end

function Log.jump_prev_change() find_next_change_line("prev") end

function Log.toggle_log_window()
	-- Check if window is already open and valid
	if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then
		-- Close the window
		vim.api.nvim_win_close(M_ref.log_win, true)
		-- Clear state
		M_ref.log_win = nil
		M_ref.log_buf = nil
		-- Also close the help window if it happens to be open
		Log.close_help_window()
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

	-- Set window options if needed (like size)
	vim.cmd("vertical resize 80")

	-- Call refresh_log_buffer, which will now:
	-- 1. Create the actual content buffer
	-- 2. Set its name to "JJ Log Viewer" using nvim_buf_set_name
	-- 3. Set the buffer into the window M_ref.log_win
	-- 4. Update M_ref.log_buf
	-- 5. Run termopen and set keymaps upon exit
	Log.refresh_log_buffer()
end

-- Initialize the module with a reference to the main state
function Log.init(main_module_ref)
	M_ref = main_module_ref
end

-- *** ADDED: Expose the new help functions ***
Log.toggle_help_window = Log.toggle_help_window
Log.close_help_window = Log.close_help_window


return Log
