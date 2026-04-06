# 🧩 Native Rollout Plan

> Small, reviewable steps for moving `penguin.nvim` filtering to C.

## Goal

The runtime target is:

- C-only filtering
- no Lua fallback in normal operation
- Lua matcher deleted after C is validated

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

## Step D: Port Features One By One

Port matcher behavior in narrow slices:

- subsequence matching
- token splitting
- segmented single-token matching such as `splbot`
- scoring and ranking details

Each slice should:

- add one behavior
- add one or a few focused checks
- stay small enough to review quickly

## Step E: Remove Lua Runtime Path

- make C the only runtime backend
- delete Lua fallback behavior
- keep benchmark and correctness evidence for the transition

## Benchmark Principle

Benchmarking should compare:

- naive Lua
- naive C
- optimized C

The benchmark harness should run inside real headless Neovim with fixed in-memory datasets and repeated matcher calls.
