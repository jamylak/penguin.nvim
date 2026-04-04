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
- selected or typed commands can be executed from the picker

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

Or press `Alt-Space` in normal mode.

At this stage the picker opens, filters, navigates, completes, and executes commands from the prompt.

Current controls:

- type to filter
- `Up` / `Down` to move
- `Ctrl-j` / `Ctrl-k` to move
- `Enter` executes the selected item
- `Shift-Enter` executes the current text box contents directly
- `Ctrl-e` fills the text box from the selected item without executing
- `Esc` closes the picker

## Local Development

Manual test session with seeded command history:

```sh
make run
```

That launches a clean Neovim using [scripts/minimal_init.lua](/Users/james/proj/penguin.nvim/scripts/minimal_init.lua), loads `penguin.nvim` from this repo, and seeds a few history entries so `:Penguin` is immediately useful.

Headless smoke check:

```sh
make check
```

That runs [scripts/headless_check.lua](/Users/james/proj/penguin.nvim/scripts/headless_check.lua), which verifies basic loading, matcher examples, and picker session startup.
