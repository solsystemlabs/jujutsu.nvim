-- jujutsu.nvim - Log window module
-- Provides a togglable floating window that displays the jujutsu log

local M = {}
local fn = vim.fn
local utils = require('jujutsu.utils')

-- Cache for state management
local state = {
	buf = nil,    -- Buffer for log content
	win = nil,    -- Window ID
	visible = false, -- Whether the log window is visible
	last_size = nil, -- Last size of the window
	last_pos = nil, -- Last position of the window
	prev_win = nil, -- Previous window ID
	refresh_timer = nil, -- Timer for auto-refresh
}

-- Default configuration
local default_config = {
	window = {
		width = 80, -- Width of the window (in columns)
		height = 25, -- Height of the window (in rows)
		border = "single", -- Border style: "none", "single", "double", "rounded", "solid", "shadow"
		position = "left", -- Position of the window: "left", "right", "top", "bottom", "center"
		title = "Jujutsu Log", -- Window title
	},
	log_args = {
		"--no-graph", -- Default log arguments
		"--template", "{short_id} {author|name} {description|firstline}"
	},
	auto_refresh = {
		enable = true, -- Automatically refresh the log
		interval = 5000, -- Refresh interval in ms
	},
	mappings = {
		quit = "q", -- Close the log window
		refresh = "r", -- Refresh the log
		open_commit = "<CR>", -- Open the commit under cursor
		toggle_graph = "g", -- Toggle graph display
		diff = "d", -- Show diff for commit under cursor
	},
	format_commit_id = true, -- Format commit IDs with highlighting
}

-- Initialize the module with user config
function M.setup(config)
	M.config = vim.tbl_deep_extend('force', default_config, config or {})
end

-- Toggle the log window
function M.toggle_window(args)
	if state.visible and state.win and vim.api.nvim_win_is_valid(state.win) then
		M.close_window()
	else
		M.open_window(args)
	end
end

-- Open the log window
function M.open_window(args)
	-- If already open, just focus it
	if state.visible and state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_set_current_win(state.win)
		return
	end

	-- Save current window
	state.prev_win = vim.api.nvim_get_current_win()

	-- Process additional args if provided
	if args and #args > 0 then
		-- Add additional args to log_args (preserving the default template)
		local template_args = {}
		local has_template = false

		-- Check if we have a template in the config
		for i, arg in ipairs(M.config.log_args) do
			if arg == "--template" then
				has_template = true
				template_args = { M.config.log_args[i], M.config.log_args[i + 1] }
				break
			end
		end

		-- Clear the log args but preserve the template if it exists
		M.config.log_args = {}

		-- Add custom args
		for _, arg in ipairs(args) do
			table.insert(M.config.log_args, arg)
		end

		-- Re-add template if it existed
		if has_template then
			table.insert(M.config.log_args, template_args[1])
			table.insert(M.config.log_args, template_args[2])
		end
	end

	-- Create or reuse a buffer
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		state.buf = vim.api.nvim_create_buf(false, true)
		vim.bo[state.buf].bufhidden = 'wipe'
		vim.bo[state.buf].buftype = 'nofile'
		vim.bo[state.buf].swapfile = false
		vim.bo[state.buf].filetype = 'jujutsu-log'
	end

	-- Set up window position and size
	local width, height, row, col
	local editor_width = vim.o.columns
	local editor_height = vim.o.lines

	width = M.config.window.width
	height = M.config.window.height

	if width > editor_width then
		width = editor_width - 4
	end
	if height > editor_height - 4 then
		height = editor_height - 4
	end

	-- Calculate window position based on configuration
	if M.config.window.position == "left" then
		row = math.floor((editor_height - height) / 2)
		col = 1
	elseif M.config.window.position == "right" then
		row = math.floor((editor_height - height) / 2)
		col = editor_width - width - 1
	elseif M.config.window.position == "top" then
		row = 1
		col = math.floor((editor_width - width) / 2)
	elseif M.config.window.position == "bottom" then
		row = editor_height - height - 2
		col = math.floor((editor_width - width) / 2)
	else -- center
		row = math.floor((editor_height - height) / 2)
		col = math.floor((editor_width - width) / 2)
	end

	-- Remember last size and position
	state.last_size = { width = width, height = height }
	state.last_pos = { row = row, col = col }

	-- Window options
	local win_opts = {
		relative = 'editor',
		width = width,
		height = height,
		row = row,
		col = col,
		style = 'minimal',
		border = M.config.window.border,
		title = M.config.window.title,
		title_pos = 'center',
	}

	-- Create the window
	state.win = vim.api.nvim_open_win(state.buf, true, win_opts)

	-- Set window-local options
	vim.wo[state.win].wrap = false
	vim.wo[state.win].cursorline = true
	vim.wo[state.win].winhl = 'Normal:JujutsuLogNormal,FloatBorder:JujutsuLogBorder'

	-- Set buffer keymaps
	M.set_keymaps()

	-- Load log content
	M.update_log_content()

	-- Set up auto-refresh
	if M.config.auto_refresh.enable then
		M.setup_auto_refresh()
	end

	state.visible = true
end

-- Close the log window
function M.close_window()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end

	-- Clear auto-refresh timer if it exists
	if state.refresh_timer then
		vim.fn.timer_stop(state.refresh_timer)
		state.refresh_timer = nil
	end

	state.visible = false

	-- If there was a previous window, return to it
	if state.prev_win and vim.api.nvim_win_is_valid(state.prev_win) then
		vim.api.nvim_set_current_win(state.prev_win)
	end
end

-- Set keymaps for the log window
function M.set_keymaps()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	local map_opts = { noremap = true, silent = true, buffer = state.buf }

	-- Close window
	vim.keymap.set('n', M.config.mappings.quit,
		function() require('jujutsu.log').close_window() end, map_opts)

	-- Refresh log
	vim.keymap.set('n', M.config.mappings.refresh,
		function() require('jujutsu.log').update_log_content() end, map_opts)

	-- Open commit details
	vim.keymap.set('n', M.config.mappings.open_commit,
		function() require('jujutsu.log').open_commit_at_cursor() end, map_opts)

	-- Toggle graph display
	vim.keymap.set('n', M.config.mappings.toggle_graph,
		function() require('jujutsu.log').toggle_graph_display() end, map_opts)

	-- Show diff for commit
	vim.keymap.set('n', M.config.mappings.diff,
		function() require('jujutsu.log').show_commit_diff() end, map_opts)
end

-- Update the log content in the buffer
function M.update_log_content(custom_args)
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	local dir = fn.expand('%:p:h')
	local cmd = { "jj", "log" }

	-- Use custom args if provided, else use config args
	local args_to_use = custom_args or M.config.log_args

	-- Merge config arguments
	for _, arg in ipairs(args_to_use) do
		table.insert(cmd, arg)
	end

	local result = utils.system_result(cmd, dir)

	if result.exit_code ~= 0 then
		vim.bo[state.buf].modifiable = true
		vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, {
			"Error running jj log: " .. result.stderr,
			"Make sure jujutsu is installed and this is a jujutsu repository."
		})
		vim.bo[state.buf].modifiable = false
		return
	end

	-- Split the output into lines
	local log_lines = vim.split(result.stdout, '\n')

	-- Remove trailing empty lines
	while #log_lines > 0 and log_lines[#log_lines] == "" do
		table.remove(log_lines)
	end

	-- Set the buffer content
	vim.bo[state.buf].modifiable = true
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, log_lines)
	vim.bo[state.buf].modifiable = false

	-- Apply syntax highlighting if needed
	if M.config.format_commit_id then
		M.highlight_commit_ids()
	end
end

-- Highlight commit IDs in the log output
function M.highlight_commit_ids()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	-- Clear existing highlights
	vim.api.nvim_buf_clear_namespace(state.buf, 0, 0, -1)

	local lines = vim.api.nvim_buf_get_lines(state.buf, 0, -1, false)

	for line_idx, line in ipairs(lines) do
		-- Match commit ID pattern (alphanumeric, usually at the start of the line)
		local id_start, id_end = string.find(line, "^%s*[a-z0-9]+")
		if id_start and id_end then
			vim.api.nvim_buf_add_highlight(state.buf, 0, "JujutsuCommitId", line_idx - 1, id_start - 1,
				id_end)
		end
	end
end

-- Set up auto-refresh timer
function M.setup_auto_refresh()
	-- Clear existing timer if any
	if state.refresh_timer then
		vim.fn.timer_stop(state.refresh_timer)
		state.refresh_timer = nil
	end

	-- Create a new repeating timer
	state.refresh_timer = vim.fn.timer_start(
		M.config.auto_refresh.interval,
		function()
			vim.schedule(function()
				if state.visible and state.win and vim.api.nvim_win_is_valid(state.win) then
					M.update_log_content()
				else
					-- Stop the timer if the window is no longer visible
					if state.refresh_timer then
						vim.fn.timer_stop(state.refresh_timer)
						state.refresh_timer = nil
					end
				end
			end)
		end,
		{ ['repeat'] = -1 } -- Repeat indefinitely
	)
end

-- Open the commit details at cursor
function M.open_commit_at_cursor()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	-- Get the line under cursor
	local line_nr = vim.api.nvim_win_get_cursor(state.win)[1]
	local line = vim.api.nvim_buf_get_lines(state.buf, line_nr - 1, line_nr, false)[1]

	-- Extract commit ID (first word on the line)
	local commit_id = line:match("^%s*([a-z0-9]+)")

	if not commit_id then
		vim.notify("No commit ID found on this line", vim.log.levels.WARN)
		return
	end

	-- Show commit details in a split
	local dir = fn.expand('%:p:h')
	local result = utils.system_result({ "jj", "show", commit_id }, dir)

	if result.exit_code ~= 0 then
		vim.notify("Error fetching commit details: " .. result.stderr, vim.log.levels.ERROR)
		return
	end

	-- Close the log window temporarily
	M.close_window()

	-- Show the commit details in a split
	utils.show_in_split(result.stdout, "jujutsu-show")

	-- Add a key mapping to return to the log window
	local buf = vim.api.nvim_get_current_buf()
	vim.keymap.set('n', 'q', function()
		vim.cmd("bdelete")
		require('jujutsu.log').open_window()
	end, { buffer = buf, noremap = true, silent = true })
end

-- Toggle graph display in log output
function M.toggle_graph_display()
	-- Find and toggle --no-graph flag in log_args
	local has_no_graph = false
	local idx = nil

	for i, arg in ipairs(M.config.log_args) do
		if arg == "--no-graph" then
			has_no_graph = true
			idx = i
			break
		end
	end

	if has_no_graph and idx then
		table.remove(M.config.log_args, idx)
		vim.notify("Graph display enabled", vim.log.levels.INFO)
	else
		table.insert(M.config.log_args, "--no-graph")
		vim.notify("Graph display disabled", vim.log.levels.INFO)
	end

	-- Update the display
	M.update_log_content()
end

-- Show diff for the commit under cursor
function M.show_commit_diff()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end

	-- Get the line under cursor
	local line_nr = vim.api.nvim_win_get_cursor(state.win)[1]
	local line = vim.api.nvim_buf_get_lines(state.buf, line_nr - 1, line_nr, false)[1]

	-- Extract commit ID (first word on the line)
	local commit_id = line:match("^%s*([a-z0-9]+)")

	if not commit_id then
		vim.notify("No commit ID found on this line", vim.log.levels.WARN)
		return
	end

	-- Show commit diff in a split
	local dir = fn.expand('%:p:h')
	local result = utils.system_result({ "jj", "diff", "-r", commit_id }, dir)

	if result.exit_code ~= 0 then
		vim.notify("Error fetching commit diff: " .. result.stderr, vim.log.levels.ERROR)
		return
	end

	-- Close the log window temporarily
	M.close_window()

	-- Show the diff in a split
	utils.show_in_split(result.stdout, "jujutsu-diff")

	-- Add a key mapping to return to the log window
	local buf = vim.api.nvim_get_current_buf()
	vim.keymap.set('n', 'q', function()
		vim.cmd("bdelete")
		require('jujutsu.log').open_window()
	end, { buffer = buf, noremap = true, silent = true })
end

return M
