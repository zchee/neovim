--- TUI-side workload driven by bench_tui.lua. Runs inside a real nvim attached
--- to a pty (`-c 'luafile perf/tui_workload.lua'`), then quits, so the parent
--- can time the process and difference against an iters=0 run.
---
--- Env: PERF_FILE, PERF_MODE (scroll|page), PERF_ITERS, PERF_TS (0|1).

local file = assert(vim.env.PERF_FILE, 'PERF_FILE unset')
local iters = tonumber(vim.env.PERF_ITERS) or 0
local mode = vim.env.PERF_MODE or 'scroll'

vim.cmd('edit! ' .. file)
if vim.env.PERF_TS == '1' then
  vim.treesitter.start(0, 'c')
else
  vim.cmd('syntax off')
end
vim.cmd('normal! gg')
vim.cmd('redraw')

local span = math.max(200, vim.api.nvim_buf_line_count(0) - 60)
local ce = string.char(5)

--- @param n integer
local function loop(n)
  for i = 1, n do
    if mode == 'scroll' then
      vim.cmd('normal! ' .. ce)
    else
      vim.cmd('normal! ' .. ((i * 137) % span + 1) .. 'Gzt')
    end
    vim.cmd('redraw')
  end
end

-- Warm up first: the cold pass pays for page-ins, terminfo setup and the
-- initial parse. The count is fixed (not a fraction of `iters`) so that it
-- cancels exactly when the harness differences syscall counts against an
-- iters=0 run.
loop(50)
vim.cmd('normal! gg')

-- Time the loop in-process: process wall time is dominated by nvim startup
-- variance, which is an order of magnitude larger than the workload. Repeat it
-- within the process as well, because the dominant remaining noise source is
-- per-process scheduling (P- vs E-core placement on Apple silicon): one
-- unlucky launch otherwise contributes a 4x outlier.
local repeats = tonumber(vim.env.PERF_REPEATS) or 1
local elapsed = {}
for _ = 1, repeats do
  vim.cmd('normal! gg')
  vim.cmd('redraw')
  local t0 = vim.uv.hrtime()
  loop(iters)
  elapsed[#elapsed + 1] = vim.uv.hrtime() - t0
end

local out = vim.env.PERF_TIME_OUT
if out then
  local f = io.open(out, 'w')
  if f then
    for _, ns in ipairs(elapsed) do
      f:write(tostring(ns), '\n')
    end
    f:close()
  end
end

vim.cmd('qa!')
