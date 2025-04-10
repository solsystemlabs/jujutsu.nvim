-- lua/jujutsu/init.lua
-- Main plugin file, state management, setup, public API

local M = {}

-- Load submodules
local Log = require("jujutsu.log")
local Status = require("jujutsu.status")
local Commands = require("jujutsu.commands")
-- Utils is used internally by other modules

-- Track the buffer ID
M.log_buf = nil
-- Track the window ID that contains the log buffer
M.log_win = nil
-- Track the status buffer and window IDs
M.status_buf = nil
M.status_win = nil

-- Store the current log settings
M.log_settings = {
	limit = "",        -- "" means no limit
	revset = "",       -- "" means default revset
	template = "",     -- "" means default template
	search_pattern = "" -- "" means no search pattern
}

-- Initialize submodules, passing the main module reference (M)
Log.init(M)
Status.init(M)
Commands.init(M)

-- Function to delegate log refresh calls to the Log module
-- Ensures the log window is valid before attempting refresh
function M.refresh_log()
	if M.log_win and vim.api.nvim_win_is_valid(M.log_win) then
		Log.refresh_log_buffer() -- Call the actual refresh logic
	end
end

-- Setup global keymaps
function M.setup()
	-- Changed to use 'j' namespace for global hotkeys with descriptive comments for WhichKey
	vim.keymap.set('n', '<leader>jl', function()
		Log.toggle_log_window()                -- Call Log module function
	end, { desc = "[J]ujutsu [L]og Toggle" }) -- Updated description slightly

	-- Added global mapping for showing status
	vim.keymap.set('n', '<leader>js', function()
		Status.show_status()                    -- Call Status module function
	end, { desc = "[J]ujutsu [S]tatus Show" }) -- Updated description slightly

	-- Add a mapping for resetting log settings
	vim.keymap.set('n', '<leader>jr', function()
		Log.reset_log_settings()                       -- Call Log module function
	end, { desc = "[J]ujutsu Log [R]eset Settings" }) -- Updated description slightly

	-- Add mapping for advanced log options menu
	vim.keymap.set('n', '<leader>jo', function()
		vim.ui.select(
			{
				"Set Limit",
				"Set Revset Filter",
				"Search in Log",
				"Change Template",
				"Reset Settings"
			},
			{
				prompt = "Select a Jujutsu log option:", -- Slightly updated prompt
			},
			function(choice)
				if choice == nil then return end -- Handle cancellation
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
			end
		)
	end, { desc = "[J]ujutsu Log [O]ptions" }) -- Updated description slightly

	-- Add mapping for commit command
	vim.keymap.set('n', '<leader>jc', function()
		Commands.commit_change()                  -- Call Commands module function
	end, { desc = "[J]ujutsu [C]ommit Change" }) -- Updated description slightly
end

-- Expose public API functions needed by internal keymaps (require('jujutsu')...)
-- These delegate to the appropriate submodule functions.
M.toggle_log_window = Log.toggle_log_window
M.edit_change = Commands.edit_change
M.jump_next_change = Log.jump_next_change
M.jump_prev_change = Log.jump_prev_change
M.describe_change = Commands.describe_change
M.new_change = Commands.new_change
M.abandon_change = Commands.abandon_change
M.show_status = Status.show_status -- Needed by 's' in log buffer AND <leader>js
M.set_log_limit = Log.set_log_limit
M.set_revset_filter = Log.set_revset_filter
M.search_in_log = Log.search_in_log
M.change_log_template = Log.change_log_template
M.commit_change = Commands.commit_change -- Needed by 'c' in log buffer AND <leader>jc
M.close_status_window = Status.close_status_window
M.refresh_status = Status.refresh_status
M.reset_log_settings = Log.reset_log_settings -- Expose for consistency, used by <leader>jr menu


-- Return the main module table M, which includes the setup function and public API
return M
