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

  map('q', '<Cmd>lua require("jujutsu").close_operations_log_window()<CR>', 'Close operations log window')
end

function OperationsLog.show_operations_log()
  if M_ref.operations_log_win and vim.api.nvim_win_is_valid(M_ref.operations_log_win) then
    OperationsLog.close_operations_log_window()
    return
  end

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "JJ Operations Log")

  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    col = col,
    row = row,
    style = 'minimal',
    border = 'rounded',
  })

  M_ref.operations_log_win = win
  M_ref.operations_log_buf = buf

  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false

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
