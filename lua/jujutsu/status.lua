-- lua/jujutsu/status.lua
-- Status window management and keymaps

local Status = {}

-- Reference to the main module's state (set via init)
local M_ref = nil

-- Helper function to set keymaps for status buffer
local function setup_status_buffer_keymaps(buf)
	vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':lua require("jujutsu").close_status_window()<CR>',
		{ noremap = true, silent = true, desc = "Close status window" })
	vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':lua require("jujutsu").close_status_window()<CR>',
		{ noremap = true, silent = true, desc = "Close status window" })
	vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>', ':lua require("jujutsu").close_status_window()<CR>',
		{ noremap = true, silent = true, desc = "Close status window" })
	vim.api.nvim_buf_set_keymap(buf, 'n', 'r', ':lua require("jujutsu").refresh_status()<CR>',
		{ noremap = true, silent = true, desc = "Refresh status" })
end

-- Function to show status in a floating window
function Status.show_status()
	-- Close existing status window if it exists
	if M_ref.status_win and vim.api.nvim_win_is_valid(M_ref.status_win) then
		Status.close_status_window() -- Use the close function
		return
	end

	-- Create a new scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	M_ref.status_buf = buf

	-- Set buffer name/title
	vim.api.nvim_buf_set_name(buf, "JJ Status")

	-- Calculate window size and position - made smaller
	local width = math.floor(vim.o.columns * 0.6) -- Reduced from 0.8
	local height = math.floor(vim.o.lines * 0.5) -- Reduced from 0.8
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	-- Create floating window
	local win_opts = {
		relative = "editor",
		width = width,
		height = height,
		col = col,
		row = row,
		style = "minimal",
		border = "rounded"
	}

	M_ref.status_win = vim.api.nvim_open_win(buf, true, win_opts)

	-- Run jj st in a terminal
	vim.fn.termopen("jj st", {
		on_exit = function()
			local current_win = M_ref.status_win -- Capture at time of call
			-- Check if window still exists
			if not current_win or not vim.api.nvim_win_is_valid(current_win) then
				-- If the window ID we stored is no longer valid, ensure state is cleared
				if M_ref.status_win == current_win then
					M_ref.status_win = nil
					M_ref.status_buf = nil
				end
				return
			end
			-- Switch to normal mode
			vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, true, true), 'n', true)
			-- Set buffer as read-only
			vim.bo[buf].modifiable = false
			vim.bo[buf].readonly = true
			-- Set keymaps
			setup_status_buffer_keymaps(buf)
		end
	})
end

-- Function to close the status window
function Status.close_status_window()
	if M_ref.status_win and vim.api.nvim_win_is_valid(M_ref.status_win) then
		vim.api.nvim_win_close(M_ref.status_win, true)
	end
	-- Always clear state after attempting close
	M_ref.status_win = nil
	M_ref.status_buf = nil
end

-- Function to refresh the status window
function Status.refresh_status()
	if M_ref.status_win and vim.api.nvim_win_is_valid(M_ref.status_win) then
		-- Remember the window ID
		local win_id = M_ref.status_win
		-- Create a new buffer
		local new_buf = vim.api.nvim_create_buf(false, true)
		-- Set buffer name (optional, but good practice)
		vim.api.nvim_buf_set_name(new_buf, "JJ Status")
		-- Set the buffer in the window
		vim.api.nvim_win_set_buf(win_id, new_buf)
		-- Update the buffer reference
		M_ref.status_buf = new_buf
		-- Run jj st again
		vim.fn.termopen("jj st", {
			on_exit = function()
				-- Check if window still exists
				if not vim.api.nvim_win_is_valid(win_id) then
					if M_ref.status_win == win_id then -- Clear state if it matches
						M_ref.status_win = nil
						M_ref.status_buf = nil
					end
					return
				end
				-- Switch to normal mode
				vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-\\><C-n>', true, true, true), 'n', true)
				-- Set buffer as read-only
				vim.bo[new_buf].modifiable = false
				vim.bo[new_buf].readonly = true
				-- Set keymaps
				setup_status_buffer_keymaps(new_buf)
			end
		})
	else
		-- If window doesn't exist, create a new one
		Status.show_status()
	end
end

-- Initialize the module with a reference to the main state
function Status.init(main_module_ref)
	M_ref = main_module_ref
end

return Status
