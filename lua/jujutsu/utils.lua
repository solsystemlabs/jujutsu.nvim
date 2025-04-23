-- lua/jujutsu/utils.lua
-- Utility functions

local Utils = {}

-- Helper function to extract a change ID from a line
function Utils.extract_change_id(line)
	if not line then return nil end

	-- Look for an email address and get the word before it (which should be the change ID)
	local id = line:match("([a-z]+)%s+[a-zA-Z0-9_.+-]+@[a-zA-Z0-9-]+%.[a-zA-Z0-9-.]+")

	-- Check if it's a valid 8-letter change ID
	if id and #id == 8 then
		return id
	end

	return nil
end

-- Helper function to create a selection buffer with checkboxes
function Utils.create_selection_buffer(title, options)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
	vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
	vim.api.nvim_buf_set_option(buf, 'swapfile', false)

	-- Set buffer name
	vim.api.nvim_buf_set_name(buf, title)

	-- Prepare the content with checkboxes
	local content = {
		"# " .. title,
		"# Press Space to toggle selection, Enter to confirm",
		"#",
		"# Selected changes will be marked with [x]",
		"",
	}

	-- Add each option with a checkbox
	for _, option in ipairs(options) do
		table.insert(content, "[ ] " .. option)
	end

	-- Set the content
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, content)
	return buf
end

-- Helper function to open a selection window
function Utils.open_selection_window(buf, items)
	local width = math.floor(vim.o.columns * 0.8)
	local height = math.min(#items + 5, math.floor(vim.o.lines * 0.8))
	local col = math.floor((vim.o.columns - width) / 2)
	local row = math.floor((vim.o.lines - height) / 2)

	local opts = {
		relative = 'editor',
		width = width,
		height = height,
		col = col,
		row = row,
		style = 'minimal',
		border = 'rounded'
	}

	local win = vim.api.nvim_open_win(buf, true, opts)
	local current_win = vim.api.nvim_get_current_win()
	return win, current_win
end

return Utils
