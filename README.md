# `penguin.nvim`

Fast command-history picker for Neovim.

## Status

Pure Lua vertical slice.

Current stage:

- plugin loads
- `:Penguin` opens a floating picker
- Ex command history is collected from Neovim
- empty query shows recent commands first
- fuzzy filtering runs in Lua
- command execution is not implemented yet

## Installation

### Native Neovim

```lua
vim.opt.runtimepath:append("/Users/james/proj/penguin.nvim")
require("penguin").setup({})
```

### `lazy.nvim`

```lua
{
  dir = "/Users/james/proj/penguin.nvim",
  name = "penguin.nvim",
  config = function()
    require("penguin").setup({})
  end,
}
```

## Usage

Run:

```vim
:Penguin
```

At this stage the picker opens, filters, and navigates, but it does not execute commands yet.

Current controls:

- type to filter
- `Up` / `Down` to move
- `Ctrl-j` / `Ctrl-k` to move
- `Enter` selects the current item and closes the picker
- `Esc` closes the picker
