local t = require('test.unit.testutil')
local describe = t.describe
local itp = t.gen_itp(t.it)

local ffi = t.ffi
local cimport = t.cimport
local eq = t.eq

local tui = cimport('./src/nvim/tui/tui.h')

--- Builds a uv_buf_t array from a list of strings.
---
--- The backing char arrays are returned alongside the array: dropping them
--- would let the garbage collector free the memory the buffers point at.
---
--- @param strs string[]
--- @return ffi.cdata* bufs, table anchor
local function make_bufs(strs)
  local anchor = {}
  local bufs = ffi.new('uv_buf_t[?]', #strs)
  for i, s in ipairs(strs) do
    local mem = ffi.new('char[?]', #s + 1, s)
    anchor[i] = mem
    bufs[i - 1].base = mem
    bufs[i - 1].len = #s
  end
  return bufs, anchor
end

--- Concatenates the bytes still waiting to go out, starting at buffer `from`.
---
--- @param bufs ffi.cdata*
--- @param from integer 0-based index of the first unwritten buffer
--- @param nbufs integer
--- @return string
local function unwritten(bufs, from, nbufs)
  local parts = {}
  for i = from, nbufs - 1 do
    parts[#parts + 1] = ffi.string(bufs[i].base, tonumber(bufs[i].len))
  end
  return table.concat(parts)
end

describe('tui_bufs_advance', function()
  -- The shape flush_buf produces: a prologue, the rendered grid, an epilogue.
  local FLUSH = { 'abc', 'defgh', 'ij' }

  itp('reports no buffer done when the write made no progress', function()
    local bufs, _anchor = make_bufs(FLUSH)
    eq(0, tui.tui_bufs_advance(bufs, 3, 0))
    eq('abcdefghij', unwritten(bufs, 0, 3))
  end)

  itp('splits a buffer the write stopped inside', function()
    local bufs, _anchor = make_bufs(FLUSH)
    -- All of 'abc' plus 'de': the second buffer keeps its tail only.
    eq(1, tui.tui_bufs_advance(bufs, 3, 5))
    eq('fghij', unwritten(bufs, 1, 3))
  end)

  itp('consumes a buffer whole when the write lands on its boundary', function()
    local bufs, _anchor = make_bufs(FLUSH)
    eq(1, tui.tui_bufs_advance(bufs, 3, 3))
    eq('defghij', unwritten(bufs, 1, 3))

    bufs, _anchor = make_bufs(FLUSH)
    eq(2, tui.tui_bufs_advance(bufs, 3, 8))
    eq('ij', unwritten(bufs, 2, 3))
  end)

  itp('reports every buffer done when the whole array went out', function()
    local bufs, _anchor = make_bufs(FLUSH)
    eq(3, tui.tui_bufs_advance(bufs, 3, 10))
  end)

  itp('treats an empty leading buffer as already written', function()
    -- flush_buf emits an empty prologue whenever it has no cursor sequence
    -- to prepend, so zero-progress must still step past it.
    local bufs, _anchor = make_bufs({ '', 'ab' })
    eq(1, tui.tui_bufs_advance(bufs, 2, 0))
    eq('ab', unwritten(bufs, 1, 2))
  end)

  itp('resumes correctly when applied to the remainder of a previous call', function()
    -- The write loop calls this repeatedly on `bufs + done`, so partial
    -- progress must compose to the same result as one complete write.
    local bufs, _anchor = make_bufs(FLUSH)
    local done = tui.tui_bufs_advance(bufs, 3, 4)
    eq(1, done)
    done = done + tui.tui_bufs_advance(bufs + done, 3 - done, 2)
    eq(1, done)
    eq('ghij', unwritten(bufs, 1, 3))
    done = done + tui.tui_bufs_advance(bufs + done, 3 - done, 4)
    eq(3, done)
  end)
end)
