-- lua/jujutsu/commands.lua
-- Functions that execute jj commands

local Commands = {}

local Utils = require("jujutsu.utils")

-- Reference to the main module (set via init) for state and calling refresh
local M_ref = nil

-- Execute a jj command and refresh log if necessary
-- Returns true on success, false on failure
-- (Unchanged)
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
		local error_text
		if err_output == nil then
			error_text = "(No error output captured)"
		elseif type(err_output) ~= "string" then
			error_text = "(Non-string error output: " .. type(err_output) .. ")"
		elseif err_output == "" then
			error_text = "(Empty error output, shell error: " .. vim.v.shell_error .. ")"
		else
			error_text = err_output
		end
		error_text = error_text:gsub("[\n\r]+$", "")
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

-- *** EXTENDED: Function to create a new change with additional options ***
-- Based on documentation and error messages, the correct syntax appears to be:
-- For simple creation: jj new [parent_change_id] [-m description]
-- For insert-after: jj new [-m description] --insert-after target_id
-- For insert-before: jj new [-m description] --insert-before target_id
function Commands.new_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = Utils.extract_change_id(line)

	-- Create a function to show the advanced options dialog
	local function show_advanced_options(description)
		vim.ui.select(
			{
				"Create simple change",
				"Insert before another change (select from list)",
				"Insert after another change (select from list)",
				"Insert before another change (select from log window)",
				"Insert after another change (select from log window)",
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
				elseif choice == "Insert before another change (select from list)" then
					-- Show a list of changes to select from
					-- Get a list of recent changes
					local function display_change_list_for_selection(callback)
						-- Run jj log to get a list of recent changes
						local cmd = "jj log -n 15 --no-graph"
						local changes = vim.fn.systemlist(cmd)
						if vim.v.shell_error ~= 0 or #changes == 0 then
							vim.api.nvim_echo({ { "Failed to get change list", "ErrorMsg" } }, true, {})
							return
						end

						-- Format changes for selection
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

					-- Show change selection UI
					display_change_list_for_selection(function(target_id)
						-- Command format: jj new [-m description] --insert-before target_id
						local cmd_parts = { "jj", "new" }

						-- Add description if provided
						if description ~= "" then
							table.insert(cmd_parts, "-m")
							table.insert(cmd_parts, description)
						end

						-- Add the insert-before flag and target
						table.insert(cmd_parts, "--insert-before")
						table.insert(cmd_parts, target_id)

						execute_jj_command(
							cmd_parts,
							"Created new change inserted before " .. target_id,
							true
						)
					end
					)
				elseif choice == "Insert after another change (select from list)" then
					-- Show a list of changes to select from
					-- Get a list of recent changes
					local function display_change_list_for_selection(callback)
						-- Run jj log to get a list of recent changes
						local cmd = "jj log -n 15 --no-graph -T '{change_id} {description.first_line()}'"
						local changes = vim.fn.systemlist(cmd)
						if vim.v.shell_error ~= 0 or #changes == 0 then
							vim.api.nvim_echo({ { "Failed to get change list: " .. vim.inspect(changes), "ErrorMsg" } }, true, {})
							return
						end

						-- Format changes for selection
						local options = {}
						local change_ids = {}
						for _, change_line in ipairs(changes) do
							local change_id, desc = change_line:match("([a-z0-9]+)%s+(.*)")
							if change_id then
								if not desc or desc == "" then
									desc = "(no description)"
								end
								table.insert(options, change_id .. " - " .. desc)
								table.insert(change_ids, change_id)
							end
						end

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

					-- Show change selection UI
					display_change_list_for_selection(function(target_id)
						-- Command format: jj new [-m description] --insert-after target_id
						local cmd_parts = { "jj", "new" }

						-- Add description if provided
						if description ~= "" then
							table.insert(cmd_parts, "-m")
							table.insert(cmd_parts, description)
						end

						-- Add the insert-after flag and target
						table.insert(cmd_parts, "--insert-after")
						table.insert(cmd_parts, target_id)

						execute_jj_command(
							cmd_parts,
							"Created new change inserted after " .. target_id,
							true
						)
					end
					)
				elseif choice == "Insert before another change (select from log window)" then
					-- Use log window to select a change
					select_from_log_window(function(target_id)
						if not target_id then
							return -- Selection cancelled or failed
						end

						-- Command format: jj new [-m description] --insert-before target_id
						local cmd_parts = { "jj", "new" }

						-- Add description if provided
						if description ~= "" then
							table.insert(cmd_parts, "-m")
							table.insert(cmd_parts, description)
						end

						-- Add the insert-before flag and target
						table.insert(cmd_parts, "--insert-before")
						table.insert(cmd_parts, target_id)

						execute_jj_command(
							cmd_parts,
							"Created new change inserted before " .. target_id,
							true
						)
					end)
				elseif choice == "Insert after another change (select from log window)" then
					-- Use log window to select a change
					select_from_log_window(function(target_id)
						if not target_id then
							return -- Selection cancelled or failed
						end

						-- Command format: jj new [-m description] --insert-after target_id
						local cmd_parts = { "jj", "new" }

						-- Add description if provided
						if description ~= "" then
							table.insert(cmd_parts, "-m")
							table.insert(cmd_parts, description)
						end

						-- Add the insert-after flag and target
						table.insert(cmd_parts, "--insert-after")
						table.insert(cmd_parts, target_id)

						execute_jj_command(
							cmd_parts,
							"Created new change inserted after " .. target_id,
							true
						)
					end)
				end
			end
		)
	end

	-- Helper function to select a change from log window
	local function select_from_log_window(callback)
		-- If the log window isn't open, open it first
		if not M_ref.log_win or not vim.api.nvim_win_is_valid(M_ref.log_win) then
			-- Save current window
			local current_win = vim.api.nvim_get_current_win()

			-- Open log window
			local log_module = require("jujutsu.log")
			log_module.toggle_log_window()

			-- Provide instructions
			vim.api.nvim_echo({
				{ "Select a change from log window, then press ", "Normal" },
				{ "Enter",                                        "Special" },
				{ " to confirm",                                  "Normal" }
			}, true, {})

			-- Set up a temporary mapping for Enter key in log window
			if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then
				local buf = vim.api.nvim_win_get_buf(M_ref.log_win)
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

			return -- Exit here, the callback will continue the flow
		else
			-- Log window is already open, just provide instructions
			vim.api.nvim_echo({
				{ "Select a change from log window, then press ", "Normal" },
				{ "Enter",                                        "Special" },
				{ " to confirm",                                  "Normal" }
			}, true, {})

			-- Set up a temporary mapping for Enter key in log window
			local buf = vim.api.nvim_win_get_buf(M_ref.log_win)
			local opts = { noremap = true, silent = true, buffer = buf }

			-- Store the original mapping if it exists
			local original_cr_mapping = vim.fn.maparg("<CR>", "n", false, true)

			-- Original window where command was initiated
			local current_win = vim.api.nvim_get_current_win()

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

-- *** MODIFIED: Function to run jj git push and display output via vim.notify ***
function Commands.git_push()
	local cmd_parts = { "jj", "git", "push" }
	local cmd_str = table.concat(cmd_parts, " ")

	-- Indicate start via notify (optional, can be removed)
	vim.notify("Running: " .. cmd_str .. "...", vim.log.levels.INFO, { title = "Jujutsu" })

	-- Run the command and capture combined stdout/stderr using systemlist
	local output_lines = vim.fn.systemlist(cmd_str .. " 2>&1")
	local shell_error_code = vim.v.shell_error
	local success = (shell_error_code == 0)

	-- Combine output lines into a single string for notify message body
	local output_string = table.concat(output_lines, "\n")
	output_string = output_string:gsub("[\n\r]+$", "") -- Trim trailing newline

	if success then
		-- Command succeeded
		local message
		if output_string ~= "" then
			message = output_string
		else
			message = "jj git push completed successfully (no output)."
		end
		-- Display success output as INFO level notification
		vim.notify(message, vim.log.levels.INFO, { title = "jj git push" })

		-- Refresh log on success
		if M_ref and M_ref.refresh_log then
			M_ref.refresh_log()
		end
	else
		-- Command failed
		local error_message
		if output_string ~= "" then
			error_message = output_string
		else
			error_message = "(No error output captured, shell error: " .. shell_error_code .. ")"
		end
		-- Display failure output as ERROR level notification
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
		if name ~= nil and name ~= "" then
			execute_jj_command({ "jj", "bookmark", "create", name, "-r", change_id },
				"Bookmark '" .. name .. "' created at " .. change_id, true)
		elseif name == "" then
			vim.api.nvim_echo({ { "Bookmark creation cancelled: Name cannot be empty.", "WarningMsg" } }, false, {})
		else
			vim.api.nvim_echo({ { "Bookmark creation cancelled.", "Normal" } }, false, {})
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
		if selected_name then
			vim.ui.select({ "Yes", "No" }, { prompt = "Delete bookmark '" .. selected_name .. "'?" }, function(choice)
				if choice == "Yes" then
					execute_jj_command({ "jj", "bookmark", "delete", selected_name }, "Bookmark '" .. selected_name .. "' deleted.",
						true)
				else
					vim.api.nvim_echo({ { "Bookmark deletion cancelled.", "Normal" } }, false, {})
				end
			end)
		else
			vim.api.nvim_echo({ { "Bookmark deletion cancelled.", "Normal" } }, false, {})
		end
	end)
end

function Commands.move_bookmark()
	local line = vim.api.nvim_get_current_line()
	local change_id = Utils.extract_change_id(line)
	if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line to move bookmark to.", "WarningMsg" } }, false, {}); return
	end
	local existing_bookmarks = get_bookmark_names() or {}
	vim.ui.input({
		prompt = "Bookmark name to create/move: ",
		completion = function(arg_lead)
			local matches = {}; for _, name in ipairs(existing_bookmarks) do
				if name:sub(1, #arg_lead) == arg_lead then
					table
							.insert(matches, name)
				end
			end; return matches
		end
	}, function(name)
		if name == nil then
			vim.api.nvim_echo({ { "Bookmark move cancelled.", "Normal" } }, false, {}); return
		end
		if name == "" then
			vim.api.nvim_echo({ { "Bookmark move cancelled: Name cannot be empty.", "WarningMsg" } }, false, {}); return
		end
		local cmd_parts_attempt1 = { "jj", "bookmark", "set", name, "-r", change_id }; local cmd_str_attempt1 = table.concat(
			cmd_parts_attempt1, " ")
		local output = vim.fn.system(cmd_str_attempt1 .. " 2>&1"); local shell_error_code = vim.v.shell_error; local success = (shell_error_code == 0)
		if success then
			vim.api.nvim_echo({ { "Bookmark '" .. name .. "' set to " .. change_id, "Normal" } }, false, {}); M_ref
					.refresh_log()
		else
			local backward_error_found = false
			if output and type(output) == "string" then if output:lower():find("refusing to move bookmark backwards", 1, true) then backward_error_found = true end end
			if backward_error_found then
				vim.ui.select({ "Yes", "No" }, { prompt = "Allow moving bookmark '" .. name .. "' backward?" }, function(choice)
					if choice == "Yes" then
						local cmd_parts_attempt2 = { "jj", "bookmark", "set", "--allow-backwards", name, "-r", change_id }; execute_jj_command(
							cmd_parts_attempt2, "Bookmark '" .. name .. "' set backward to " .. change_id, true)
					else
						vim.api.nvim_echo({ { "Bookmark move cancelled.", "Normal" } }, false, {})
					end
				end)
			else
				local msg_chunks = { { "Error executing: ", "ErrorMsg" }, { cmd_str_attempt1 .. "\n", "Code" } }; local error_text
				if output == nil then
					error_text = "(No error output captured)"
				elseif type(output) ~= "string" then
					error_text = "(Non-string error output: " .. type(output) .. ")"
				elseif output == "" then
					error_text = "(Empty error output, shell error code: " .. shell_error_code .. ")"
				else
					error_text = output
				end; error_text = error_text:gsub("[\n\r]+$", ""); table.insert(msg_chunks, { error_text, "ErrorMsg" }); vim.api
						.nvim_echo(msg_chunks, true, {})
			end
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
				if input ~= nil and input ~= "" then
					execute_jj_command({ "jj", "commit", "-m", input }, "Committed change with message: " .. input, true)
				else
					if input == "" then
						vim.api.nvim_echo({ { "Commit cancelled: Empty message not allowed.", "WarningMsg" } }, false, {})
					else
						vim.api.nvim_echo({ { "Commit cancelled", "Normal" } }, false, {})
					end
				end
			end)
	end
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


return Commands
