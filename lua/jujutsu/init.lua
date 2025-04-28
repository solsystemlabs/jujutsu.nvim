-- lua/jujutsu/init.lua
-- Main plugin file, state management, setup, public API

local M = {}

-- Load submodules
local Log = require("jujutsu.log")
local Status = require("jujutsu.status")
local Commands = require("jujutsu.commands")
-- Utils is used internally by other modules

-- State variables with type annotations
---@type number|nil
M.log_buf = nil
---@type number|nil
M.log_win = nil
---@type number|nil
M.status_buf = nil
---@type number|nil
M.status_win = nil
M.log_settings = { limit = "", revset = "", template = "", search_pattern = "" }
M.is_operation_log = false

-- Initialize submodules... (unchanged)
Log.init(M); Status.init(M); Commands.init(M)

-- Delegate log refresh calls... (unchanged)
function M.refresh_log()
	if M.log_win then
		-- Defer the check and refresh to avoid fast event context issues
		vim.defer_fn(function()
			if M.log_win and vim.api.nvim_win_is_valid(M.log_win) then
				Log.refresh_log_buffer()
			end
		end, 0)
	end
end

-- Setup global keymaps
function M.setup()
	-- Define options once
	local opts = { noremap = true, silent = true }
	-- test

	-- Existing mappings
	vim.keymap.set('n', '<leader>jl', function() Log.toggle_log_window() end,
		vim.tbl_extend('keep', { desc = "[L]og Toggle" }, opts))
	vim.keymap.set('n', '<leader>js', function() Status.show_status() end,
		vim.tbl_extend('keep', { desc = "[S]tatus Show" }, opts))
	vim.keymap.set('n', '<leader>jr', function() Log.reset_log_settings() end,
		vim.tbl_extend('keep', { desc = "Log [R]eset Settings" }, opts))
	vim.keymap.set('n', '<leader>jo', function()
		vim.ui.select({ "Set Limit", "Set Revset Filter", "Search in Log", "Change Template", "Reset Settings" },
			{ prompt = "Select a Jujutsu log option:", },
			function(choice)
				if not choice then return end -- Handle cancel
				if choice == "Set Limit" then
					Log.set_log_limit()
				elseif choice == "Set Revset Filter" then
					Log.set_revset_filter()
				elseif choice == "Search in Log" then
					Log.search_in_log()
				elseif choice == "Change Template" then
					Log.change_log_template()
				elseif choice == "Reset Settings" then
					Log.reset_log_settings()
				end
			end)
	end, vim.tbl_extend('keep', { desc = "Log [O]ptions" }, opts))
	vim.keymap.set('n', '<leader>jc', function() Commands.commit_change() end,
		vim.tbl_extend('keep', { desc = "[C]ommit Change" }, opts))
	vim.keymap.set('n', '<leader>jn', function() Commands.new_change() end,
		vim.tbl_extend('keep', { desc = "[N]ew Change" }, opts))
	vim.keymap.set('n', '<leader>jp', function() Commands.git_push() end,
		vim.tbl_extend('keep', { desc = "Git [P]ush" }, opts))
	vim.keymap.set('n', '<leader>jrb', function() Commands.rebase_change() end,
		vim.tbl_extend('keep', { desc = "[R]e[B]ase Change" }, opts))
	vim.keymap.set('n', '<leader>jS', function() Commands.split_change() end,
		vim.tbl_extend('keep', { desc = "[S]plit Change" }, opts))
	vim.keymap.set('n', '<leader>jrm', function() Commands.rebase_onto_master() end,
		vim.tbl_extend('keep', { desc = "[R]ebase onto [M]aster" }, opts))
	vim.keymap.set('n', '<leader>jsq', function() Commands.squash_change() end,
		vim.tbl_extend('keep', { desc = "[S]quash Change" }, opts))
	vim.keymap.set('n', '<leader>jsw', function() Commands.squash_workflow() end,
		vim.tbl_extend('keep', { desc = "[S]quash [W]orkflow" }, opts))
	vim.keymap.set('n', '<leader>jol', function() Log.toggle_operation_log() end,
		vim.tbl_extend('keep', { desc = "[O]peration [L]og Toggle" }, opts))
	vim.keymap.set('n', '<leader>jam', function() Commands.abandon_multiple_changes() end,
		vim.tbl_extend('keep', { desc = "[A]bandon [M]ultiple Changes" }, opts))
end

-- Expose public API functions needed by internal keymaps (require('jujutsu')...)
-- ... (existing assignments) ...
M.toggle_log_window = Log.toggle_log_window
M.edit_change = Commands.edit_change
M.jump_next_change = Log.jump_next_change
M.jump_prev_change = Log.jump_prev_change
M.describe_change = Commands.describe_change
M.new_change = Commands.new_change
M.abandon_change = Commands.abandon_change
M.show_status = Status.show_status
M.set_log_limit = Log.set_log_limit
M.set_revset_filter = Log.set_revset_filter
M.search_in_log = Log.search_in_log
M.change_log_template = Log.change_log_template
M.commit_change = Commands.commit_change
M.close_status_window = Status.close_status_window
M.refresh_status = Status.refresh_status
M.reset_log_settings = Log.reset_log_settings
M.toggle_log_help = Log.toggle_help_window
M.close_log_help = Log.close_help_window
M.create_bookmark = Commands.create_bookmark
M.delete_bookmark = Commands.delete_bookmark
M.move_bookmark = Commands.move_bookmark
M.git_push = Commands.git_push
M.rebase_change = Commands.rebase_change
M.split_change = Commands.split_change
M.squash_change = Commands.squash_change
M.squash_workflow = Commands.squash_workflow
M.rebase_onto_master = Commands.rebase_onto_master
M.show_diff = Commands.show_diff
M.toggle_operation_log = Log.toggle_operation_log
M.abandon_multiple_changes = Commands.abandon_multiple_changes


-- Return the main module table M
return M
