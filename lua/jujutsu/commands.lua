-- lua/jujutsu/commands.lua
-- Functions that execute jj commands

local Commands = {}

local Utils = require("jujutsu.utils")

-- Reference to the main module (set via init) for state and calling refresh
local M_ref = nil

-- Execute a jj command and refresh log if necessary
-- Now calls M_ref.refresh_log which delegates to the Log module
local function execute_jj_command(command_parts, success_message, refresh_log)
	if type(command_parts) ~= "table" then
		vim.api.nvim_echo({ { "Internal Error: execute_jj_command requires a table.", "ErrorMsg" } }, true, {})
		return
	end

	local command_str = table.concat(command_parts, " ")
	-- Execute silently first
	vim.fn.system(command_parts)

	if vim.v.shell_error ~= 0 then
		-- Error occurred, try to capture stderr
		local err_output = vim.fn.system(command_str .. " 2>&1")

		-- Safely build the message chunks for nvim_echo
		local msg_chunks = {
			{ "Error executing: ",                          "ErrorMsg" },
			{ (command_str or "<missing command>") .. "\n", "Code" } -- Add command safely
		}

		-- Determine the error text safely
		local error_text
		if err_output == nil then
			error_text = "(No error output captured)"
		elseif type(err_output) ~= "string" then
			error_text = "(Non-string error output: " .. type(err_output) .. ")"
		elseif err_output == "" then
			error_text = "(Empty error output)"
		else
			-- It's a non-empty string, use it
			error_text = err_output
		end

		-- Add the error text chunk
		-- Ensure error_text is treated as a single block, remove potential trailing newline for cleaner echo
		error_text = error_text:gsub("[\n\r]+$", "") -- Remove trailing newlines/CR
		table.insert(msg_chunks, { error_text, "ErrorMsg" })

		-- Call nvim_echo with the safely constructed chunks
		vim.api.nvim_echo(msg_chunks, true, {}) -- `true` forces redraw

		return                                -- Stop further processing on error
	end

	-- If no error:
	if success_message then
		vim.api.nvim_echo({ { success_message, "Normal" } }, false, {})
	end

	if refresh_log then
		M_ref.refresh_log() -- Delegate refresh call
	end
end
-- Function to edit change with jj edit command
function Commands.edit_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = Utils.extract_change_id(line)

	if change_id then
		execute_jj_command(
			{ "jj", "edit", change_id },
			change_id,
			"Applied edit to change " .. change_id,
			true -- Refresh log
		)
	else
		vim.api.nvim_echo({ { "No change ID found on this line", "WarningMsg" } }, false, {})
	end
end

-- Function to abandon a change
function Commands.abandon_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = Utils.extract_change_id(line)
	if not change_id then
		-- Use nvim_echo for consistency
		vim.api.nvim_echo({ { "No change ID found on this line", "WarningMsg" } }, false, {})
		return
	end

	-- Revert to using vim.ui.select for confirmation as in the original code
	vim.ui.select(
		{ "Yes", "No" }, -- Options
		{
			prompt = "Are you sure you want to abandon change " .. change_id .. "?",
			-- You could add 'kind' or 'format' here if desired later
		},
		function(choice)
			-- callback receives the selected string ("Yes" or "No") or nil if cancelled (e.g., Esc)
			if choice == "Yes" then
				-- Execute the command if "Yes" was explicitly chosen
				execute_jj_command({ "jj", "abandon", change_id }, "Abandoned change " .. change_id, true)
			else
				-- Treat "No" or cancellation (choice is "No" or nil) as cancellation
				vim.api.nvim_echo({ { "Abandon cancelled", "Normal" } }, false, {})
			end
		end
	)
end

-- Function to add or edit change description
function Commands.describe_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = Utils.extract_change_id(line)

	if change_id then
		-- Use a plain format to get just the raw description text without any formatting
		local description_cmd = { "jj", "log", "-r", change_id, "--no-graph", "-T", "description" }
		local description = vim.fn.system(description_cmd)
		if vim.v.shell_error ~= 0 then
			vim.api.nvim_echo({ { "Error getting description for " .. change_id, "ErrorMsg" } }, true, {})
			return
		end

		-- Trim whitespace
		description = description:gsub("^%s*(.-)%s*$", "%1")

		-- Do not replace newlines here, handle in command execution

		-- Use vim.ui.input() for simple input at the bottom of the screen
		vim.ui.input(
			{
				prompt = "Description for " .. change_id .. ": ",
				default = description,
				completion = "file", -- This gives a decent sized input box
			},
			function(input)
				if input ~= nil then -- If not cancelled (ESC returns nil)
					-- Allow empty description
					-- Run the describe command using -m for the message
					local cmd_parts = { "jj", "describe", change_id, "-m", input }
					execute_jj_command(
						cmd_parts,
						change_id,
						"Updated description for change " .. change_id,
						true -- Refresh log
					)
				else
					-- Show cancel message if the user pressed ESC
					vim.api.nvim_echo({ { "Description edit cancelled", "Normal" } }, false, {})
				end
			end
		)
	else
		vim.api.nvim_echo({ { "No change ID found on this line", "WarningMsg" } }, false, {})
	end
end

-- Function to create a new change
function Commands.new_change()
	local line = vim.api.nvim_get_current_line()
	local change_id = Utils.extract_change_id(line)

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
			if input == nil then -- Cancelled
				vim.api.nvim_echo({ { "New change cancelled", "Normal" } }, false, {})
				return
			end

			-- If user didn't provide description, use empty string
			local description = input or ""

			-- Run the new command, optionally with a description
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

			execute_jj_command(
				cmd_parts,
				change_id, -- Pass original ID for context if needed, though not used by execute_jj_command
				success_msg,
				true   -- Refresh log
			)
		end
	)
end

-- Function to handle jj commit command
function Commands.commit_change()
	-- Get the current commit message (if any)
	local desc_cmd = { "jj", "log", "-r", "@", "--no-graph", "-T", "description" }
	local current_description = vim.fn.system(desc_cmd)
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({ { "Error getting current description.", "ErrorMsg" } }, true, {})
		return
	end


	-- Trim whitespace
	current_description = current_description:gsub("^%s*(.-)%s*$", "%1")

	-- Check if the change already has a description
	if current_description ~= "" and current_description:lower() ~= "(no description set)" then
		-- If it already has a description, just commit directly
		execute_jj_command(
			{ "jj", "commit" },
			nil,
			"Committed change with existing message",
			true -- Refresh log
		)
	else
		-- If it doesn't have a description, prompt for one
		vim.ui.input(
			{
				prompt = "Commit message: ",
				default = "",
				completion = "file", -- This gives a decent sized input box
			},
			function(input)
				if input ~= nil and input ~= "" then -- If not cancelled and not empty message
					-- Use jj commit with the provided message
					local cmd_parts = { "jj", "commit", "-m", input }
					execute_jj_command(
						cmd_parts,
						nil,
						"Committed change with message: " .. input,
						true -- Refresh log
					)
				else
					if input == "" then
						vim.api.nvim_echo({ { "Commit cancelled: Empty message", "WarningMsg" } }, false, {})
					else
						-- Show cancel message if the user pressed ESC or entered empty message
						vim.api.nvim_echo({ { "Commit cancelled", "Normal" } }, false, {})
					end
				end
			end
		)
	end
end

-- Initialize the module with a reference to the main state/module
function Commands.init(main_module_ref)
	M_ref = main_module_ref
end

return Commands
