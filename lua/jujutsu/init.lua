-- lua/jujutsu/init.lua
-- Main plugin file, state management, setup, public API

local M = {}

-- Load submodules
local Log = require("jujutsu.log")
local Status = require("jujutsu.status")
local Commands = require("jujutsu.commands")
-- Utils is used internally by other modules

-- State variables... (unchanged)
M.log_buf = nil; M.log_win = nil; M.status_buf = nil; M.status_win = nil
M.log_settings = { limit = "", revset = "", template = "", search_pattern = "" }

-- Initialize submodules... (unchanged)
Log.init(M); Status.init(M); Commands.init(M)

-- Delegate log refresh calls... (unchanged)
function M.refresh_log()
	if M.log_win and vim.api.nvim_win_is_valid(M.log_win) then
		Log.refresh_log_buffer()
	end
end

-- Setup global keymaps... (unchanged)
function M.setup()
	vim.keymap.set('n', '<leader>jl', function() Log.toggle_log_window() end, { desc = "[J]ujutsu [L]og Toggle" })
	vim.keymap.set('n', '<leader>js', function() Status.show_status() end, { desc = "[J]ujutsu [S]tatus Show" })
	vim.keymap.set('n', '<leader>jr', function() Log.reset_log_settings() end, { desc = "[J]ujutsu Log [R]eset Settings" })
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
	end, { desc = "[J]ujutsu Log [O]ptions" })
	vim.keymap.set('n', '<leader>jc', function() Commands.commit_change() end, { desc = "[J]ujutsu [C]ommit Change" })
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
M.toggle_log_help = Log.toggle_help_window -- Keep help toggle exposed
M.close_log_help = Log.close_help_window

-- *** ADDED: Expose bookmark functions ***
M.create_bookmark = Commands.create_bookmark
M.delete_bookmark = Commands.delete_bookmark
M.move_bookmark = Commands.move_bookmark


-- Return the main module table M
return M
