// Compositor: merge floating grids with the main grid for display in
// TUI and non-multigrid UIs.
//
// Layer-based compositing: https://en.wikipedia.org/wiki/Digital_compositing

#include <assert.h>
#include <inttypes.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <uv.h>

#include "klib/kvec.h"
#include "nvim/api/private/defs.h"
#include "nvim/api/private/helpers.h"
#include "nvim/ascii_defs.h"
#include "nvim/buffer_defs.h"
#include "nvim/globals.h"
#include "nvim/grid.h"
#include "nvim/highlight.h"
#include "nvim/highlight_defs.h"
#include "nvim/highlight_group.h"
#include "nvim/log.h"
#include "nvim/macros_defs.h"
#include "nvim/memory.h"
#include "nvim/message.h"
#include "nvim/option_vars.h"
#include "nvim/os/time.h"
#include "nvim/popupmenu.h"
#include "nvim/types_defs.h"
#include "nvim/ui.h"
#include "nvim/ui_compositor.h"

#include "ui_compositor.c.generated.h"

static int composed_uis = 0;
kvec_t(ScreenGrid *) layers = KV_INITIAL_VALUE;

static size_t bufsize = 0;
static schar_T *linebuf;
static sattr_T *attrbuf;

#ifndef NDEBUG
static int chk_width = 0, chk_height = 0;
#endif

static ScreenGrid *curgrid;

static bool valid_screen = true;
static int msg_current_row = INT_MAX;
static bool msg_was_scrolled = false;

static int msg_sep_row = -1;
static schar_T msg_sep_char = schar_from_ascii(' ');

static int dbghl_normal, dbghl_clear, dbghl_composed, dbghl_recompose;

static UICompMetrics ui_comp_metrics;

typedef struct {
  int start;
  int end;
} OverlaySpan;

static kvec_t(OverlaySpan) overlay_row_spans = KV_INITIAL_VALUE;

void ui_comp_init(void)
{
  kv_push(layers, &default_grid);
  curgrid = &default_grid;
}

#ifdef EXITFREE
void ui_comp_free_all_mem(void)
{
  kv_destroy(layers);
  xfree(linebuf);
  xfree(attrbuf);
}
#endif

void ui_comp_syn_init(void)
{
  dbghl_normal = syn_check_group(S_LEN("RedrawDebugNormal"));
  dbghl_clear = syn_check_group(S_LEN("RedrawDebugClear"));
  dbghl_composed = syn_check_group(S_LEN("RedrawDebugComposed"));
  dbghl_recompose = syn_check_group(S_LEN("RedrawDebugRecompose"));
}

void ui_comp_attach(RemoteUI *ui)
{
  composed_uis++;
  ui->composed = true;
}

void ui_comp_detach(RemoteUI *ui)
{
  composed_uis--;
  if (composed_uis == 0) {
    XFREE_CLEAR(linebuf);
    XFREE_CLEAR(attrbuf);
    bufsize = 0;
  }
  ui->composed = false;
}

bool ui_comp_should_draw(void)
{
  return composed_uis != 0 && valid_screen;
}

/// Raises or lowers the layer, syncing comp_index with zindex.
///
/// This function adjusts the position of a layer in the layers array
/// based on its zindex, either raising or lowering it.
///
/// @param[in]  layer_idx  Index of the layer to be raised or lowered.
/// @param[in]  raise      Raise the layer if true, else lower it.
void ui_comp_layers_adjust(size_t layer_idx, bool raise)
{
  size_t size = layers.size;
  ScreenGrid *layer = layers.items[layer_idx];

  if (raise) {
    while (layer_idx < size - 1 && layer->zindex > layers.items[layer_idx + 1]->zindex) {
      layers.items[layer_idx] = layers.items[layer_idx + 1];
      layers.items[layer_idx]->comp_index = layer_idx;
      layers.items[layer_idx]->pending_comp_index_update = true;
      layer_idx++;
    }
  } else {
    while (layer_idx > 0 && layer->zindex < layers.items[layer_idx - 1]->zindex) {
      layers.items[layer_idx] = layers.items[layer_idx - 1];
      layers.items[layer_idx]->comp_index = layer_idx;
      layers.items[layer_idx]->pending_comp_index_update = true;
      layer_idx--;
    }
  }
  layers.items[layer_idx] = layer;
  layer->comp_index = layer_idx;
  layer->pending_comp_index_update = true;
}

/// Places `grid` at (col,row) position with (width * height) size.
/// Adds `grid` as the top layer if it is a new layer.
///
/// TODO(bfredl): later on the compositor should just use win_float_pos events,
/// though that will require slight event order adjustment: emit the win_pos
/// events in the beginning of update_screen(), rather than in ui_flush()
bool ui_comp_put_grid(ScreenGrid *grid, int row, int col, int height, int width, bool valid,
                      bool on_top)
{
  bool moved;
  grid->pending_comp_index_update = true;

  grid->comp_height = height;
  grid->comp_width = width;
  if (grid->comp_index != 0) {
    moved = (row != grid->comp_row) || (col != grid->comp_col);
    if (ui_comp_should_draw()) {
      // Redraw the area covered by the old position, and is not covered
      // by the new position. Disable the grid so that compose_area() will not
      // use it.
      grid->comp_disabled = true;
      compose_area(grid->comp_row, row,
                   grid->comp_col, grid->comp_col + grid->cols);
      if (grid->comp_col < col) {
        compose_area(MAX(row, grid->comp_row),
                     MIN(row + height, grid->comp_row + grid->rows),
                     grid->comp_col, col);
      }
      if (col + width < grid->comp_col + grid->cols) {
        compose_area(MAX(row, grid->comp_row),
                     MIN(row + height, grid->comp_row + grid->rows),
                     col + width, grid->comp_col + grid->cols);
      }
      compose_area(row + height, grid->comp_row + grid->rows,
                   grid->comp_col, grid->comp_col + grid->cols);
      grid->comp_disabled = false;
    }
    grid->comp_row = row;
    grid->comp_col = col;
  } else {
    moved = true;
#ifndef NDEBUG
    for (size_t i = 0; i < kv_size(layers); i++) {
      if (kv_A(layers, i) == grid) {
        abort();
      }
    }
#endif

    size_t insert_at = kv_size(layers);
    while (insert_at > 0 && kv_A(layers, insert_at - 1)->zindex > grid->zindex) {
      insert_at--;
    }

    if (curwin && kv_A(layers, insert_at - 1) == &curwin->w_grid_alloc
        && kv_A(layers, insert_at - 1)->zindex == grid->zindex
        && !on_top) {
      insert_at--;
    }
    // not found: new grid
    kv_pushp(layers);
    for (size_t i = kv_size(layers) - 1; i > insert_at; i--) {
      kv_A(layers, i) = kv_A(layers, i - 1);
      kv_A(layers, i)->comp_index = i;
      kv_A(layers, i)->pending_comp_index_update = true;
    }
    kv_A(layers, insert_at) = grid;

    grid->comp_row = row;
    grid->comp_col = col;
    grid->comp_index = insert_at;
    grid->pending_comp_index_update = true;
  }
  if (moved && valid && ui_comp_should_draw()) {
    compose_area(grid->comp_row, grid->comp_row + grid->rows,
                 grid->comp_col, grid->comp_col + grid->cols);
  }
  return moved;
}

void ui_comp_remove_grid(ScreenGrid *grid)
{
  assert(grid != &default_grid);
  if (grid->comp_index == 0) {
    // grid wasn't present
    return;
  }

  if (curgrid == grid) {
    curgrid = &default_grid;
  }

  for (size_t i = grid->comp_index; i < kv_size(layers) - 1; i++) {
    kv_A(layers, i) = kv_A(layers, i + 1);
    kv_A(layers, i)->comp_index = i;
    kv_A(layers, i)->pending_comp_index_update = true;
  }
  (void)kv_pop(layers);
  grid->comp_index = 0;
  grid->pending_comp_index_update = true;

  // recompose the area under the grid
  // inefficient when being overlapped: only draw up to grid->comp_index
  ui_comp_compose_grid(grid);
}

bool ui_comp_set_grid(handle_T handle)
{
  if (curgrid->handle == handle) {
    return true;
  }
  ScreenGrid *grid = NULL;
  for (size_t i = 0; i < kv_size(layers); i++) {
    if (kv_A(layers, i)->handle == handle) {
      grid = kv_A(layers, i);
      break;
    }
  }
  if (grid != NULL) {
    curgrid = grid;
    return true;
  }
  return false;
}

void ui_comp_raise_grid(ScreenGrid *grid, size_t new_index)
{
  size_t old_index = grid->comp_index;
  for (size_t i = old_index; i < new_index; i++) {
    kv_A(layers, i) = kv_A(layers, i + 1);
    kv_A(layers, i)->comp_index = i;
    kv_A(layers, i)->pending_comp_index_update = true;
  }
  kv_A(layers, new_index) = grid;
  grid->comp_index = new_index;
  grid->pending_comp_index_update = true;
  for (size_t i = old_index; i < new_index; i++) {
    ScreenGrid *grid2 = kv_A(layers, i);
    int startcol = MAX(grid->comp_col, grid2->comp_col);
    int endcol = MIN(grid->comp_col + grid->cols,
                     grid2->comp_col + grid2->cols);
    compose_area(MAX(grid->comp_row, grid2->comp_row),
                 MIN(grid->comp_row + grid->rows, grid2->comp_row + grid2->rows),
                 startcol, endcol);
  }
}

void ui_comp_grid_cursor_goto(Integer grid_handle, Integer r, Integer c)
{
  if (!ui_comp_set_grid((int)grid_handle)) {
    return;
  }
  int cursor_row = curgrid->comp_row + (int)r;
  int cursor_col = curgrid->comp_col + (int)c;

  // TODO(bfredl): maybe not the best time to do this, for efficiency we
  // should configure all grids before entering win_update()
  if (curgrid != &default_grid) {
    size_t new_index = kv_size(layers) - 1;

    while (new_index > 1 && kv_A(layers, new_index)->zindex > curgrid->zindex) {
      new_index--;
    }

    if (curgrid->comp_index < new_index) {
      ui_comp_raise_grid(curgrid, new_index);
    }
  }

  if (cursor_col >= default_grid.cols || cursor_row >= default_grid.rows) {
    // TODO(bfredl): this happens with 'writedelay', refactor?
    // abort();
    return;
  }
  ui_composed_call_grid_cursor_goto(1, cursor_row, cursor_col);
}

ScreenGrid *ui_comp_mouse_focus(int row, int col)
{
  for (ssize_t i = (ssize_t)kv_size(layers) - 1; i > 0; i--) {
    ScreenGrid *grid = kv_A(layers, i);
    if (grid->mouse_enabled
        && row >= grid->comp_row && row < grid->comp_row + grid->rows
        && col >= grid->comp_col && col < grid->comp_col + grid->cols) {
      return grid;
    }
  }
  if (ui_has(kUIMultigrid)) {
    FOR_ALL_WINDOWS_IN_TAB(wp, curtab) {
      ScreenGrid *grid = &wp->w_grid_alloc;
      if (grid->mouse_enabled && row >= wp->w_winrow && row < wp->w_winrow + grid->rows
          && col >= wp->w_wincol && col < wp->w_wincol + grid->cols) {
        return grid;
      }
    }
  }
  return NULL;
}

/// Compute which grid is on top at supplied screen coordinates
ScreenGrid *ui_comp_get_grid_at_coord(int row, int col)
{
  for (ssize_t i = (ssize_t)kv_size(layers) - 1; i > 0; i--) {
    ScreenGrid *grid = kv_A(layers, i);
    if (row >= grid->comp_row && row < grid->comp_row + grid->rows
        && col >= grid->comp_col && col < grid->comp_col + grid->cols) {
      return grid;
    }
  }

  FOR_ALL_WINDOWS_IN_TAB(wp, curtab) {
    ScreenGrid *grid = &wp->w_grid_alloc;
    if (row >= grid->comp_row && row < grid->comp_row + grid->rows
        && col >= grid->comp_col && col < grid->comp_col + grid->cols
        && !wp->w_config.hide) {
      return grid;
    }
  }
  return &default_grid;
}

/// Baseline implementation. This is always correct, but we can sometimes
/// do something more efficient (where efficiency means smaller deltas to
/// the downstream UI.)
static void compose_line(Integer row, Integer startcol, Integer endcol, LineFlags flags)
{
  // If rightleft is set, startcol may be -1. In such cases, the assertions
  // will fail because no overlap is found. Adjust startcol to prevent it.
  startcol = MAX(startcol, 0);
  // in case we start on the right half of a double-width char, we need to
  // check the left half. But skip it in output if it wasn't doublewidth.
  int skipstart = 0;
  int skipend = 0;
  if (startcol > 0 && (flags & kLineFlagInvalid)) {
    startcol--;
    skipstart = 1;
  }
  if (endcol < default_grid.cols && (flags & kLineFlagInvalid)) {
    endcol++;
    skipend = 1;
  }

  int col = (int)startcol;
  ScreenGrid *grid = NULL;
  schar_T *bg_line = &default_grid.chars[default_grid.line_offset[row]
                                         + (size_t)startcol];
  sattr_T *bg_attrs = &default_grid.attrs[default_grid.line_offset[row]
                                          + (size_t)startcol];

  while (col < endcol) {
    int until = 0;
    for (size_t i = 0; i < kv_size(layers); i++) {
      ScreenGrid *g = kv_A(layers, i);
      // compose_line may have been called after a shrinking operation but
      // before the resize has actually been applied. Therefore, we need to
      // first check to see if any grids have pending updates to width/height,
      // to ensure that we don't accidentally put any characters into `linebuf`
      // that have been invalidated.
      int grid_width = MIN(g->cols, g->comp_width);
      int grid_height = MIN(g->rows, g->comp_height);
      if (g->comp_row > row || row >= g->comp_row + grid_height
          || g->comp_disabled) {
        continue;
      }
      if (g->comp_col <= col && col < g->comp_col + grid_width) {
        grid = g;
        until = g->comp_col + grid_width;
      } else if (g->comp_col > col) {
        until = MIN(until, g->comp_col);
      }
    }
    until = MIN(until, (int)endcol);

    assert(grid != NULL);
    assert(until > col);
    assert(until <= default_grid.cols);
    size_t n = (size_t)(until - col);

    if (row == msg_sep_row && grid->comp_index <= msg_grid.comp_index) {
      // TODO(bfredl): when we implement borders around floating windows, then
      // msgsep can just be a border "around" the message grid.
      grid = &msg_grid;
      sattr_T msg_sep_attr = (sattr_T)HL_ATTR(HLF_MSGSEP);
      for (int i = col; i < until; i++) {
        linebuf[i - startcol] = msg_sep_char;
        attrbuf[i - startcol] = msg_sep_attr;
      }
    } else {
      size_t off = grid->line_offset[row - grid->comp_row]
                   + (size_t)(col - grid->comp_col);
      memcpy(linebuf + (col - startcol), grid->chars + off, n * sizeof(*linebuf));
      memcpy(attrbuf + (col - startcol), grid->attrs + off, n * sizeof(*attrbuf));
      if (grid->comp_col + grid->cols > until
          && grid->chars[off + n] == NUL) {
        linebuf[until - 1 - startcol] = schar_from_ascii(' ');
        if (col == startcol && n == 1) {
          skipstart = 0;
        }
      }
    }

    // 'pumblend' and 'winblend'
    if (grid->blending) {
      int width;
      for (int i = col - (int)startcol; i < until - startcol; i += width) {
        width = 1;
        // negative space
        bool thru = (linebuf[i] == schar_from_ascii(' ')
                     || linebuf[i] == schar_from_char(L'\u2800')) && bg_line[i] != NUL;
        if (i + 1 < endcol - startcol && bg_line[i + 1] == NUL) {
          width = 2;
          thru &= (linebuf[i + 1] == schar_from_ascii(' ')
                   || linebuf[i + 1] == schar_from_char(L'\u2800'));
        }
        attrbuf[i] = (sattr_T)hl_blend_attrs(bg_attrs[i], attrbuf[i], &thru);
        if (width == 2) {
          attrbuf[i + 1] = (sattr_T)hl_blend_attrs(bg_attrs[i + 1],
                                                   attrbuf[i + 1], &thru);
        }
        if (thru) {
          memcpy(linebuf + i, bg_line + i, (size_t)width * sizeof(linebuf[i]));
        }
      }
    }

    // Tricky: if overlap caused a doublewidth char to get cut-off, must
    // replace the visible half with a space.
    if (linebuf[col - startcol] == NUL) {
      linebuf[col - startcol] = schar_from_ascii(' ');
      if (col == endcol - 1) {
        skipend = 0;
      }
    } else if (col == startcol && n > 1 && linebuf[1] == NUL) {
      skipstart = 0;
    }

    col = until;
  }
  if (linebuf[endcol - startcol - 1] == NUL) {
    skipend = 0;
  }

  assert(endcol <= chk_width);
  assert(row < chk_height);

  if (!(grid && (grid == &default_grid || (grid->comp_col == 0 && grid->cols == Columns)))) {
    flags = flags & ~kLineFlagWrap;
  }

  for (int i = skipstart; i < (endcol - skipend) - startcol; i++) {
    if (attrbuf[i] < 0) {
      if (rdb_flags & kOptRdbFlagInvalid) {
        abort();
      } else {
        attrbuf[i] = 0;
      }
    }
  }
  ui_composed_call_raw_line(1, row, startcol + skipstart,
                            endcol - skipend, endcol - skipend, 0, flags,
                            (const schar_T *)linebuf + skipstart,
                            (const sattr_T *)attrbuf + skipstart);
}

static void compose_debug(Integer startrow, Integer endrow, Integer startcol, Integer endcol,
                          int syn_id, bool delay)
{
  if (!(rdb_flags & kOptRdbFlagCompositor) || startcol >= endcol) {
    return;
  }

  endrow = MIN(endrow, default_grid.rows);
  endcol = MIN(endcol, default_grid.cols);
  int attr = syn_id2attr(syn_id);

  if (delay) {
    debug_delay(endrow - startrow);
  }

  for (int row = (int)startrow; row < endrow; row++) {
    ui_composed_call_raw_line(1, row, startcol, startcol, endcol, attr, false,
                              (const schar_T *)linebuf,
                              (const sattr_T *)attrbuf);
  }

  if (delay) {
    debug_delay(endrow - startrow);
  }
}

static void debug_delay(Integer lines)
{
  ui_call_flush();
  uint64_t wd = (uint64_t)llabs(p_wd);
  uint64_t factor = (uint64_t)MAX(MIN(lines, 5), 1);
  os_sleep(factor * wd);
}

static int overlay_span_cmp(const void *lhs, const void *rhs)
{
  const OverlaySpan *a = (const OverlaySpan *)lhs;
  const OverlaySpan *b = (const OverlaySpan *)rhs;
  if (a->start != b->start) {
    return a->start - b->start;
  }
  return a->end - b->end;
}

static size_t collect_overlay_spans(Integer row, Integer startcol, Integer endcol)
{
  startcol = MAX(startcol, 0);
  endcol = MIN(endcol, default_grid.cols);
  if (endcol <= startcol) {
    kv_size(overlay_row_spans) = 0;
    return 0;
  }

  kv_size(overlay_row_spans) = 0;

  size_t layer_count = kv_size(layers);
  for (size_t i = 1; i < layer_count; i++) {
    ScreenGrid *g = kv_A(layers, i);
    if (g->comp_disabled) {
      continue;
    }

    int grid_width = MIN(g->cols, g->comp_width);
    int grid_height = MIN(g->rows, g->comp_height);
    if (grid_width <= 0 || grid_height <= 0) {
      continue;
    }
    if (row < g->comp_row || row >= g->comp_row + grid_height) {
      continue;
    }

    int grid_left = g->comp_col;
    int grid_right = grid_left + grid_width;
    if (grid_right <= startcol || grid_left >= endcol) {
      continue;
    }

    int span_start = (int)MAX(startcol, grid_left);
    if (span_start < 0) {
      span_start = 0;
    }
    int span_end = (int)MIN(endcol, grid_right);
    if (span_end <= span_start) {
      continue;
    }

    OverlaySpan span = { span_start, span_end };
    kv_push(overlay_row_spans, span);
  }

  if (kv_size(overlay_row_spans) == 0) {
    return 0;
  }

  OverlaySpan *spans = overlay_row_spans.items;
  size_t span_count = kv_size(overlay_row_spans);
  qsort(spans, span_count, sizeof(OverlaySpan), overlay_span_cmp);

  size_t write_index = 0;
  OverlaySpan current = spans[0];
  for (size_t i = 1; i < span_count; i++) {
    OverlaySpan span = spans[i];
    if (span.start <= current.end) {
      if (span.end > current.end) {
        current.end = span.end;
      }
    } else {
      spans[write_index++] = current;
      current = span;
    }
  }
  spans[write_index++] = current;
  kv_size(overlay_row_spans) = write_index;

  return kv_size(overlay_row_spans);
}

Array ui_comp_collect_overlay_spans(int row, int startcol, int endcol, Arena *arena)
{
  Array result = arena_array(arena, 0);
  size_t span_count = collect_overlay_spans(row, startcol, endcol);
  if (span_count == 0) {
    return result;
  }
  Array spans = arena_array(arena, span_count);
  for (size_t i = 0; i < span_count; i++) {
    OverlaySpan span = kv_A(overlay_row_spans, i);
    Array entry = arena_array(arena, 2);
    ADD_C(entry, INTEGER_OBJ((Integer)span.start));
    ADD_C(entry, INTEGER_OBJ((Integer)span.end));
    ADD_C(spans, ARRAY_OBJ(entry));
  }
  return spans;
}

static void compose_area(Integer startrow, Integer endrow, Integer startcol, Integer endcol)
{
  compose_debug(startrow, endrow, startcol, endcol, dbghl_recompose, true);
  endrow = MIN(endrow, default_grid.rows);
  endcol = MIN(endcol, default_grid.cols);
  if (endcol <= startcol) {
    return;
  }
  for (int r = (int)startrow; r < endrow; r++) {
    size_t span_count = collect_overlay_spans(r, startcol, endcol);
    if (span_count == 0) {
      compose_line(r, startcol, endcol, kLineFlagInvalid);
      continue;
    }
    uint64_t overlay_width_sum = 0;
    for (size_t i = 0; i < span_count; i++) {
      OverlaySpan span = kv_A(overlay_row_spans, i);
      overlay_width_sum += (uint64_t)(span.end - span.start);
    }
    if (overlay_width_sum > 0) {
      ui_comp_metrics.overlay_prune_calls++;
      ui_comp_metrics.overlay_prune_width_total += overlay_width_sum;
    }
    for (size_t i = 0; i < span_count; i++) {
      OverlaySpan span = kv_A(overlay_row_spans, i);
      compose_line(r, span.start, span.end, kLineFlagInvalid);
    }
  }
}

/// compose the area under the grid.
///
/// This is needed when some option affecting composition is changed,
/// such as 'pumblend' for popupmenu grid.
void ui_comp_compose_grid(ScreenGrid *grid)
{
  if (ui_comp_should_draw()) {
    compose_area(grid->comp_row, grid->comp_row + grid->rows,
                 grid->comp_col, grid->comp_col + grid->cols);
  }
}

void ui_comp_raw_line(Integer grid, Integer row, Integer startcol, Integer endcol, Integer clearcol,
                      Integer clearattr, LineFlags flags, const schar_T *chunk,
                      const sattr_T *attrs)
{
  if (!ui_comp_should_draw() || !ui_comp_set_grid((int)grid)) {
    return;
  }

  row += curgrid->comp_row;
  startcol += curgrid->comp_col;
  endcol += curgrid->comp_col;
  clearcol += curgrid->comp_col;
  if (curgrid != &default_grid) {
    flags = flags & ~kLineFlagWrap;
  }

  assert(endcol <= clearcol);

  // TODO(bfredl): this should not really be necessary. But on some condition
  // when resizing nvim, a window will be attempted to be drawn on the older
  // and possibly larger global screen size.
  if (row >= default_grid.rows) {
    DLOG("compositor: invalid row %" PRId64 " on grid %" PRId64, row, grid);
    return;
  }
  if (clearcol > default_grid.cols) {
    DLOG("compositor: invalid last column %" PRId64 " on grid %" PRId64,
         clearcol, grid);
    if (startcol >= default_grid.cols) {
      return;
    }
    clearcol = default_grid.cols;
    endcol = MIN(endcol, clearcol);
  }

  bool covered = curgrid_covered_above((int)row, 1, NULL, NULL, NULL, NULL);
  // TODO(bfredl): eventually should just fix compose_line to respect clearing
  // and optimize it for uncovered lines.
  if ((flags & kLineFlagInvalid) || curgrid->blending) {
    compose_debug(row, row + 1, startcol, clearcol, dbghl_composed, true);
    compose_line(row, startcol, clearcol, flags);
    return;
  }

  if (covered) {
    size_t span_count = collect_overlay_spans(row, startcol, clearcol);
    if (span_count == 0) {
      compose_debug(row, row + 1, startcol, clearcol, dbghl_composed, true);
      compose_line(row, startcol, clearcol, flags);
      return;
    }

    uint64_t overlay_width_sum = 0;
    for (size_t i = 0; i < span_count; i++) {
      OverlaySpan span = kv_A(overlay_row_spans, i);
      overlay_width_sum += (uint64_t)(span.end - span.start);
    }
    if (overlay_width_sum > 0) {
      ui_comp_metrics.overlay_prune_calls++;
      ui_comp_metrics.overlay_prune_width_total += overlay_width_sum;
    }

    compose_debug(row, row + 1, startcol, clearcol, dbghl_composed, true);

    int seg_cursor = (int)startcol;
    for (size_t i = 0; i < span_count && seg_cursor < (int)clearcol; i++) {
      OverlaySpan span = kv_A(overlay_row_spans, i);
      int span_start = span.start;
      int span_end = span.end;

      if (span_start > seg_cursor && seg_cursor < (int)endcol) {
        int text_end = MIN(span_start, (int)endcol);
        if (text_end > seg_cursor) {
          size_t offset = (size_t)(seg_cursor - startcol);
          compose_debug(row, row + 1, seg_cursor, text_end, dbghl_normal,
                        text_end >= (int)clearcol);
#ifndef NDEBUG
          for (int i_attr = 0; i_attr < text_end - seg_cursor; i_attr++) {
            assert(attrs[offset + (size_t)i_attr] >= 0);
          }
#endif
          ui_composed_call_raw_line(1, row, seg_cursor, text_end, text_end, clearattr,
                                    flags, chunk + offset, attrs + offset);
        }
      }

      if (span_end > seg_cursor) {
        compose_line(row, span_start, span_end, flags);
        seg_cursor = span_end;
      }
    }

    if (seg_cursor < (int)endcol) {
      int text_end = (int)endcol;
      size_t offset = (size_t)(seg_cursor - startcol);
      compose_debug(row, row + 1, seg_cursor, text_end, dbghl_normal, text_end >= (int)clearcol);
#ifndef NDEBUG
      for (int i_attr = 0; i_attr < text_end - seg_cursor; i_attr++) {
        assert(attrs[offset + (size_t)i_attr] >= 0);
      }
#endif
      ui_composed_call_raw_line(1, row, seg_cursor, text_end, text_end, clearattr,
                                flags, chunk + offset, attrs + offset);
      seg_cursor = text_end;
    }

    if (seg_cursor < (int)clearcol) {
      int clean_start = seg_cursor;
      int chunk_col = (int)MIN((Integer)endcol, (Integer)clean_start);
      size_t offset = (size_t)(chunk_col - startcol);
      compose_debug(row, row + 1, clean_start, clearcol, dbghl_clear, true);
      ui_composed_call_raw_line(1, row, clean_start, clean_start, clearcol, clearattr,
                                flags, chunk + offset, attrs + offset);
    }
  } else {
    compose_debug(row, row + 1, startcol, endcol, dbghl_normal, endcol >= clearcol);
    compose_debug(row, row + 1, endcol, clearcol, dbghl_clear, true);
#ifndef NDEBUG
    for (int i = 0; i < endcol - startcol; i++) {
      assert(attrs[i] >= 0);
    }
#endif
    ui_composed_call_raw_line(1, row, startcol, endcol, clearcol, clearattr,
                              flags, chunk, attrs);
  }
}

/// The screen is invalid and will soon be cleared
///
/// Don't redraw floats until screen is cleared
bool ui_comp_set_screen_valid(bool valid)
{
  bool old_val = valid_screen;
  valid_screen = valid;
  if (!valid) {
    msg_sep_row = -1;
  }
  return old_val;
}

void ui_comp_msg_set_pos(Integer grid, Integer row, Boolean scrolled, String sep_char,
                         Integer zindex, Integer compindex)
{
  msg_grid.pending_comp_index_update = true;
  msg_grid.comp_row = (int)row;
  if (scrolled && row > 0) {
    msg_sep_row = (int)row - 1;
    if (sep_char.data) {
      msg_sep_char = schar_from_buf(sep_char.data, sep_char.size);
    }
  } else {
    msg_sep_row = -1;
  }

  if (row > msg_current_row && ui_comp_should_draw()) {
    compose_area(MAX(msg_current_row - 1, 0), row, 0, default_grid.cols);
  } else if (row < msg_current_row && ui_comp_should_draw()
             && (msg_current_row < Rows || (scrolled && !msg_was_scrolled))) {
    int delta = msg_current_row - (int)row;
    if (msg_grid.blending) {
      int first_row = MAX((int)row - (scrolled ? 1 : 0), 0);
      compose_area(first_row, Rows - delta, 0, Columns);
    } else {
      // scroll separator together with message text
      int first_row = MAX((int)row - (msg_was_scrolled ? 1 : 0), 0);
      ui_composed_call_grid_scroll(1, first_row, Rows, 0, Columns, delta, 0);
      if (scrolled && !msg_was_scrolled && row > 0) {
        compose_area(row - 1, row, 0, Columns);
      }
    }
  }

  msg_current_row = (int)row;
  msg_was_scrolled = scrolled;
}

/// check if curgrid is covered on row or above
///
/// TODO(bfredl): currently this only handles message row
static bool curgrid_covered_above(int row, int span, bool *above_msg_out,
                                  uint64_t *cover_handle_out, int *cover_zindex_out,
                                  ScreenGrid **cover_grid_out)
{
  size_t layer_count = kv_size(layers);
  bool above_msg = false;
  bool ignore_msg = false;
  int span_abs = span >= 0 ? span : -span;
  int bottom_row = row + (span_abs > 0 ? span_abs - 1 : 0);
  ScreenGrid *cover_grid = NULL;
  if (layer_count > 0) {
    ScreenGrid *top = kv_A(layers, layer_count - 1);
    if (top == &msg_grid) {
      if (msg_current_row == INT_MAX) {
        ignore_msg = true;
      } else {
        int msg_threshold = msg_current_row - (msg_was_scrolled ? 1 : 0);
        bool msg_above_row = row < msg_threshold;
        bool msg_overlap_span = bottom_row >= msg_threshold;
        if (msg_above_row && msg_overlap_span) {
          above_msg = true;
        } else {
          ignore_msg = true;
        }
      }
    }
  }
  if (above_msg_out != NULL) {
    *above_msg_out = above_msg;
  }
  size_t effective_count = layer_count - ((above_msg || ignore_msg) ? 1 : 0);
  bool covered = effective_count > (size_t)curgrid->comp_index + 1;
  uint64_t handle = 0;
  int zindex = 0;
  if (covered) {
    for (size_t i = (size_t)curgrid->comp_index + 1; i < layer_count; i++) {
      ScreenGrid *g = kv_A(layers, i);
      if (g == &msg_grid && (above_msg || ignore_msg)) {
        continue;
      }
      handle = (uint64_t)g->handle;
      zindex = g->zindex;
      cover_grid = g;
      break;
    }
  }
  if (cover_handle_out != NULL) {
    *cover_handle_out = handle;
  }
  if (cover_zindex_out != NULL) {
    *cover_zindex_out = zindex;
  }
  if (cover_grid_out != NULL) {
    *cover_grid_out = cover_grid;
  }
  return covered;
}

void ui_comp_grid_scroll(Integer grid, Integer top, Integer bot, Integer left, Integer right,
                         Integer rows, Integer cols)
{
  if (!ui_comp_should_draw() || !ui_comp_set_grid((int)grid)) {
    return;
  }
  top += curgrid->comp_row;
  bot += curgrid->comp_row;
  left += curgrid->comp_col;
  right += curgrid->comp_col;
  int left_col = (int)left;
  int right_col = (int)right;
  bool covered_above_msg = false;
  uint64_t covered_handle = 0;
  int covered_zindex = 0;
  bool covered_external = false;
  bool covered_popup = false;
  ScreenGrid *cover_grid = NULL;
  int checked_row = (int)(bot - MAX(rows, 0));
  int span = (int)rows;
  if (span < 0) {
    span = -span;
  }
  bool covered = curgrid_covered_above(checked_row, span, &covered_above_msg, &covered_handle,
                                       &covered_zindex, &cover_grid);
  bool popup_candidate = covered && covered_zindex >= kZIndexPopupMenu
                         && covered_zindex < kZIndexCmdlinePopupMenu;
  if (popup_candidate) {
    if (!pum_visible()) {
      ui_comp_metrics.fallback_popup_ignored++;
      ui_composed_call_grid_scroll(1, top, bot, left, right, rows, cols);
      if (rdb_flags & kOptRdbFlagCompositor) {
        debug_delay(2);
      }
      return;
    } else {
      covered_popup = true;
    }
  }
  if (covered && covered_handle == 0 && covered_zindex == 0) {
    covered_external = true;
  }

  if (!covered && !curgrid->blending) {
    ui_composed_call_grid_scroll(1, top, bot, left, right, rows, cols);
    if (rdb_flags & kOptRdbFlagCompositor) {
      debug_delay(2);
    }
    return;
  }

  if (covered || curgrid->blending) {
    // TODO(bfredl):
    // 1. check if rectangles actually overlap
    // 2. calculate subareas that can scroll.
    compose_debug(top, bot, left, right, dbghl_recompose, true);

    int loop_start = (int)(top + MAX(-rows, 0));
    int loop_end = (int)(bot - MAX(rows, 0));
    int row_overlap_start = loop_start;
    int row_overlap_end = loop_end;
    int overlap_left = left_col;
    int overlap_right = right_col;
    if (cover_grid != NULL) {
      int cover_row_start = cover_grid->comp_row;
      int cover_row_end = cover_grid->comp_row + cover_grid->rows;
      int cover_col_start = cover_grid->comp_col;
      int cover_col_end = cover_grid->comp_col + cover_grid->cols;
      row_overlap_start = MAX(loop_start, cover_row_start);
      row_overlap_end = MIN(loop_end, cover_row_end);
      overlap_left = MAX(left_col, cover_col_start);
      overlap_right = MIN(right_col, cover_col_end);
      if (row_overlap_start < loop_start) {
        row_overlap_start = loop_start;
      }
      if (row_overlap_end > loop_end) {
        row_overlap_end = loop_end;
      }
      if (overlap_left < left_col) {
        overlap_left = left_col;
      }
      if (overlap_right > right_col) {
        overlap_right = right_col;
      }
      if (row_overlap_start < row_overlap_end && overlap_left < overlap_right) {
        ui_composed_call_grid_scroll(1, top, bot, left, right, rows, cols);
        if (rdb_flags & kOptRdbFlagCompositor) {
          debug_delay(2);
        }
      } else {
        row_overlap_start = loop_start;
        row_overlap_end = loop_end;
        overlap_left = left_col;
        overlap_right = right_col;
      }
    }
    int target_span = row_overlap_end - row_overlap_start;
    if (target_span < 0) {
      target_span = 0;
    }
    int recomposed_lines = 0;
    uint64_t processed_width = 0;

#if defined(STAP_PROBE4) && defined(STAP_PROBE5)
    // USDT probe records fallback scroll entry: bit0=covered, bit1=blending.
    NVIM_PROBE(nvim_ui_comp_scroll_fallback_begin, 5, (int64_t)curgrid->handle,
               (int64_t)top, (int64_t)bot, (int64_t)rows,
               (int64_t)((covered ? 1 : 0) | (curgrid->blending ? 2 : 0)));
#endif
    for (int r = row_overlap_start; r < row_overlap_end; r++) {
      // TODO(bfredl): workaround for win_update() performing two scrolls in a
      // row, where the latter might scroll invalid space created by the first.
      // ideally win_update() should keep track of this itself and not scroll
      // the invalid space.
      size_t attr_off = curgrid->line_offset[r - curgrid->comp_row]
                        + (size_t)overlap_left - (size_t)curgrid->comp_col;
      if (curgrid->attrs[attr_off] >= 0) {
        recomposed_lines++;
        compose_line(r, overlap_left, overlap_right, 0);
        processed_width += (uint64_t)(overlap_right - overlap_left);
      }
    }

#if defined(STAP_PROBE4) && defined(STAP_PROBE5)
    // USDT probe emits recomposed span length alongside processed rows.
    NVIM_PROBE(nvim_ui_comp_scroll_fallback_end, 4, (int64_t)curgrid->handle,
               (int64_t)target_span, (int64_t)recomposed_lines,
               (int64_t)(overlap_right - overlap_left));
#endif

    ui_comp_metrics.fallback_calls++;
    ui_comp_metrics.fallback_span_total += (uint64_t)target_span;
    ui_comp_metrics.fallback_recomposed_total += (uint64_t)recomposed_lines;
    ui_comp_metrics.fallback_width_total += processed_width;
    uint64_t skipped_lines = 0;
    if (target_span > recomposed_lines) {
      skipped_lines = (uint64_t)(target_span - recomposed_lines);
    }
    ui_comp_metrics.fallback_skipped_lines_total += skipped_lines;
    ui_comp_metrics.fallback_last_row_checked = (int64_t)checked_row;
    ui_comp_metrics.fallback_msg_row = (int64_t)msg_current_row;
    ui_comp_metrics.fallback_rows_argument = (int64_t)rows;
    ui_comp_metrics.fallback_last_row_checked = (int64_t)checked_row;
    ui_comp_metrics.fallback_msg_row = (int64_t)msg_current_row;
    ui_comp_metrics.fallback_rows_argument = (int64_t)rows;
    if (curgrid->blending) {
      ui_comp_metrics.fallback_blending_calls++;
    }
    if (covered) {
      ui_comp_metrics.fallback_covered_calls++;
      if (covered_above_msg) {
        ui_comp_metrics.fallback_above_msg_calls++;
      }
      ui_comp_metrics.fallback_cover_handle_last = covered_handle;
      ui_comp_metrics.fallback_cover_zindex_last = covered_zindex;
      if (covered_popup) {
        ui_comp_metrics.fallback_popup_calls++;
      }
      if (covered_external) {
        ui_comp_metrics.fallback_external_calls++;
      }
    } else {
      ui_comp_metrics.fallback_cover_handle_last = 0;
      ui_comp_metrics.fallback_cover_zindex_last = 0;
    }
  } else {
    ui_composed_call_grid_scroll(1, top, bot, left, right, rows, cols);
    if (rdb_flags & kOptRdbFlagCompositor) {
      debug_delay(2);
    }
  }
}

void ui_comp_grid_resize(Integer grid, Integer width, Integer height)
{
  if (grid == 1) {
    ui_composed_call_grid_resize(1, width, height);
#ifndef NDEBUG
    chk_width = (int)width;
    chk_height = (int)height;
#endif
    size_t new_bufsize = (size_t)width;
    if (bufsize != new_bufsize) {
      xfree(linebuf);
      xfree(attrbuf);
      linebuf = xmalloc(new_bufsize * sizeof(*linebuf));
      attrbuf = xmalloc(new_bufsize * sizeof(*attrbuf));
      bufsize = new_bufsize;
    }
  }
}

/// Collects compositor fallback metrics without resetting counters.
void ui_comp_metrics_snapshot(UICompMetrics *out)
{
  if (out != NULL) {
    *out = ui_comp_metrics;
  }
}

/// Resets compositor fallback metrics counters.
void ui_comp_metrics_reset(void)
{
  memset(&ui_comp_metrics, 0, sizeof(ui_comp_metrics));
}
