-- jujutsu.nvim - Highlight module
-- Handles highlighting setup for jujutsu.nvim

local M = {}
local api = vim.api

-- Define highlight groups
function M.setup()
	-- Define hl groups for signs
	api.nvim_set_hl(0, "JujutsuSignAdd", { fg = "#00ff00", ctermfg = "green" })
	api.nvim_set_hl(0, "JujutsuSignChange", { fg = "#ffff00", ctermfg = "yellow" })
	api.nvim_set_hl(0, "JujutsuSignDelete", { fg = "#ff0000", ctermfg = "red" })
	api.nvim_set_hl(0, "JujutsuSignTopDelete", { fg = "#ff0000", ctermfg = "red" })
	api.nvim_set_hl(0, "JujutsuSignChangeDelete", { fg = "#ff5000", ctermfg = "red" })
	api.nvim_set_hl(0, "JujutsuSignUntracked", { fg = "#00ffff", ctermfg = "cyan" })

	-- Define hl groups for line numbers when numhl is enabled
	api.nvim_set_hl(0, "JujutsuSignNrAdd", { fg = "#00ff00", ctermfg = "green" })
	api.nvim_set_hl(0, "JujutsuSignNrChange", { fg = "#ffff00", ctermfg = "yellow" })
	api.nvim_set_hl(0, "JujutsuSignNrDelete", { fg = "#ff0000", ctermfg = "red" })
	api.nvim_set_hl(0, "JujutsuSignNrTopDelete", { fg = "#ff0000", ctermfg = "red" })
	api.nvim_set_hl(0, "JujutsuSignNrChangeDelete", { fg = "#ff5000", ctermfg = "red" })
	api.nvim_set_hl(0, "JujutsuSignNrUntracked", { fg = "#00ffff", ctermfg = "cyan" })

	-- Define hl groups for line highlighting when linehl is enabled
	api.nvim_set_hl(0, "JujutsuLineAdd", { bg = "#005500", ctermbg = "darkgreen" })
	api.nvim_set_hl(0, "JujutsuLineChange", { bg = "#555500", ctermbg = "darkyellow" })
	api.nvim_set_hl(0, "JujutsuLineDelete", { bg = "#550000", ctermbg = "darkred" })
	api.nvim_set_hl(0, "JujutsuLineTopDelete", { bg = "#550000", ctermbg = "darkred" })
	api.nvim_set_hl(0, "JujutsuLineChangeDelete", { bg = "#553000", ctermbg = "darkred" })
	api.nvim_set_hl(0, "JujutsuLineUntracked", { bg = "#005555", ctermbg = "darkcyan" })

	-- Define log window highlights
	api.nvim_set_hl(0, "JujutsuLogNormal", { link = "Normal" })
	api.nvim_set_hl(0, "JujutsuLogBorder", { link = "FloatBorder" })
	api.nvim_set_hl(0, "JujutsuCommitId", { fg = "#88ccff", ctermfg = "cyan", bold = true })
	api.nvim_set_hl(0, "JujutsuAuthor", { fg = "#99cc99", ctermfg = "green" })
	api.nvim_set_hl(0, "JujutsuDate", { fg = "#cccccc", ctermfg = "white" })
	api.nvim_set_hl(0, "JujutsuGraph", { fg = "#666666", ctermfg = "gray" })
	api.nvim_set_hl(0, "JujutsuBookmark", { fg = "#ff88ff", ctermfg = "magenta", bold = true })
	api.nvim_set_hl(0, "JujutsuWorkingCopy", { fg = "#ffcc66", ctermfg = "yellow", bold = true })
end

return M
