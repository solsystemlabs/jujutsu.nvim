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
		return false
	end
	local command_str = table.concat(command_parts, " ")
	vim.fn.system(command_parts)
	if vim.v.shell_error ~= 0 then
		local err_output = vim.fn.system(command_str .. " 2>&1")
		local msg_chunks = { { "Error executing: ", "ErrorMsg" }, { (command_str or "<missing command>") .. "\n", "Code" } }
		local error_text = format_error_output(err_output, vim.v.shell_error)
		table.insert(msg_chunks, { error_text, "ErrorMsg" } })
		vim.api.nvim_echo(msg_chunks, true, {})
		return false
	end
	if success_message then vim.api.nvim_echo({ { success_message, "Normal" } }, false, {}) end
	if refresh_log and M_ref and M_ref.refresh_log then
		M_ref.refresh_log()
	end
	return true
end

-- Helper function to get existing bookmark names
local function get_bookmark_names()
	local output = vim.fn.systemlist({ "jj", "bookmark", "list" })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({ { "Error getting bookmark list.", "ErrorMsg" } }, true, {})
		return nil
	end
	local names = {}
	for _, line in ipairs(output) do
		local name = line:match("^([^:]+):")
		if name then table.insert(names, name:gsub("%s+$", "")) end
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
			local desc = change_line:match(".*@.-%.%w+%s+(.*)") or "(no description)"
			table.insert(options, change_id .. " - " .. desc)
			table.insert(change_ids, change_id)
		end
	end
	return options, change_ids
end

-- Helper function to select a change from a list
local function select_change(callback, limit)
	limit = limit or 15
	local cmd = "jj log -n " .. limit .. " --no-graph"
	local changes = vim.fn.systemlist(cmd)
	if vim.v.shell_error ~= 0 or #changes == 0 then
		vim.api.nvim_echo({ { "Failed to get change list", "ErrorMsg" } }, true, {})
		return
	end

	local options, change_ids = format_changes_for_selection(changes)
	vim.ui.select(options, { prompt = "Select target change:" }, function(_, idx)
		if idx and change_ids[idx] then
			callback(change_ids[idx])
		else
			vim.api.nvim_echo({ { "Change selection cancelled", "Normal" } }, false, {})
		end
	end)
end

-- Helper function to setup log window selection mapping
local function setup_log_selection_mapping(buf, current_win, callback)
	local opts = { noremap = true, silent = true, buffer = buf }
	local original_cr_mapping = vim.fn.maparg("<CR>", "n", false, true)

	vim.keymap.set("n", "<CR>", function()
		local line = vim.api.nvim_get_current_line()
		local selected_id = Utils.extract_change_id(line)
		vim.keymap.del("n", "<CR>", { buffer = buf })

		if original_cr_mapping and original_cr_mapping.buffer then
			local restore_cmd = original_cr_mapping.mode .. (original_cr_mapping.noremap == 1 and "noremap" or "map")
			if original_cr_mapping.silent == 1 then restore_cmd = restore_cmd .. " <silent>" end
			vim.cmd(restore_cmd .. " <buffer> " .. original_cr_mapping.lhs .. " " .. original_cr_mapping.rhs)
		end

		if vim.api.nvim_win_is_valid(current_win) then
			vim.api.nvim_set_current_win(current_win)
		end

		if selected_id then
			callback(selected_id)
		else
			vim.api.nvim_echo({ { "No valid change ID found on that line", "WarningMsg" } }, false, {})
			callback(nil)
		end
	end, opts)
end

-- Helper function to select a change from log window
local function select_from_log_window(callback, prompt)
	local log_module = require("jujutsu.log")
	if not M_ref.log_win or not vim.api.nvim_win_is_valid(M_ref.log_win) then
		local current_win = vim.api.nvim_get_current_win()
		log_module.toggle_log_window()
		vim.api.nvim_echo({
			{ prompt or "Select a change from log window, then press ", "Normal" },
			{ "Enter", "Special" },
			{ " to confirm", "Normal" }
		}, true, {})
		if M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) then
			local buf = vim.api.nvim_win_get_buf(M_ref.log_win)
			setup_log_selection_mapping(buf, current_win, callback)
		end
		return
	else
		vim.api.nvim_echo({
			{ prompt or "Select a change from log window, then press ", "Normal" },
			{ "Enter", "Special" },
			{ " to confirm", "Normal" }
		}, true, {})
		local buf = vim.api.nvim_win_get_buf(M_ref.log_win)
		local current_win = vim.api.nvim_get_current_win()
		setup_log_selection_mapping(buf, current_win, callback)
	end
end

-- Function to create a new change with additional options
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

	-- Helper function for multi-select parent changes
	local function select_multiple_parents(callback)
		local cmd = "jj log -n 20 --no-graph"
		local changes = vim.fn.systemlist(cmd)
		if vim.v.shell_error ~= 0 or #changes == 0 then
			vim.api.nvim_echo({ { "Failed to get list of changes", "ErrorMsg" } }, true, {})
			return
		end

		local options, change_ids = format_changes_for_selection(changes)
		local buf = Utils.create_selection_buffer("Select Multiple Parents", options)
		local selected = {}
		for i = 1, #options do selected[i] = false end

		local win, current_win = Utils.open_selection_window(buf, options)

		local function toggle_selection()
			local line_nr = vim.api.nvim_win_get_cursor(win)[1]
			if line_nr <= 5 then return end
			local option_idx = line_nr - 5
			if option_idx > #options then return end
			selected[option_idx] = not selected[option_idx]
			local marker = selected[option_idx] and "x" or " "
			local new_line = "[" .. marker .. "] " .. options[option_idx]
			vim.api.nvim_buf_set_lines(buf, line_nr - 1, line_nr, false, { new_line })
		end

		local function confirm_selection()
			local result = {}
			for i, is_selected in ipairs(selected) do
				if is_selected then table.insert(result, change_ids[i]) end
			end
			vim.api.nvim_win_close(win, true)
			if vim.api.nvim_win_is_valid(current_win) then
				vim.api.nvim_set_current_win(current_win)
			end
			callback(result)
		end

		local function cancel_selection()
			vim.api.nvim_win_close(win, true)
			if vim.api.nvim_win_is_valid(current_win) then
				vim.api.nvim_set_current_win(current_win)
			end
			callback({})
		end

		local opts = { noremap = true, silent = true, buffer = buf }
		vim.keymap.set('n', '<Space>', toggle_selection, opts)
		vim.keymap.set('n', '<CR>', confirm_selection, opts)
		vim.keymap.set('n', 'q', cancel_selection, opts)
		vim.keymap.set('n', '<Esc>', cancel_selection, opts)

		vim.api.nvim_win_set_option(win, 'cursorline', true)
		vim.api.nvim_set_current_buf(buf)
		vim.cmd('syntax match Comment /^#.*/')
		vim.cmd('syntax match Selected /\\[x\\]/')
		vim.cmd('highlight link Selected String')
	end

	-- Show advanced options dialog
	local function show_advanced_options(description)
		vim.ui.select({
			"Create simple change",
			"Create change with multiple parents",
			"Insert before another change",
			"Insert after another change",
			"Cancel"
		}, { prompt = "Select new change placement option:" }, function(choice)
			if choice == "Cancel" or not choice then
				vim.api.nvim_echo({ { "New change cancelled", "Normal" } }, false, {})
				return
			elseif choice == "Create simple change" then
				local cmd_parts = { "jj", "new" }
				local success_msg = change_id and "Created new change based on " .. change_id or "Created new change"
				if change_id then table.insert(cmd_parts, change_id) end
				if description ~= "" then
					table.insert(cmd_parts, "-m")
					table.insert(cmd_parts, description)
				end
				execute_jj_command(cmd_parts, success_msg, true)
			elseif choice == "Create change with multiple parents" then
				select_multiple_parents(function(result)
					if #result == 0 then
						vim.api.nvim_echo({ { "No parent changes selected - operation cancelled", "WarningMsg" } }, false, {})
						return
					end
					local cmd_parts = { "jj", "new" }
					for _, parent_id in ipairs(result) do table.insert(cmd_parts, parent_id) end
					if description ~= "" then
						table.insert(cmd_parts, "-m")
						table.insert(cmd_parts, description)
					end
					execute_jj_command(cmd_parts, "Created new change with " .. #result .. " parents", true)
				end)
			elseif choice == "Insert before another change" then
				select_from_log_window(function(target_id)
					if target_id then
						create_insert_change(description, target_id, "--insert-before", "before")
					end
				end)
			elseif choice == "Insert after another change" then
				select_from_log_window(function(target_id)
					if target_id then
						create_insert_change(description, target_id, "--insert-after", "after")
					end
				end)
			end
		end)
	end

	local prompt_text = change_id and ("Description for new change based on " .. change_id .. ": ") or "Description for new change: "
	vim.ui.input({ prompt = prompt_text, default = "", completion = "file" }, function(input)
		if input == nil then
			vim.api.nvim_echo({ { "New change cancelled", "Normal" } }, false, {})
			return
		end
		show_advanced_options(input)
	end)
end

-- Function to rebase changes with support for different flag variations
function Commands.rebase_change()
	local source_id = M_ref.log_win and vim.api.nvim_win_is_valid(M_ref.log_win) and Utils.extract_change_id(vim.api.nvim_get_current_line()) or nil
	if not source_id then
		source_id = "@"
		vim.api.nvim_echo({ { "Using current change for rebase.", "Normal" } }, false, {})
	end

	vim.ui.select({
		"Rebase single change",
		"Rebase whole branch",
		"Rebase change and descendants",
		"Cancel"
	}, { prompt = "Select rebase scope for " .. source_id .. ":" }, function(scope_choice)
		if scope_choice == "Cancel" or not scope_choice then
			vim.api.nvim_echo({ { "Rebase cancelled", "Normal" } }, false, {})
			return
		end

		local flag = scope_choice == "Rebase single change" and "-r" or
		             scope_choice == "Rebase whole branch" and "-b" or "-s"

		local function execute_rebase_command(dest_id)
			local cmd_parts = { "jj", "rebase", flag, source_id, "-d", dest_id }
			execute_jj_command(cmd_parts, "Rebased " .. source_id .. " onto " .. dest_id, true)
		end

		vim.ui.select({
			"Select change from log window",
			"Select bookmark",
			"Cancel"
		}, { prompt = "Select destination for rebase:" }, function(dest_choice)
			if dest_choice == "Cancel" or not dest_choice then
				vim.api.nvim_echo({ { "Rebase destination selection cancelled", "Normal" } }, false, {})
				return
			end

			if dest_choice == "Select change from log window" then
				select_from_log_window(function(dest_id)
					if dest_id then execute_rebase_command(dest_id) end
				end, "Select destination change for rebase, then press ")
			else
				local bookmark_names = get_bookmark_names() or {}
				if #bookmark_names == 0 then
					vim.api.nvim_echo({ { "No bookmarks found to rebase onto.", "WarningMsg" } }, false, {})
					return
				end
				vim.ui.select(bookmark_names, { prompt = "Select bookmark to rebase onto:" }, function(bookmark)
					if bookmark then execute_rebase_command(bookmark) end
				end)
			end
		end)
	end)
end

-- Function to run jj git push and display output via vim.notify
function Commands.git_push()
	local cmd_parts = { "jj", "git", "push" }
	local cmd_str = table.concat(cmd_parts, " ")
	vim.notify("Running: " .. cmd_str .. "...", vim.log.levels.INFO, { title = "Jujutsu" })

	local output_lines = vim.fn.systemlist(cmd_str .. " 2>&1")
	local shell_error_code = vim.v.shell_error
	local output_string = table.concat(output_lines, "\n"):gsub("[\n\r]+$", "")

	if shell_error_code == 0 then
		local message = output_string ~= "" and output_string or "jj git push completed successfully (no output)."
		vim.notify(message, vim.log.levels.INFO, { title = "jj git push" })
		if M_ref and M_ref.refresh_log then M_ref.refresh_log() end
	else
		local error_message = output_string ~= "" and output_string or "(No error output captured, shell error: " .. shell_error_code .. ")"
		vim.notify(error_message, vim.log.levels.ERROR, { title = "jj git push Error" })
	end
end

-- Bookmark management functions
local function move_bookmark_to_change(name, change_id)
	local cmd_parts = { "jj", "bookmark", "set", name, "-r", change_id }
	local cmd_str = table.concat(cmd_parts, " ")
	local output = vim.fn.system(cmd_str .. " 2>&1")
	if vim.v.shell_error == 0 then
		vim.api.nvim_echo({ { "Bookmark '" .. name .. "' set to " .. change_id, "Normal" } }, false, {})
		if M_ref and M_ref.refresh_log then M_ref.refresh_log() end
	else
		if output and output:lower():find("refusing to move bookmark backwards", 1, true) then
			vim.ui.select({ "Yes", "No" }, { prompt = "Allow moving bookmark '" .. name .. "' backward?" }, function(choice)
				if choice == "Yes" then
					local cmd_parts_alt = { "jj", "bookmark", "set", "--allow-backwards", name, "-r", change_id }
					execute_jj_command(cmd_parts_alt, "Bookmark '" .. name .. "' set backward to " .. change_id, true)
				else
					vim.api.nvim_echo({ { "Bookmark move cancelled.", "Normal" } }, false, {})
				end
			end)
		else
			local msg_chunks = { { "Error executing: ", "ErrorMsg" }, { cmd_str .. "\n", "Code" } }
			local error_text = format_error_output(output, vim.v.shell_error)
			table.insert(msg_chunks, { error_text, "ErrorMsg" } })
			vim.api.nvim_echo(msg_chunks, true, {})
		end
	end
end

function Commands.create_bookmark()
	local change_id = Utils.extract_change_id(vim.api.nvim_get_current_line())
	if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line to bookmark.", "WarningMsg" } }, false, {})
		return
	end
	vim.ui.input({ prompt = "Bookmark name to create: " }, function(name)
		if not name then
			vim.api.nvim_echo({ { "Bookmark creation cancelled.", "Normal" } }, false, {})
		elseif name == "" then
			vim.api.nvim_echo({ { "Bookmark creation cancelled: Name cannot be empty.", "WarningMsg" } }, false, {})
		else
			execute_jj_command({ "jj", "bookmark", "create", name, "-r", change_id }, "Bookmark '" .. name .. "' created at " .. change_id, true)
		end
	end)
end

function Commands.delete_bookmark()
	local bookmark_names = get_bookmark_names()
	if not bookmark_names or #bookmark_names == 0 then
		vim.api.nvim_echo({ { "No bookmarks found to delete.", "Normal" } }, false, {})
		return
	end
	vim.ui.select(bookmark_names, { prompt = "Select bookmark to delete:" }, function(selected_name)
		if selected_name then
			vim.ui.select({ "Yes", "No" }, { prompt = "Delete bookmark '" .. selected_name .. "'?" }, function(choice)
				if choice == "Yes" then
					execute_jj_command({ "jj", "bookmark", "delete", selected_name }, "Bookmark '" .. selected_name .. "' deleted.", true)
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
	local change_id = Utils.extract_change_id(vim.api.nvim_get_current_line())
	if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line to move bookmark to.", "WarningMsg" } }, false, {})
		return
	end
	local existing_bookmarks = get_bookmark_names() or {}
	local options = {}
	for _, name in ipairs(existing_bookmarks) do table.insert(options, name) end
	table.insert(options, "Create new bookmark...")

	vim.ui.select(options, { prompt = "Select bookmark to move or create new:" }, function(selected)
		if not selected then
			vim.api.nvim_echo({ { "Bookmark move cancelled.", "Normal" } }, false, {})
		elseif selected == "Create new bookmark..." then
			vim.ui.input({ prompt = "New bookmark name: " }, function(name)
				if not name then
					vim.api.nvim_echo({ { "Bookmark creation cancelled.", "Normal" } }, false, {})
				elseif name == "" then
					vim.api.nvim_echo({ { "Bookmark move cancelled: Name cannot be empty.", "WarningMsg" } }, false, {})
				else
					move_bookmark_to_change(name, change_id)
				end
			end)
		else
			move_bookmark_to_change(selected, change_id)
		end
	end)
end

function Commands.edit_change()
	local change_id = Utils.extract_change_id(vim.api.nvim_get_current_line())
	if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line", "WarningMsg" } }, false, {})
		return
	end
	execute_jj_command({ "jj", "edit", change_id }, "Applied edit to change " .. change_id, true)
end

function Commands.abandon_change()
	local change_id = Utils.extract_change_id(vim.api.nvim_get_current_line())
	if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line", "WarningMsg" } }, false, {})
		return
	end
	vim.ui.select({ "Yes", "No" }, { prompt = "Are you sure you want to abandon change " .. change_id .. "?" }, function(choice)
		if choice == "Yes" then
			execute_jj_command({ "jj", "abandon", change_id }, "Abandoned change " .. change_id, true)
		else
			vim.api.nvim_echo({ { "Abandon cancelled", "Normal" } }, false, {})
		end
	end)
end

function Commands.describe_change()
	local change_id = Utils.extract_change_id(vim.api.nvim_get_current_line())
	if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line", "WarningMsg" } }, false, {})
		return
	end
	local description = vim.fn.system({ "jj", "log", "-r", change_id, "--no-graph", "-T", "description" })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({ { "Error getting description for " .. change_id .. ". Does it exist?", "ErrorMsg" } }, true, {})
		return
	end
	description = description:gsub("^%s*(.-)%s*$", "%1")
	vim.ui.input({ prompt = "Description for " .. change_id .. ": ", default = description, completion = "file" }, function(input)
		if input ~= nil then
			execute_jj_command({ "jj", "describe", change_id, "-m", input }, "Updated description for change " .. change_id, true)
		else
			vim.api.nvim_echo({ { "Description edit cancelled", "Normal" } }, false, {})
		end
	end)
end

function Commands.split_change()
	local change_id = Utils.extract_change_id(vim.api.nvim_get_current_line())
	if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line to split.", "WarningMsg" } }, false, {})
		return
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, "JJ Split TUI")

	local width = math.floor(vim.o.columns * 0.9)
	local height = math.floor(vim.o.lines * 0.9)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor", width = width, height = height,
		row = row, col = col, style = "minimal", border = "rounded"
	})

	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].buflisted = false

	local shell = vim.env.SHELL or "/bin/sh"
	vim.fn.termopen(shell, {
		env = {
			EDITOR = vim.env.EDITOR or "vim",
			TERM = vim.env.TERM or "xterm-256color",
			COLUMNS = tostring(width),
			LINES = tostring(height)
		},
		on_exit = function(_, code, _)
			if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
			if code == 0 then
				vim.api.nvim_echo({ { "Change " .. change_id .. " split successfully", "Normal" } }, false, {})
				if M_ref and M_ref.refresh_log then M_ref.refresh_log() end
			else
				local error_msg = vim.api.nvim_buf_is_valid(buf) and table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n") or "Unknown error"
				vim.api.nvim_echo({ { "Error splitting change " .. change_id .. ": " .. error_msg, "ErrorMsg" } }, true, {})
			end
		end,
		on_stdout = function(_, data, _)
			for _, line in ipairs(data) do
				if line:match("Done") or line:match("Split complete") then
					if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
					break
				end
			end
		end
	})

	vim.defer_fn(function()
		if vim.api.nvim_buf_is_valid(buf) and vim.b[buf].terminal_job_id then
			vim.fn.chansend(vim.b[buf].terminal_job_id, "jj split -i -r " .. change_id .. "\n")
		end
	end, 100)
	vim.cmd("startinsert")
end

function Commands.commit_change()
	local current_description = vim.fn.system({ "jj", "log", "-r", "@", "--no-graph", "-T", "description" })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({ { "Error getting current description. Are you at a valid change?", "ErrorMsg" } }, true, {})
		return
	end
	current_description = current_description:gsub("^%s*(.-)%s*$", "%1")
	if current_description ~= "" and current_description:lower() ~= "(no description set)" then
		execute_jj_command({ "jj", "commit" }, "Committed change with existing message", true)
	else
		vim.ui.input({ prompt = "Commit message: ", default = "", completion = "file" }, function(input)
			if not input then
				vim.api.nvim_echo({ { "Commit cancelled", "Normal" } }, false, {})
			elseif input == "" then
				vim.api.nvim_echo({ { "Commit cancelled: Empty message not allowed.", "WarningMsg" } }, false, {})
			else
				execute_jj_command({ "jj", "commit", "-m", input }, "Committed change with message: " .. input, true)
			end
		end)
	end
end

function Commands.squash_change()
	local change_id = Utils.extract_change_id(vim.api.nvim_get_current_line())
	if not change_id then
		vim.api.nvim_echo({ { "No change ID found on this line to squash.", "WarningMsg" } }, false, {})
		return
	end

	vim.ui.select({
		"Squash non-interactively",
		"Squash interactively",
		"Cancel"
	}, { prompt = "Select squash mode for " .. change_id .. ":" }, function(choice)
		if choice == "Cancel" or not choice then
			vim.api.nvim_echo({ { "Squash cancelled", "Normal" } }, false, {})
			return
		end

		local cmd_parts = { "jj", "squash", "-r", change_id }
		local success_msg = "Squashed change " .. change_id
		if choice == "Squash interactively" then
			table.insert(cmd_parts, "-i")
			success_msg = success_msg .. " interactively"
		end
		execute_jj_command(cmd_parts, success_msg, true)
	end)
end

function Commands.rebase_onto_master()
	execute_jj_command({ "jj", "rebase", "-b", "@", "-d", "master" }, "Rebased current branch onto master", true)
end

-- Function to show diff of a change
function Commands.show_diff()
	local change_id = Utils.extract_change_id(vim.api.nvim_get_current_line()) or "@"
	if change_id == "@" then
		vim.api.nvim_echo({ { "Showing diff for current working copy", "Normal" } }, false, {})
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, "JJ Diff Viewer - " .. change_id)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "hide"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "diff"

	local width = math.floor(vim.o.columns * 0.8)
	local height = math.floor(vim.o.lines * 0.8)
	local row = math.floor((vim.o.lines - height) / 2)
	local col = math.floor((vim.o.columns - width) / 2)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor", width = width, height = height,
		row = row, col = col, style = "minimal", border = "rounded"
	})

	vim.fn.termopen({ "jj", "diff", "-r", change_id }, {
		on_exit = function()
			if vim.api.nvim_win_is_valid(win) then
				vim.bo[buf].modifiable = false
				vim.bo[buf].readonly = true
			end
		end
	})

	local opts = { noremap = true, silent = true, buffer = buf }
	vim.keymap.set('n', 'q', function()
		if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
	end, opts)
	vim.keymap.set('n', '<Esc>', function()
		if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
	end, opts)
end

-- Initialize the module with a reference to the main state/module
function Commands.init(main_module_ref)
	M_ref = main_module_ref
end

return Commands
