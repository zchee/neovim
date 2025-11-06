#pragma once

#ifdef UNIT_TESTING
# include <uv.h>
#endif

#include "nvim/highlight_defs.h"  // IWYU pragma: keep
#include "nvim/tui/terminfo_defs.h"
#include "nvim/tui/tui_defs.h"  // IWYU pragma: keep
#include "nvim/ui_defs.h"  // IWYU pragma: keep

#ifdef UNIT_TESTING
size_t nvim_test_terminfo_copy_cached(TerminfoDef def, const char *str, bool parametric,
                                      size_t cached_len_in, size_t *cached_len_out,
                                      char *dst, size_t len);

typedef struct {
  size_t try_call_count;
  size_t write_call_count;
  size_t try_total;
  size_t try_buf_lens[3];
  size_t write_total;
  size_t write_buf_lens[3];
  bool final_invisible;
} NvimTuiFlushDiag;

NvimTuiFlushDiag nvim_test_tui_flush_diag(size_t payload_len, ssize_t try_result,
                                          int write_ret, bool start_invisible,
                                          bool want_invisible);
#endif

#include "tui/tui.h.generated.h"
