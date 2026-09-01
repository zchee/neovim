--- Typing-latency proxy: keystroke in, screen update out.
---
--- For each key the client sends `nvim_input` as a notification and stops the
--- clock when the child's `flush` UI event comes back, i.e. one full
--- key -> decode -> edit -> redraw -> emit cycle. That is the same shape as a
--- terminal keystroke, minus the terminal itself (see bench_tui.lua for the
--- tty path). A bulk case measures the paste-like input path where redraws
--- coalesce.
---
---   nvim -u NONE -l perf/bench_input.lua [nvim] [--runs=5] [--keys=400]

local ROOT = vim.fs.normalize(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))))
package.path = ROOT .. '/?.lua;' .. ROOT .. '/perf/?.lua;' .. package.path

local uv = vim.uv
local B = require('lib.bench')
local C = require('lib.client')

local a = _G.arg or {}
local nvim = B.nvim_path(a)
local o = B.opts(a, {
  runs = 5,
  keys = 400,
  grid_w = 120,
  grid_h = 50,
})
local corpus = B.corpus()

-- A 'statuscolumn' in the shape people actually run: sign column plus a
-- relative/absolute number expression, re-evaluated for every screen row.
local STC = [[vim.o.statuscolumn = "%s%=%{v:virtnum<1?(v:relnum?v:relnum:v:lnum):''} "]]
local KEYS = 'abcdefghijklmnopqrstuvwxyz_0123456789'

--- Child in insert mode in the middle of a large C file.
--- @param treesitter boolean
--- @return perf.Client
local function setup(treesitter)
  local c = C.spawn(nvim, { embed_only = true })
  c:ui_attach(o.grid_w, o.grid_h)
  c:request('nvim_command', { 'edit! ' .. corpus.big })
  if treesitter then
    c:lua('vim.treesitter.start(0, "c")')
    c:lua(STC)
    c:lua('vim.o.number = true; vim.o.relativenumber = true; vim.o.signcolumn = "yes"')
  else
    c:request('nvim_command', { 'syntax off' })
  end
  c:request('nvim_command', { 'normal! 5000Gzz' })
  c:request('nvim_input', { 'o' })
  -- nvim_input is asynchronous; make sure Insert mode is actually reached
  -- before any key is timed.
  c:wait(function()
    return c:request('nvim_get_mode', {}).mode == 'i'
  end, 10000)
  return c
end

--- @param i integer
--- @return string
local function key(i)
  return KEYS:sub((i - 1) % #KEYS + 1, (i - 1) % #KEYS + 1)
end

--- Per-key round trip; returns the sample vector for one run.
--- @param treesitter boolean
--- @return number[] ns_per_key, table counters
local function run_latency(treesitter)
  local c = setup(treesitter)
  for i = 1, 40 do -- warmup
    local seen = c.flushes or 0
    c:notify('nvim_input', { key(i) })
    c:wait(function()
      return (c.flushes or 0) > seen
    end, 10000)
  end
  c:reset_counters()
  local samples = {}
  for i = 1, o.keys do
    local seen = c.flushes or 0
    local t0 = uv.hrtime()
    c:notify('nvim_input', { key(i) })
    c:wait(function()
      return (c.flushes or 0) > seen
    end, 10000)
    samples[i] = uv.hrtime() - t0
  end
  local counters = c:snapshot()
  c:close()
  return samples, counters
end

--- All keys in one shot; the child pings back when the last edit lands.
--- @return number ns_per_key, table counters
local function run_bulk()
  local c = setup(true)
  local chan = c:request('nvim_get_api_info', {})[1]
  local done = false
  c.on_notify = function(method)
    if method == 'perf_done' then
      done = true
    end
  end
  -- TextChangedI can coalesce across a burst of keys, so ping on the observed
  -- line length instead of on an event count.
  c:lua(
    [[
    local chan, n = ...
    local pinged = false
    vim.api.nvim_create_autocmd('TextChangedI', {
      callback = function()
        if not pinged and #vim.api.nvim_get_current_line() >= n then
          pinged = true
          vim.rpcnotify(chan, 'perf_done')
        end
      end,
    })
  ]],
    { chan, o.keys }
  )
  local text = {}
  for i = 1, o.keys do
    text[i] = key(i)
  end
  c:reset_counters()
  local t0 = uv.hrtime()
  c:notify('nvim_input', { table.concat(text) })
  c:wait(function()
    return done
  end, 60000)
  local ns = uv.hrtime() - t0
  local counters = c:snapshot()
  c:close()
  return ns / o.keys, counters
end

--- p-quantile of a sorted-on-demand sample vector.
--- @param s number[]
--- @param p number
--- @return number
local function quantile(s, p)
  local t = vim.deepcopy(s)
  table.sort(t)
  return t[math.max(1, math.min(#t, math.ceil(p * #t)))]
end

local cases = {
  {
    case = 'latency_plain',
    fn = function()
      local s, c = run_latency(false)
      return B.stats(s).median, c, s
    end,
  },
  {
    case = 'latency_ts_stc',
    fn = function()
      local s, c = run_latency(true)
      return B.stats(s).median, c, s
    end,
  },
  { case = 'bulk_input_ts_stc', fn = run_bulk },
}

for _, k in ipairs(cases) do
  local per_run = {}
  local last, last_samples
  for _ = 1, o.runs do
    local v, counters, s = k.fn()
    per_run[#per_run + 1] = v
    last, last_samples = counters, s
  end
  local st = B.stats(per_run)
  B.emit({
    bench = 'input',
    case = k.case,
    unit = 'ns',
    metric = 'ns_per_key',
    stats = st,
    keys = o.keys,
    keys_per_s = 1e9 / st.median,
    -- Tail latency matters more than the mean for typing; report it from the
    -- last run's per-key samples where we have them.
    p95_ns = last_samples and quantile(last_samples, 0.95) or nil,
    p99_ns = last_samples and quantile(last_samples, 0.99) or nil,
    bytes_per_key = last.bytes_in / o.keys,
    ui_events_per_key = last.ui_events / o.keys,
    grid = { w = o.grid_w, h = o.grid_h },
    nvim = nvim,
    sha = B.git_sha(),
  })
end
