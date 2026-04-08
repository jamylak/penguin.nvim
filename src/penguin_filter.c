#include <stdlib.h>

/*
 * Rough native matcher sizing direction:
 *
 * - the command-text estimate is based on average bytes per command string,
 *   not on the size of the matcher struct itself
 * - examples:
 *   - 1,000 commands * ~50 bytes  ~=   50 KB raw text
 *   - 5,000 commands * ~64 bytes  ~=  320 KB raw text
 *   - 10,000 commands * ~80 bytes ~=  800 KB raw text
 * - with result entries, pointers, and extra metadata, even a heavy command
 *   history is still expected to stay in the low single-digit MB range
 *
 */
typedef struct penguin_result {
  int index;
  int score;
} penguin_result;

typedef struct penguin_exact_matcher {
  int text_count;
  int result_capacity;
  penguin_result *results;
} penguin_exact_matcher;

int penguin_stub_version(void) { return 1; }

/* First native-state slice: allocate a long-lived matcher object once, keep it
 * across queries, and free it when the Lua-owned handle dies.
 *
 * This constructor only knows text_count, so it is not yet sizing native
 * candidate storage from the actual string bytes. Query logic and fuller
 * native allocations land in later diffs.
 */
penguin_exact_matcher *penguin_exact_matcher_new(int text_count) {
  size_t total_bytes;
  size_t result_bytes;
  unsigned char *cursor;
  penguin_exact_matcher *matcher;

  if (text_count <= 0) {
    return 0;
  }

  /* Grow the single build-time allocation to include reusable result buffers.
   * Candidate ownership and filtering logic still land in later diffs. */
  result_bytes = sizeof(penguin_result) * (size_t)text_count;
  total_bytes = sizeof(penguin_exact_matcher) + result_bytes;
  matcher = malloc(total_bytes);

  if (!matcher) {
    return 0;
  }

  /* The first bytes of this allocation already hold the matcher struct, so
   * the reusable buffers have to start immediately after that header. */
  cursor = (unsigned char *)(matcher + 1);
  matcher->text_count = text_count;
  matcher->result_capacity = text_count;
  /* Result entries are stored as contiguous {index, score} pairs because the
   * hot path naturally produces and consumes them together. */
  matcher->results = (penguin_result *)cursor;

  return matcher;
}

int penguin_exact_matcher_result_capacity(
    const penguin_exact_matcher *matcher) {
  if (!matcher) {
    return 0;
  }

  return matcher->result_capacity;
}

void penguin_exact_matcher_free(penguin_exact_matcher *matcher) {
  free(matcher);
}
