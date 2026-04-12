# 🧩 Native Rollout Plan

> Small, reviewable steps for moving `penguin.nvim` filtering to C.

## Goal

The runtime target is:

- maximum raw speed, not merely acceptable speed
- C-only filtering
- no Lua fallback in normal operation
- Lua matcher deleted after C is validated
- long-lived native matcher state reused across queries
- zero fresh allocations on the steady-state query path
- temporary Lua-to-C build handoff only; matcher-owned memory lives natively after construction

To get there without huge diffs, native work should land in tiny vertical slices.

Every slice should be judged against the real objective:

- tighter native ownership
- less Lua work on the query path
- fewer allocations
- better cache behavior
- one Lua -> C call per query on the hot path; reject per-candidate or
  per-result helper-call designs

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
- keep Lua-to-C build-time staging temporary and minimal; separate `ffi.new(...)`
  pointer/length buffers are acceptable only as short-lived transition scaffolding
- prefer a single struct-array handoff over multiple temporary FFI allocations when
  tightening the constructor boundary
- start with exact-only bulk filtering if that keeps the diff tiny
- subsequence matching
- token splitting
- segmented single-token matching such as `splbot`
- scoring and ranking details

Each slice should:

- add one behavior
- add one or a few focused checks
- stay small enough to review quickly

Native iteration workflow:

- keep both a manual Neovim entrypoint and a headless verification path ready
- add or update benchmark scenarios before deeper optimization passes
- rerun the same benchmark scenarios before and after each non-trivial hot-path change
- prefer small optimization diffs that still move benchmarked hot-path code

Still missing before the final fast path:

- native-owned corpus preprocessing at build time
- normalized text and metadata stored in C
- one bulk query entrypoint that performs scan, scoring, and final result
  selection without additional Lua -> C helper calls
- no repeated Lua-side marshalling on the query path
- full query-time matching and scoring in C
- native top-k selection / ranking
- consider whether a build-time index helps this workload; only keep it if
  benchmarks beat the tight full-scan path on real command-history datasets
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

The first benchmark harness should:

- cover multiple history sizes
- cover multiple query scenarios
- compare Lua and native implementations on identical in-memory fixtures
- stay easy to rerun while iterating on low-level matcher changes
