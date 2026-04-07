#include <stdlib.h>

typedef struct penguin_exact_matcher {
  int text_count;
} penguin_exact_matcher;

int penguin_stub_version(void) {
  return 1;
}

/* First native-state slice: allocate a long-lived matcher object once, keep it
 * across queries, and free it when the Lua-owned handle dies.
 *
 * This constructor only knows text_count, so it is not yet sizing native
 * candidate storage from the actual string bytes. Query logic and fuller
 * native allocations land in later diffs.
 */
penguin_exact_matcher *penguin_exact_matcher_new(int text_count) {
  penguin_exact_matcher *matcher;

  if (text_count <= 0) {
    return 0;
  }

  /* This first slice allocates only the matcher header; later slices can grow
   * this into the fuller one-build native allocation for matcher data. */
  matcher = malloc(sizeof(penguin_exact_matcher));

  if (!matcher) {
    return 0;
  }

  matcher->text_count = text_count;
  return matcher;
}

void penguin_exact_matcher_free(penguin_exact_matcher *matcher) {
  free(matcher);
}
