-- jujutsu.nvim - Jujutsu (jj) integration for Neovim
-- A plugin to integrate jujutsu version control with Neovim
local M = {}
local config = {}
local api = vim.api
local fn = vim.fn
local utils = require('jujutsu.utils')
local signs = require('jujutsu.signs')
local cache = {}

-- Default configuration
local default_config = {
	signs               = {
		add          = { text = '│' },
		change       = { text = '│' },
		delete       = { text = '_' },
		topdelete    = { text = '‾' },
		changedelete = { text = '~' },
		untracked    = { text = '┆' },
	},
	signcolumn          = true, -- Toggle with `:JujutsuToggleSignsColumn`
	numhl               = false, -- Toggle with `:JujutsuToggleNumhl`
	linehl              = false, -- Toggle with `:JujutsuToggleLinehl`
	word_diff           = false, -- Toggle with `:JujutsuToggleWordDiff`
	watch_index         = {
		interval = 1000,
		follow_files = true,
	},
	sign_priority       = 6,
	update_debounce     = 100,
	status_formatter    = nil, -- Use default
	max_file_length     = 40000, -- Disable if file exceeds this size (in lines)
	preview_config      = {
		-- Options passed to nvim_open_win
		border = 'single',
		style = 'minimal',
		relative = 'cursor',
		row = 0,
		col = 1
	},
	attach_to_untracked = true,
	watch_jujutsu       = {
		interval = 1000,
		enable = true,
	},
	jujutsu_cmd         = "jj", -- Command to run jujutsu
	yadm                = {
		enable = false
	},
	on_attach           = nil,
}

-- Initialize the plugin
function M.setup(opts)
	config = vim.tbl_deep_extend('force', default_config, opts or {})
	signs.setup(config)

	M.create_commands()
	M.create_autocommands()

	-- Set up key mappings if enabled
	if type(config.on_attach) == 'function' then
		config.on_attach()
	elseif config.on_attach ~= false then
		M.setup_keymaps()
	end

	return M
end

-- Create user commands
function M.create_commands()
	api.nvim_create_user_command('JujutsuSignsAdd', function() M.add_signs() end, {})
	api.nvim_create_user_command('JujutsuSignsRemove', function() M.remove_signs() end, {})
	api.nvim_create_user_command('JujutsuStatus', function() M.status() end, {})
	api.nvim_create_user_command('JujutsuDiff', function(opts) M.diff(opts.args) end, { nargs = '?' })
	api.nvim_create_user_command('JujutsuNew', function() M.new() end, {})
	api.nvim_create_user_command('JujutsuSquash', function() M.squash() end, {})
	api.nvim_create_user_command('JujutsuEdit', function() M.edit() end, {})
	api.nvim_create_user_command('JujutsuDescribe', function() M.describe() end, {})
	api.nvim_create_user_command('JujutsuToggleSignsColumn', function() M.toggle_signs_column() end, {})
	api.nvim_create_user_command('JujutsuToggleNumhl', function() M.toggle_numhl() end, {})
	api.nvim_create_user_command('JujutsuToggleLinehl', function() M.toggle_linehl() end, {})
	api.nvim_create_user_command('JujutsuBlame', function() M.blame() end, {})
end

-- Create autocommands
function M.create_autocommands()
	local group = api.nvim_create_augroup('jujutsu', { clear = true })

	-- Check and attach to buffers
	api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile', 'BufWritePost' }, {
		group = group,
		callback = function(args)
			if args.file ~= '' then
				M.check_and_attach(args.buf)
			end
		end,
	})

	-- Update signs when buffer is modified
	api.nvim_create_autocmd('BufWritePost', {
		group = group,
		callback = function(args)
			if M.is_attached(args.buf) then
				vim.defer_fn(function()
					M.update_signs(args.buf)
				end, config.update_debounce)
			end
		end,
	})

	-- Update on focus if watching is enabled
	if config.watch_jujutsu.enable then
		api.nvim_create_autocmd({ 'FocusGained', 'BufEnter' }, {
			group = group,
			callback = function(args)
				if M.is_attached(args.buf) then
					vim.defer_fn(function()
						M.update_signs(args.buf)
					end, config.update_debounce)
				end
			end,
		})
	end
end

-- Setup keymaps
function M.setup_keymaps()
	-- Default keymaps
	local map = function(mode, lhs, rhs, desc)
		vim.keymap.set(mode, lhs, rhs, { noremap = true, silent = true, desc = desc })
	end

	map('n', '<leader>jn', M.next_hunk, "Next jujutsu hunk")
	map('n', '<leader>jp', M.prev_hunk, "Previous jujutsu hunk")
	map('n', '<leader>js', M.stage_hunk, "Stage jujutsu hunk")
	map('n', '<leader>ju', M.undo_stage_hunk, "Undo stage jujutsu hunk")
	map('n', '<leader>jr', M.reset_hunk, "Reset jujutsu hunk")
	map('n', '<leader>jb', M.blame, "Jujutsu blame")
	map('n', '<leader>jd', function() M.diff() end, "Jujutsu diff")
	map('n', '<leader>jS', M.status, "Jujutsu status")
	map('n', '<leader>jN', M.new, "Jujutsu new change")
	map('n', '<leader>jq', M.squash, "Jujutsu squash changes")
	map('n', '<leader>je', M.edit, "Jujutsu edit parent")
	map('n', '<leader>jm', M.describe, "Jujutsu edit commit message")
end

-- Check if the current file is in a jujutsu repo and attach
function M.check_and_attach(bufnr)
	bufnr = bufnr or api.nvim_get_current_buf()
	local bufname = api.nvim_buf_get_name(bufnr)

	-- Skip empty buffers or already attached ones
	if bufname == '' or M.is_attached(bufnr) then
		return
	end

	-- Skip certain filetypes
	local filetype = vim.bo[bufnr].filetype
	local skip_filetypes = { 'git', 'gitcommit', 'gitrebase', 'gitsendemail', 'jujutsu' }
	for _, ft in ipairs(skip_filetypes) do
		if ft == filetype then
			return
		end
	end

	-- Attach if in jujutsu repo
	if M.is_jujutsu_repo() then
		M.attach(bufnr)
	end
end

-- Check if buffer is attached
function M.is_attached(bufnr)
	bufnr = bufnr or api.nvim_get_current_buf()
	return cache[bufnr] ~= nil
end

-- Check if the current directory is within a jujutsu repo
function M.is_jujutsu_repo()
	local dir = fn.expand('%:p:h')
	local result = utils.system_result({ config.jujutsu_cmd, "st", "--no-pager" }, dir)
	return result.exit_code == 0
end

-- Attach jujutsu signs to the current buffer
function M.attach(bufnr)
	bufnr = bufnr or api.nvim_get_current_buf()
	if cache[bufnr] then
		return
	end

	cache[bufnr] = {
		signs = {},
		hunks = {},
	}

	M.update_signs(bufnr)
end

-- Detach jujutsu signs from the current buffer
function M.detach(bufnr)
	bufnr = bufnr or api.nvim_get_current_buf()
	if not cache[bufnr] then
		return
	end

	M.remove_signs(bufnr)
	cache[bufnr] = nil
end

-- Update signs for a specific buffer
function M.update_signs(bufnr)
	bufnr = bufnr or api.nvim_get_current_buf()
	if not cache[bufnr] then
		return
	end

	local bufname = api.nvim_buf_get_name(bufnr)
	if bufname == '' then
		return
	end

	-- Get the diff for the current file
	local dir = fn.expand('%:p:h')
	local relative_path = fn.expand('%:.')
	local result = utils.system_result({ config.jujutsu_cmd, "diff", "--git", relative_path }, dir)

	if result.exit_code ~= 0 then
		return
	end

	local hunks = utils.parse_diff(result.stdout)
	if not hunks or #hunks == 0 then
		M.remove_signs(bufnr)
		cache[bufnr].hunks = {}
		return
	end

	cache[bufnr].hunks = hunks
	M.add_signs(bufnr)
end

-- Add signs to the buffer
function M.add_signs(bufnr)
	bufnr = bufnr or api.nvim_get_current_buf()
	if not cache[bufnr] or not cache[bufnr].hunks then
		return
	end

	M.remove_signs(bufnr) -- Clear existing signs

	for _, hunk in ipairs(cache[bufnr].hunks) do
		for i = hunk.start, hunk.finish do
			local sign_type
			if i == hunk.start and hunk.type == 'remove' then
				sign_type = 'delete'
			elseif i == hunk.start and hunk.type == 'change' then
				sign_type = 'change'
			elseif i == hunk.start and hunk.type == 'add' then
				sign_type = 'add'
			elseif i > hunk.start and i <= hunk.finish and hunk.type ~= 'remove' then
				sign_type = 'add'
			end

			if sign_type then
				signs.add(bufnr, i, sign_type, config.sign_priority)
				cache[bufnr].signs[i] = sign_type
			end
		end
	end
end

-- Remove signs from the buffer
function M.remove_signs(bufnr)
	bufnr = bufnr or api.nvim_get_current_buf()
	if not cache[bufnr] or not cache[bufnr].signs then
		return
	end

	for line, _ in pairs(cache[bufnr].signs) do
		signs.remove(bufnr, line)
	end

	cache[bufnr].signs = {}
end

-- Toggle the signcolumn
function M.toggle_signs_column()
	config.signcolumn = not config.signcolumn
	M.refresh()
end

-- Toggle numhl
function M.toggle_numhl()
	config.numhl = not config.numhl
	signs.update_config(config)
	M.refresh()
end

-- Toggle linehl
function M.toggle_linehl()
	config.linehl = not config.linehl
	signs.update_config(config)
	M.refresh()
end

-- Refresh all signs
function M.refresh()
	for bufnr, _ in pairs(cache) do
		if api.nvim_buf_is_valid(bufnr) then
			M.update_signs(bufnr)
		else
			cache[bufnr] = nil
		end
	end
end

-- Show jujutsu status
function M.status()
	local dir = fn.expand('%:p:h')
	local output = utils.system_result({ config.jujutsu_cmd, "st" }, dir)

	if output.exit_code == 0 then
		utils.show_in_split(output.stdout, "jujutsu-status")
	else
		utils.error("Failed to get jujutsu status: " .. output.stderr)
	end
end

-- Show diff
function M.diff(args)
	args = args or ""
	local dir = fn.expand('%:p:h')
	local cmd = { config.jujutsu_cmd, "diff" }

	-- Add arguments if provided
	if args ~= "" then
		for arg in args:gmatch("%S+") do
			table.insert(cmd, arg)
		end
	end

	local output = utils.system_result(cmd, dir)

	if output.exit_code == 0 then
		utils.show_in_split(output.stdout, "jujutsu-diff")
	else
		utils.error("Failed to get jujutsu diff: " .. output.stderr)
	end
end

-- Create a new change
function M.new()
	local dir = fn.expand('%:p:h')
	local output = utils.system_result({ config.jujutsu_cmd, "new" }, dir)

	if output.exit_code == 0 then
		vim.notify("Created new change", vim.log.levels.INFO)
		M.refresh()
	else
		utils.error("Failed to create new change: " .. output.stderr)
	end
end

-- Squash changes
function M.squash()
	local dir = fn.expand('%:p:h')
	local output = utils.system_result({ config.jujutsu_cmd, "squash" }, dir)

	if output.exit_code == 0 then
		vim.notify("Squashed changes", vim.log.levels.INFO)
		M.refresh()
	else
		utils.error("Failed to squash changes: " .. output.stderr)
	end
end

-- Edit a change
function M.edit()
	local dir = fn.expand('%:p:h')
	local output = utils.system_result({ config.jujutsu_cmd, "edit", "@-" }, dir)

	if output.exit_code == 0 then
		vim.notify("Editing parent change", vim.log.levels.INFO)
		M.refresh()
	else
		utils.error("Failed to edit change: " .. output.stderr)
	end
end

-- Describe (add/edit commit message)
function M.describe()
	local dir = fn.expand('%:p:h')

	-- Create a temp file for the message
	local temp_file = fn.tempname()

	-- Get current description first
	local current_desc = utils.system_result({ config.jujutsu_cmd, "describe", "--stdout" }, dir)

	if current_desc.exit_code == 0 then
		-- Write current description to temp file
		local file = io.open(temp_file, "w")
		if file then
			file:write(current_desc.stdout)
			file:close()
		end

		-- Open temp file in editor
		vim.cmd("edit " .. temp_file)

		-- Set up autocmd to update the commit message when done
		local group = api.nvim_create_augroup('jujutsu_temp_' .. fn.fnamemodify(temp_file, ':t'),
			{ clear = true })
		api.nvim_create_autocmd("BufWritePost", {
			group = group,
			pattern = temp_file,
			callback = function()
				local content = utils.read_file(temp_file)
				local update_result = utils.system_result(
					{ config.jujutsu_cmd, "describe", "-m", content }, dir)

				if update_result.exit_code == 0 then
					vim.notify("Updated commit message", vim.log.levels.INFO)
					vim.cmd("bdelete!")
					os.remove(temp_file)
				else
					utils.error("Failed to update commit message: " .. update_result.stderr)
				end
			end,
			once = true
		})
	else
		utils.error("Failed to get current description: " .. current_desc.stderr)
	end
end

-- Show blame for current file
function M.blame()
	local dir = fn.expand('%:p:h')
	local relative_path = fn.expand('%:.')

	-- For jujutsu 0.24+ with file annotate support (similar to git blame)
	local output = utils.system_result({ config.jujutsu_cmd, "file", "annotate", relative_path }, dir)

	if output.exit_code == 0 then
		utils.show_in_split(output.stdout, "jujutsu-blame")
	else
		-- Fallback to log for the file
		local fallback = utils.system_result({ config.jujutsu_cmd, "log", relative_path }, dir)
		if fallback.exit_code == 0 then
			utils.show_in_split(fallback.stdout, "jujutsu-log")
		else
			utils.error("Failed to get file history: " .. fallback.stderr)
		end
	end
end

-- Navigate to next hunk
function M.next_hunk()
	local bufnr = api.nvim_get_current_buf()
	if not cache[bufnr] or not cache[bufnr].hunks or #cache[bufnr].hunks == 0 then
		return
	end

	local hunks = cache[bufnr].hunks
	local lnum = api.nvim_win_get_cursor(0)[1]

	for _, hunk in ipairs(hunks) do
		if hunk.start > lnum then
			api.nvim_win_set_cursor(0, { hunk.start, 0 })
			return
		end
	end

	-- Wrap around to the first hunk
	api.nvim_win_set_cursor(0, { hunks[1].start, 0 })
end

-- Navigate to previous hunk
function M.prev_hunk()
	local bufnr = api.nvim_get_current_buf()
	if not cache[bufnr] or not cache[bufnr].hunks or #cache[bufnr].hunks == 0 then
		return
	end

	local hunks = cache[bufnr].hunks
	local lnum = api.nvim_win_get_cursor(0)[1]
	local prev_hunk = nil

	for _, hunk in ipairs(hunks) do
		if hunk.start >= lnum then
			break
		end
		prev_hunk = hunk
	end

	if prev_hunk then
		api.nvim_win_set_cursor(0, { prev_hunk.start, 0 })
	else
		-- Wrap around to the last hunk
		api.nvim_win_set_cursor(0, { hunks[#hunks].start, 0 })
	end
end

-- Stage the current hunk
function M.stage_hunk()
	-- For jujutsu, this would be adding the changes to the current change
	-- Since jujutsu auto-stages, this is more of a no-op but included for API compatibility
	vim.notify("Jujutsu automatically stages changes on each command", vim.log.levels.INFO)
end

-- Undo stage the current hunk
function M.undo_stage_hunk()
	-- Not directly applicable in jujutsu's model, but we can offer to create a new change
	local choice = fn.confirm("Create new change instead?", "&Yes\n&No", 1)
	if choice == 1 then
		M.new()
	end
end

-- Reset the current hunk
function M.reset_hunk()
	local bufnr = api.nvim_get_current_buf()
	if not cache[bufnr] or not cache[bufnr].hunks or #cache[bufnr].hunks == 0 then
		return
	end

	local lnum = api.nvim_win_get_cursor(0)[1]
	local current_hunk = nil

	for _, hunk in ipairs(cache[bufnr].hunks) do
		if lnum >= hunk.start and lnum <= hunk.finish then
			current_hunk = hunk
			break
		end
	end

	if not current_hunk then
		vim.notify("No hunk found at cursor", vim.log.levels.WARN)
		return
	end

	local dir = fn.expand('%:p:h')
	local relative_path = fn.expand('%:.')

	-- Use jj restore to reset the file or specific lines
	local cmd = { config.jujutsu_cmd, "restore", relative_path }
	local output = utils.system_result(cmd, dir)

	if output.exit_code == 0 then
		vim.notify("Reset hunk", vim.log.levels.INFO)
		M.refresh()
		-- Reload the buffer
		vim.cmd("edit!")
	else
		utils.error("Failed to reset hunk: " .. output.stderr)
	end
end

return M
