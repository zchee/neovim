--- Redraw throughput over the remote-UI (msgpack) path.
---
--- Attaches a real UI grid to an `--embed` child and drives two workloads over
--- three corpora:
---   * scroll -- Ctrl-E one line at a time (grid_scroll + one grid_line/frame)
---   * page   -- jump + `zt` so the whole viewport changes (~one grid_line per
---               screen row per frame), i.e. the full-frame redraw case
--- Timing comes from the child's own clock around the redraw loop, so the
--- client's msgpack decoding is off the measured path; the byte and event
--- counters are collected by the client over that same region.
---
---   nvim -u NONE -l perf/bench_redraw.lua [nvim] [--runs=5] [--grid-w=200] ...

local ROOT = vim.fs.normalize(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))))
package.path = ROOT .. '/?.lua;' .. ROOT .. '/perf/?.lua;' .. package.path

local B = require('lib.bench')
local C = require('lib.client')

local a = _G.arg or {}
local nvim = B.nvim_path(a)
local o = B.opts(a, {
  runs = 5,
  grid_w = 200,
  grid_h = 50,
  scroll_iters = 400,
  page_iters = 100,
})
local corpus = B.corpus()

-- Ctrl-E: scroll the window one line down, the cheapest realistic redraw.
local SCROLL_BODY = [[
local n = __a[1]
local ce = string.char(5)
for _ = 1, n do
  vim.cmd('normal! ' .. ce)
  vim.cmd('redraw')
end
]]

-- Jump far enough that no row survives the diff, then pin it to the top: every
-- screen row is re-emitted, which is the full-frame case.
local PAGE_BODY = [[
local n, span = __a[1], __a[2]
for i = 1, n do
  vim.cmd('normal! ' .. ((i * 137) % span + 1) .. 'Gzt')
  vim.cmd('redraw')
end
]]

--- One measured run: fresh child, fresh buffer and grid state.
--- @param file string
--- @param treesitter boolean
--- @param body string
--- @param iters integer
--- @return number ns, table counters
local function run(file, treesitter, body, iters)
  local c = C.spawn(nvim, { embed_only = true })
  c:ui_attach(o.grid_w, o.grid_h)
  c:request('nvim_command', { 'edit! ' .. file })
  if treesitter then
    c:lua('vim.treesitter.start(0, "c")')
  else
    c:request('nvim_command', { 'syntax off' })
  end
  local span = math.max(200, c:lua('return vim.api.nvim_buf_line_count(0)') - o.grid_h - 10)
  local args = { iters, span }
  -- Warmup: fault in the buffer, the grid and (if any) the parse tree.
  c:time_lua(body, { math.max(4, math.floor(iters / 10)), span })
  c:request('nvim_command', { 'normal! gg' })
  c:reset_counters()
  local ns = c:time_lua(body, args)
  local counters = c:snapshot()
  c:close()
  return ns, counters
end

local cases = {
  {
    case = 'ascii_scroll',
    file = corpus.ascii,
    ts = false,
    body = SCROLL_BODY,
    iters = o.scroll_iters,
  },
  { case = 'ascii_page', file = corpus.ascii, ts = false, body = PAGE_BODY, iters = o.page_iters },
  {
    case = 'cjk_scroll',
    file = corpus.cjk,
    ts = false,
    body = SCROLL_BODY,
    iters = o.scroll_iters,
  },
  { case = 'cjk_page', file = corpus.cjk, ts = false, body = PAGE_BODY, iters = o.page_iters },
  { case = 'ts_scroll', file = corpus.big, ts = true, body = SCROLL_BODY, iters = o.scroll_iters },
  { case = 'ts_page', file = corpus.big, ts = true, body = PAGE_BODY, iters = o.page_iters },
}

for _, k in ipairs(cases) do
  local samples, last = B.repeat_n(o.runs, function()
    local ns, counters = run(k.file, k.ts, k.body, k.iters)
    return ns / k.iters, counters
  end)
  local st = B.stats(samples)
  local fps = 1e9 / st.median
  B.emit({
    bench = 'redraw',
    case = k.case,
    unit = 'ns',
    metric = 'ns_per_frame',
    stats = st,
    iters = k.iters,
    grid = { w = o.grid_w, h = o.grid_h },
    frames_per_s = fps,
    ui_events_per_frame = last.ui_events / k.iters,
    bytes_per_frame = last.bytes_in / k.iters,
    ui_events_per_s = (last.ui_events / k.iters) * fps,
    bytes_per_s = (last.bytes_in / k.iters) * fps,
    grid_line_per_frame = (last.by_event['grid_line'] or 0) / k.iters,
    nvim = nvim,
    sha = B.git_sha(),
  })
end
