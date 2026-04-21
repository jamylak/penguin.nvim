#ifndef PENGUIN_MATCH_SPANS_H
#define PENGUIN_MATCH_SPANS_H

#include "penguin_filter_types.h"

void penguin_collect_match_spans_for_query(penguin_result *result,
                                           const char *text,
                                           int text_length,
                                           const char *query,
                                           int query_length);

void penguin_result_clear_match_spans(penguin_result *result);

#endif
