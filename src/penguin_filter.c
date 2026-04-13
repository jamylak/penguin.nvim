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

typedef struct penguin_query_result {
  int count;
  const penguin_result *results;
} penguin_query_result;

typedef struct penguin_exact_matcher_text {
  const char *text;
  int length;
} penguin_exact_matcher_text;

typedef struct penguin_exact_matcher {
  int text_count;
  int result_capacity;
  int text_bytes;
  int *text_offsets;
  int *text_lengths;
  /* Lowercased candidate text with non-word separators removed, matching the
   * Lua-side compact(...) form used for separator-crossing fuzzy queries. */
  int *compact_text_offsets;
  int *compact_text_lengths;
  char *lower_corpus_text;
  char *compact_corpus_text;
  penguin_query_result query_result;
  penguin_result *results;
} penguin_exact_matcher;

int penguin_stub_version(void) { return 1; }

static unsigned char penguin_ascii_lower_byte(unsigned char byte) {
  if (byte >= 'A' && byte <= 'Z') {
    return (unsigned char)(byte + ('a' - 'A'));
  }

  return byte;
}

/* Mirror Lua's [%w_] handling for compact candidate text: keep ASCII letters,
 * digits, and underscores; drop separators such as spaces and punctuation. */
static int penguin_ascii_word_byte(unsigned char byte) {
  return (byte >= '0' && byte <= '9') || (byte >= 'A' && byte <= 'Z') ||
         (byte >= 'a' && byte <= 'z') || byte == '_';
}

static int penguin_subsequence_score(const char *needle,
                                     int needle_length,
                                     const char *haystack,
                                     int haystack_length);

/* Future full-query native path needs to walk one raw query string and pull
 * out compact lowered tokens without bouncing back through Lua. The caller
 * owns one cursor integer for that query; each call starts reading at
 * *cursor, skips separators, copies the next [%w_]-only token into buffer,
 * then updates *cursor so the next call resumes from the following byte.
 * Return value is the compact token length, or 0 when no token remains.
 *
 * Example:
 *   query  = "  spl  bot "
 *   cursor = 0  -> token "spl", cursor ends at the first space after "spl"
 *   cursor = 5  -> token "bot", cursor ends at the trailing space
 *   cursor = 10 -> no token remains, return 0
 *
 * This helper is rollout scaffolding for the future full-query native path.
 * If the final hot path benchmarks better with the token walk inlined into the
 * main scan, fold this logic back into that code later.
 */
static int penguin_next_compact_query_token(const char *query,
                                            int query_length,
                                            int *cursor,
                                            char *buffer) {
  int compact_length = 0;
  int index;

  if (!query || query_length <= 0 || !cursor || !buffer) {
    return 0;
  }

  index = *cursor;

  /* Skip separators before the next token starts. */
  while (index < query_length &&
         !penguin_ascii_word_byte((unsigned char)query[index])) {
    index++;
  }

  /* Copy the next token into the compact lowered buffer. */
  while (index < query_length &&
         penguin_ascii_word_byte((unsigned char)query[index])) {
    buffer[compact_length] =
        (char)penguin_ascii_lower_byte((unsigned char)query[index]);
    compact_length++;
    index++;
  }

  *cursor = index;

  return compact_length;
}

/* Materialize the full raw query into compact lowered tokens stored back-to-
 * back in token_buffer, with per-token offset/length metadata written into the
 * caller arrays. This is the first directly useful building block for the
 * eventual native full-query path: parse once, then let later matcher code
 * score against those compact tokens without bouncing back through Lua.
 *
 * Example:
 *   query         = "  spl  bot "
 *   token_buffer  = "splbot"
 *   token_offsets = [0, 3]
 *   token_lengths = [3, 3]
 *   token_count   = 2
 *
 * This may be folded back into the final hot path later if the fastest
 * version wants query parsing inlined directly into the matcher scan.
 */
static int penguin_collect_compact_query_tokens(const char *query,
                                                int query_length,
                                                int *token_offsets,
                                                int *token_lengths,
                                                int token_capacity,
                                                char *token_buffer) {
  char scratch_buffer[query_length > 0 ? query_length : 1];
  int cursor = 0;
  int token_count = 0;
  int token_bytes = 0;
  int token_length;

  if (!query || query_length <= 0 || !token_offsets || !token_lengths ||
      token_capacity <= 0 || !token_buffer) {
    return 0;
  }

  while (token_count < token_capacity &&
         (token_length = penguin_next_compact_query_token(
              query, query_length, &cursor, scratch_buffer)) > 0) {
    token_offsets[token_count] = token_bytes;
    token_lengths[token_count] = token_length;
    memcpy(token_buffer + token_bytes, scratch_buffer, (size_t)token_length);
    token_bytes += token_length;
    token_count++;
  }

  return token_count;
}

/* Score one candidate against a packed compact-token query. This keeps the
 * current matcher contract for multi-token queries: every token must match,
 * token scores sum, and a multi-token bonus is applied when more than one
 * token is present. Query parsing and candidate scoring stay separate here so
 * each piece can land in reviewable native slices before the final hot path is
 * fused together.
 *
 * Example:
 *   token_buffer  = "splbot"
 *   token_offsets = [0, 3]
 *   token_lengths = [3, 3]
 *   candidate     = "verticalbotrightsplit"
 *
 * This scores "spl" against the candidate, then "bot" against the same
 * candidate, sums those scores, and finally applies the multi-token bonus.
 *
 * This may not be the final fastest shape. If benchmarks show that rescanning
 * one candidate per token loses too much, replace this with a tighter one-pass
 * candidate scan that advances all token state together.
 */
static int penguin_score_compact_query_tokens(
    const char *token_buffer,
    const int *token_offsets,
    const int *token_lengths,
    int token_count,
    const char *candidate,
    int candidate_length) {
  int total_score = 0;
  int token_index;

  if (!token_buffer || !token_offsets || !token_lengths || token_count <= 0 ||
      !candidate || candidate_length <= 0) {
    return -1;
  }

  for (token_index = 0; token_index < token_count; token_index++) {
    int score = penguin_subsequence_score(
        token_buffer + token_offsets[token_index], token_lengths[token_index],
        candidate, candidate_length);

    if (score < 0) {
      return -1;
    }

    total_score += score;
  }

  if (token_count > 1) {
    total_score += token_count * 12;
  }

  return total_score;
}

/* Baseline exact-substring search. Correct and easy to review, but not the
 * final optimized implementation for the raw-speed target. */
static int penguin_exact_substring_score(const char *needle,
                                         int needle_length,
                                         const char *haystack,
                                         int haystack_length) {
  unsigned char first_byte;
  int start;
  int last_start;

  if (!needle || !haystack || needle_length <= 0 || haystack_length <= 0 ||
      needle_length > haystack_length) {
    return -1;
  }

  last_start = haystack_length - needle_length;
  first_byte = (unsigned char)needle[0];

  for (start = 0; start <= last_start; start++) {
    if ((unsigned char)haystack[start] != first_byte) {
      continue;
    }

    if (memcmp(haystack + start, needle, (size_t)needle_length) == 0) {
      int score = 300 - ((start + 1) * 4) - (haystack_length - needle_length);

      if (start == 0) {
        score += 30;
      }

      return score;
    }
  }

  return -1;
}

/* First native fuzzy-scoring slice. Keep exact substring scoring as the fast
 * strong path, then fall back to subsequence scoring on compact candidate
 * text for separator-crossing queries. */
static int penguin_subsequence_score(const char *needle,
                                     int needle_length,
                                     const char *haystack,
                                     int haystack_length) {
  int substring_score = penguin_exact_substring_score(needle, needle_length,
                                                      haystack, haystack_length);
  /* Continue scanning from just after the last matched byte. */
  int position = 0;
  /* First matched byte in the haystack, used for prefix/earliness bias. */
  int first_index = -1;
  /* Bytes skipped between matched characters. */
  int gaps = 0;
  /* Neighboring matched characters that stay contiguous. */
  int adjacent = 0;
  /* Previous matched byte index so adjacency is cheap to detect. */
  int previous = -1;
  int index;

  if (substring_score >= 0) {
    /* Exact substring hit stays the stronger fast path. */
    return substring_score;
  }

  if (!needle || !haystack || needle_length <= 0 || haystack_length <= 0) {
    return -1;
  }

  /* After exact substring misses, scan for the native fuzzy subsequence path. */
  for (index = 0; index < needle_length; index++) {
    unsigned char byte = (unsigned char)needle[index];
    int found = -1;
    int scan_index;

    /* Walk forward until this query byte is found in order. */
    for (scan_index = position; scan_index < haystack_length; scan_index++) {
      if ((unsigned char)haystack[scan_index] == byte) {
        found = scan_index;
        break;
      }
    }

    if (found < 0) {
      /* Subsequence matching fails as soon as one query byte cannot be placed. */
      return -1;
    }

    if (first_index < 0) {
      /* Remember where the subsequence starts for early-match bias later. */
      first_index = found;
    }

    if (previous >= 0 && found == previous + 1) {
      /* Reward characters that stay contiguous instead of scattering apart. */
      adjacent++;
    }

    gaps += found - position;
    previous = found;
    position = found + 1;
  }

  {
    /* Favor tighter, earlier, more contiguous subsequence matches. */
    int score = 120 - (gaps * 3) + (adjacent * 8) - ((first_index + 1) * 2);

    if (first_index == 0) {
      score += 15;
    }

    return score;
  }
}

/* Keep the whole matcher in one allocation and move candidate-text ownership
 * into that native state now. Query logic still lands in later diffs, but the
 * matcher already gets the runtime shape needed for fast case-insensitive
 * scans: reusable result space, per-entry offsets/lengths, and one contiguous
 * pre-lowercased corpus buffer owned by C.
 */
penguin_exact_matcher *penguin_exact_matcher_new(
    const penguin_exact_matcher_text *texts,
    int text_count,
    int text_bytes) {
  size_t total_bytes;
  size_t result_bytes;
  size_t offset_bytes;
  size_t length_bytes;
  size_t compact_offset_bytes;
  size_t compact_length_bytes;
  size_t lower_corpus_text_bytes;
  size_t compact_corpus_text_bytes;
  int total_text_bytes = 0;
  int total_compact_text_bytes = 0;
  unsigned char *cursor;
  penguin_exact_matcher *matcher;
  int index;
  int offset = 0;
  int compact_offset = 0;

  if (text_count <= 0 || text_bytes < 0 || !texts) {
    return 0;
  }

  for (index = 0; index < text_count; index++) {
    if (!texts[index].text || texts[index].length < 0) {
      return 0;
    }

    total_text_bytes += texts[index].length;

    for (int byte_index = 0; byte_index < texts[index].length; byte_index++) {
      if (penguin_ascii_word_byte((unsigned char)texts[index].text[byte_index])) {
        total_compact_text_bytes++;
      }
    }
  }

  if (total_text_bytes != text_bytes) {
    return 0;
  }

  /* The matcher layout is packed as:
   *   [struct][results AoS][offsets][lengths][lower corpus text]
   * so every build-time structure stays cache-friendly and owned by C. */
  result_bytes = sizeof(penguin_result) * (size_t)text_count;
  offset_bytes = sizeof(int) * (size_t)text_count;
  length_bytes = sizeof(int) * (size_t)text_count;
  compact_offset_bytes = sizeof(int) * (size_t)text_count;
  compact_length_bytes = sizeof(int) * (size_t)text_count;
  lower_corpus_text_bytes = (size_t)text_bytes;
  compact_corpus_text_bytes = (size_t)total_compact_text_bytes;
  total_bytes = sizeof(penguin_exact_matcher) + result_bytes + offset_bytes +
                length_bytes + compact_offset_bytes + compact_length_bytes +
                lower_corpus_text_bytes + compact_corpus_text_bytes;
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
  matcher->compact_text_offsets = (int *)cursor;
  cursor += compact_offset_bytes;
  matcher->compact_text_lengths = (int *)cursor;
  cursor += compact_length_bytes;
  /* Pre-lowercased mirror of the same corpus so future query-time matching can
   * scan normalized candidate text without re-lowercasing per query. */
  matcher->lower_corpus_text = (char *)cursor;
  cursor += lower_corpus_text_bytes;
  matcher->compact_corpus_text = (char *)cursor;

  for (index = 0; index < text_count; index++) {
    int length = texts[index].length;
    int byte_index;
    int compact_length = 0;

    matcher->text_offsets[index] = offset;
    matcher->text_lengths[index] = length;
    matcher->compact_text_offsets[index] = compact_offset;

    if (length > 0) {
      for (byte_index = 0; byte_index < length; byte_index++) {
        unsigned char lowered =
            penguin_ascii_lower_byte((unsigned char)texts[index].text[byte_index]);
        matcher->lower_corpus_text[offset + byte_index] = (char)lowered;

        if (penguin_ascii_word_byte((unsigned char)texts[index].text[byte_index])) {
          matcher->compact_corpus_text[compact_offset + compact_length] = (char)lowered;
          compact_length++;
        }
      }
    }

    matcher->compact_text_lengths[index] = compact_length;
    offset += length;
    compact_offset += compact_length;
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

const penguin_query_result *penguin_exact_matcher_find_exact(
    penguin_exact_matcher *matcher,
    const char *query,
    int query_length) {
  int count = 0;
  int index;

  if (!matcher || !query || query_length <= 0) {
    return 0;
  }

  for (index = 0; index < matcher->text_count; index++) {
    const char *candidate =
        matcher->lower_corpus_text + matcher->text_offsets[index];
    int score = penguin_exact_substring_score(
        query, query_length, candidate, matcher->text_lengths[index]);

    if (score >= 0) {
      matcher->results[count].index = index;
      matcher->results[count].score = score;
      count++;
    }
  }

  matcher->query_result.count = count;
  matcher->query_result.results = matcher->results;

  return &matcher->query_result;
}

const penguin_query_result *penguin_exact_matcher_find_fuzzy(
    penguin_exact_matcher *matcher,
    const char *query,
    int query_length) {
  int count = 0;
  int index;

  if (!matcher || !query || query_length <= 0) {
    return 0;
  }

  /* Temporary native fuzzy slice: the query arrives already compacted on the
   * Lua side, so this bulk scan runs against the matcher's compact corpus text
   * only. Multi-token query handling and broader query preprocessing still
   * live outside this function for now. */
  for (index = 0; index < matcher->text_count; index++) {
    const char *candidate =
        matcher->compact_corpus_text + matcher->compact_text_offsets[index];
    int score = penguin_subsequence_score(
        query, query_length, candidate, matcher->compact_text_lengths[index]);

    if (score >= 0) {
      /* Reuse the matcher's long-lived result buffer so the hot query path does
       * not allocate while collecting matching candidate indexes and scores. */
      matcher->results[count].index = index;
      matcher->results[count].score = score;
      count++;
    }
  }

  /* Publish the reused result buffer through the stable query_result view that
   * Lua already knows how to read. */
  matcher->query_result.count = count;
  matcher->query_result.results = matcher->results;

  return &matcher->query_result;
}

const char *penguin_exact_matcher_lower_text_at(
    const penguin_exact_matcher *matcher,
    int index) {
  if (!matcher || index < 0 || index >= matcher->text_count) {
    return 0;
  }

  return matcher->lower_corpus_text + matcher->text_offsets[index];
}

int penguin_exact_matcher_text_length_at(const penguin_exact_matcher *matcher,
                                         int index) {
  if (!matcher || index < 0 || index >= matcher->text_count) {
    return 0;
  }

  return matcher->text_lengths[index];
}

void penguin_exact_matcher_free(penguin_exact_matcher *matcher) {
  free(matcher);
}
