#pragma once

#include "nvim/api/private/defs.h"  // IWYU pragma: keep
#include "nvim/tui/terminfo_defs.h"

typedef struct {
  long num;
  char *string;
} TPVAR;

bool terminfo_is_parametric(const char *str);

#include "tui/terminfo.h.generated.h"
