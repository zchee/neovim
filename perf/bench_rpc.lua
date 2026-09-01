--- RPC throughput: 100k-line payloads in and out over msgpack.
---
--- Both ends of the channel are the same binary, so msgpack encode/decode
--- changes are counted on both sides; the number is an end-to-end client wall
--- time, which is what an LSP or a plugin actually pays.
---
---   nvim -u NONE -l perf/bench_rpc.lua [nvim] [--runs=5] [--lines=100000]

local ROOT = vim.fs.normalize(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))))
package.path = ROOT .. '/?.lua;' .. ROOT .. '/perf/?.lua;' .. package.path

local uv = vim.uv
local B = require('lib.bench')
local C = require('lib.client')

local a = _G.arg or {}
local nvim = B.nvim_path(a)
local o = B.opts(a, {
  runs = 5,
  lines = 100000,
  width = 48,
})

--- Payload with a realistic mix of line lengths, built once.
--- @return string[], integer bytes
local function payload()
  local lines, bytes = {}, 0
  for i = 1, o.lines do
    local l = string.format('line %07d %s', i, string.rep('x', (i % o.width) + 8))
    lines[i] = l
    bytes = bytes + #l + 1
  end
  return lines, bytes
end

local LINES, BYTES = payload()

--- @return perf.Client
local function fresh()
  local c = C.spawn(nvim, {})
  c:request('nvim_command', { 'enew!' })
  return c
end

local cases = {}

--- nvim_buf_set_lines of the whole payload, timed on the client.
cases[#cases + 1] = {
  case = 'set_lines_100k',
  fn = function()
    local c = fresh()
    c:request('nvim_buf_set_lines', { 0, 0, -1, true, { 'warmup' } })
    local t0 = uv.hrtime()
    c:request('nvim_buf_set_lines', { 0, 0, -1, true, LINES })
    local ns = uv.hrtime() - t0
    c:close()
    return ns
  end,
}

--- nvim_buf_get_lines of the whole payload, timed on the client.
cases[#cases + 1] = {
  case = 'get_lines_100k',
  fn = function()
    local c = fresh()
    c:request('nvim_buf_set_lines', { 0, 0, -1, true, LINES })
    c:request('nvim_buf_get_lines', { 0, 0, 10, true })
    local t0 = uv.hrtime()
    local got = c:request('nvim_buf_get_lines', { 0, 0, -1, true })
    local ns = uv.hrtime() - t0
    assert(#got == o.lines, ('got %d lines, want %d'):format(#got, o.lines))
    c:close()
    return ns
  end,
}

--- Same buffer write driven from inside the child: isolates the buffer/memline
--- cost from the msgpack transport.
cases[#cases + 1] = {
  case = 'set_lines_100k_inproc',
  fn = function()
    local c = fresh()
    c:lua('_G.__perf_lines = nil; collectgarbage()')
    c:lua(
      [[
      local n, w = ...
      local t = {}
      for i = 1, n do
        t[i] = string.format('line %07d %s', i, string.rep('x', (i % w) + 8))
      end
      _G.__perf_lines = t
    ]],
      { o.lines, o.width }
    )
    local ns = c:time_lua('vim.api.nvim_buf_set_lines(0, 0, -1, true, _G.__perf_lines)')
    c:close()
    return ns
  end,
}

for _, k in ipairs(cases) do
  local samples = B.repeat_n(o.runs, k.fn)
  local st = B.stats(samples)
  B.emit({
    bench = 'rpc',
    case = k.case,
    unit = 'ns',
    metric = 'ns_total',
    stats = st,
    lines = o.lines,
    payload_bytes = BYTES,
    lines_per_s = o.lines / (st.median / 1e9),
    mb_per_s = (BYTES / 1048576) / (st.median / 1e9),
    nvim = nvim,
    sha = B.git_sha(),
  })
end
