-- lua/jujutsu/commands.lua
-- Functions that execute jj commands

local Commands = {}

local Utils = require("jujutsu.utils")

-- Reference to the main module (set via init) for state and calling refresh
---@class JujutsuMainRef
---@field log_win number|nil
---@field log_buf number|nil
---@field status_win number|nil
---@field status_buf number|nil
---@field refresh_log function|nil
local M_ref = nil

-- Helper function to format error output
local function format_error_output(output, shell_error_code)
	local error_text
	if output == nil then
		error_text = "(No error output captured)"
	elseif type(output) ~= "string" then
		error_text = "(Non-string error output: " .. type(output) .. ")"
	elseif output == "" then
		error_text = "(Empty error output, shell error code: " .. shell_error_code .. ")"
	else
		error_text = output
	end
	return error_text:gsub("[\n\r]+$", "")
end


-- Execute a jj command and refresh log if necessary
-- Returns true on success, false on failure
local function execute_jj_command(command_parts, success_message, refresh_log)
	if type(command_parts) ~= "table" then
		vim.api.nvim_echo({ { "Internal Error: execute_jj_command requires a table.", "ErrorMsg" } }, true, {})
		return false -- Indicate failure
	end
	local command_str = table.concat(command_parts, " ")
	vim.fn.system(command_parts) -- Execute silently
	if vim.v.shell_error ~= 0 then
		local err_output = vim.fn.system(command_str .. " 2>&1")
		local msg_chunks = { { "Error executing: ", "ErrorMsg" }, { (command_str or "<missing command>") .. "\n", "Code" } }
		local error_text = format_error_output(err_output, vim.v.shell_error)
		table.insert(msg_chunks, { error_text, "ErrorMsg" })
		vim.api.nvim_echo(msg_chunks, true, {})
		return false -- Indicate failure
	end
	if success_message then vim.api.nvim_echo({ { success_message, "Normal" } }, false, {}) end
	if refresh_log then
		if M_ref and M_ref.refresh_log then
			M_ref.refresh_log()
		else
			vim.api.nvim_echo(
				{ { "Internal Error: M_ref not initialized for refresh.", "ErrorMsg" } }, true, {})
		end
	end
	return true -- Indicate success
end

-- Helper function to get existing bookmark names
-- (Unchanged)
local function get_bookmark_names()
	local output = vim.fn.systemlist({ "jj", "bookmark", "list" })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({ { "Error getting bookmark list.", "ErrorMsg" } }, true, {}); return nil
	end
	local names = {}
	for _, line in ipairs(output) do
		local name = line:match("^([^:]+):")
		if name then table.insert(names, (name:gsub("%s+$", ""))) end -- Parentheses fix included
	end
	return names
end

-- Helper function to format changes for selection UI
local function format_changes_for_selection(changes)
	local options = {}
	local change_ids = {}
	for _, change_line in ipairs(changes) do
		local change_id = Utils.extract_change_id(change_line)
		if change_id then
			-- Get description (the part after email)
			local desc = change_line:match(".*@.-%.%w+%s+(.*)")
			if not desc or desc == "" then
				desc = "(no description)"
			end
			table.insert(options, change_id .. " - " .. desc)
			table.insert(change_ids, change_id)
		end
	end
	return options, change_ids
end

-- Helper function to get a list of changes for selection
local function display_change_list_for_selection(callback, limit)
	limit = limit or 15
	-- Run jj log to get a list of recent changes
	local cmd = "jj log -n " .. limit .. " --no-graph"
	local changes = vim.fn.systemlist(cmd)
	if vim.v.shell_error ~= 0 or #changes == 0 then
		vim.api.nvim_echo({ { "Failed to get change list", "ErrorMsg" } }, true, {})
		return
	end

	local options, change_ids = format_changes_for_selection(changes)
	-- Let user select a change
	vim.ui.select(options, {
		prompt = "Select target change:",
	}, function(choice, idx)
		if choice and idx and change_ids[idx] then
			callback(change_ids[idx])
		else
			vim.api.nvim_echo({ { "Change selection cancelled", "Normal" } }, false, {})
		end
	end)
end

-- Helper function to setup log window selection mapping
local function setup_log_selection_mapping(buf, current_win, callback)
	local opts = { noremap = true, silent = true, buffer = buf }

	-- Store the original mapping if it exists
	local original_cr_mapping = vim.fn.maparg("<CR>", "n", false, true)

	-- Set temporary mapping
	vim.keymap.set("n", "<CR>", function()
		-- Get the current line
		local line = vim.api.nvim_get_current_line()
		local selected_id = Utils.extract_change_id(line)

		-- Reset the mapping
		vim.keymap.del("n", "<CR>", { buffer = buf })

		-- Restore original mapping if it existed
		if original_cr_mapping and original_cr_mapping.buffer then
			local restore_cmd = original_cr_mapping.mode .. "map"
			if original_cr_mapping.noremap == 1 then
				restore_cmd = original_cr_mapping.mode .. "noremap"
			end
			if original_cr_mapping.silent == 1 then
				restore_cmd = restore_cmd .. " <silent>"
			end
			vim.cmd(restore_cmd .. " <buffer> " .. original_cr_mapping.lhs .. " " .. original_cr_mapping.rhs)
		end

		-- Return to the original window
		if vim.api.nvim_win_is_valid(current_win) then
			vim.api.nvim_set_current_win(current_win)
		end

		-- Call the callback with the selected ID
		if selected_id then
			callback(selected_id)
		else
			vim.api.nvim_echo({
				{ "No valid change ID found on that line", "WarningMsg" }
			}, false, {})
			callback(nil)
		end
	end, opts)
end

-- Helper function to select a change from log window
local function select_from_log_window(callback, prompt)
	-- If the log window isn't open, open it first
	if not M_ref.log_win or not vim.api.nvim_win_is_valid(M_ref.log_win) then
		-- Save current window
		local current_win = vim.api.nvim_get_current_win()

		-- Open log window
		local log_module = require("jujutsu.log")
		log_module.toggle_log_window()

		-- Provide instructions
		vim.api.nvim_echo({
			{ prompt or "Select a change from log window, then press ", "Normal" },
			{ "Enter",                                                  "Special" },
			{ " to confirm",                                            "Normal" }
		}, true, {})

		-- Set up a temporary mapping for Enter key in log window
		if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then
			local buf = vim.api.nvim_win_get_buf(M_ref.log_win)
			setup_log_selection_mapping(buf, current_win, callback)
		end

		return -- Exit here, the callback will continue the flow
	else
		-- Log window is already open, just provide instructions
		vim.api.nvim_echo({
			{ prompt or "Select a change from log window, then press ", "Normal" },
			{ "Enter",                                                  "Special" },
			{ " to confirm",                                            "Normal" }
		}, true, {})

		-- Set up a temporary mapping for Enter key in log window
		local buf = vim.api.nvim_win_get_buf(M_ref.log_win)
		local current_win = vim.api.nvim_get_current_win()
		setup_log_selection_mapping(buf, current_win, callback)
	end
end

-- *** EXTENDED: Function to create a new change with additional options ***
-- Based on documentation and error messages, the correct syntax appears to be:
-- For simple creation: jj new [parent_change_id] [-m description]
-- For insert-after: jj new [-m description] --insert-after target_id
-- For insert-before: jj new [-m description] --insert-before target_id
function Commands.new_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = Utils.extract_change_id(line)

	-- Helper function to create an insert change command
	local function create_insert_change(description, target_id, flag, position)
		local cmd_parts = { "jj", "new" }
		if description ~= "" then
			table.insert(cmd_parts, "-m")
			table.insert(cmd_parts, description)
		end
		table.insert(cmd_parts, flag)
		table.insert(cmd_parts, target_id)
		execute_jj_command(cmd_parts, "Created new change inserted " .. position .. " " .. target_id, true)
	end


	-- Create a function to show the advanced options dialog
	local function show_advanced_options(description)
		-- Create a temporary buffer for multi-select parent changes
		local function create_multi_select_buffer(callback)
			-- Get list of changes
			local cmd = "jj log -n 20 --no-graph"
			local changes = vim.fn.systemlist(cmd)
			if vim.v.shell_error ~= 0 or #changes == 0 then
				vim.api.nvim_echo({ { "Failed to get list of changes", "ErrorMsg" } }, true, {})
				return
			end

			local options, change_ids = format_changes_for_selection(changes)
			local buf = Utils.create_selection_buffer("Select Multiple Parents", options)
			local selected = {}
			for i = 1, #options do
				selected[i] = false
			end

			-- Create window for the buffer
			local win, current_win = Utils.open_selection_window(buf, options)

			-- Set mappings for the buffer
			local function toggle_selection()
				local line_nr = vim.api.nvim_win_get_cursor(win)[1]
				-- Ignore header lines
				if line_nr <= 5 then return end

				local option_idx = line_nr - 5
				if option_idx > #options then return end

				-- Toggle selection
				selected[option_idx] = not selected[option_idx]

				-- Update the line
				local marker = selected[option_idx] and "x" or " "
				local new_line = "[" .. marker .. "] " .. options[option_idx]
				vim.api.nvim_buf_set_lines(buf, line_nr - 1, line_nr, false, { new_line })
			end

			local function confirm_selection()
				-- Collect the selected options
				local result = {}
				for i, is_selected in ipairs(selected) do
					if is_selected then
						table.insert(result, change_ids[i])
					end
				end

				-- Close the window
				vim.api.nvim_win_close(win, true)

				-- Return to the original window
				if vim.api.nvim_win_is_valid(current_win) then
					vim.api.nvim_set_current_win(current_win)
				end

				-- Call the callback with the result
				callback(result)
			end

			local function cancel_selection()
				-- Close the window
				vim.api.nvim_win_close(win, true)

				-- Return to the original window
				if vim.api.nvim_win_is_valid(current_win) then
					vim.api.nvim_set_current_win(current_win)
				end

				-- Call the callback with an empty result
				callback({})
			end

			-- Set keymaps
			local opts = { noremap = true, silent = true, buffer = buf }
			vim.keymap.set('n', '<Space>', toggle_selection, opts)
			vim.keymap.set('n', '<CR>', confirm_selection, opts)
			vim.keymap.set('n', 'q', cancel_selection, opts)
			vim.keymap.set('n', '<Esc>', cancel_selection, opts)

			-- Set buffer local settings
			vim.api.nvim_win_set_option(win, 'cursorline', true)
			vim.api.nvim_set_current_buf(buf)
			vim.cmd('syntax match Comment /^#.*/')
			vim.cmd('syntax match Selected /\\[x\\]/')
			vim.cmd('highlight link Selected String')
		end

		vim.ui.select(
			{
				"Create simple change",
				"Create change with multiple parents",
				"Insert before another change",
				"Insert after another change",
				"Cancel"
			},
			{
				prompt = "Select new change placement option:",
			},
			function(choice)
				if choice == "Cancel" or choice == nil then
					vim.api.nvim_echo({ { "New change cancelled", "Normal" } }, false, {})
					return
				elseif choice == "Create simple change" then
					-- Standard behavior - create a change based on the current change or a new root change
					local cmd_parts = { "jj", "new" }
					local success_msg = "Created new change"

					if change_id then
						table.insert(cmd_parts, change_id)
						success_msg = "Created new change based on " .. change_id
					end

					if description ~= "" then
						table.insert(cmd_parts, "-m")
						table.insert(cmd_parts, description)
					end

					execute_jj_command(cmd_parts, success_msg, true)
				elseif choice == "Create change with multiple parents" then
					create_multi_select_buffer(function(result)
						if #result == 0 then
							vim.api.nvim_echo({ { "No parent changes selected - operation cancelled", "WarningMsg" } }, false, {})
							return
						end

						-- Construct the command
						local cmd_parts = { "jj", "new" }

						-- Add all selected parent IDs
						for _, parent_id in ipairs(result) do
							table.insert(cmd_parts, parent_id)
						end

						-- Add description if provided
						if description ~= "" then
							table.insert(cmd_parts, "-m")
							table.insert(cmd_parts, description)
						end

						-- Execute the command
						execute_jj_command(
							cmd_parts,
							"Created new change with " .. #result .. " parents",
							true
						)
					end)
				elseif choice == "Insert before another change" then
					-- Use log window to select a change
					select_from_log_window(function(target_id)
						if not target_id then
							return -- Selection cancelled or failed
						end
						create_insert_change(description, target_id, "--insert-before", "before")
					end)
				elseif choice == "Insert after another change" then
					-- Use log window to select a change
					select_from_log_window(function(target_id)
						if not target_id then
							return -- Selection cancelled or failed
						end
						create_insert_change(description, target_id, "--insert-after", "after")
					end)
				end
			end
		)
	end

	-- Start by asking for a description
	local prompt_text = change_id and ("Description for new change based on " .. change_id .. ": ") or
			"Description for new change: "
	vim.ui.input({
			prompt = prompt_text,
			default = "",
			completion = "file",
		},
		function(input)
			if input == nil then
				vim.api.nvim_echo({ { "New change cancelled", "Normal" } }, false, {})
				return
			end

			-- Show advanced options with the description
			show_advanced_options(input)
		end
	)
end

-- *** NEW: Function to rebase changes with support for different flag variations ***
-- Based on jj rebase command syntax:
-- - Single change: jj rebase -r <revision> -d <destination>
-- - Whole branch: jj rebase -b <branch> -d <destination>
-- - Change and descendants: jj rebase -s <source> -d <destination>
function Commands.rebase_change()
	local source_id
	if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then
		local line = vim.api.nvim_get_current_line()
		source_id = Utils.extract_change_id(line)
	end
	if not source_id then
		source_id = "@" -- Use current change if log window is not open or no ID found
		vim.api.nvim_echo({ { "Using current change for rebase.", "Normal" } }, false, {})
	end

	-- Step 1: Select the scope of the rebase
	vim.ui.select(
		{
			"Rebase single change",
			"Rebase whole branch",
			"Rebase change and descendants",
			"Cancel"
		},
		{
			prompt = "Select rebase scope for " .. source_id .. ":",
		},
		function(scope_choice)
			if scope_choice == "Cancel" or scope_choice == nil then
				vim.api.nvim_echo({ { "Rebase cancelled", "Normal" } }, false, {})
				return
			end

			local flag = ""
			if scope_choice == "Rebase single change" then
				flag = "-r"
			elseif scope_choice == "Rebase whole branch" then
				flag = "-b"
			elseif scope_choice == "Rebase change and descendants" then
				flag = "-s"
			end

			-- Helper function to execute the rebase command
			local function execute_rebase_command(source_id, dest_id, flag)
				local cmd_parts = { "jj", "rebase", flag, source_id, "-d", dest_id }
				local success_msg = "Rebased " .. source_id .. " onto " .. dest_id
				execute_jj_command(cmd_parts, success_msg, true)
			end

			-- Step 2: Select the destination (change or bookmark)
			vim.ui.select(
				{
					"Select change from log window",
					"Select bookmark",
					"Cancel"
				},
				{
					prompt = "Select destination for rebase:",
				},
				function(dest_choice)
					if dest_choice == "Cancel" or dest_choice == nil then
						vim.api.nvim_echo({ { "Rebase destination selection cancelled", "Normal" } }, false, {})
						return
					end

					if dest_choice == "Select change from log window" then
						select_from_log_window(function(dest_id)
							if not dest_id then
								vim.api.nvim_echo({ { "Rebase destination selection cancelled", "Normal" } }, false, {})
								return
							end
							execute_rebase_command(source_id, dest_id, flag)
						end, "Select destination change for rebase, then press ")
					elseif dest_choice == "Select bookmark" then
						local bookmark_names = get_bookmark_names() or {}
						if #bookmark_names == 0 then
							vim.api.nvim_echo({ { "No bookmarks found to rebase onto.", "WarningMsg" } }, false, {})
							return
						end
						vim.ui.select(bookmark_names, { prompt = "Select bookmark to rebase onto:" }, function(bookmark)
							if not bookmark then
								vim.api.nvim_echo({ { "Rebase destination selection cancelled", "Normal" } }, false, {})
								return
							end
							execute_rebase_command(source_id, bookmark, flag)
						end)
					end
				end
			)
		end
	)
end

-- Function to run jj git push and display output via vim.notify
function Commands.git_push()
	local cmd_parts = { "jj", "git", "push" }
	local cmd_str = table.concat(cmd_parts, " ")

	-- Indicate start via notify
	vim.notify("Running: " .. cmd_str .. "...", vim.log.levels.INFO, { title = "Jujutsu" })

	-- Run the command and capture combined stdout/stderr using systemlist
	local output_lines = vim.fn.systemlist(cmd_str .. " 2>&1")
	local shell_error_code = vim.v.shell_error
	local success = (shell_error_code == 0)

	-- Combine output lines into a single string for notify message body
	local output_string = table.concat(output_lines, "\n")
	output_string = output_string:gsub("[\n\r]+$", "") -- Trim trailing newline

	if success then
		local message = output_string ~= "" and output_string or "jj git push completed successfully (no output)."
		vim.notify(message, vim.log.levels.INFO, { title = "jj git push" })
		if M_ref and M_ref.refresh_log then
			M_ref.refresh_log()
		end
	else
		local error_message = output_string ~= "" and output_string or
				"(No error output captured, shell error: " .. shell_error_code .. ")"
		vim.notify(error_message, vim.log.levels.ERROR, { title = "jj git push Error" })
	end
end

-- Existing command functions (create_bookmark, delete_bookmark, move_bookmark, etc.)
-- ... (ensure they are present and correct) ...
function Commands.create_bookmark()
	local line = vim.api.nvim_get_current_line()
	local change_id = Utils.extract_change_id(line)
	if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line to bookmark.", "WarningMsg" } }, false, {}); return
	end
	vim.ui.input({ prompt = "Bookmark name to create: " }, function(name)
		if name == nil then
			vim.api.nvim_echo({ { "Bookmark creation cancelled.", "Normal" } }, false, {})
		elseif name == "" then
			vim.api.nvim_echo({ { "Bookmark creation cancelled: Name cannot be empty.", "WarningMsg" } }, false, {})
		else
			execute_jj_command({ "jj", "bookmark", "create", name, "-r", change_id },
				"Bookmark '" .. name .. "' created at " .. change_id, true)
		end
	end)
end

function Commands.delete_bookmark()
	local bookmark_names = get_bookmark_names()
	if bookmark_names == nil then return end
	if not bookmark_names or #bookmark_names == 0 then
		vim.api.nvim_echo({ { "No bookmarks found to delete.", "Normal" } }, false, {}); return
	end
	vim.ui.select(bookmark_names, { prompt = "Select bookmark to delete:" }, function(selected_name)
		if not selected_name then
			vim.api.nvim_echo({ { "Bookmark deletion cancelled.", "Normal" } }, false, {})
			return
		end
		vim.ui.select({ "Yes", "No" }, { prompt = "Delete bookmark '" .. selected_name .. "'?" }, function(choice)
			if choice == "Yes" then
				execute_jj_command({ "jj", "bookmark", "delete", selected_name }, "Bookmark '" .. selected_name .. "' deleted.",
					true)
			else
				vim.api.nvim_echo({ { "Bookmark deletion cancelled.", "Normal" } }, false, {})
			end
		end)
	end)
end

-- Helper function to move a bookmark to a specific change
local function move_bookmark_to_change(name, change_id)
	local cmd_parts_attempt1 = { "jj", "bookmark", "set", name, "-r", change_id }
	local cmd_str_attempt1 = table.concat(cmd_parts_attempt1, " ")
	local output = vim.fn.system(cmd_str_attempt1 .. " 2>&1")
	local shell_error_code = vim.v.shell_error
	local success = (shell_error_code == 0)
	if success then
		vim.api.nvim_echo({ { "Bookmark '" .. name .. "' set to " .. change_id, "Normal" } }, false, {})
		M_ref.refresh_log()
	else
		local backward_error_found = false
		if output and type(output) == "string" then
			if output:lower():find("refusing to move bookmark backwards", 1, true) then
				backward_error_found = true
			end
		end
		if backward_error_found then
			vim.ui.select({ "Yes", "No" }, { prompt = "Allow moving bookmark '" .. name .. "' backward?" }, function(choice)
				if choice == "Yes" then
					local cmd_parts_attempt2 = { "jj", "bookmark", "set", "--allow-backwards", name, "-r", change_id }
					execute_jj_command(cmd_parts_attempt2, "Bookmark '" .. name .. "' set backward to " .. change_id, true)
				else
					vim.api.nvim_echo({ { "Bookmark move cancelled.", "Normal" } }, false, {})
				end
			end)
		else
			local msg_chunks = { { "Error executing: ", "ErrorMsg" }, { cmd_str_attempt1 .. "\n", "Code" } }
			local error_text = format_error_output(output, shell_error_code)
			table.insert(msg_chunks, { error_text, "ErrorMsg" })
			vim.api.nvim_echo(msg_chunks, true, {})
		end
	end
end

function Commands.move_bookmark()
	local line = vim.api.nvim_get_current_line()
	local change_id = Utils.extract_change_id(line)
	if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line to move bookmark to.", "WarningMsg" } }, false, {}); return
	end
	local existing_bookmarks = get_bookmark_names() or {}
	local options = {}
	for _, name in ipairs(existing_bookmarks) do
		table.insert(options, name)
	end
	table.insert(options, "Create new bookmark...")

	vim.ui.select(options, { prompt = "Select bookmark to move or create new:" }, function(selected)
		if not selected then
			vim.api.nvim_echo({ { "Bookmark move cancelled.", "Normal" } }, false, {}); return
		end
		if selected == "Create new bookmark..." then
			vim.ui.input({ prompt = "New bookmark name: " }, function(name)
				if name == nil then
					vim.api.nvim_echo({ { "Bookmark creation cancelled.", "Normal" } }, false, {}); return
				end
				if name == "" then
					vim.api.nvim_echo({ { "Bookmark move cancelled: Name cannot be empty.", "WarningMsg" } }, false, {}); return
				end
				move_bookmark_to_change(name, change_id)
			end)
		else
			move_bookmark_to_change(selected, change_id)
		end
	end)
end

function Commands.edit_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = Utils.extract_change_id(line)
	if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line", "WarningMsg" } }, false, {}); return
	end
	execute_jj_command({ "jj", "edit", change_id }, "Applied edit to change " .. change_id, true)
end

function Commands.abandon_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = Utils.extract_change_id(line)
	if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line", "WarningMsg" } }, false, {}); return
	end
	vim.ui.select({ "Yes", "No" }, { prompt = "Are you sure you want to abandon change " .. change_id .. "?", },
		function(choice)
			if choice == "Yes" then
				execute_jj_command({ "jj", "abandon", change_id }, "Abandoned change " .. change_id, true)
			else
				vim.api.nvim_echo({ { "Abandon cancelled", "Normal" } }, false, {})
			end
		end)
end

function Commands.describe_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = Utils.extract_change_id(line)
	if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line", "WarningMsg" } }, false, {}); return
	end
	local description_cmd = { "jj", "log", "-r", change_id, "--no-graph", "-T", "description" }
	local description = vim.fn.system(description_cmd)
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({ { "Error getting description for " .. change_id .. ". Does it exist?", "ErrorMsg" } }, true, {}); return
	end
	description = description:gsub("^%s*(.-)%s*$", "%1")
	vim.ui.input({ prompt = "Description for " .. change_id .. ": ", default = description, completion = "file", },
		function(input)
			if input ~= nil then
				execute_jj_command({ "jj", "describe", change_id, "-m", input }, "Updated description for change " .. change_id,
					true)
			else
				vim.api.nvim_echo({ { "Description edit cancelled", "Normal" } }, false, {})
			end
		end)
end

function Commands.split_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = Utils.extract_change_id(line)
	if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line to split.", "WarningMsg" } }, false, {}); return
	end

	-- Open a terminal buffer for the split TUI
	vim.cmd("belowright new")
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_name(buf, "JJ Split TUI")
	vim.fn.termopen("jj split " .. change_id, {
		on_exit = function(_, code)
			if code == 0 then
				vim.api.nvim_echo({ { "Change " .. change_id .. " split successfully", "Normal" } }, false, {})
				if M_ref and M_ref.refresh_log then
					M_ref.refresh_log()
				end
			else
				vim.api.nvim_echo({ { "Error splitting change " .. change_id, "ErrorMsg" } }, true, {})
			end
		end
	})
	-- Start insert mode in the terminal
	vim.cmd("startinsert")
end

function Commands.commit_change()
	local desc_cmd = { "jj", "log", "-r", "@", "--no-graph", "-T", "description" }
	local current_description = vim.fn.system(desc_cmd)
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({ { "Error getting current description. Are you at a valid change?", "ErrorMsg" } }, true, {}); return
	end
	current_description = current_description:gsub("^%s*(.-)%s*$", "%1")
	if current_description ~= "" and current_description:lower() ~= "(no description set)" then
		execute_jj_command({ "jj", "commit" }, "Committed change with existing message", true)
	else
		vim.ui.input({ prompt = "Commit message: ", default = "", completion = "file", },
			function(input)
				if input == nil then
					vim.api.nvim_echo({ { "Commit cancelled", "Normal" } }, false, {})
				elseif input == "" then
					vim.api.nvim_echo({ { "Commit cancelled: Empty message not allowed.", "WarningMsg" } }, false, {})
				else
					execute_jj_command({ "jj", "commit", "-m", input }, "Committed change with message: " .. input, true)
				end
			end)
	end
end

-- Function to rebase current branch onto master
function Commands.rebase_onto_master()
	local cmd_parts = { "jj", "rebase", "-b", "@", "-d", "master" }
	local success_msg = "Rebased current branch onto master"
	execute_jj_command(cmd_parts, success_msg, true)
end

-- Initialize the module with a reference to the main state/module
function Commands.init(main_module_ref)
	M_ref = main_module_ref
end

-- Expose functions (including git_push)
Commands.create_bookmark = Commands.create_bookmark
Commands.delete_bookmark = Commands.delete_bookmark
Commands.move_bookmark = Commands.move_bookmark
Commands.git_push = Commands.git_push
Commands.edit_change = Commands.edit_change
Commands.abandon_change = Commands.abandon_change
Commands.describe_change = Commands.describe_change
Commands.new_change = Commands.new_change
Commands.commit_change = Commands.commit_change
Commands.split_change = Commands.split_change
Commands.rebase_onto_master = Commands.rebase_onto_master


return Commands
