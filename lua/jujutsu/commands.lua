-- lua/jujutsu/commands.lua
-- Functions that execute jj commands

local Commands = {}

local Utils = require("jujutsu.utils")

-- Reference to the main module (set via init) for state and calling refresh
local M_ref = nil

-- Execute a jj command and refresh log if necessary
-- (Unchanged)
local function execute_jj_command(command_parts, success_message, refresh_log)
	if type(command_parts) ~= "table" then
		vim.api.nvim_echo({ { "Internal Error: execute_jj_command requires a table.", "ErrorMsg" } }, true, {}); return false
	end
	local command_str = table.concat(command_parts, " "); vim.fn.system(command_parts)
	if vim.v.shell_error ~= 0 then
		local err_output = vim.fn.system(command_str .. " 2>&1"); local msg_chunks = { { "Error executing: ", "ErrorMsg" }, { (command_str or "<missing command>") .. "\n", "Code" } }
		local error_text; if err_output == nil then
			error_text = "(No error output captured)"
		elseif type(err_output) ~= "string" then
			error_text =
					"(Non-string error output: " .. type(err_output) .. ")"
		elseif err_output == "" then
			error_text =
					"(Empty error output, shell error: " .. vim.v.shell_error .. ")"
		else
			error_text = err_output
		end
		error_text = error_text:gsub("[\n\r]+$", ""); table.insert(msg_chunks, { error_text, "ErrorMsg" }); vim.api
				.nvim_echo(msg_chunks, true, {}); return false
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
	return true
end

-- Helper function to get existing bookmark names
-- (Unchanged)
local function get_bookmark_names()
	local output = vim.fn.systemlist({ "jj", "bookmark", "list" }); if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({ { "Error getting bookmark list.", "ErrorMsg" } }, true, {}); return nil
	end
	local names = {}; for _, line in ipairs(output) do
		local name = line:match("^([^:]+):"); if name then table.insert(names, (name:gsub("%s+$", ""))) end
	end; return names
end

-- Function to run jj git push and display output via vim.notify
-- (Unchanged)
function Commands.git_push()
	local cmd_parts = { "jj", "git", "push" }; local cmd_str = table.concat(cmd_parts, " ")
	vim.notify("Running: " .. cmd_str .. "...", vim.log.levels.INFO, { title = "Jujutsu" })
	local output_lines = vim.fn.systemlist(cmd_str .. " 2>&1"); local shell_error_code = vim.v.shell_error; local success = (shell_error_code == 0)
	local output_string = table.concat(output_lines, "\n"); output_string = output_string:gsub("[\n\r]+$", "")
	if success then
		local message; if output_string ~= "" then
			message = output_string
		else
			message =
			"jj git push completed successfully (no output)."
		end
		vim.notify(message, vim.log.levels.INFO, { title = "jj git push" }); if M_ref and M_ref.refresh_log then
			M_ref
					.refresh_log()
		end
	else
		local error_message; if output_string ~= "" then
			error_message = output_string
		else
			error_message =
					"(No error output captured, shell error: " .. shell_error_code .. ")"
		end
		vim.notify(error_message, vim.log.levels.ERROR, { title = "jj git push Error" })
	end
end

-- *** NEW: Function to start an interactive squash session ***
function Commands.squash_interactive()
	-- Open a terminal buffer running the interactive command
	-- This allows jj to take over for the interactive session
	vim.cmd('terminal jj squash -i')
	-- Inform the user they might need to refresh manually
	vim.notify("Started interactive squash. Refresh log (R) when done.", vim.log.levels.INFO, { title = "Jujutsu" })
	-- We don't automatically refresh here as the operation is interactive.
end

-- Existing command functions (create_bookmark, delete_bookmark, move_bookmark, etc.)
-- ... (ensure they are present and correct) ...
function Commands.create_bookmark()
	local line = vim.api.nvim_get_current_line(); local change_id = Utils.extract_change_id(line)
	if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line to bookmark.", "WarningMsg" } }, false, {}); return
	end
	vim.ui.input({ prompt = "Bookmark name to create: " },
		function(name)
			if name ~= nil and name ~= "" then
				execute_jj_command(
					{ "jj", "bookmark", "create", name, "-r", change_id }, "Bookmark '" .. name .. "' created at " .. change_id,
					true)
			elseif name == "" then
				vim.api.nvim_echo({ { "Bookmark creation cancelled: Name cannot be empty.", "WarningMsg" } }, false, {})
			else
				vim
						.api.nvim_echo({ { "Bookmark creation cancelled.", "Normal" } }, false, {})
			end
		end)
end

function Commands.delete_bookmark()
	local bookmark_names = get_bookmark_names(); if bookmark_names == nil then return end; if not bookmark_names or #bookmark_names == 0 then
		vim.api.nvim_echo({ { "No bookmarks found to delete.", "Normal" } }, false, {}); return
	end
	vim.ui.select(bookmark_names, { prompt = "Select bookmark to delete:" },
		function(selected_name)
			if selected_name then
				vim.ui.select({ "Yes", "No" },
					{ prompt = "Delete bookmark '" .. selected_name .. "'?" },
					function(choice)
						if choice == "Yes" then
							execute_jj_command({ "jj", "bookmark", "delete", selected_name },
								"Bookmark '" .. selected_name .. "' deleted.", true)
						else
							vim.api.nvim_echo(
								{ { "Bookmark deletion cancelled.", "Normal" } }, false, {})
						end
					end)
			else
				vim.api.nvim_echo(
					{ { "Bookmark deletion cancelled.", "Normal" } }, false, {})
			end
		end)
end

function Commands.move_bookmark()
	local line = vim.api.nvim_get_current_line(); local change_id = Utils.extract_change_id(line)
	if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line to move bookmark to.", "WarningMsg" } }, false, {}); return
	end
	local existing_bookmarks = get_bookmark_names() or {}
	vim.ui.input(
		{
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
			end; if name == "" then
				vim.api.nvim_echo({ { "Bookmark move cancelled: Name cannot be empty.", "WarningMsg" } }, false, {}); return
			end
			local cmd_parts_attempt1 = { "jj", "bookmark", "set", name, "-r", change_id }; local cmd_str_attempt1 = table
					.concat(
						cmd_parts_attempt1, " "); local output = vim.fn.system(cmd_str_attempt1 .. " 2>&1"); local shell_error_code =
					vim
					.v
					.shell_error; local success = (shell_error_code == 0)
			if success then
				vim.api.nvim_echo({ { "Bookmark '" .. name .. "' set to " .. change_id, "Normal" } }, false, {}); M_ref
						.refresh_log()
			else
				local backward_error_found = false; if output and type(output) == "string" then if output:lower():find("refusing to move bookmark backwards", 1, true) then backward_error_found = true end end
				if backward_error_found then
					vim.ui.select({ "Yes", "No" }, { prompt = "Allow moving bookmark '" .. name .. "' backward?" },
						function(choice)
							if choice == "Yes" then
								local cmd_parts_attempt2 = { "jj", "bookmark", "set", "--allow-backwards", name, "-r", change_id }; execute_jj_command(
									cmd_parts_attempt2, "Bookmark '" .. name .. "' set backward to " .. change_id, true)
							else
								vim.api.nvim_echo({ { "Bookmark move cancelled.", "Normal" } }, false, {})
							end
						end)
				else
					local msg_chunks = { { "Error executing: ", "ErrorMsg" }, { cmd_str_attempt1 .. "\n", "Code" } }; local error_text; if output == nil then
						error_text =
						"(No error output captured)"
					elseif type(output) ~= "string" then
						error_text = "(Non-string error output: " ..
								type(output) .. ")"
					elseif output == "" then
						error_text = "(Empty error output, shell error code: " ..
								shell_error_code .. ")"
					else
						error_text = output
					end; error_text = error_text:gsub("[\n\r]+$", ""); table
							.insert(msg_chunks, { error_text, "ErrorMsg" }); vim.api.nvim_echo(msg_chunks, true, {})
				end
			end
		end)
end

function Commands.edit_change()
	local line = vim.api.nvim_get_current_line(); local change_id = Utils.extract_change_id(line); if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line", "WarningMsg" } }, false, {}); return
	end; execute_jj_command({ "jj", "edit", change_id }, "Applied edit to change " .. change_id, true)
end

function Commands.abandon_change()
	local line = vim.api.nvim_get_current_line(); local change_id = Utils.extract_change_id(line); if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line", "WarningMsg" } }, false, {}); return
	end; vim.ui.select({ "Yes", "No" }, { prompt = "Are you sure you want to abandon change " .. change_id .. "?", },
		function(choice)
			if choice == "Yes" then
				execute_jj_command({ "jj", "abandon", change_id },
					"Abandoned change " .. change_id, true)
			else
				vim.api.nvim_echo({ { "Abandon cancelled", "Normal" } }, false, {})
			end
		end)
end

function Commands.describe_change()
	local line = vim.api.nvim_get_current_line(); local change_id = Utils.extract_change_id(line); if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line", "WarningMsg" } }, false, {}); return
	end; local description_cmd = { "jj", "log", "-r", change_id, "--no-graph", "-T", "description" }; local description =
			vim.fn.system(description_cmd); if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({ { "Error getting description for " .. change_id .. ". Does it exist?", "ErrorMsg" } }, true, {}); return
	end; description = description:gsub("^%s*(.-)%s*$", "%1"); vim.ui.input(
		{ prompt = "Description for " .. change_id .. ": ", default = description, completion = "file", },
		function(input)
			if input ~= nil then
				execute_jj_command({ "jj", "describe", change_id, "-m", input },
					"Updated description for change " .. change_id, true)
			else
				vim.api.nvim_echo(
					{ { "Description edit cancelled", "Normal" } }, false, {})
			end
		end)
end

function Commands.new_change()
	local line = vim.api.nvim_get_current_line(); local change_id = Utils.extract_change_id(line); local prompt_text =
			change_id and ("Description for new change based on " .. change_id .. ": ") or "Description for new change: "; vim
			.ui
			.input({ prompt = prompt_text, default = "", completion = "file", },
				function(input)
					if input == nil then
						vim.api.nvim_echo({ { "New change cancelled", "Normal" } }, false, {}); return
					end; local description = input; local cmd_parts = { "jj", "new" }; local success_msg = "Created new change"; if change_id then
						table.insert(cmd_parts, change_id); success_msg = "Created new change based on " .. change_id
					end; if description ~= "" then
						table.insert(cmd_parts, "-m"); table.insert(cmd_parts, description)
					end; execute_jj_command(cmd_parts, success_msg, true)
				end)
end

function Commands.commit_change()
	local desc_cmd = { "jj", "log", "-r", "@", "--no-graph", "-T", "description" }; local current_description = vim.fn
			.system(desc_cmd); if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({ { "Error getting current description. Are you at a valid change?", "ErrorMsg" } }, true, {}); return
	end; current_description = current_description:gsub("^%s*(.-)%s*$", "%1"); if current_description ~= "" and current_description:lower() ~= "(no description set)" then
		execute_jj_command({ "jj", "commit" }, "Committed change with existing message", true)
	else
		vim.ui.input(
			{ prompt = "Commit message: ", default = "", completion = "file", },
			function(input)
				if input ~= nil and input ~= "" then
					execute_jj_command({ "jj", "commit", "-m", input },
						"Committed change with message: " .. input, true)
				else
					if input == "" then
						vim.api.nvim_echo(
							{ { "Commit cancelled: Empty message not allowed.", "WarningMsg" } }, false, {})
					else
						vim.api.nvim_echo(
							{ { "Commit cancelled", "Normal" } }, false, {})
					end
				end
			end)
	end
end

-- Initialize the module with a reference to the main state/module
function Commands.init(main_module_ref)
	M_ref = main_module_ref
end

-- Expose functions
Commands.create_bookmark = Commands.create_bookmark
Commands.delete_bookmark = Commands.delete_bookmark
Commands.move_bookmark = Commands.move_bookmark
Commands.git_push = Commands.git_push
Commands.edit_change = Commands.edit_change
Commands.abandon_change = Commands.abandon_change
Commands.describe_change = Commands.describe_change
Commands.new_change = Commands.new_change
Commands.commit_change = Commands.commit_change
-- *** NEW: Expose squash_interactive ***
Commands.squash_interactive = Commands.squash_interactive


return Commands
