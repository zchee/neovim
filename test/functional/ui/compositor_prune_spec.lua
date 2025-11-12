local t = require('test.testutil')
local n = require('test.functional.testnvim')()
local Screen = require('test.functional.ui.screen')

local eq = t.eq
local clear = n.clear
local feed = n.feed
local exec_lua = n.exec_lua

describe('ui compositor row/column pruning', function()
  before_each(clear)

  it('reports overlay spans for covered rows', function()
    local overlay_col = 12
    local overlay_width = 4

    feed('iabcdefghijklmnopqrstuv<Esc>')

    local screen = Screen.new(40, 6)

    exec_lua([[
      local col, width = ...
      local overlay_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(overlay_buf, 0, -1, true, { 'OVER' })
      vim.api.nvim_open_win(overlay_buf, false, {
        relative = 'editor',
        row = 0,
        col = col,
        width = width,
        height = 1,
        style = 'minimal',
        focusable = false,
        zindex = 60,
      })
    ]], overlay_col, overlay_width)

    local spans = exec_lua('return vim.api.nvim__collect_overlay_spans(...)', 0, 0, 80)
    eq(1, #spans)
    eq(overlay_col, spans[1][1])
    eq(overlay_col + overlay_width, spans[1][2])

    screen:detach()
  end)
end)
