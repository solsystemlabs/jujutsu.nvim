-- jujutsu.nvim - Health check module
local M = {}

local function check_jujutsu()
	local health = vim.health or require('health')

	health.start('jujutsu.nvim - Jujutsu integration')

	-- Check Neovim version
	if vim.fn.has('nvim-0.10.0') == 1 then
		health.ok('Neovim 0.10.0+ installed')
	else
		health.error('Neovim 0.10.0+ required')
	end

	-- Check for jujutsu binary
	if vim.fn.executable('jj') == 1 then
		-- Get version
		local handle = io.popen('jj --version 2>&1')
		local result = ""
		if handle then
			result = handle:read("*a") or ""
			handle:close()
		end

		if result and result:match('jj %d+%.%d+%.%d+') then
			health.ok('Jujutsu (jj) is installed: ' .. result:gsub('\n', ''))
		else
			health.warn('Jujutsu (jj) installed but could not determine version')
		end
	else
		health.error('Jujutsu (jj) not found in PATH')
		health.info('Install jujutsu from https://github.com/jj-vcs/jj')
	end

	-- Check plugin configuration
	local status, jujutsu = pcall(require, 'jujutsu')
	if status and jujutsu then
		health.ok('jujutsu.nvim is properly loaded')
	else
		health.error('jujutsu.nvim is not properly loaded')
	end

	-- Check if in a jujutsu repository
	local handle = io.popen('jj status --help 2>&1')
	local output = ""
	if handle then
		output = handle:read("*a") or ""
		handle:close()
	end

	if output:match('usage:') then
		health.ok('Current directory can use jujutsu commands')

		-- Check if in a jujutsu repository
		handle = io.popen('jj status 2>&1')
		output = ""
		if handle then
			output = handle:read("*a") or ""
			handle:close()
		end

		if not output:match('not a jujutsu repository') then
			health.ok('Current directory is in a jujutsu repository')
		else
			health.info('Current directory is not in a jujutsu repository')
			health.info(
				'Run `jj init` to initialize a jujutsu repo or `jj git init` to use with an existing git repo')
		end
	else
		health.warn('Could not determine jujutsu repository status')
	end
end

function M.check()
	check_jujutsu()
end

return M
