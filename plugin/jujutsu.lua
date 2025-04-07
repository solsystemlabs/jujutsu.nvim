-- jujutsu.nvim - Plugin entry point
-- This file is loaded automatically by Neovim

-- Check if Neovim version is compatible
if vim.fn.has('nvim-0.10.0') ~= 1 then
	vim.notify('jujutsu.nvim requires at least Neovim 0.10.0', vim.log.levels.ERROR)
	return
end

-- Check if jujutsu command is available
local jj_available = vim.fn.executable('jj') == 1

if not jj_available then
	vim.notify('jujutsu (jj) command not found. Please install jujutsu first.', vim.log.levels.WARN)
end

-- Create user command to initialize the plugin
vim.api.nvim_create_user_command('JujutsuSetup', function(opts)
	if opts.fargs[1] then
		-- Use load instead of loadstring for Neovim 0.10+
		local config_fn, err = load('return ' .. opts.fargs[1])
		if config_fn then
			require('jujutsu').setup(config_fn())
		else
			vim.notify('Error in configuration: ' .. (err or 'unknown error'), vim.log.levels.ERROR)
		end
	else
		require('jujutsu').setup()
	end
end, {
	nargs = '?',
	desc = 'Setup jujutsu.nvim with optional configuration',
})

-- Setup autocmd for deferred loading
local group = vim.api.nvim_create_augroup('jujutsu_setup', { clear = true })
vim.api.nvim_create_autocmd("VimEnter", {
	group = group,
	callback = function()
		if vim.g.jujutsu_auto_setup then
			-- Use saved config if available
			if vim.g.jujutsu_config then
				local config_fn, err = load('return ' .. vim.g.jujutsu_config)
				if config_fn then
					require('jujutsu').setup(config_fn())
				else
					vim.notify('Error in jujutsu_config: ' .. (err or 'unknown error'),
						vim.log.levels.ERROR)
				end
			else
				require('jujutsu').setup()
			end
		end
	end,
})

-- Return success
return true
