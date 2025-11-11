local t = require('test.testutil')
local n = require('test.functional.testnvim')()

local api = n.api
local clear = n.clear
local eq = t.eq
local exec_capture = n.exec_capture
local exec_lua = n.exec_lua
local feed = n.feed

-- Reference text
-- aa
--  aa
--   aa
--
--   aa
--  aa
-- aa
local example_lines = { 'aa', ' aa', '  aa', '', '  aa', ' aa', 'aa' }

local set_commentstring = function(commentstring)
  api.nvim_set_option_value('commentstring', commentstring, { buf = 0 })
end

local get_lines = function(from, to)
  from, to = from or 0, to or -1
  return api.nvim_buf_get_lines(0, from, to, false)
end

local set_lines = function(lines, from, to)
  from, to = from or 0, to or -1
  api.nvim_buf_set_lines(0, from, to, false, lines)
end

local set_cursor = function(row, col)
  api.nvim_win_set_cursor(0, { row, col })
end

local get_cursor = function()
  return api.nvim_win_get_cursor(0)
end

local ensure_project_runtime = function()
  exec_lua [[
    local cwd = vim.fn.getcwd()
    local project_rtp = cwd .. '/runtime'
    if not vim.o.runtimepath:find(project_rtp, 1, true) then
      vim.opt.runtimepath:prepend(project_rtp)
    end
    local build_rtp = cwd .. '/build/lib/nvim'
    if vim.uv.fs_stat(build_rtp) and not vim.o.runtimepath:find(build_rtp, 1, true) then
      vim.opt.runtimepath:prepend(build_rtp)
    end
  ]]
end

local reset_debug_log = function()
  exec_lua [[
    if vim.g._comment_debug then
      pcall(vim.fn.delete, vim.g._comment_debug)
    end
    vim.g._comment_debug = '/tmp/comment_debug.log'
  ]]
end

local setup_treesitter = function()
  -- NOTE: This leverages bundled Vimscript and Lua tree-sitter parsers
  api.nvim_set_option_value('filetype', 'vim', { buf = 0 })
  exec_lua [[
    local cwd = vim.fn.getcwd()
    local project_rtp = cwd .. '/runtime'
    if not vim.o.runtimepath:find(project_rtp, 1, true) then
      vim.opt.runtimepath:prepend(project_rtp)
    end
    local build_rtp = cwd .. '/build/lib/nvim'
    if not vim.o.runtimepath:find(build_rtp, 1, true) then
      vim.opt.runtimepath:prepend(build_rtp)
    end
    vim.treesitter.language.require_language('vim')
    vim.treesitter.language.require_language('lua')
    vim.treesitter.start(0, 'vim')
    local parser = vim.treesitter.get_parser(0, 'vim')
    parser:parse(true)
  ]]
end
before_each(function()
  -- avoid options, but we still need TS parsers
  clear({ args_rm = { '--cmd' }, args = { '--clean', '--cmd', n.runtime_set } })
end)

describe('commenting', function()
  before_each(function()
    set_lines(example_lines)
    set_commentstring('# %s')
    ensure_project_runtime()
  end)

  describe('toggle_lines()', function()
    local toggle_lines = function(...)
      exec_lua([[
        local comment = require('vim._comment')
        if not vim.g._comment_loaded_source then
          vim.g._comment_loaded_source = debug.getinfo(comment.toggle_lines).source
        end
        comment.toggle_lines(...)
      ]], ...)
    end

    it('works', function()
      toggle_lines(3, 5)
      eq(get_lines(2, 5), { '  # aa', '  #', '  # aa' })

      toggle_lines(3, 5)
      eq(get_lines(2, 5), { '  aa', '', '  aa' })
    end)

    it("works with different 'commentstring' options", function()
      local validate = function(lines_before, lines_after, lines_again)
        set_lines(lines_before)
        toggle_lines(1, #lines_before)
        eq(get_lines(), lines_after)
        toggle_lines(1, #lines_before)
        eq(get_lines(), lines_again or lines_before)
      end

      -- Single whitespace inside comment parts (main case)
      set_commentstring('# %s #')
      -- - General case
      validate(
        { 'aa', '  aa', 'aa  ', '  aa  ' },
        { '# aa #', '#   aa #', '# aa   #', '#   aa   #' }
      )
      -- - Tabs
      validate(
        { 'aa', '\taa', 'aa\t', '\taa\t' },
        { '# aa #', '# \taa #', '# aa\t #', '# \taa\t #' }
      )
      -- - With indent
      validate({ ' aa', '  aa' }, { ' # aa #', ' #  aa #' })
      -- - With blank/empty lines
      validate(
        { '  aa', '', '  ', '\t' },
        { '  # aa #', '  ##', '  ##', '  ##' },
        { '  aa', '', '', '' }
      )

      set_commentstring('# %s')
      validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { '# aa', '#   aa', '# aa  ', '#   aa  ' })
      validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { '# aa', '# \taa', '# aa\t', '# \taa\t' })
      validate({ ' aa', '  aa' }, { ' # aa', ' #  aa' })
      validate(
        { '  aa', '', '  ', '\t' },
        { '  # aa', '  #', '  #', '  #' },
        { '  aa', '', '', '' }
      )

      set_commentstring('%s #')
      validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { 'aa #', '  aa #', 'aa   #', '  aa   #' })
      validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { 'aa #', '\taa #', 'aa\t #', '\taa\t #' })
      validate({ ' aa', '  aa' }, { ' aa #', '  aa #' })
      validate(
        { '  aa', '', '  ', '\t' },
        { '  aa #', '  #', '  #', '  #' },
        { '  aa', '', '', '' }
      )

      -- No whitespace in parts
      set_commentstring('#%s#')
      validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { '#aa#', '#  aa#', '#aa  #', '#  aa  #' })
      validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { '#aa#', '#\taa#', '#aa\t#', '#\taa\t#' })
      validate({ ' aa', '  aa' }, { ' #aa#', ' # aa#' })
      validate(
        { '  aa', '', '  ', '\t' },
        { '  #aa#', '  ##', '  ##', '  ##' },
        { '  aa', '', '', '' }
      )

      set_commentstring('#%s')
      validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { '#aa', '#  aa', '#aa  ', '#  aa  ' })
      validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { '#aa', '#\taa', '#aa\t', '#\taa\t' })
      validate({ ' aa', '  aa' }, { ' #aa', ' # aa' })
      validate({ '  aa', '', '  ', '\t' }, { '  #aa', '  #', '  #', '  #' }, { '  aa', '', '', '' })

      set_commentstring('%s#')
      validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { 'aa#', '  aa#', 'aa  #', '  aa  #' })
      validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { 'aa#', '\taa#', 'aa\t#', '\taa\t#' })
      validate({ ' aa', '  aa' }, { ' aa#', '  aa#' })
      validate({ '  aa', '', '  ', '\t' }, { '  aa#', '  #', '  #', '  #' }, { '  aa', '', '', '' })

      -- Extra whitespace inside comment parts
      set_commentstring('#  %s  #')
      validate(
        { 'aa', '  aa', 'aa  ', '  aa  ' },
        { '#  aa  #', '#    aa  #', '#  aa    #', '#    aa    #' }
      )
      validate(
        { 'aa', '\taa', 'aa\t', '\taa\t' },
        { '#  aa  #', '#  \taa  #', '#  aa\t  #', '#  \taa\t  #' }
      )
      validate({ ' aa', '  aa' }, { ' #  aa  #', ' #   aa  #' })
      validate(
        { '  aa', '', '  ', '\t' },
        { '  #  aa  #', '  ##', '  ##', '  ##' },
        { '  aa', '', '', '' }
      )

      set_commentstring('#  %s')
      validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { '#  aa', '#    aa', '#  aa  ', '#    aa  ' })
      validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { '#  aa', '#  \taa', '#  aa\t', '#  \taa\t' })
      validate({ ' aa', '  aa' }, { ' #  aa', ' #   aa' })
      validate(
        { '  aa', '', '  ', '\t' },
        { '  #  aa', '  #', '  #', '  #' },
        { '  aa', '', '', '' }
      )

      set_commentstring('%s  #')
      validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { 'aa  #', '  aa  #', 'aa    #', '  aa    #' })
      validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { 'aa  #', '\taa  #', 'aa\t  #', '\taa\t  #' })
      validate({ ' aa', '  aa' }, { ' aa  #', '  aa  #' })
      validate(
        { '  aa', '', '  ', '\t' },
        { '  aa  #', '  #', '  #', '  #' },
        { '  aa', '', '', '' }
      )

      -- Whitespace outside of comment parts
      set_commentstring(' # %s # ')
      validate(
        { 'aa', '  aa', 'aa  ', '  aa  ' },
        { ' # aa # ', ' #   aa # ', ' # aa   # ', ' #   aa   # ' }
      )
      validate(
        { 'aa', '\taa', 'aa\t', '\taa\t' },
        { ' # aa # ', ' # \taa # ', ' # aa\t # ', ' # \taa\t # ' }
      )
      validate({ ' aa', '  aa' }, { '  # aa # ', '  #  aa # ' })
      validate(
        { '  aa', '', '  ', '\t' },
        { '   # aa # ', '  ##', '  ##', '  ##' },
        { '  aa', '', '', '' }
      )

      set_commentstring(' # %s ')
      validate(
        { 'aa', '  aa', 'aa  ', '  aa  ' },
        { ' # aa ', ' #   aa ', ' # aa   ', ' #   aa   ' }
      )
      validate(
        { 'aa', '\taa', 'aa\t', '\taa\t' },
        { ' # aa ', ' # \taa ', ' # aa\t ', ' # \taa\t ' }
      )
      validate({ ' aa', '  aa' }, { '  # aa ', '  #  aa ' })
      validate(
        { '  aa', '', '  ', '\t' },
        { '   # aa ', '  #', '  #', '  #' },
        { '  aa', '', '', '' }
      )

      set_commentstring(' %s # ')
      validate(
        { 'aa', '  aa', 'aa  ', '  aa  ' },
        { ' aa # ', '   aa # ', ' aa   # ', '   aa   # ' }
      )
      validate(
        { 'aa', '\taa', 'aa\t', '\taa\t' },
        { ' aa # ', ' \taa # ', ' aa\t # ', ' \taa\t # ' }
      )
      validate({ ' aa', '  aa' }, { '  aa # ', '   aa # ' })
      validate(
        { '  aa', '', '  ', '\t' },
        { '   aa # ', '  #', '  #', '  #' },
        { '  aa', '', '', '' }
      )

      -- LaTeX
      set_commentstring('% %s')
      validate({ 'aa', '  aa', 'aa  ', '  aa  ' }, { '% aa', '%   aa', '% aa  ', '%   aa  ' })
      validate({ 'aa', '\taa', 'aa\t', '\taa\t' }, { '% aa', '% \taa', '% aa\t', '% \taa\t' })
      validate({ ' aa', '  aa' }, { ' % aa', ' %  aa' })
      validate(
        { '  aa', '', '  ', '\t' },
        { '  % aa', '  %', '  %', '  %' },
        { '  aa', '', '', '' }
      )
    end)

    it('respects tree-sitter injections', function()
      setup_treesitter()

    local lines = {
      'set background=dark',
      'lua << EOF',
      'print(1)',
      'vim.api.nvim_exec2([[',
      '    set background=light',
      ']])',
      'EOF',
    }

    -- Single line comments
    local validate = function(line, ref_output)
      reset_debug_log()
      exec_lua([[vim.g._comment_debug = '/tmp/comment_debug.log']], line)
      set_lines(lines)
      toggle_lines(line, line)
      local actual = get_lines()[line]
      exec_lua([[
        if vim.g._comment_debug then
          local line, actual, expected = ...
          vim.fn.writefile(
            {('single_validate\t%d\t%s\t%s'):format(line, actual, expected)},
            vim.g._comment_debug,
            'a'
          )
        end
      ]], line, actual, ref_output)
      eq(actual, ref_output)
    end

      validate(1, '"set background=dark')
      validate(2, '"lua << EOF')
      validate(3, '-- print(1)')
      validate(4, '-- vim.api.nvim_exec2([[')
      validate(5, '    "set background=light')
      validate(6, '-- ]])')
      validate(7, '"EOF')

      -- Multiline comments should be computed based on first line 'commentstring'
      reset_debug_log()
      exec_lua([[vim.g._comment_debug = '/tmp/comment_debug.log']])
      set_lines(lines)
      reset_debug_log()
      toggle_lines(1, 3)
      local out_lines = get_lines()
      eq(out_lines[1], '"set background=dark')
      eq(out_lines[2], '"lua << EOF')
      eq(out_lines[3], '"print(1)')
    end)

    it('correctly computes indent', function()
      toggle_lines(2, 4)
      eq(get_lines(1, 4), { ' # aa', ' #  aa', ' #' })
    end)

    it('correctly detects comment/uncomment', function()
      local validate = function(from, to, ref_lines)
        set_lines({ '', 'aa', '# aa', '# aa', 'aa', '' })
        toggle_lines(from, to)
        eq(get_lines(), ref_lines)
      end

      -- It should uncomment only if all non-blank lines are comments
      validate(3, 4, { '', 'aa', 'aa', 'aa', 'aa', '' })
      validate(2, 4, { '', '# aa', '# # aa', '# # aa', 'aa', '' })
      validate(3, 5, { '', 'aa', '# # aa', '# # aa', '# aa', '' })
      validate(1, 6, { '#', '# aa', '# # aa', '# # aa', '# aa', '#' })

      -- Blank lines should be ignored when making a decision
      set_lines({ '# aa', '', '  ', '\t', '# aa' })
      toggle_lines(1, 5)
      eq(get_lines(), { 'aa', '', '  ', '\t', 'aa' })
    end)

    it('correctly matches comment parts during checking and uncommenting', function()
      local validate = function(from, to, ref_lines)
        set_lines({ '/*aa*/', '/* aa */', '/*  aa  */' })
        toggle_lines(from, to)
        eq(get_lines(), ref_lines)
      end

      -- Should first try to match 'commentstring' parts exactly with their
      -- whitespace, with fallback on trimmed parts
      set_commentstring('/*%s*/')
      validate(1, 3, { 'aa', ' aa ', '  aa  ' })
      validate(2, 3, { '/*aa*/', ' aa ', '  aa  ' })
      validate(3, 3, { '/*aa*/', '/* aa */', '  aa  ' })

      set_commentstring('/* %s */')
      validate(1, 3, { 'aa', 'aa', ' aa ' })
      validate(2, 3, { '/*aa*/', 'aa', ' aa ' })
      validate(3, 3, { '/*aa*/', '/* aa */', ' aa ' })

      set_commentstring('/*  %s  */')
      validate(1, 3, { 'aa', ' aa ', 'aa' })
      validate(2, 3, { '/*aa*/', ' aa ', 'aa' })
      validate(3, 3, { '/*aa*/', '/* aa */', 'aa' })

      set_commentstring(' /*%s*/ ')
      validate(1, 3, { 'aa', ' aa ', '  aa  ' })
      validate(2, 3, { '/*aa*/', ' aa ', '  aa  ' })
      validate(3, 3, { '/*aa*/', '/* aa */', '  aa  ' })
    end)

    it('uncomments on inconsistent indent levels', function()
      set_lines({ '# aa', ' # aa', '  # aa' })
      toggle_lines(1, 3)
      eq(get_lines(), { 'aa', ' aa', '  aa' })
    end)

    it('respects tabs', function()
      api.nvim_set_option_value('expandtab', false, { buf = 0 })
      set_lines({ '\t\taa', '\t\taa' })

      toggle_lines(1, 2)
      eq(get_lines(), { '\t\t# aa', '\t\t# aa' })

      toggle_lines(1, 2)
      eq(get_lines(), { '\t\taa', '\t\taa' })
    end)

    it('works with trailing whitespace', function()
      -- Without right-hand side
      set_commentstring('# %s')
      set_lines({ ' aa', ' aa  ', '  ' })
      toggle_lines(1, 3)
      eq(get_lines(), { ' # aa', ' # aa  ', ' #' })
      toggle_lines(1, 3)
      eq(get_lines(), { ' aa', ' aa  ', '' })

      -- With right-hand side
      set_commentstring('%s #')
      set_lines({ ' aa', ' aa  ', '  ' })
      toggle_lines(1, 3)
      eq(get_lines(), { ' aa #', ' aa   #', ' #' })
      toggle_lines(1, 3)
      eq(get_lines(), { ' aa', ' aa  ', '' })

      -- Trailing whitespace after right side should be preserved for non-blanks
      set_commentstring('%s #')
      set_lines({ ' aa #  ', ' aa #\t', ' #  ', ' #\t' })
      toggle_lines(1, 4)
      eq(get_lines(), { ' aa  ', ' aa\t', '', '' })
    end)
  end)

  describe('Operator', function()
    it('works in Normal mode', function()
      reset_debug_log()
      set_cursor(2, 2)
      feed('gc', 'ap')
      local expected = { '# aa', '#  aa', '#   aa', '#', '  aa', ' aa', 'aa' }
      exec_lua([[
        if vim.g._comment_debug then
          vim.fn.writefile({('operator_expected\t%s'):format(vim.inspect(...))}, vim.g._comment_debug, 'a')
        end
      ]], expected)
      eq(get_lines(), expected)
      -- Cursor moves to start line
      eq(get_cursor(), { 1, 0 })

      -- Supports `v:count`
      set_lines(example_lines)
      set_cursor(2, 0)
      feed('2gc', 'ap')
      eq(get_lines(), { '# aa', '#  aa', '#   aa', '#', '#   aa', '#  aa', '# aa' })
    end)

    it('allows dot-repeat in Normal mode', function()
      local doubly_commented = { '# # aa', '# #  aa', '# #   aa', '# #', '#   aa', '#  aa', '# aa' }

      set_lines(example_lines)
      set_cursor(2, 2)
      feed('gc', 'ap')
      feed('.')
      eq(get_lines(), doubly_commented)

      -- Not immediate dot-repeat
      set_lines(example_lines)
      set_cursor(2, 2)
      feed('gc', 'ap')
      set_cursor(7, 0)
      feed('.')
      eq(get_lines(), doubly_commented)
    end)

    it('works in Visual mode', function()
      set_cursor(2, 2)
      feed('v', 'ap', 'gc')
      eq(get_lines(), { '# aa', '#  aa', '#   aa', '#', '  aa', ' aa', 'aa' })

      -- Cursor moves to start line
      eq(get_cursor(), { 1, 0 })
    end)

    it('allows dot-repeat after initial Visual mode', function()
      -- local example_lines = { 'aa', ' aa', '  aa', '', '  aa', ' aa', 'aa' }

      set_lines(example_lines)
      set_cursor(2, 2)
      feed('vip', 'gc')
      eq(get_lines(), { '# aa', '#  aa', '#   aa', '', '  aa', ' aa', 'aa' })
      eq(get_cursor(), { 1, 0 })

      -- Dot-repeat after first application in Visual mode should apply to the same
      -- relative region
      feed('.')
      eq(get_lines(), example_lines)

      reset_debug_log()
      set_cursor(3, 0)
      feed('.')
      eq(get_lines(), { 'aa', ' aa', '  # aa', '  #', '  # aa', ' aa', 'aa' })
    end)

    it("respects 'commentstring'", function()
      set_commentstring('/*%s*/')
      set_cursor(2, 2)
      feed('gc', 'ap')
      eq(get_lines(), { '/*aa*/', '/* aa*/', '/*  aa*/', '/**/', '  aa', ' aa', 'aa' })
    end)

    it("works with empty 'commentstring'", function()
      set_commentstring('')
      set_cursor(2, 2)
      feed('gc', 'ap')
      eq(get_lines(), example_lines)
      eq(exec_capture('1messages'), [[Option 'commentstring' is empty.]])
    end)

    it('respects tree-sitter injections', function()
      setup_treesitter()

      local lines = {
        'set background=dark',
        'lua << EOF',
        'print(1)',
        'vim.api.nvim_exec2([[',
        '    set background=light',
        ']])',
        'EOF',
      }

      -- Single line comments
      local validate = function(line, ref_output)
      reset_debug_log()
      set_lines(lines)
      set_cursor(line, 0)
      feed('gc_')
      local actual = get_lines(line - 1, line)[1]
      exec_lua([[
        if vim.g._comment_debug then
          local line, actual, expected = ...
          vim.fn.writefile({('single_validate\t%d\t%s\t%s'):format(line, vim.inspect(actual), vim.inspect(expected))}, vim.g._comment_debug, 'a')
        end
      ]], line, actual, ref_output)
      eq(actual, ref_output)
    end

      validate(1, '"set background=dark')
      validate(2, '"lua << EOF')
      validate(3, '-- print(1)')
      validate(4, '-- vim.api.nvim_exec2([[')
      validate(5, '    "set background=light')
      validate(6, '-- ]])')
      validate(7, '"EOF')

      -- Has proper dot-repeat which recomputes 'commentstring'
      reset_debug_log()
      reset_debug_log()
      set_lines(lines)

      set_cursor(1, 0)
      feed('gc_')
      local line1 = get_lines()[1]
      exec_lua([[
        if vim.g._comment_debug then
          local actual, expected = ...
          vim.fn.writefile({('dot_repeat_initial\t%s\t%s'):format(vim.inspect(actual), vim.inspect(expected))}, vim.g._comment_debug, 'a')
        end
      ]], line1, '"set background=dark')
      eq(line1, '"set background=dark')

      set_cursor(3, 0)
      feed('.')
      local line3 = get_lines()[3]
      exec_lua([[
        if vim.g._comment_debug then
          local actual, expected = ...
          vim.fn.writefile({('dot_repeat_result\t%s\t%s'):format(vim.inspect(actual), vim.inspect(expected))}, vim.g._comment_debug, 'a')
        end
      ]], line3, '-- print(1)')
      eq(line3, '-- print(1)')

      -- Multiline comments should be computed based on cursor position
      -- which in case of Visual selection means its left part
      reset_debug_log()
      set_lines(lines)
      set_cursor(1, 0)
      feed('v2j', 'gc')
      local out_lines = get_lines()
      exec_lua([[
        if vim.g._comment_debug then
          local l1, l2, l3 = ...
          vim.fn.writefile({
            ('visual_result\t1\t%s'):format(vim.inspect(l1)),
            ('visual_result\t2\t%s'):format(vim.inspect(l2)),
            ('visual_result\t3\t%s'):format(vim.inspect(l3)),
          }, vim.g._comment_debug, 'a')
        end
      ]], out_lines[1], out_lines[2], out_lines[3])
      eq(out_lines[1], '"set background=dark')
      eq(out_lines[2], '"lua << EOF')
      eq(out_lines[3], '"print(1)')
    end)

    it("recomputes local 'commentstring' based on cursor position", function()
      setup_treesitter()
      local lines = {
        '  print(1)',
        'lua << EOF',
        '  print(1)',
        'EOF',
      }
      set_lines(lines)

      set_cursor(1, 1)
      feed('gc_')
      local first_line = get_lines()[1]
      exec_lua([[
        if vim.g._comment_debug then
          vim.fn.writefile({('recompute_initial\t%s'):format(vim.inspect(...))}, vim.g._comment_debug, 'a')
        end
      ]], first_line)
      eq(first_line, '  "print(1)')

      set_lines(lines)
      set_cursor(3, 2)
      feed('.')
      local third_line = get_lines()[3]
      exec_lua([[
        if vim.g._comment_debug then
          vim.fn.writefile({('recompute_result\t%s'):format(vim.inspect(...))}, vim.g._comment_debug, 'a')
        end
      ]], third_line)
      eq(third_line, '  -- print(1)')
    end)

    it('preserves marks', function()
      set_cursor(2, 0)
      -- Set '`<' and '`>' marks
      feed('VV')
      feed('gc', 'ip')
      eq(api.nvim_buf_get_mark(0, '<'), { 2, 0 })
      eq(api.nvim_buf_get_mark(0, '>'), { 2, 2147483647 })
    end)
  end)

  describe('Current line', function()
    it('works', function()
      set_lines(example_lines)
      set_cursor(1, 1)
      feed('gcc')
      eq(get_lines(0, 2), { '# aa', ' aa' })

      -- Does not comment empty line
      set_lines(example_lines)
      set_cursor(4, 0)
      feed('gcc')
      eq(get_lines(2, 5), { '  aa', '', '  aa' })

      -- Supports `v:count`
      set_lines(example_lines)
      set_cursor(2, 0)
      feed('2gcc')
      eq(get_lines(0, 3), { 'aa', ' # aa', ' #  aa' })
    end)

    it('allows dot-repeat', function()
      set_lines(example_lines)
      set_cursor(1, 1)
      feed('gcc')
      feed('.')
      eq(get_lines(), example_lines)

      -- Not immediate dot-repeat
      set_lines(example_lines)
      set_cursor(1, 1)
      feed('gcc')
      set_cursor(7, 0)
      feed('.')
      eq(get_lines(6, 7), { '# aa' })
    end)

    it('respects tree-sitter injections', function()
      setup_treesitter()

      local lines = {
        'set background=dark',
        'lua << EOF',
        'print(1)',
        'EOF',
      }
      reset_debug_log()
      reset_debug_log()
      reset_debug_log()
      set_lines(lines)

      set_cursor(1, 0)
      feed('gcc')
      eq(get_lines(), { '"set background=dark', 'lua << EOF', 'print(1)', 'EOF' })

      -- Should work with dot-repeat
      reset_debug_log()
      set_cursor(3, 0)
      feed('.')
      eq(get_lines(), { '"set background=dark', 'lua << EOF', '-- print(1)', 'EOF' })
    end)

    it('respects tree-sitter commentstring metadata', function()
      exec_lua [=[
        vim.treesitter.query.set('vim', 'highlights', [[
          ((list) @_list (#set! @_list bo.commentstring "!! %s"))
        ]])
      ]=]
      setup_treesitter()

      local lines = {
        'set background=dark',
        'let mylist = [',
        [[  \"a",]],
        [[  \"b",]],
        [[  \"c",]],
        '  \\]',
      }
      set_lines(lines)

      set_cursor(1, 0)
      feed('gcc')
      eq(
        { '"set background=dark', 'let mylist = [', [[  \"a",]], [[  \"b",]], [[  \"c",]], '  \\]' },
        get_lines()
      )

      -- Should work with dot-repeat
      set_cursor(4, 0)
      feed('.')
      eq({
        '"set background=dark',
        'let mylist = [',
        [[  \"a",]],
        [[  !! \"b",]],
        [[  \"c",]],
        '  \\]',
      }, get_lines())
    end)

    it('only applies the innermost tree-sitter commentstring metadata', function()
      exec_lua [=[
        vim.treesitter.query.set('vim', 'highlights', [[
          ((list) @_list (#gsub! @_list "(.*)" "%1") (#set! bo.commentstring "!! %s"))
          ((script_file) @_src (#set! @_src bo.commentstring "## %s"))
        ]])
      ]=]
      setup_treesitter()

      local lines = {
        'set background=dark',
        'let mylist = [',
        [[  \"a",]],
        [[  \"b",]],
        [[  \"c",]],
        '  \\]',
      }
      set_lines(lines)

      set_cursor(1, 0)
      feed('gcc')
      eq({
        '## set background=dark',
        'let mylist = [',
        [[  \"a",]],
        [[  \"b",]],
        [[  \"c",]],
        '  \\]',
      }, get_lines())

      -- Should work with dot-repeat
      reset_debug_log()
      set_cursor(4, 0)
      feed('.')
      eq({
        '## set background=dark',
        'let mylist = [',
        [[  \"a",]],
        [[  !! \"b",]],
        [[  \"c",]],
        '  \\]',
      }, get_lines())
    end)

    it('respects injected tree-sitter commentstring metadata', function()
      exec_lua [=[
        vim.treesitter.query.set('lua', 'highlights', [[
          ((string) @string (#set! @string bo.commentstring "; %s"))
        ]])
      ]=]
      setup_treesitter()

      local lines = {
        'set background=dark',
        'lua << EOF',
        'print[[',
        'Inside string',
        ']]',
        'EOF',
      }
      set_lines(lines)

      set_cursor(1, 0)
      feed('gcc')
      eq({
        '"set background=dark',
        'lua << EOF',
        'print[[',
        'Inside string',
        ']]',
        'EOF',
      }, get_lines())

      -- Should work with dot-repeat
      reset_debug_log()
      set_cursor(4, 0)
      feed('.')
      eq({
        '"set background=dark',
        'lua << EOF',
        'print[[',
        '; Inside string',
        ']]',
        'EOF',
      }, get_lines())

      reset_debug_log()
      set_cursor(3, 0)
      feed('.')
      eq({
        '"set background=dark',
        'lua << EOF',
        '-- print[[',
        '; Inside string',
        ']]',
        'EOF',
      }, get_lines())
    end)

    it('exposes tree-sitter commentstring metadata through captures', function()
      exec_lua [=[
        vim.treesitter.query.set('lua', 'highlights', [[
          ((string) @string (#set! @string bo.commentstring "; %s"))
        ]])
      ]=]
      setup_treesitter()

      set_lines({
        'set background=dark',
        'lua << EOF',
        'print[[',
        'Inside string',
        ']]',
        'EOF',
      })

      eq('; %s', exec_lua [=[
        for _, cap in ipairs(vim.treesitter.get_captures_at_pos(0, 3, 0)) do
          local md = cap.metadata
          if md['bo.commentstring'] then
            return md['bo.commentstring']
          end
          local capture_md = md[cap.id]
          if capture_md and capture_md['bo.commentstring'] then
            return capture_md['bo.commentstring']
          end
        end
      ]=])

      exec_lua [[vim.treesitter.query.set('lua', 'highlights', nil)]]
    end)

    it('works across combined injections #30799', function()
      exec_lua [=[
        vim.treesitter.query.set('lua', 'injections', [[
          ((function_call
            name: (_) @_vimcmd_identifier
            arguments: (arguments
              (string
                content: _ @injection.content)))
            (#eq? @_vimcmd_identifier "vim.cmd")
            (#set! injection.language "vim")
            (#set! injection.combined))
        ]])
      ]=]

      api.nvim_set_option_value('filetype', 'lua', { buf = 0 })
      exec_lua('vim.treesitter.start()')

      local lines = {
        'vim.cmd([[" some text]])',
        'local a = 123',
        'vim.cmd([[" some more text]])',
      }
      set_lines(lines)

      set_cursor(2, 0)
      feed('gcc')
      eq({
        'vim.cmd([[" some text]])',
        '-- local a = 123',
        'vim.cmd([[" some more text]])',
      }, get_lines())
    end)
  end)

  describe('Textobject', function()
    it('works', function()
      set_lines({ 'aa', '# aa', '# aa', 'aa' })
      set_cursor(2, 0)
      feed('d', 'gc')
      eq(get_lines(), { 'aa', 'aa' })
    end)

    it('allows dot-repeat', function()
      set_lines({ 'aa', '# aa', '# aa', 'aa', '# aa' })
      set_cursor(2, 0)
      feed('d', 'gc')
      set_cursor(3, 0)
      feed('.')
      eq(get_lines(), { 'aa', 'aa' })
    end)

    it('does nothing when not inside textobject', function()
      -- Builtin operators
      feed('d', 'gc')
      eq(get_lines(), example_lines)

      -- Comment operator
      local validate_no_action = function(line, col)
        set_lines(example_lines)
        set_cursor(line, col)
        feed('gc', 'gc')
        eq(get_lines(), example_lines)
      end

      validate_no_action(1, 1)
      validate_no_action(2, 2)

      -- Doesn't work (but should) because both `[` and `]` are set to (1, 0)
      -- (instead of more reasonable (1, -1) or (0, 2147483647)).
      -- validate_no_action(1, 0)
    end)

    it('respects tree-sitter injections', function()
      setup_treesitter()
      local lines = {
        '"set background=dark',
        '"set termguicolors',
        'lua << EOF',
        '-- print(1)',
        '-- print(2)',
        'EOF',
      }
      reset_debug_log()
      set_lines(lines)

      set_cursor(1, 0)
      feed('dgc')
      local after_delete = get_lines()
      exec_lua([[
        if vim.g._comment_debug then
          local state = ...
          vim.fn.writefile({ 'textobject_after_dgc\t' .. vim.inspect(state) }, vim.g._comment_debug, 'a')
        end
      ]], after_delete)
      eq(after_delete, { 'lua << EOF', '-- print(1)', '-- print(2)', 'EOF' })

      -- Should work with dot-repeat
      reset_debug_log()
      set_cursor(2, 0)
      feed('.')
      local after_repeat = get_lines()
      exec_lua([[
        if vim.g._comment_debug then
          local state = ...
          vim.fn.writefile({ 'textobject_after_repeat\t' .. vim.inspect(state) }, vim.g._comment_debug, 'a')
        end
      ]], after_repeat)
      eq(after_repeat, { 'lua << EOF', 'EOF' })
    end)
  end)
end)
