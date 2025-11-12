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

    exec_lua(
      [[
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
    ]],
      overlay_col,
      overlay_width
    )

    local spans = exec_lua('return vim.api.nvim__collect_overlay_spans(...)', 0, 0, 80)
    eq(1, #spans)
    eq(overlay_col, spans[1][1])
    eq(overlay_col + overlay_width, spans[1][2])

    screen:detach()
  end)

  it('skips recomposition when overlay content is unchanged', function()
    feed('iline1\nline2\nline3\nline4<Esc>gg')

    local screen = Screen.new(40, 8)

    exec_lua([[
      local overlay_buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(overlay_buf, 0, -1, true, { 'FLOAT' })
      local win = vim.api.nvim_open_win(overlay_buf, false, {
        relative = 'editor',
        row = 1,
        col = 0,
        width = 10,
        height = 1,
        style = 'minimal',
        focusable = false,
        zindex = 60,
      })
      return win
    ]])

    screen:expect {
      grid = [[
      ^line1                                   |
      {4:FLOAT     }                              |
      line3                                   |
      line4                                   |
      {1:~                                       }|*3
                                              |
      ]],
    }

    exec_lua('vim.api.nvim__reset_ui_comp_stats()')

    exec_lua([[
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 1, 2, true, { 'line2-updated' })
    ]])

    screen:expect {
      grid = [[
      ^line1                                   |
      {4:FLOAT     }ted                           |
      line3                                   |
      line4                                   |
      {1:~                                       }|*3
                                              |
      ]],
    }

    exec_lua([[
      local buf = vim.api.nvim_get_current_buf()
      vim.api.nvim_buf_set_lines(buf, 1, 2, true, { 'line2-updated-again' })
    ]])

    screen:expect {
      grid = [[
      ^line1                                   |
      {4:FLOAT     }ted-again                     |
      line3                                   |
      line4                                   |
      {1:~                                       }|*3
                                              |
      ]],
    }

    exec_lua("vim.cmd('redraw!')")
    screen:expect_unchanged()

    local stats = exec_lua('return vim.api.nvim__stats()')
    local overlay_stats = stats.ui_comp_scroll_fallback
    assert(
      overlay_stats.overlay_skip_calls > 0,
      string.format('expected overlay skip calls > 0 (got %d)', overlay_stats.overlay_skip_calls)
    )
    assert(
      overlay_stats.overlay_skip_rows > 0,
      string.format('expected overlay skip rows > 0 (got %d)', overlay_stats.overlay_skip_rows)
    )

    exec_lua([[
      local wins = vim.api.nvim_tabpage_list_wins(0)
      for _, win in ipairs(wins) do
        if vim.api.nvim_win_get_config(win).relative ~= '' then
          vim.api.nvim_win_close(win, true)
        end
      end
    ]])

    screen:detach()
  end)
end)
