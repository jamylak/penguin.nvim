# 🧩 Native Rollout Plan

> Small, reviewable steps for moving `penguin.nvim` filtering to C.

## Goal

The runtime target is:

- C-only filtering
- no Lua fallback in normal operation
- Lua matcher deleted after C is validated
- long-lived native matcher state reused across queries
- zero fresh allocations on the steady-state query path
- temporary Lua-to-C build handoff only; matcher-owned memory lives natively after construction

To get there without huge diffs, native work should land in tiny vertical slices.

## Step A: Build Plumbing Only

- add native build target
- add ignored build output directory
- add empty or tiny exported C stub
- add Lua loader stub
- no matcher behavior change

Review rule:

- this step must not change picker behavior

## Step B: Tiny Exported Function

- add one very small exported C function
- keep behavior intentionally narrow
- verify it can be called from Lua

Example scope:

- exact substring only
- or one trivial score function

## Step C: Temporary Wiring

- call the C function from Lua behind a temporary development switch
- keep Lua matcher as a development reference only
- verify identical call flow around the boundary

Caveat:

- this switch is transitional scaffolding only
- it should not remain as a permanent user-facing runtime mode

## Step D: Port Features One By One

Port matcher behavior in narrow slices:

- first add native matcher-state construction and lifetime
- then move candidate ownership and reusable result buffers into native matcher state
- start with exact-only bulk filtering if that keeps the diff tiny
- subsequence matching
- token splitting
- segmented single-token matching such as `splbot`
- scoring and ranking details

Each slice should:

- add one behavior
- add one or a few focused checks
- stay small enough to review quickly

Still missing before the final fast path:

- native-owned corpus preprocessing at build time
- normalized text and metadata stored in C
- full query-time matching and scoring in C
- native top-k selection / ranking
- compact result records returned to Lua only
- final benchmark, assembly, and SIMD validation passes

## Step E: Remove Lua Runtime Path

- make C the only runtime backend
- delete Lua fallback behavior
- keep benchmark and correctness evidence for the transition

## Benchmark Principle

Benchmarking should compare:

- naive Lua
- transitional Lua + C slices
- naive C
- optimized Lua + C runtime shape
- optimized C
- assembly-aware native tuning when useful
- SIMD-aware native tuning when useful

The benchmark harness should run inside real headless Neovim with fixed in-memory datasets and repeated matcher calls.
