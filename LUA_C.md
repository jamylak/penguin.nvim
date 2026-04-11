# ⚡ Lua / C Speed Plan

> Maximum raw-speed direction for `penguin.nvim`.
>
> The standard is not "fast enough."
> The standard is the fastest practical runtime shape we can defend with benchmarks.

## Fastest Practical Shape

- one long-lived native matcher object per command-set refresh
- one build call from Lua into C
- C copies all candidate text into one native-owned arena / contiguous block
- C preprocesses corpus data once:
  - lowercase / normalized text
  - offsets
  - lengths
  - token and word-boundary metadata
- query path does zero fresh allocations
- one query call from Lua into C
- full matching, scoring, and top-k selection happen in C
- C returns only compact result records
- Lua only renders the final small result set

## Best Memory Layout

Corpus data should stay native-owned and tightly packed.

- corpus text: flat contiguous byte blob
- corpus metadata: `SoA`
  - `offsets[]`
  - `lengths[]`
  - boundary / token metadata arrays
- results: `AoS`
  - `{ index, score }`
  - results are produced, sorted, and consumed as pairs

## Why This Is Fast

- no per-candidate Lua↔C calls
- no per-query `malloc` / `free`
- no repeated normalization of corpus text
- sequential scans over tight native memory
- low cache-miss rate
- compact result handling
- minimal data crossing back to Lua

## About `ffi.new(...)`

With the current FFI boundary, a temporary build-time `ffi.new(...)` pointer array is acceptable.

Why:

- it happens once at matcher build / rebuild time
- not on the keystroke hot path
- C copies the real data it needs into native-owned matcher memory
- the temporary handoff buffer dies immediately after construction

Avoiding that temporary build-time handoff entirely would usually require:

- repeated Lua→C calls to push strings one by one
- or a more complex packed-blob handoff format

Those alternatives are not obviously faster overall.

## Deep-Tech Optimization Passes

After the native matcher shape is correct, later speed work should include:

- `-O3`
- LTO
- PGO
- assembly inspection
- SIMD where it wins
- branch reduction in matcher loops
- top-k selection instead of full sorting when possible
- careful fixed-width types where safe
- benchmark verification for every claimed speed win

## Bottom Line

Fastest real design:

- C-owned corpus
- C-owned precomputed metadata
- C-owned reusable result buffers
- zero query-path allocations
- one Lua→C call per query
- compact results returned to Lua only
