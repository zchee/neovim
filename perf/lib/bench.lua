--- Shared helpers for the perf/ benchmark harness.
---
--- Every benchmark script emits one JSON object per case on stdout (JSONL) and
--- a human-readable line on stderr, so `run_all.sh` can pipe stdout through jq
--- while a human still sees progress.

local uv = vim.uv

local M = {}

--- Nanosecond monotonic clock.
--- @return integer
function M.hrtime()
  return uv.hrtime()
end

--- Descriptive statistics over a sample vector.
--- @param samples number[]
--- @return table
function M.stats(samples)
  local s = vim.deepcopy(samples)
  table.sort(s)
  local n = #s
  assert(n > 0, 'no samples')
  local sum = 0
  for _, v in ipairs(s) do
    sum = sum + v
  end
  local mean = sum / n
  local median
  if n % 2 == 1 then
    median = s[(n + 1) / 2]
  else
    median = (s[n / 2] + s[n / 2 + 1]) / 2
  end
  local var = 0
  for _, v in ipairs(s) do
    var = var + (v - mean) ^ 2
  end
  var = n > 1 and var / (n - 1) or 0
  return {
    n = n,
    median = median,
    min = s[1],
    max = s[n],
    mean = mean,
    stddev = math.sqrt(var),
    -- Relative spread; the methodology gate for "is this run trustworthy".
    rsd_pct = mean ~= 0 and (math.sqrt(var) / mean) * 100 or 0,
    samples = s,
  }
end

--- Run `fn` `n` times, collecting one number per run.
--- `fn(i)` returns the sample value; anything it returns second is kept from
--- the last iteration as `extra` (used for event/byte counters).
--- @param n integer
--- @param fn fun(i: integer): number, table?
--- @return number[], table?
function M.repeat_n(n, fn)
  local samples = {}
  local extra
  for i = 1, n do
    local v, e = fn(i)
    samples[#samples + 1] = v
    extra = e or extra
  end
  return samples, extra
end

--- Emit one benchmark case.
--- @param case table Must carry at least `bench`, `case`, `unit`, `stats`.
function M.emit(case)
  case.ts = os.date('!%Y-%m-%dT%H:%M:%SZ')
  io.stdout:write(vim.json.encode(case), '\n')
  io.stdout:flush()
  local st = case.stats or {}
  io.stderr:write(
    string.format(
      '  %-28s %-22s median=%s min=%s max=%s rsd=%.1f%% (n=%d)\n',
      case.bench or '?',
      case.case or '?',
      M.fmt(st.median, case.unit),
      M.fmt(st.min, case.unit),
      M.fmt(st.max, case.unit),
      st.rsd_pct or 0,
      st.n or 0
    )
  )
end

--- Human formatting for a value in `unit`.
--- @param v number?
--- @param unit string?
--- @return string
function M.fmt(v, unit)
  if v == nil then
    return '-'
  end
  if unit == 'ns' then
    if v >= 1e9 then
      return string.format('%.3fs', v / 1e9)
    elseif v >= 1e6 then
      return string.format('%.3fms', v / 1e6)
    elseif v >= 1e3 then
      return string.format('%.1fus', v / 1e3)
    end
    return string.format('%.0fns', v)
  end
  if math.abs(v) >= 1e6 then
    return string.format('%.3fM', v / 1e6)
  elseif math.abs(v) >= 1e3 then
    return string.format('%.1fk', v / 1e3)
  end
  return string.format('%.3f', v)
end

--- Repo root (parent of perf/).
--- @return string
function M.root()
  local this = debug.getinfo(1, 'S').source:sub(2)
  return vim.fs.normalize(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(this))))
end

--- Resolve the nvim binary under test.
--- @param a string[] script args
--- @return string
function M.nvim_path(a)
  local p = a[1]
  if p == nil or p == '' or p:sub(1, 2) == '--' then
    p = M.root() .. '/build/bin/nvim'
  end
  p = vim.fs.normalize(p)
  assert(uv.fs_stat(p), ('nvim binary not found: %s'):format(p))
  return p
end

--- Named `--key=value` script options with defaults.
--- @param a string[]
--- @param defaults table<string, any>
--- @return table<string, any>
function M.opts(a, defaults)
  local o = vim.deepcopy(defaults)
  for _, v in ipairs(a) do
    local k, val = v:match('^%-%-([%w_%-]+)=(.*)$')
    if k then
      k = k:gsub('%-', '_')
      if type(o[k]) == 'number' then
        o[k] = assert(tonumber(val), ('bad number for --%s'):format(k))
      else
        o[k] = val
      end
    end
  end
  return o
end

--- Ensure the generated corpus exists; generate it on first use.
--- @return table<string, string> map of corpus name to path
function M.corpus()
  local dir = M.root() .. '/perf/corpus'
  local gen = dir .. '/gen_corpus.lua'
  local files = {
    ascii = dir .. '/ascii.c',
    cjk = dir .. '/cjk.txt',
    big = dir .. '/big.c',
  }
  local missing = false
  for _, p in pairs(files) do
    if not uv.fs_stat(p) then
      missing = true
    end
  end
  if missing then
    io.stderr:write('  (generating corpus)\n')
    dofile(gen)
  end
  return files
end

--- Sanity guard: benchmarks must never be run against a dirty/moved tree
--- without noticing. Returns the current HEAD sha.
--- @return string
function M.git_sha()
  local p = io.popen('git -C ' .. vim.fn.shellescape(M.root()) .. ' rev-parse HEAD 2>/dev/null')
  if not p then
    return 'unknown'
  end
  local sha = (p:read('*l') or 'unknown'):gsub('%s+$', '')
  p:close()
  return sha
end

return M
