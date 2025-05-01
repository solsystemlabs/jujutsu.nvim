-- Operations log window management

local OperationsLog = {}

-- Reference to the main module's state (set via init)
---@class JujutsuMainRef
---@field operations_log_win number|nil
---@field operations_log_buf number|nil
---@field refresh_log function|nil
local M_ref = nil

local function setup_operations_log_buffer_keymaps(buf)
  local opts = { noremap = true, silent = true }
  local function map(key, cmd, desc)
    vim.api.nvim_buf_set_keymap(buf, 'n', key, cmd, vim.tbl_extend("force", opts, { desc = desc }))
  end

  -- Close window mappings
  map('q', '<Cmd>lua require("jujutsu").close_operations_log_window()<CR>', 'Close operations log window')
  map('<Esc>', '<Cmd>lua require("jujutsu").close_operations_log_window()<CR>', 'Close operations log window with Esc')
  
  -- Navigation between nodes (lines starting with ○)
  map('j', '<Cmd>lua require("jujutsu.operations_log").jump_next_node()<CR>', 'Jump to next node')
  map('k', '<Cmd>lua require("jujutsu.operations_log").jump_prev_node()<CR>', 'Jump to previous node')
  
  -- Disable other common Vim motions
  local disabled_keys = {'h', 'l', 'w', 'b', 'e', '0', '$', 'G', 'gg', '^', '%', '{', '}', '(', ')', '[', ']', '<Up>', '<Down>', '<Left>', '<Right>'}
  for _, key in ipairs(disabled_keys) do
    map(key, '<Nop>', 'Disabled motion')
  end
end

-- Function to find the next or previous node (line starting with ○ or @)
function OperationsLog.jump_next_node()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  if not cursor_pos then return end
  local current_line = cursor_pos[1]
  local line_count = vim.api.nvim_buf_line_count(0)
  local found_line = nil

  for i = current_line + 1, line_count do
    local lines = vim.api.nvim_buf_get_lines(0, i - 1, i, false)
    if lines and #lines > 0 and (lines[1]:match("^○") or lines[1]:match("^@")) then
      found_line = i
      break
    end
  end

  if found_line then
    vim.api.nvim_win_set_cursor(0, { found_line, 0 })
  else
    vim.api.nvim_echo({ { "No more nodes below", "WarningMsg" } }, false, {})
  end
end

function OperationsLog.jump_prev_node()
  local cursor_pos = vim.api.nvim_win_get_cursor(0)
  if not cursor_pos then return end
  local current_line = cursor_pos[1]
  local found_line = nil

  for i = current_line - 1, 1, -1 do
    local lines = vim.api.nvim_buf_get_lines(0, i - 1, i, false)
    if lines and #lines > 0 and (lines[1]:match("^○") or lines[1]:match("^@")) then
      found_line = i
      break
    end
  end

  if found_line then
    vim.api.nvim_win_set_cursor(0, { found_line, 0 })
  else
    vim.api.nvim_echo({ { "No more nodes above", "WarningMsg" } }, false, {})
  end
end

function OperationsLog.show_operations_log()
  if M_ref.operations_log_win and vim.api.nvim_win_is_valid(M_ref.operations_log_win) then
    OperationsLog.close_operations_log_window()
    return
  end

  -- Create a new vertical split window
  vim.cmd("botright vsplit")
  M_ref.operations_log_win = vim.api.nvim_get_current_win()

  -- Check if window creation failed
  if not M_ref.operations_log_win or not vim.api.nvim_win_is_valid(M_ref.operations_log_win) then
    vim.api.nvim_echo({ { "Failed to create split window for operations log.", "ErrorMsg" } }, true, {})
    M_ref.operations_log_win = nil
    return
  end

  -- Set window options (like size)
  vim.cmd("vertical resize 80")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "JJ Operations Log")

  M_ref.operations_log_buf = buf

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false

  -- Set this buffer into the window
  vim.api.nvim_win_set_buf(M_ref.operations_log_win, buf)

  setup_operations_log_buffer_keymaps(buf)

  vim.fn.termopen("jj op log", {
    on_exit = function()
      local current_win = M_ref.operations_log_win
      if not current_win or not vim.api.nvim_win_is_valid(current_win) then
        if M_ref.operations_log_win == current_win then
          M_ref.operations_log_win = nil
          M_ref.operations_log_buf = nil
        end
        return
      end
      vim.api.nvim_win_set_buf(current_win, M_ref.operations_log_buf)
      vim.bo[M_ref.operations_log_buf].modifiable = false
      vim.bo[M_ref.operations_log_buf].readonly = true
    end
  })
end

function OperationsLog.close_operations_log_window()
  if M_ref.operations_log_win and vim.api.nvim_win_is_valid(M_ref.operations_log_win) then
    vim.api.nvim_win_close(M_ref.operations_log_win, true)
    M_ref.operations_log_win = nil
    M_ref.operations_log_buf = nil
  end
end

function OperationsLog.refresh_operations_log()
  if M_ref.operations_log_win and vim.api.nvim_win_is_valid(M_ref.operations_log_win) then
    local win_id = M_ref.operations_log_win
    local new_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(new_buf, "JJ Operations Log")
    vim.api.nvim_win_set_buf(win_id, new_buf)
    M_ref.operations_log_buf = new_buf

    vim.bo[new_buf].buftype = "nofile"
    vim.bo[new_buf].bufhidden = "hide"
    vim.bo[new_buf].swapfile = false

    setup_operations_log_buffer_keymaps(new_buf)

    vim.fn.termopen("jj op log", {
      on_exit = function()
        if not vim.api.nvim_win_is_valid(win_id) then
          if M_ref.operations_log_win == win_id then
            M_ref.operations_log_win = nil
            M_ref.operations_log_buf = nil
          end
          return
        end
        vim.api.nvim_win_set_buf(win_id, M_ref.operations_log_buf)
        vim.bo[M_ref.operations_log_buf].modifiable = false
        vim.bo[M_ref.operations_log_buf].readonly = true
      end
    })
  end
end

function OperationsLog.init(main_module_ref)
  M_ref = main_module_ref
end

return OperationsLog
