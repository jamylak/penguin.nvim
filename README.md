# `penguin.nvim`

Fast command-history picker for Neovim.

## Status

Early scaffold only.

Current stage:

- plugin loads
- `:Penguin` command exists
- picker UI is not implemented yet

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

At this stage the command only confirms that the plugin is wired correctly.
