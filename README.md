# jujutsu.nvim

A Neovim plugin for [Jujutsu](https://github.com/jj-vcs/jj) (jj) integration, providing gitsigns-like functionality for Jujutsu repositories.

## Features

- Shows Jujutsu (jj) status in the sign column
- Integrates with Jujutsu's unique working copy model
- Provides commands for common Jujutsu operations:
  - Create new changes (`jj new`)
  - Squash changes (`jj squash`)
  - Edit commit messages (`jj describe`)
  - Navigate between hunks in files
  - Show status and diffs in split windows
- Automatically detects Jujutsu repositories
- Syntax highlighting for Jujutsu output

## Requirements

- Neovim 0.10.0 or higher
- [Jujutsu](https://github.com/jj-vcs/jj) installed and available in your PATH

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'yourusername/jujutsu.nvim',
  config = function()
    require('jujutsu').setup()
  end,
  dependencies = {
    -- Optional dependencies, if you want to use them
  }
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'yourusername/jujutsu.nvim',
  config = function()
    require('jujutsu').setup()
  end
}
```

### Using [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'yourusername/jujutsu.nvim'

" In your init.vim or after/plugin/jujutsu.vim:
lua require('jujutsu').setup()
```

## Configuration

### Default Configuration

```lua
require('jujutsu').setup({
  signs = {
    add          = { text = '│' },
    change       = { text = '│' },
    delete       = { text = '_' },
    topdelete    = { text = '‾' },
    changedelete = { text = '~' },
    untracked    = { text = '┆' },
  },
  signcolumn = true,  -- Toggle with `:JujutsuToggleSignsColumn`
  numhl      = false, -- Toggle with `:JujutsuToggleNumhl`
  linehl     = false, -- Toggle with `:JujutsuToggleLinehl`
  word_diff  = false, -- Toggle with `:JujutsuToggleWordDiff`
  watch_index = {
    interval = 1000,
    follow_files = true,
  },
  attach_to_untracked = true,
  jujutsu_cmd = "jj", -- Path to jujutsu command

  -- You can disable the default keymaps by setting on_attach to false
  on_attach = nil, -- Or provide a custom function
})
```

### Custom Key Mappings

By default, the following key mappings are set up:

| Mapping      | Description                                   |
| ------------ | --------------------------------------------- |
| `<leader>jn` | Next hunk                                     |
| `<leader>jp` | Previous hunk                                 |
| `<leader>js` | Stage hunk (informational in jj)              |
| `<leader>ju` | Undo stage hunk (offers to create new change) |
| `<leader>jr` | Reset hunk                                    |
| `<leader>jb` | Show blame                                    |
| `<leader>jd` | Show diff                                     |
| `<leader>jS` | Show status                                   |
| `<leader>jN` | Create new change                             |
| `<leader>jq` | Squash changes                                |
| `<leader>je` | Edit parent change                            |
| `<leader>jm` | Edit commit message                           |

You can disable the default key mappings and set up your own:

```lua
require('jujutsu').setup({
  -- Other options...

  -- Disable default keymaps
  on_attach = false,
})

-- Then set up your own mappings
vim.keymap.set('n', '<leader>jn', require('jujutsu').next_hunk, { desc = 'Next jujutsu hunk' })
vim.keymap.set('n', '<leader>jp', require('jujutsu').prev_hunk, { desc = 'Previous jujutsu hunk' })
-- ... other mappings
```

Or provide a custom on_attach function:

```lua
require('jujutsu').setup({
  -- Other options...

  -- Custom on_attach function
  on_attach = function(bufnr)
    local jj = require('jujutsu')

    -- Define your mappings here
    vim.keymap.set('n', '<leader>jn', jj.next_hunk, { buffer = bufnr, desc = 'Next jujutsu hunk' })
    -- ... other mappings
  end,
})
```

## Commands

| Command                     | Description                       |
| --------------------------- | --------------------------------- |
| `:JujutsuStatus`            | Show jujutsu status               |
| `:JujutsuDiff [args]`       | Show diff with optional arguments |
| `:JujutsuNew`               | Create a new change               |
| `:JujutsuSquash`            | Squash changes into parent        |
| `:JujutsuEdit`              | Edit parent commit                |
| `:JujutsuDescribe`          | Edit commit message               |
| `:JujutsuBlame`             | Show blame information            |
| `:JujutsuToggleSignsColumn` | Toggle signs column               |
| `:JujutsuToggleNumhl`       | Toggle number highlight           |
| `:JujutsuToggleLinehl`      | Toggle line highlight             |
| `:JujutsuUpdateNow`         | Update signs now                  |

## Understanding Jujutsu vs Git

Jujutsu has a different working model than Git that affects this plugin's functionality:

1. **Working Copy as a Commit**: In Jujutsu, the working copy is automatically committed. Each file change is recorded immediately as part of the working copy commit.

2. **No Index/Staging Area**: Jujutsu doesn't have a concept of an index or staging area. All changes are automatically tracked.

3. **Change ID vs Commit ID**: Jujutsu distinguishes between a "change ID" (stable identifier for a change that can evolve) and a "commit ID" (hash of a specific state of a change).

4. **Different Commands**: Commands like `jj new`, `jj edit`, and `jj squash` replace Git's commit workflow.

This plugin adapts to Jujutsu's model while providing familiar Git-like workflow commands where possible.

## Common Workflows

### Basic Workflow

1. Make changes to files
2. View the changes with `:JujutsuDiff` or using sign column indicators
3. Once done with your current change, use `:JujutsuNew` to create a new change
4. Add a commit message with `:JujutsuDescribe`

### Editing Earlier Changes

1. Use `:JujutsuEdit` to move to the parent commit
2. Make your changes
3. Optionally, view with `:JujutsuDiff`
4. Either create a new change with `:JujutsuNew` or squash the changes with `:JujutsuSquash`

### Viewing History

1. Use `:JujutsuBlame` to see who modified lines
2. Use `:JujutsuStatus` to see the repository status

## Troubleshooting

### Signs Not Appearing

Make sure you have jujutsu (jj) installed and accessible in your PATH:

```bash
which jj
```

Check if your repository is properly initialized with jujutsu:

```bash
jj status
```

Try explicitly updating the signs:

```vim
:JujutsuUpdateNow
```

### Command Not Found Errors

If you get "command not found" errors, ensure that:

1. Jujutsu is installed and in your PATH
2. The plugin is properly installed
3. You've run the setup function

Run `:checkhealth` to see if there are any issues detected by Neovim.

## License

[MIT](./LICENSE)

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgements

- This plugin is inspired by [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim)
- Thanks to the [Jujutsu](https://github.com/jj-vcs/jj) team for creating an excellent Git-compatible VCS
