#include <stdlib.h>
#include <string.h>

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
  int text_bytes;
  int *text_offsets;
  int *text_lengths;
  char *corpus_text;
  penguin_result *results;
} penguin_exact_matcher;

int penguin_stub_version(void) { return 1; }

/* Keep the whole matcher in one allocation and move candidate-text ownership
 * into that native state now. Query logic still lands in later diffs, but the
 * matcher already gets the final memory shape it wants: reusable result space,
 * per-entry offsets/lengths, and one contiguous native corpus buffer.
 */
penguin_exact_matcher *penguin_exact_matcher_new(const char *const *texts,
                                                 const int *text_lengths,
                                                 int text_count,
                                                 int text_bytes) {
  size_t total_bytes;
  size_t result_bytes;
  size_t offset_bytes;
  size_t length_bytes;
  size_t corpus_text_bytes;
  int total_text_bytes = 0;
  unsigned char *cursor;
  penguin_exact_matcher *matcher;
  int index;
  int offset = 0;

  if (text_count <= 0 || text_bytes < 0 || !texts || !text_lengths) {
    return 0;
  }

  for (index = 0; index < text_count; index++) {
    if (!texts[index] || text_lengths[index] < 0) {
      return 0;
    }

    total_text_bytes += text_lengths[index];
  }

  if (total_text_bytes != text_bytes) {
    return 0;
  }

  /* The matcher layout is packed as:
   *   [struct][results AoS][offsets][lengths][corpus text]
   * so every build-time structure stays cache-friendly and owned by C. */
  result_bytes = sizeof(penguin_result) * (size_t)text_count;
  offset_bytes = sizeof(int) * (size_t)text_count;
  length_bytes = sizeof(int) * (size_t)text_count;
  corpus_text_bytes = (size_t)text_bytes;
  total_bytes = sizeof(penguin_exact_matcher) + result_bytes + offset_bytes +
                length_bytes + corpus_text_bytes;
  matcher = malloc(total_bytes);

  if (!matcher) {
    return 0;
  }

  /* The first bytes of this allocation already hold the matcher struct, so
   * the reusable buffers have to start immediately after that header. */
  cursor = (unsigned char *)(matcher + 1);
  matcher->text_count = text_count;
  matcher->result_capacity = text_count;
  matcher->text_bytes = text_bytes;
  /* Result entries are stored as contiguous {index, score} pairs because the
   * hot path naturally produces and consumes them together. */
  matcher->results = (penguin_result *)cursor;
  cursor += result_bytes;
  matcher->text_offsets = (int *)cursor;
  cursor += offset_bytes;
  matcher->text_lengths = (int *)cursor;
  cursor += length_bytes;
  /* Flat contiguous storage for every candidate string. Offsets and lengths
   * point into this buffer, so query-time scans can walk one native corpus. */
  matcher->corpus_text = (char *)cursor;

  for (index = 0; index < text_count; index++) {
    int length = text_lengths[index];

    matcher->text_offsets[index] = offset;
    matcher->text_lengths[index] = length;

    if (length > 0) {
      memcpy(matcher->corpus_text + offset, texts[index], (size_t)length);
    }

    offset += length;
  }

  return matcher;
}

int penguin_exact_matcher_result_capacity(
    const penguin_exact_matcher *matcher) {
  if (!matcher) {
    return 0;
  }

  return matcher->result_capacity;
}

const char *penguin_exact_matcher_text_at(const penguin_exact_matcher *matcher,
                                          int index) {
  if (!matcher || index < 0 || index >= matcher->text_count) {
    return 0;
  }

  return matcher->corpus_text + matcher->text_offsets[index];
}

int penguin_exact_matcher_text_length_at(
    const penguin_exact_matcher *matcher,
    int index) {
  if (!matcher || index < 0 || index >= matcher->text_count) {
    return 0;
  }

  return matcher->text_lengths[index];
}

void penguin_exact_matcher_free(penguin_exact_matcher *matcher) {
  free(matcher);
}
