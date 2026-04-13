# Native Matcher Optimisations

Known speed debts to remove as the native fuzzy path matures:

- Multi-token native scoring currently rescans the same candidate once per token.
  This is a baseline shape, not the likely fastest end state.
  Target direction: one candidate scan that advances all token state together.

- Native score ordering currently uses insertion sort.
  This was a tiny-diff baseline, not a final raw-speed choice.
  Target direction: replace with a faster top-k selection / final ordering path.

- Lua still resolves equal-score tie-breaks after native score ordering.
  This keeps extra result-path work outside C.
  Target direction: move final native comparison rules fully into C and delete
  the Lua tie-break cleanup on the native path.

- Native still builds full match lists and then orders them.
  For maximum raw speed this is likely the wrong final shape when the UI only
  needs a small result limit.
  Target direction: native top-k selection during the scan, then final-order
  only those kept results.

- Multi-token scoring still rescans the same candidate once per token.
  Target direction: one candidate scan that advances all token state together.

- Top-k replacement currently rescans the kept set to find the current worst
  result after a replacement.
  Target direction: keep a tighter worst-entry tracking strategy if benchmarks
  show this scan matters.

- Lua still resolves equal-score tie-breaks after the native path returns.
  Target direction: move the final tie-break comparison fully into native code.

- Native still does a final sort of the kept top-k set after selection.
  Target direction: benchmark whether maintaining a tighter ordered kept set is
  faster than the current select-then-sort baseline.

- No native one-pass "scan candidate once, update all token state" path yet.
  Target direction: benchmark and likely replace the per-token rescanning shape
  once the simpler native top-k baseline is fully proven out.

- Benchmark every non-trivial matcher change against real command-history
  workloads before assuming a new structure is actually faster.
