#pragma once

#include "nvim/highlight_defs.h"  // IWYU pragma: keep
#include "nvim/tui/terminfo_defs.h"
#include "nvim/tui/tui_defs.h"  // IWYU pragma: keep
#include "nvim/ui_defs.h"  // IWYU pragma: keep

#ifdef UNIT_TESTING
size_t nvim_test_terminfo_copy_cached(TerminfoDef def, const char *str, bool parametric,
                                      size_t cached_len_in, size_t *cached_len_out,
                                      char *dst, size_t len);
#endif

#include "tui/tui.h.generated.h"
