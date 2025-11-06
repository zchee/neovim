local t = require('test.unit.testutil')
local itp = t.gen_itp(it)

local terminfo = t.cimport('./src/nvim/tui/terminfo.h')
local terminfo_defs = t.cimport('./src/nvim/tui/terminfo_defs.h')
local tui = t.cimport('./src/nvim/tui/tui.h')

describe('terminfo_is_parametric', function()
  itp('detects simple constant sequences', function()
    t.eq(false, terminfo.terminfo_is_parametric('\027[?25l'))
    t.eq(false, terminfo.terminfo_is_parametric(''))
    t.eq(false, terminfo.terminfo_is_parametric(nil))
  end)

  itp('ignores escaped percent literals', function()
    t.eq(false, terminfo.terminfo_is_parametric('%%'))
    t.eq(false, terminfo.terminfo_is_parametric('\027]0;%%s\027\\'))
  end)

  itp('flags parameterized capabilities', function()
    t.eq(true, terminfo.terminfo_is_parametric('\027[%p1%dA'))
    t.eq(true, terminfo.terminfo_is_parametric('%+'))
  end)
end)


describe('terminfo cached copy helper', function()
  local ffi = require('ffi')

  itp('copies non-parametric capability from cache when it fits', function()
    local buf = ffi.new('char[?]', 32)
    local cached_len = ffi.new('size_t[1]', 0)

    local seq = '\027[?25l'
    local written = tui.nvim_test_terminfo_copy_cached(
      terminfo_defs.kTerm_cursor_invisible,
      seq,
      false,
      0,
      cached_len,
      buf,
      32
    )

    t.eq(#seq, written)
    t.eq(seq, ffi.string(buf, written))
    t.eq(#seq, cached_len[0])
  end)

  itp('falls back when buffer is too small', function()
    local buf = ffi.new('char[?]', 4)
    local cached_len = ffi.new('size_t[1]', 0)

    local seq = '\027[?25l'
    local written = tui.nvim_test_terminfo_copy_cached(
      terminfo_defs.kTerm_cursor_invisible,
      seq,
      false,
      0,
      cached_len,
      buf,
      4
    )

    t.eq(0, written)
    t.eq(#seq, cached_len[0])
  end)
end)
