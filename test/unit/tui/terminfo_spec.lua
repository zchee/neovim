local t = require('test.unit.testutil')
local describe = t.describe
local itp = t.gen_itp(t.it)

local ffi = t.ffi
local cimport = t.cimport
local to_cstr = t.to_cstr
local eq = t.eq
local neq = t.neq

-- Import terminfo headers
local terminfo = cimport('./src/nvim/tui/terminfo.h')

-- Every $TERM that terminfo_from_builtin() answers with a distinct entry.
local BUILTIN_TERMS = {
  'ansi',
  'conemu',
  'cygwin',
  'ghostty',
  'interix',
  'iterm2',
  'linux',
  'putty-256color',
  'rxvt-256color',
  'screen-256color',
  'st-256color',
  'tmux-256color',
  'vte-256color',
  'vtpcon',
  'win32con',
  'xterm-256color',
}

describe('terminfo_fmt', function()
  itp('stack overflow fails before producing output', function()
    -- Creates a buffer
    local buf = ffi.new('char[256]')
    local buf_end = buf + ffi.sizeof(buf) -- One past end

    -- Sets input parameters
    local params = ffi.new('TPVAR[9]')
    params[0].num = 65 -- 'A'
    params[0].string = nil

    -- 20 pushes (TPSTACK nums array limit) then prints one char
    local valid_fmt = string.rep('%p1', 20) .. '%c'
    local valid_n = terminfo.terminfo_fmt(buf, buf_end, to_cstr(valid_fmt), params)
    eq(1, valid_n)

    -- Overflows with 21 pushes and fails before print
    local overflow_fmt = string.rep('%p1', 21) .. '%c'
    local overflow_n = terminfo.terminfo_fmt(buf, buf_end, to_cstr(overflow_fmt), params)
    eq(0, overflow_n)
  end)

  -- tui.c caches the rendered form of every capability that contains no '%',
  -- on the grounds that terminfo_fmt copies any byte outside a '%' directive
  -- straight through, so such a capability renders to its own bytes. If that
  -- ever stops being true the cache starts emitting the wrong escape
  -- sequences, so it is asserted here against the interpreter itself, for
  -- every zero-parameter capability of every built-in terminal.
  itp('renders every zero-parameter capability to its own bytes', function()
    local buf = ffi.new('char[1024]')
    local buf_end = buf + ffi.sizeof(buf)
    local params = ffi.new('TPVAR[9]')
    local termname = ffi.new('char *[1]')
    local checked = 0

    for _, term in ipairs(BUILTIN_TERMS) do
      local ti = terminfo.terminfo_from_builtin(to_cstr(term), termname)
      for i = 0, tonumber(terminfo.kTermCount) - 1 do
        local cap = ti.defs[i]
        if cap ~= nil then
          local want = ffi.string(cap)
          -- '%%' is a Lua pattern matching one literal '%'.
          if not want:find('%%') then
            ffi.fill(buf, ffi.sizeof(buf), 0)
            local n = assert(tonumber(terminfo.terminfo_fmt(buf, buf_end, cap, params)))
            eq(#want, n)
            eq(want, ffi.string(buf, n))
            checked = checked + 1
          end
        end
      end
    end

    -- Guard against the loop silently testing nothing.
    neq(0, checked)
  end)
end)
