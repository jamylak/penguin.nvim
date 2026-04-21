#include "penguin_match_spans.h"

#include <string.h>

static unsigned char penguin_match_span_ascii_lower_byte(unsigned char byte) {
  if (byte >= 'A' && byte <= 'Z') {
    return (unsigned char)(byte + ('a' - 'A'));
  }

  return byte;
}

/* Match-span helpers:
 *
 *   raw per-token hits      -> [3,4] [4,6] [9,10]
 *   sorted in-place         -> [3,4] [4,6] [9,10]
 *   merged render spans     -> [3,6] [9,10]
 *
 * The scorer still decides whether a candidate matches and how strong it is.
 * This helper block only answers the UI question:
 *   "Which byte ranges inside the already-matched row should be highlighted?"
 */
void penguin_result_clear_match_spans(penguin_result *result) {
  /* Reset phase:
   *   previous render spans -> discarded
   *   next token/query pass -> starts from an empty span set
   */
  if (!result) {
    return;
  }

  result->match_span_count = 0;
}

static void penguin_result_push_match_span(penguin_result *result,
                                           int start,
                                           int end) {
  /* Guard phase:
   *   reject null results, invalid ranges, or writes beyond the fixed cap
   */
  if (!result || result->match_span_count >= PENGUIN_MAX_MATCH_SPANS ||
      start < 0 || end <= start) {
    return;
  }

  /* Append phase:
   *   [existing spans ...] + [start,end]
   */
  result->match_span_starts[result->match_span_count] = start;
  result->match_span_ends[result->match_span_count] = end;
  result->match_span_count++;
}

/* Small insertion sort because the span set is tiny and bounded. The goal is
 * deterministic left-to-right rendering, not a general-purpose sort helper.
 *
 * Visual shape:
 *   before = [9,10] [3,4] [4,6]
 *   after  = [3,4] [4,6] [9,10]
 */
static void penguin_result_sort_match_spans(penguin_result *result) {
  int left;

  /* Fast exit:
   *   0 or 1 span is already ordered
   */
  if (!result || result->match_span_count <= 1) {
    return;
  }

  /* Insertion pass:
   *   grow a sorted left-hand side one span at a time
   */
  for (left = 1; left < result->match_span_count; left++) {
    int current_start = result->match_span_starts[left];
    int current_end = result->match_span_ends[left];
    int index = left;

    /* Shift phase:
     *   move later spans right until the current span fits in sorted order
     */
    while (index > 0 &&
           (current_start < result->match_span_starts[index - 1] ||
            (current_start == result->match_span_starts[index - 1] &&
             current_end < result->match_span_ends[index - 1]))) {
      result->match_span_starts[index] = result->match_span_starts[index - 1];
      result->match_span_ends[index] = result->match_span_ends[index - 1];
      index--;
    }

    result->match_span_starts[index] = current_start;
    result->match_span_ends[index] = current_end;
  }
}

/* Collapse touching or overlapping byte ranges so the UI gets the fewest
 * extmarks needed for the same visual result.
 *
 * Visual shape:
 *   input  = [3,4] [4,6] [9,10]
 *   output = [3,6] [9,10]
 */
static void penguin_result_merge_match_spans(penguin_result *result) {
  int read_index;
  int write_index = 0;

  /* Fast exit:
   *   nothing to merge when the span set is empty or already singular
   */
  if (!result || result->match_span_count <= 1) {
    return;
  }

  /* Ordering phase:
   *   merge logic assumes left-to-right spans
   */
  penguin_result_sort_match_spans(result);

  /* Merge sweep:
   *   read_index  -> next candidate span
   *   write_index -> current merged output span
   */
  for (read_index = 1; read_index < result->match_span_count; read_index++) {
    int start = result->match_span_starts[read_index];
    int end = result->match_span_ends[read_index];

    if (start > result->match_span_ends[write_index]) {
      write_index++;
      result->match_span_starts[write_index] = start;
      result->match_span_ends[write_index] = end;
    } else if (end > result->match_span_ends[write_index]) {
      result->match_span_ends[write_index] = end;
    }
  }

  /* Publish phase:
   *   trim the logical span count down to the merged output size
   */
  result->match_span_count = write_index + 1;
}

/* Fallback range derivation for one token when exact substring search did not
 * find any whole-token occurrences in the rendered row.
 *
 * Visual shape:
 *   haystack = "checkhealth"
 *   needle   = "ceh"
 *   spans    = [0,1] [2,3] [5,6]
 *
 * Roll back to `original_count` if the subsequence fails partway through so a
 * partial prefix never leaks into the final highlight set.
 */
static int penguin_find_subsequence_ranges(const char *haystack,
                                           int haystack_length,
                                           const char *needle,
                                           int needle_length,
                                           penguin_result *result) {
  int original_count;
  int position = 0;
  int index;

  if (!haystack || haystack_length <= 0 || !needle || needle_length <= 0 ||
      !result) {
    return 0;
  }

  /* Rollback checkpoint:
   *   if the subsequence fails midway, restore the incoming span set exactly
   */
  original_count = result->match_span_count;

  /* Ordered scan:
   *   walk needle bytes left-to-right and place each one after the previous
   *   matched byte in the haystack
   */
  for (index = 0; index < needle_length; index++) {
    unsigned char byte = (unsigned char)needle[index];
    int found = -1;
    int scan_index;

    /* Search phase:
     *   find the next occurrence of this byte without moving backward
     */
    for (scan_index = position; scan_index < haystack_length; scan_index++) {
      if ((unsigned char)haystack[scan_index] == byte) {
        found = scan_index;
        break;
      }
    }

    if (found < 0) {
      /* Failure rollback:
       *   a partial prefix is not a valid highlight result
       */
      result->match_span_count = original_count;
      return 0;
    }

    /* Commit phase:
     *   each matched byte becomes a 1-byte highlight span
     */
    penguin_result_push_match_span(result, found, found + 1);
    position = found + 1;
  }

  /* Success:
   *   every needle byte found a valid ordered placement
   */
  return 1;
}

/* Recreate UI highlight spans directly from the native query/result pair.
 *
 * Pipeline:
 *   raw query          -> split on whitespace
 *   each unique token  -> exact spans if present
 *   no exact spans     -> ordered subsequence spans
 *   all token spans    -> merge into final render spans
 *
 * This mirrors the temporary Lua highlight behavior closely enough that the
 * renderer can stop re-deriving ranges in Lua for native fuzzy matches.
 */
void penguin_collect_match_spans_for_query(penguin_result *result,
                                           const char *text,
                                           int text_length,
                                           const char *query,
                                           int query_length) {
  int cursor = 0;
  int token_count = 0;
  int token_starts[query_length > 0 ? query_length : 1];
  int token_lengths[query_length > 0 ? query_length : 1];
  char lowered_query[query_length > 0 ? query_length : 1];

  if (!result || !text || text_length <= 0 || !query || query_length <= 0) {
    return;
  }

  /* Session reset:
   *   spans are recomputed fresh for this candidate/query pair
   */
  penguin_result_clear_match_spans(result);

  /* Token loop:
   *   raw query -> unique lowered tokens -> spans appended into `result`
   */
  while (cursor < query_length && token_count < query_length) {
    int token_start;
    int token_length;
    int seen = 0;
    int previous_index;
    int found_exact = 0;
    int start;

    /* Skip separators:
     *   move to the next token boundary in the raw query
     */
    while (cursor < query_length &&
           ((unsigned char)query[cursor] == ' ' ||
            (unsigned char)query[cursor] == '\t' ||
            (unsigned char)query[cursor] == '\n' ||
            (unsigned char)query[cursor] == '\r' ||
            (unsigned char)query[cursor] == '\f' ||
            (unsigned char)query[cursor] == '\v')) {
      cursor++;
    }

    if (cursor >= query_length) {
      break;
    }

    token_start = cursor;

    /* Lower just this token into stack storage so the original FFI-owned query
     * bytes stay untouched while matching against the pre-lowered corpus text.
     */
    while (cursor < query_length &&
           !((unsigned char)query[cursor] == ' ' ||
             (unsigned char)query[cursor] == '\t' ||
             (unsigned char)query[cursor] == '\n' ||
             (unsigned char)query[cursor] == '\r' ||
             (unsigned char)query[cursor] == '\f' ||
             (unsigned char)query[cursor] == '\v')) {
      lowered_query[cursor] =
          (char)penguin_match_span_ascii_lower_byte((unsigned char)query[cursor]);
      cursor++;
    }

    token_length = cursor - token_start;

    if (token_length <= 0) {
      continue;
    }

    /* Dedup phase:
     *   repeated tokens should not duplicate highlight ranges
     */
    for (previous_index = 0; previous_index < token_count; previous_index++) {
      if (token_lengths[previous_index] == token_length &&
          memcmp(lowered_query + token_starts[previous_index],
                 lowered_query + token_start,
                 (size_t)token_length) == 0) {
        seen = 1;
        break;
      }
    }

    if (seen) {
      /* The Lua-side highlight pass ignored duplicate tokens; keep the same
       * visual behavior here so repeated words do not duplicate extmarks.
       */
      continue;
    }

    token_starts[token_count] = token_start;
    token_lengths[token_count] = token_length;
    token_count++;

    /* Exact-hit sweep:
     *   collect every exact occurrence of this token in the lowered row
     */
    for (start = 0; start <= text_length - token_length; start++) {
      if (memcmp(text + start, lowered_query + token_start,
                 (size_t)token_length) == 0) {
        penguin_result_push_match_span(result, start, start + token_length);
        found_exact = 1;
      }
    }

    if (!found_exact) {
      /* When no exact substring occurrence exists, fall back to the same
       * ordered-character highlight shape used by the temporary Lua path.
       */
      (void)penguin_find_subsequence_ranges(
          text, text_length, lowered_query + token_start, token_length, result);
    }
  }

  /* Final compaction:
   *   exact hits and subsequence hits may touch or overlap once combined
   */
  penguin_result_merge_match_spans(result);
}
