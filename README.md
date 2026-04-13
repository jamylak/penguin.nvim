# `penguin.nvim`

Fast command-history picker for Neovim.

## Status

Pure Lua vertical slice.

Current stage:

- plugin loads
- `:Penguin` opens a floating picker
- Ex command history is collected from Neovim
- live Ex command suggestions are merged into non-empty queries
- empty query shows recent commands first
- the native single-token fuzzy runtime slice is the default local dev path
- the Lua matcher path remains available as a comparison baseline only
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
- non-empty queries can show both history hits and live command completions
- `Up` / `Down` to move
- `Ctrl-j` / `Ctrl-k` to move
- `Ctrl-n` / `Ctrl-p` to move
- `Ctrl-w` to delete the previous word
- `Enter` executes the selected item
- `Shift-Enter` executes the current text box contents directly
- `Ctrl-e` fills the text box from the selected item without executing
- `Esc` closes the picker

## Local Development

Manual test session with seeded command history:

```sh
make run
```

That builds the native module first and launches Neovim using [scripts/minimal_native_init.lua](/Users/james/proj/penguin.nvim/scripts/minimal_native_init.lua). It loads `penguin.nvim` from this repo, enables the current native runtime slice, and seeds a few history entries so `:Penguin` is immediately useful.

Lua baseline dev session:

```sh
make run-lua
```

That launches Neovim using [scripts/minimal_init.lua](/Users/james/proj/penguin.nvim/scripts/minimal_init.lua) so the older Lua matcher path stays available for comparison while native remains the default.

At the current rollout stage this is still not the final C-only fuzzy runtime filter. The single-token compact fuzzy path is native, while multi-token and segmented fuzzy behavior still remains in Lua.

Optional native stub build:

```sh
make native
```

Headless native check:

```sh
make check
```

That verifies the native loader and the current native runtime slice.

Headless Lua baseline check:

```sh
make check-lua
```

That runs [scripts/headless_check.lua](/Users/james/proj/penguin.nvim/scripts/headless_check.lua), which keeps the older Lua behavior available as a correctness baseline while native remains the default path.

The Lua path is no longer the default development mode and should not be presented as the normal runtime direction.

Headless benchmark run:

```sh
make bench
```

That runs [scripts/headless_bench.lua](/Users/james/proj/penguin.nvim/scripts/headless_bench.lua), which compares the current Lua exact-scan baseline, native exact-scan baseline, and the current matcher runtime slice across multiple dataset sizes and query scenarios.

The benchmark output includes both raw timings and a simple ASCII bar chart per scenario.
