--- TUI path: same redraw workloads, but through a real terminal.
---
--- The child runs under a pty with a real TUI attached, so this covers what the
--- remote-UI benchmark cannot: terminfo emission, the cell/attr loop, and the
--- write syscalls. Each measured repetition runs the workload twice -- once
--- with N iterations and once with 0 -- and reports the difference, which
--- cancels process startup, file load and the initial paint.
---
--- Syscalls come from perf/syscount.c (DYLD interposition), because `dtruss`
--- needs root and `sudo -n` is not available here.
---
---   nvim -u NONE -l perf/bench_tui.lua [nvim] [--runs=5] [--scroll-iters=400]

local ROOT = vim.fs.normalize(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, 'S').source:sub(2))))
package.path = ROOT .. '/?.lua;' .. ROOT .. '/perf/?.lua;' .. package.path

local uv = vim.uv
local B = require('lib.bench')

local a = _G.arg or {}
local nvim = B.nvim_path(a)
local o = B.opts(a, {
  runs = 5,
  scroll_iters = 400,
  page_iters = 100,
  width = 200,
  height = 50,
  repeats = 4,
  term = 'xterm-256color',
})
local corpus = B.corpus()

local OUT = ROOT .. '/perf/out'
local DYLIB = OUT .. '/syscount.dylib'
local WORKLOAD = ROOT .. '/perf/tui_workload.lua'

--- Build the syscall interposer once per harness run. Returns nil (with a
--- reason) when it cannot be built or loaded; the benchmark still reports wall
--- time and byte counts in that case.
--- @return string? path, string? reason
local function ensure_dylib()
  if uv.fs_stat(DYLIB) then
    return DYLIB
  end
  local cmd = ('clang -dynamiclib -O2 -o %s %s 2>&1'):format(
    vim.fn.shellescape(DYLIB),
    vim.fn.shellescape(ROOT .. '/perf/syscount.c')
  )
  local p = io.popen(cmd)
  local out = p and p:read('*a') or ''
  local ok = p and p:close()
  if not ok or not uv.fs_stat(DYLIB) then
    return nil, 'clang failed: ' .. out
  end
  return DYLIB
end

local dylib, dylib_err = ensure_dylib()

--- Read the interposer's report.
---
--- A terminal nvim is two processes: the process launched is the *UI client*
--- (it writes escape sequences to the tty), and it spawns `nvim --embed` as
--- the server child (which writes msgpack UI events back over a pipe). Both
--- appear in the report, so counters are attributed by role -- the row whose
--- pid is another row's ppid is the UI client.
---
--- @param path string
--- @return table<string, table<string, number>>? role -> counters
local function read_syscounts(path)
  local f = io.open(path, 'r')
  if not f then
    return nil
  end
  local rows = {}
  for line in f:lines() do
    local t = {}
    for k, v in line:gmatch('([%w_]+)=(%d+)') do
      t[k] = tonumber(v)
    end
    if t.pid then
      rows[#rows + 1] = t
    end
  end
  f:close()
  if #rows == 0 then
    return nil
  end
  local is_parent = {}
  for _, r in ipairs(rows) do
    is_parent[r.ppid] = true
  end
  local out = {}
  for _, r in ipairs(rows) do
    local role = (#rows == 1 and 'single') or (is_parent[r.pid] and 'tui_client' or 'server')
    out[role] = r
  end
  return out
end

--- Run the workload once in a pty.
--- @param file string
--- @param mode string
--- @param iters integer
--- @param ts boolean
--- @return integer[] child-measured loop times, integer bytes, table? syscounts
local function run_once(file, mode, iters, ts)
  local tag = tostring(uv.hrtime())
  local sc_out = OUT .. '/syscount.' .. tag .. '.txt'
  local t_out = OUT .. '/time.' .. tag .. '.txt'
  os.remove(sc_out)
  os.remove(t_out)
  local env = {
    PERF_FILE = file,
    PERF_MODE = mode,
    PERF_ITERS = tostring(iters),
    PERF_TS = ts and '1' or '0',
    TERM = o.term,
    -- Keep the branch's OOB channels out of the picture: this case is the
    -- plain-tty path. NVIM_* handshake vars are cleared by nvim itself.
    SYSCOUNT_OUT = sc_out,
    PERF_TIME_OUT = t_out,
    PERF_REPEATS = tostring(o.repeats),
  }
  if dylib then
    env.DYLD_INSERT_LIBRARIES = dylib
  end
  local bytes = 0
  local job = vim.fn.jobstart({
    nvim,
    '-u',
    'NONE',
    '-i',
    'NONE',
    '-n',
    '--cmd',
    'set noswapfile',
    '-c',
    'luafile ' .. WORKLOAD,
  }, {
    pty = true,
    width = o.width,
    height = o.height,
    env = env,
    on_stdout = function(_, data)
      for _, chunk in ipairs(data) do
        bytes = bytes + #chunk + 1
      end
    end,
  })
  assert(job > 0, 'jobstart failed')
  local rc = vim.fn.jobwait({ job }, 120000)[1]
  assert(rc == 0, ('nvim exited with %s'):format(tostring(rc)))
  local times = {}
  local tf = io.open(t_out, 'r')
  if tf then
    for line in tf:lines() do
      local v = tonumber(line)
      if v then
        times[#times + 1] = v
      end
    end
    tf:close()
  end
  local counts = read_syscounts(sc_out)
  os.remove(sc_out)
  os.remove(t_out)
  return times, bytes, counts
end

--- Per-role difference of two syscall reports, plus a `total` role.
--- @param x table<string, table<string, number>>?
--- @param y table<string, table<string, number>>?
--- @return table<string, table<string, number>>?
local function diff_counts(x, y)
  if not (x and y) then
    return nil
  end
  local out = { total = {} }
  for role, xc in pairs(x) do
    local yc = y[role] or {}
    local t = {}
    for k, v in pairs(xc) do
      if k ~= 'pid' and k ~= 'ppid' then
        t[k] = v - (yc[k] or 0)
        out.total[k] = (out.total[k] or 0) + t[k]
      end
    end
    out[role] = t
  end
  return out
end

local cases = {
  {
    case = 'tui_ascii_scroll',
    file = corpus.ascii,
    mode = 'scroll',
    iters = o.scroll_iters,
    ts = false,
  },
  { case = 'tui_ascii_page', file = corpus.ascii, mode = 'page', iters = o.page_iters, ts = false },
  { case = 'tui_cjk_page', file = corpus.cjk, mode = 'page', iters = o.page_iters, ts = false },
  { case = 'tui_ts_page', file = corpus.big, mode = 'page', iters = o.page_iters, ts = true },
}

for _, k in ipairs(cases) do
  local samples, all, per_frame_bytes, counts = {}, {}, nil, nil
  local frames = k.iters * o.repeats
  for _ = 1, o.runs do
    local t_work, b_work, c_work = run_once(k.file, k.mode, k.iters, k.ts)
    local _, b_base, c_base = run_once(k.file, k.mode, 0, k.ts)
    -- Wall time is measured inside the child around the loop only; bytes and
    -- syscalls are differenced against the 0-iteration run to drop startup,
    -- file load and the initial paint (the warmup pass is a fixed 50 frames on
    -- both sides, so it cancels).
    local best
    for _, ns in ipairs(t_work) do
      local per_frame = ns / k.iters
      all[#all + 1] = per_frame
      best = math.min(best or per_frame, per_frame)
    end
    -- One sample per launch: its fastest repeat. Repeats within a process are
    -- tight; launches differ by up to 4x depending on which core cluster the
    -- child lands on, so the launch minimum is the estimator that survives.
    samples[#samples + 1] = assert(best, 'child reported no timings')
    per_frame_bytes = math.max(0, b_work - b_base) / frames
    counts = diff_counts(c_work, c_base)
  end
  local st = B.stats(samples)
  local st_all = B.stats(all)
  local out = {
    bench = 'tui',
    case = k.case,
    unit = 'ns',
    metric = 'ns_per_frame',
    stats = st,
    iters = k.iters,
    repeats = o.repeats,
    -- Headline for wave-to-wave comparison: the fastest observed frame cost,
    -- i.e. the one not taxed by efficiency-core placement.
    best_ns_per_frame = st_all.min,
    all_samples = st_all,
    pty = { w = o.width, h = o.height, term = o.term },
    frames_per_s = st.median > 0 and 1e9 / st.median or nil,
    -- pty-side count is approximate (jobstart hands back newline-split
    -- chunks); the interposer's bytes_written below is the syscall-level truth.
    pty_bytes_per_frame = per_frame_bytes,
    syscalls_available = counts ~= nil,
    syscall_note = counts == nil and (dylib_err or 'syscount.dylib not loaded') or nil,
    nvim = nvim,
    sha = B.git_sha(),
  }
  if counts then
    out.syscalls_per_frame = {}
    for role, c in pairs(counts) do
      local per = {}
      for name, v in pairs(c) do
        per[name] = v / frames
      end
      out.syscalls_per_frame[role] = per
    end
    local tot = counts.total
    out.writes_per_frame = ((tot.write or 0) + (tot.writev or 0)) / frames
    out.bytes_written_per_frame = (tot.bytes_written or 0) / frames
    if counts.tui_client then
      out.tty_writes_per_frame = ((counts.tui_client.write or 0) + (counts.tui_client.writev or 0))
        / frames
      out.tty_bytes_per_frame = (counts.tui_client.bytes_written or 0) / frames
    end
    if counts.server then
      out.server_writes_per_frame = ((counts.server.write or 0) + (counts.server.writev or 0))
        / frames
      out.server_bytes_per_frame = (counts.server.bytes_written or 0) / frames
    end
  end
  B.emit(out)
end
