local t = require('test.unit.testutil')
local itp = t.gen_itp(it)

local terminfo = t.cimport('./src/nvim/tui/terminfo.h')

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

