--- Minimal msgpack-RPC client for the perf harness.
---
--- Reuses the stream/RPC framing from `test/client/` (same repo) so the harness
--- carries no msgpack code of its own; it adds byte and UI-event counters,
--- which the test client does not have.

local uv = vim.uv

local ok_stream, uv_stream = pcall(require, 'test.client.uv_stream')
local ok_rpc, RpcStream = pcall(require, 'test.client.rpc_stream')
assert(ok_stream and ok_rpc, 'perf harness needs test/client/*.lua on package.path')

--- Wraps ProcStream and counts every byte received from the child.
--- @class perf.CountingStream
local CountingStream = {}
CountingStream.__index = CountingStream

function CountingStream.new(proc, counters)
  return setmetatable({ _proc = proc, _c = counters }, CountingStream)
end

function CountingStream:write(data)
  self._proc:write(data)
end

function CountingStream:read_start(cb)
  self._proc:read_start(function(chunk)
    if chunk then
      self._c.bytes_in = self._c.bytes_in + #chunk
      self._c.chunks_in = self._c.chunks_in + 1
    end
    cb(chunk)
  end)
end

function CountingStream:read_stop()
  self._proc:read_stop()
end

function CountingStream:close(signal, noblock)
  self._proc:close(signal, noblock)
end

--- @class perf.Client
local Client = {}
Client.__index = Client

local M = {}

--- Spawn an nvim child speaking msgpack-RPC over stdio.
---
--- @param nvim string path to the nvim binary under test
--- @param opts table? { embed_only: boolean, args: string[], env: string[] }
--- @return perf.Client
function M.spawn(nvim, opts)
  opts = opts or {}
  local argv = { nvim, '-u', 'NONE', '-i', 'NONE', '-n', '--embed' }
  if not opts.embed_only then
    -- `--embed` alone makes nvim wait for a UI; benchmarks that never attach
    -- one must add `--headless` or they deadlock at startup.
    table.insert(argv, '--headless')
  end
  for _, v in ipairs(opts.args or {}) do
    argv[#argv + 1] = v
  end

  local counters = {
    bytes_in = 0,
    chunks_in = 0,
    notifications = 0,
    ui_events = 0,
    by_event = {},
  }

  local proc = uv_stream.ProcStream.spawn(argv, opts.env, nil, nil, false)
  local self = setmetatable({
    proc = proc,
    counters = counters,
    _eof = false,
    _argv = argv,
  }, Client)
  -- uv.run('once') blocks until *some* event arrives; a slow 1 Hz timer keeps
  -- the loop waking so request/wait deadlines are always enforced, without the
  -- CPU burn (and child contention) of busy polling.
  self._watchdog = uv.new_timer()
  self._watchdog:start(1000, 1000, function() end)
  self.rpc = RpcStream.new(CountingStream.new(proc, counters))
  self.rpc:read_start(function() end, function(method, args)
    counters.notifications = counters.notifications + 1
    if self.on_notify then
      self.on_notify(method, args)
    end
    if method == 'redraw' then
      for _, ev in ipairs(args) do
        if ev[1] == 'flush' then
          self.flushes = (self.flushes or 0) + 1
        end
      end
    end
    if method == 'redraw' then
      for _, ev in ipairs(args) do
        -- One "UI event" per call: a batch is {name, call1, call2, ...}.
        local calls = #ev - 1
        counters.ui_events = counters.ui_events + calls
        local name = ev[1]
        counters.by_event[name] = (counters.by_event[name] or 0) + calls
      end
    end
  end, function()
    self._eof = true
  end)
  return self
end

--- Fire-and-forget RPC notification.
--- @param method string
--- @param args any[]
function Client:notify(method, args)
  self.rpc:write(method, args)
end

--- Pump the event loop until `pred()` is true or `timeout_ms` elapses.
--- @param pred fun(): boolean
--- @param timeout_ms integer?
function Client:wait(pred, timeout_ms)
  local deadline = uv.hrtime() + (timeout_ms or 30000) * 1e6
  while not pred() do
    if self._eof then
      error('nvim died while waiting; stderr:\n' .. self.proc.stderr)
    end
    if uv.hrtime() > deadline then
      error('timed out waiting for child')
    end
    uv.run('once')
  end
end

--- Default request deadline (ms). Long benchmark bodies run inside a single
--- request, so this is generous; it only exists to turn a deadlock into an
--- error instead of a hung harness.
Client.request_timeout_ms = 600000

--- @private
function Client:_pump_until(done_fn, what)
  local deadline = uv.hrtime() + Client.request_timeout_ms * 1e6
  while not done_fn() do
    if self._eof then
      error(('nvim died during %s; stderr:\n%s'):format(what, self.proc.stderr))
    end
    if uv.hrtime() > deadline then
      error(('timed out during %s'):format(what))
    end
    uv.run('once')
  end
end

--- Blocking RPC request.
--- @param method string
--- @param args any[]
--- @return any
function Client:request(method, args)
  local done, err, res = false, nil, nil
  self.rpc:write(method, args, function(e, r)
    done, err, res = true, e, r
  end)
  self:_pump_until(function()
    return done
  end, method)
  if err then
    error(('%s failed: %s\nstderr:\n%s'):format(method, vim.inspect(err), self.proc.stderr))
  end
  return res
end

--- Run Lua in the child and return its result.
--- @param code string
--- @param args any[]?
--- @return any
function Client:lua(code, args)
  return self:request('nvim_exec_lua', { code, args or {} })
end

--- Time a Lua chunk inside the child, in nanoseconds, using the child's clock.
--- The chunk body runs between two `vim.uv.hrtime()` reads, so client-side
--- msgpack cost is excluded from the number.
--- @param body string Lua statements
--- @param args any[]?
--- @return integer ns, any result
function Client:time_lua(body, args)
  local code = table.concat({
    'local __a = {...}',
    'local __t0 = vim.uv.hrtime()',
    body,
    'local __t1 = vim.uv.hrtime()',
    'return __t1 - __t0',
  }, '\n')
  return self:lua(code, args)
end

--- Reset the byte/event counters (call right before a timed region).
function Client:reset_counters()
  local c = self.counters
  c.bytes_in, c.chunks_in, c.notifications, c.ui_events, c.by_event = 0, 0, 0, 0, {}
end

--- Snapshot of the counters.
--- @return table
function Client:snapshot()
  return vim.deepcopy(self.counters)
end

--- Attach a remote UI grid.
--- @param w integer
--- @param h integer
function Client:ui_attach(w, h)
  self:request('nvim_ui_attach', { w, h, { rgb = true, ext_linegrid = true } })
end

function Client:close()
  pcall(function()
    self.rpc:write('nvim_command', { 'qa!' })
  end)
  if self._watchdog and not self._watchdog:is_closing() then
    self._watchdog:stop()
    self._watchdog:close()
  end
  self.proc:close('term', false)
end

return M
