-- jujutsu.nvim - Signs module
-- Handles the sign column integration for jujutsu.nvim

local M = {}
local config = {}
local sign_map = {}
local sign_define_cache = {}

-- Set up signs based on configuration
function M.setup(cfg)
	config = cfg or {}

	-- Define the signs
	for type, sign_def in pairs(config.signs or {}) do
		M.define_sign(type, sign_def)
	end
end

-- Define a sign with the given type and definition
function M.define_sign(type, sign_def)
	local sign_name = "JujutsuSign" .. type:gsub("^%l", string.upper)

	-- Cache sign definition to avoid redundant define_sign calls
	local cached = sign_define_cache[sign_name]
	if cached
	    and cached.text == sign_def.text
	    and cached.texthl == sign_def.texthl
	    and cached.numhl == sign_def.numhl
	    and cached.linehl == sign_def.linehl
	then
		sign_map[type] = sign_name
		return
	end

	sign_define_cache[sign_name] = {
		text = sign_def.text,
		texthl = sign_def.texthl or ("JujutsuSign" .. type:gsub("^%l", string.upper)),
		numhl = config.numhl and ("JujutsuSignNr" .. type:gsub("^%l", string.upper)) or nil,
		linehl = config.linehl and ("JujutsuLine" .. type:gsub("^%l", string.upper)) or nil,
	}

	-- Define highlight groups if they don't exist
	if not sign_def.texthl then
		local hl_exists = vim.fn.hlexists("JujutsuSign" .. type:gsub("^%l", string.upper))
		if hl_exists == 0 then
			-- Default highlight colors similar to gitsigns
			M.define_highlight_groups(type)
		end
	end

	-- Define the sign
	vim.fn.sign_define(sign_name, {
		text = sign_def.text,
		texthl = sign_define_cache[sign_name].texthl,
		numhl = sign_define_cache[sign_name].numhl,
		linehl = sign_define_cache[sign_name].linehl,
	})

	sign_map[type] = sign_name
end

-- Define highlight groups
function M.define_highlight_groups(type)
	if type == "add" then
		vim.api.nvim_set_hl(0, "JujutsuSignAdd", { fg = "#00ff00", ctermfg = "green" })
		if config.numhl then
			vim.api.nvim_set_hl(0, "JujutsuSignNrAdd", { fg = "#00ff00", ctermfg = "green" })
		end
		if config.linehl then
			vim.api.nvim_set_hl(0, "JujutsuLineAdd", { bg = "#005500", ctermbg = "darkgreen" })
		end
	elseif type == "change" then
		vim.api.nvim_set_hl(0, "JujutsuSignChange", { fg = "#ffff00", ctermfg = "yellow" })
		if config.numhl then
			vim.api.nvim_set_hl(0, "JujutsuSignNrChange", { fg = "#ffff00", ctermfg = "yellow" })
		end
		if config.linehl then
			vim.api.nvim_set_hl(0, "JujutsuLineChange", { bg = "#555500", ctermbg = "darkyellow" })
		end
	elseif type == "delete" then
		vim.api.nvim_set_hl(0, "JujutsuSignDelete", { fg = "#ff0000", ctermfg = "red" })
		if config.numhl then
			vim.api.nvim_set_hl(0, "JujutsuSignNrDelete", { fg = "#ff0000", ctermfg = "red" })
		end
		if config.linehl then
			vim.api.nvim_set_hl(0, "JujutsuLineDelete", { bg = "#550000", ctermbg = "darkred" })
		end
	elseif type == "topdelete" then
		vim.api.nvim_set_hl(0, "JujutsuSignTopDelete", { fg = "#ff0000", ctermfg = "red" })
		if config.numhl then
			vim.api.nvim_set_hl(0, "JujutsuSignNrTopDelete", { fg = "#ff0000", ctermfg = "red" })
		end
		if config.linehl then
			vim.api.nvim_set_hl(0, "JujutsuLineTopDelete", { bg = "#550000", ctermbg = "darkred" })
		end
	elseif type == "changedelete" then
		vim.api.nvim_set_hl(0, "JujutsuSignChangeDelete", { fg = "#ff5000", ctermfg = "red" })
		if config.numhl then
			vim.api.nvim_set_hl(0, "JujutsuSignNrChangeDelete", { fg = "#ff5000", ctermfg = "red" })
		end
		if config.linehl then
			vim.api.nvim_set_hl(0, "JujutsuLineChangeDelete", { bg = "#553000", ctermbg = "darkred" })
		end
	elseif type == "untracked" then
		vim.api.nvim_set_hl(0, "JujutsuSignUntracked", { fg = "#00ffff", ctermfg = "cyan" })
		if config.numhl then
			vim.api.nvim_set_hl(0, "JujutsuSignNrUntracked", { fg = "#00ffff", ctermfg = "cyan" })
		end
		if config.linehl then
			vim.api.nvim_set_hl(0, "JujutsuLineUntracked", { bg = "#005555", ctermbg = "darkcyan" })
		end
	end
end

-- Place a sign at a specific line
function M.add(bufnr, lnum, sign_type, priority)
	if not config.signcolumn then
		return
	end

	local sign_name = sign_map[sign_type]
	if not sign_name then
		return
	end

	-- Generate a unique ID for this sign based on buffer and line number
	local id = bufnr * 100000 + lnum

	-- Place the sign
	vim.fn.sign_place(
		id,                                 -- Sign ID
		"jujutsu",                          -- Sign group
		sign_name,                          -- Sign name
		bufnr,                              -- Buffer number
		{
			lnum = lnum,                -- Line number
			priority = priority or config.sign_priority or 6 -- Sign priority
		}
	)
end

-- Remove a sign from a specific line
function M.remove(bufnr, lnum)
	-- Generate the ID for the sign at this line
	local id = bufnr * 100000 + lnum

	-- Remove the sign
	vim.fn.sign_unplace(
		"jujutsu", -- Sign group
		{
			buffer = bufnr, -- Buffer number
			id = id -- Sign ID
		}
	)
end

-- Remove all signs from a buffer
function M.remove_all(bufnr)
	vim.fn.sign_unplace(
		"jujutsu", -- Sign group
		{
			buffer = bufnr -- Buffer number
		}
	)
end

-- Update sign configuration
function M.update_config(cfg)
	config = cfg

	-- Redefine the signs with new configuration
	for type, sign_def in pairs(config.signs) do
		M.define_sign(type, sign_def)
	end
end

-- Get sign name for a type
function M.get_sign_name(type)
	return sign_map[type]
end

-- Check if a sign type exists
function M.has_sign_type(type)
	return sign_map[type] ~= nil
end

-- Get the priority for a sign type
function M.get_priority(type)
	return config.sign_priority or 6
end

return M
