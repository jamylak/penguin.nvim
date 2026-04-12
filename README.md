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
- native build plumbing exists, but filtering still runs in Lua
- a temporary native probe path can be enabled for development only
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

Manual native dev session with the temporary probe enabled:

```sh
make run-native
```

That launches Neovim using [scripts/minimal_native_init.lua](/Users/james/proj/penguin.nvim/scripts/minimal_native_init.lua), builds the native module first, and enables the current native exact-filter runtime slice for manual testing.

At the current rollout stage this is still not the final C-only fuzzy runtime filter. The history exact-substring path is native, while broader fuzzy behavior still remains in Lua.

Optional native stub build:

```sh
make native
```

Native loader stub check:

```sh
make check-native
```

That verifies the native loader and a temporary dev-only probe path without changing normal picker behavior.

The probe path is transitional scaffolding for native bring-up only. It is not intended as a permanent user-facing runtime mode.

Headless smoke check:

```sh
make check
```

That runs [scripts/headless_check.lua](/Users/james/proj/penguin.nvim/scripts/headless_check.lua), which verifies basic loading, matcher examples, and picker session startup.

Headless benchmark run:

```sh
make bench
```

That runs [scripts/headless_bench.lua](/Users/james/proj/penguin.nvim/scripts/headless_bench.lua), which compares the current Lua exact-scan baseline and native exact-scan baseline across multiple dataset sizes and query scenarios.

The benchmark output includes both raw timings and a simple ASCII bar chart per scenario.
