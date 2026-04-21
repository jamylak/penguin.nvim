#ifndef PENGUIN_FILTER_TYPES_H
#define PENGUIN_FILTER_TYPES_H

#define PENGUIN_MAX_MATCH_SPANS 24

typedef struct penguin_result {
  int index;
  int score;
  /* Merged byte ranges to highlight inside the rendered candidate row. */
  int match_span_count;
  int match_span_starts[PENGUIN_MAX_MATCH_SPANS];
  int match_span_ends[PENGUIN_MAX_MATCH_SPANS];
} penguin_result;

#endif
