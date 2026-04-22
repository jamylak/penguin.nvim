# Native Matcher Optimisations

Known speed debts to remove as the native fuzzy path matures:

- Large-list selection movement is no longer forced through a full rerender.
  The UI now rewrites only the old/new marker rows and moves the selection
  extmark, which keeps 100-row scrolling in the sub-millisecond range in the
  new `selection_render_runtime` benchmark slice.
  Recent benchmark snapshot:
  `visible100 mixed selection_render_runtime=0.360948 ms/step`.
  Target direction: keep selection-only work incremental and avoid regressing it
  back into a full line rewrite + namespace clear path.

- Keep the default benchmark routine fast.
  The larger `visible100` workload is useful when tuning scrolling behavior, but
  it is not a good fit for the default bench target if it makes routine runs
  noticeably slower.
  Target direction: keep focused long-running scenarios behind explicit bench
  targets so the fast path still gets run often.

- Highlight-span generation still looks like live optimisation headroom.
  Recent benchmark snapshot:
  `visible100 mixed native_highlights_runtime=0.400898 ms/query`
  vs `visible100 mixed matcher_native_topk12=0.446598 ms/query`.
  That means span generation is now in the same rough cost range as the whole
  native top-k match step for a larger visible-list workload too.
  Target direction: reduce exact-span scans and fallback subsequence span work,
  especially for rows that are already in the kept top-k set.

- Top-k maintenance still looks worth revisiting.
  The current path keeps a bounded result set during the scan, but replacement
  still calls `penguin_find_worst_result_index()` after each winning overwrite,
  and we still finish with a final sort of the kept set.
  Recent benchmark snapshot:
  `large common native_fuzzy_raw_all=5.162296 ms/query`
  vs `large common native_fuzzy_raw_topk12=0.226362 ms/query`.
  The gap says top-k limiting is a huge win already, but also that the kept-set
  maintenance policy is now important enough to benchmark more aggressively.
  Target direction: benchmark tighter worst-entry tracking or a heap / ordered
  kept-set approach against the current replace-then-rescan baseline.

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
