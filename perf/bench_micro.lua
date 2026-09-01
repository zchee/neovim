--- Vimscript / Lua / treesitter micro-benchmarks.
---
---   * vimscript_funcall_1e6 -- `for` loop calling a user function 1e6 times
---   * vimscript_map_1e6     -- map() over a 1e6-item list (list built untimed)
---   * lua_api_call_1e6      -- 1e6 C->Lua->C API round trips
---   * ts_iter_captures      -- highlights query over the whole big.c tree
---
---   nvim -u NONE -l perf/bench_micro.lua [nvim] [--runs=9] [--iters=1000000]

local ROOT = vim.fs.normalize(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))))
package.path = ROOT .. '/?.lua;' .. ROOT .. '/perf/?.lua;' .. package.path

local B = require('lib.bench')
local C = require('lib.client')

local a = _G.arg or {}
local nvim = B.nvim_path(a)
local o = B.opts(a, {
  runs = 9,
  iters = 1000000,
})
local corpus = B.corpus()

-- reltime() brackets only the region under test, so list construction and
-- function definition stay out of the number.
local VIMSCRIPT = [[
function! PerfAdd(x) abort
  return a:x + 1
endfunction

function! PerfFuncall(n) abort
  let s = 0
  let t = reltime()
  for i in range(a:n)
    let s = PerfAdd(s)
  endfor
  return reltimefloat(reltime(t))
endfunction

function! PerfMap(n) abort
  let l = range(a:n)
  let t = reltime()
  call map(l, 'v:val + 1')
  return reltimefloat(reltime(t))
endfunction
]]

--- @param setup fun(c: perf.Client)?
--- @return perf.Client
local function fresh(setup)
  local c = C.spawn(nvim, {})
  c:request('nvim_exec2', { VIMSCRIPT, vim.empty_dict() })
  if setup then
    setup(c)
  end
  return c
end

local cases = {
  {
    case = 'vimscript_funcall_1e6',
    per = o.iters,
    fn = function()
      local c = fresh()
      c:lua('return vim.fn.PerfFuncall(1000)') -- warmup
      local s = c:lua('return vim.fn.PerfFuncall(...)', { o.iters })
      c:close()
      return s * 1e9
    end,
  },
  {
    case = 'vimscript_map_1e6',
    per = o.iters,
    fn = function()
      local c = fresh()
      c:lua('return vim.fn.PerfMap(1000)')
      local s = c:lua('return vim.fn.PerfMap(...)', { o.iters })
      c:close()
      return s * 1e9
    end,
  },
  {
    case = 'lua_api_call_1e6',
    per = o.iters,
    fn = function()
      local c = fresh()
      local body = [[
        local n = __a[1]
        local get = vim.api.nvim_get_current_buf
        local acc = 0
        for _ = 1, n do
          acc = acc + get()
        end
      ]]
      c:time_lua(body, { 1000 })
      local ns = c:time_lua(body, { o.iters })
      c:close()
      return ns
    end,
  },
  {
    case = 'ts_iter_captures',
    per = 1,
    fn = function()
      local c = fresh(function(cl)
        cl:request('nvim_command', { 'edit! ' .. corpus.big })
        cl:lua([[
          local parser = vim.treesitter.get_parser(0, 'c')
          parser:parse(true)
          _G.__perf_root = parser:trees()[1]:root()
          _G.__perf_query = vim.treesitter.query.get('c', 'highlights')
        ]])
      end)
      local body = [[
        local cnt = 0
        for _ in _G.__perf_query:iter_captures(_G.__perf_root, 0, 0, -1) do
          cnt = cnt + 1
        end
        _G.__perf_cnt = cnt
      ]]
      c:time_lua(body)
      local ns = c:time_lua(body)
      c:close()
      return ns
    end,
  },
}

for _, k in ipairs(cases) do
  local samples = B.repeat_n(o.runs, k.fn)
  local st = B.stats(samples)
  B.emit({
    bench = 'micro',
    case = k.case,
    unit = 'ns',
    metric = k.per > 1 and 'ns_total' or 'ns_total',
    stats = st,
    iters = k.per,
    ns_per_iter = st.median / k.per,
    ops_per_s = k.per / (st.median / 1e9),
    nvim = nvim,
    sha = B.git_sha(),
  })
end
