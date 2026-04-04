# 🐧 `penguin.nvim` Plan

> A fast command-history picker for Neovim.
> Telescope-like presentation, but smaller, lighter, and built around a C hot path.

## 🎯 What `penguin.nvim` Is

`penguin.nvim` is a focused picker for Ex command history.

The plugin opens a floating interface that:

- shows recent commands first when the query is empty
- fuzzily filters command history as the user types
- feels immediate and lightweight
- keeps the hot filtering path in C
- exposes a small Lua API
- supports both native Neovim and `lazy.nvim` installation

## 🚫 What V1 Is Not

Version 1 is intentionally narrow.

Not in V1:

- generic file picking
- buffer switching
- command palette for all commands
- search history
- Telescope dependency
- broad fuzzy-everything scope creep

V1 is about one thing only:

- excellent command-history search and execution

## ✨ Core UX

### Empty Query

Opening the picker with no query shows recent commands first.

```text
┌─ penguin.nvim ────────────────────────────────┐
│ :                                             │
├───────────────────────────────────────────────┤
│ 1  edit ~/.config/nvim/init.lua               │
│ 2  Lazy                                       │
│ 3  ls                                         │
│ 4  checkhealth                                │
│ 5  bdelete                                    │
│ 6  write                                      │
└───────────────────────────────────────────────┘
```

### Fuzzy Filtering

Filtering is fuzzy from the start.

The user does not need:

- exact substring matches
- exact full commands
- exact spacing between query tokens
- exact word order

Examples:

```text
history: "checkhealth"
query:   "ckh"
expect:  match
```

```text
history: "vertical botright split"
query:   "spl bot"
expect:  match
```

```text
history: "vertical botright split"
query:   "splbot"
expect:  match
```

```text
history: "lua require('penguin').open()"
query:   "pgo"
expect:  match
```

```text
history: "write"
query:   "zz"
expect:  no match
```

### Interaction

Initial interaction model:

- `:Penguin` opens the picker
- `Enter` executes the selected command
- `Esc` closes the picker
- `Up` / `Down` move selection
- `Ctrl-j` / `Ctrl-k` may be supported as alternates

Later interaction:

- edit-before-run action
- guarded empty-buffer `Enter` shortcut

## 🧱 Architecture

The architecture stays deliberately small.

```text
Lua layer
  ├─ setup/config
  ├─ command registration
  ├─ history collection from Neovim
  ├─ floating UI
  ├─ picker session lifecycle
  └─ bridge to native filter

C layer
  ├─ fuzzy match engine
  ├─ scoring and ranking
  └─ compact result indexes returned to Lua
```

### Planned Layout

```text
plugin/penguin.lua          -- user command wiring
lua/penguin/init.lua        -- public API
lua/penguin/config.lua      -- options and defaults
lua/penguin/history.lua     -- command-history collection/normalization
lua/penguin/ui.lua          -- floating window rendering
lua/penguin/session.lua     -- open/update/select lifecycle
lua/penguin/dev.lua         -- local dev helpers

src/penguin_filter.c        -- hot filtering path
src/penguin_filter.h        -- native internal API if needed

scripts/minimal_init.lua    -- local test entrypoint
tests/...                   -- tests and fixtures
Makefile                    -- build/dev/test/bench targets
README.md                   -- installation and usage
```

## ⚡ Performance Principles

`penguin.nvim` is performance-sensitive by design.

Non-negotiable principles:

- command-history only in V1
- small dependency surface
- no heavy framework dependency
- minimal allocations on the typing hot path
- normalized history cached outside the per-keystroke path
- compact Lua/C boundary
- measurable benchmarks for every meaningful optimization

## 🧠 Fuzzy Matching Direction

The matcher is fuzzy and practical, not pedantic.

### Required Properties

- case-insensitive matching
- incomplete query support
- non-contiguous character matching
- optional spaces between logical query tokens
- practical tolerance for non-exact word order
- intuitive ranking

### Scoring Direction

Initial ranking priorities:

- strong fuzzy match quality
- useful recency behavior
- stable ordering

Later ranking refinements may include:

- prefix bonus
- word-boundary bonus
- adjacency bonus
- token coverage bonus
- shorter-command bias

## 🪜 Iterative Roadmap

Each implementation diff should stay tiny and easy to review.

### 🟩 Step 1: Skeleton

- create plugin layout
- add `README.md`
- add `PLAN.md`
- add stub `:Penguin` command

### 🟩 Step 2: Pure Lua Vertical Slice

- collect Ex command history
- open a floating picker
- render history entries
- empty query shows recent-first ordering
- Lua-only filtering

Purpose:

- prove the UX before moving the hot path to C

### 🟨 Step 3: Local Dev Workflow

- add `scripts/minimal_init.lua`
- add a simple manual runner entrypoint for launching a clean Neovim with `penguin.nvim`
- add a simple headless verification script so the basic load/check flow is easy to rerun
- support local runtimepath activation
- support local `lazy.nvim` activation
- add a simple run target

Purpose:

- make manual iteration trivial
- make it easy to keep a copyable local test flow in the repo

### 🟨 Step 4: Native Filter MVP

- compile native module
- expose a small Lua-facing filter API
- replace Lua hot-path filtering with C filtering
- preserve the same visible behavior as Step 2

Purpose:

- move the hot path to C without changing the product shape

### 🟨 Step 5: Execute Selected Command

- run selected command
- close picker cleanly
- handle state transitions safely

### 🟨 Step 6: Guarded Empty-Buffer `Enter`

- provide an opt-in helper
- only activate in normal mode
- only activate in empty unnamed buffers
- keep it easy to disable

Purpose:

- test the shortcut safely before treating it as a promoted default

### 🟥 Step 7: Optimization Pass

- profile hot paths
- reduce allocations
- tighten ranking logic
- add microbenchmarks
- compare candidate implementations against the same fixtures

### 🟥 Step 8: Hardening

- edge-case handling
- error handling
- filter fixtures
- docs polish
- install/build polish

## 🧪 Filter Test Plan

Filter behavior is part of the product contract.

That means the matcher must be tested with example-driven fixtures, not only unit tests for internals.

Fixture coverage should include:

- positive fuzzy matches
- negative matches
- spacing-insensitive queries
- non-contiguous character matches
- non-exact word-order cases
- ranking expectations where important

Example fixture set:

```text
history: "checkhealth"
query:   "ckh"
expect:  match
```

```text
history: "vertical botright split"
query:   "spl bot"
expect:  match
```

```text
history: "vertical botright split"
query:   "splbot"
expect:  match
```

```text
history: "lua require('penguin').open()"
query:   "pgo"
expect:  match
```

```text
history: "write"
query:   "zz"
expect:  no match
```

New real-world examples should be added as permanent fixtures whenever useful matching behavior is discovered or refined.

## ⏱️ Benchmark Plan

Benchmarking is part of the design, not an afterthought.

The benchmark harness must make it easy to compare:

- baseline vs optimized implementation
- Lua matcher vs C matcher
- small vs medium vs large histories
- empty query vs short fuzzy query vs multi-token query vs low-match query

The initial benchmark baseline is the pure-Lua matcher.

That baseline exists to answer two questions:

- how fast the current Lua behavior already is
- whether a C rewrite actually produces a meaningful win

### History Sizes

Initial benchmark size buckets:

- 100 entries
- 1,000 entries
- 10,000 entries

These cover light use, typical use, and stress conditions.

### Query Categories

Benchmark queries should include:

- empty query
- short fuzzy query
- multi-token fuzzy query
- low-match query
- no-match query

Examples:

- `""`
- `ls`
- `ckh`
- `spl bot`
- `splbot`
- `git co`
- `zzzz`

### Benchmark Fixtures

Reusable benchmark inputs should include:

- synthetic histories
- fixed query sets
- real-world command-history captures later

### Benchmark Workflow

Every optimization pass should follow the same loop:

1. run the existing benchmark suite
2. make one targeted optimization
3. rerun the exact same benchmark suite
4. compare results side by side

Before the C path exists, the benchmark suite should already run against the Lua matcher alone.

That gives the project an honest starting point and avoids guessing about performance.

### Benchmark Output

Benchmark output should make comparison straightforward:

- backend name, such as `lua` or `c`
- implementation name
- dataset size
- query set
- total time
- per-query time
- median and tail latency where practical

### Important Rule

A faster matcher that breaks expected fuzzy behavior is a regression.

Optimizations are only valid when both of these remain true:

- benchmark results improve or justify the change
- fixture correctness remains intact

## 🧪 Local Activation

Local testing must be easy from the beginning.

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

### Planned Dev Helpers

- `scripts/minimal_init.lua`
- manual launch script for a clean local Neovim session
- headless verification script for quick smoke tests
- `make run`
- `make test`
- `make bench`

## 🧭 Command History Source

Initial data source:

- Neovim Ex command history

Later possibilities:

- search history
- command registry integration
- other picker modes

Those are future concerns. They are not part of V1.

## 🚨 Risks

### `Enter` Mapping Risk

- global `Enter` remapping can be surprising
- activation must be heavily guarded
- opt-in is safer than unconditional default behavior

### Native Build Risk

- build/distribution complexity can outgrow the core plugin
- the native boundary must stay small and simple

### Scope Creep Risk

- turning this into a generic picker would dilute the core idea
- V1 stays focused on command-history quality

## ✅ Definition Of Good V1

`penguin.nvim` is good when:

- opening the picker feels immediate
- filtering keeps up with typing
- fuzzy matching feels forgiving and useful
- empty query surfaces good recent commands
- local development is frictionless
- installation is simple
- the codebase stays small and understandable

## 🗺️ Tiny-Diff Policy

Implementation work follows a strict small-diff rule.

Each diff should ideally do one thing:

- add one file or one small subsystem
- change one behavior at a time
- avoid mixing feature work, refactoring, and optimization

If a diff feels large, it should be split again.

## 🎨 Visual Direction

The picker UI should feel:

- 🧊 compact
- ⚡ immediate
- 🌌 focused
- 🐧 crisp

Visual notes:

- clean floating window
- strong contrast
- subtle accent colors
- minimal chrome
- no overloaded interface

## 📌 Current Build Strategy

Build the plugin in this order:

1. ship a tiny skeleton
2. prove the UX in pure Lua
3. add frictionless local testing
4. move the filter hot path to C
5. add tests and benchmarks that lock behavior down
6. optimize with evidence
