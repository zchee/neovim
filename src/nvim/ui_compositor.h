#pragma once

#include <stdint.h>

#include "nvim/api/private/defs.h"  // IWYU pragma: keep
#include "nvim/grid_defs.h"  // IWYU pragma: keep
#include "nvim/types_defs.h"  // IWYU pragma: keep
#include "nvim/ui_defs.h"  // IWYU pragma: keep

typedef struct {
  uint64_t fallback_calls;
  uint64_t fallback_span_total;
  uint64_t fallback_recomposed_total;
  uint64_t fallback_width_total;
  uint64_t fallback_blending_calls;
  uint64_t fallback_covered_calls;
  uint64_t fallback_above_msg_calls;
  uint64_t fallback_skipped_lines_total;
  uint64_t fallback_cover_handle_last;
  int64_t fallback_last_row_checked;
  int64_t fallback_msg_row;
  int64_t fallback_rows_argument;
  int64_t fallback_cover_zindex_last;
  uint64_t fallback_popup_calls;
  uint64_t fallback_popup_ignored;
  uint64_t fallback_external_calls;
  uint64_t overlay_prune_calls;
  uint64_t overlay_prune_width_total;
} UICompMetrics;

void ui_comp_metrics_snapshot(UICompMetrics *out);
void ui_comp_metrics_reset(void);
Array ui_comp_collect_overlay_spans(int row, int startcol, int endcol, Arena *arena);

#include "ui_compositor.h.generated.h"
