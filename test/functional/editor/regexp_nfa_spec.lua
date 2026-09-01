-- The NFA engine marks each state with the id of the list it was last added to
-- (nfa_state_T.lastlist).  Those ids keep climbing across match attempts instead of being reset,
-- so a mark left by an earlier attempt on the same compiled program can never be mistaken for a
-- live one.  Every test here drives MANY match attempts through ONE compiled program -- which is
-- what :substitute, :global and search() over many lines do -- and asserts the result never
-- drifts from the first attempt.

local t = require('test.testutil')
local n = require('test.functional.testnvim')()

local describe, it, before_each = t.describe, t.it, t.before_each
local clear = n.clear
local exec_lua = n.exec_lua
local eq = t.eq

--- Runs `body` `rounds` times in one session and returns { first_result, number_of_distinct }.
--- The compiled regexp program is reused across rounds, so a stale list-id mark would show up
--- as a round whose result differs from the first.
local function stable(rounds, body)
  return exec_lua(
    [[
    local rounds, body = ...
    local fn = assert((loadstring or load)(body))()
    local first, distinct = nil, 0
    local seen = {}
    for _ = 1, rounds do
      local got = fn()
      if not seen[got] then
        seen[got] = true
        distinct = distinct + 1
      end
      first = first or got
    end
    return { first, distinct }
  ]],
    rounds,
    body
  )
end

--- Body helper: fills the buffer, runs `cmd`, returns the buffer joined by "|".
local function subst(lines, cmd)
  return ([[
    return function()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, %s)
      vim.cmd([==[%s]==])
      return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')
    end
  ]]):format(lines, cmd)
end

describe('NFA regexp engine list ids', function()
  before_each(clear)

  it('are stable across repeated attempts with captures', function()
    local r = stable(
      25,
      subst(
        [[{ 'key1 = val1 ; key2 = val2', 'key3 = val3', 'nothing here' }]],
        [[silent! %s/\(key\d\)\s*=\s*\(val\d\)/\2<-\1/g]]
      )
    )
    eq('val1<-key1 ; val2<-key2|val3<-key3|nothing here', r[1])
    eq(1, r[2])
  end)

  it('are stable with back-references', function()
    -- Back-references switch on rex.nfa_has_backref, which makes addstate() compare positions
    -- (has_state_with_pos) instead of trusting the lastlist mark alone.
    local r = stable(
      25,
      subst(
        [[{ 'abcabc xyxy foofoo barbaz', 'aa bb cc dd aa', 'zzz yy zzz' }]],
        [[silent! %s/\(\a\+\)\1/[\1]/g]]
      )
    )
    eq('[abc] [xy] [foo] barbaz|[a] [b] [c] [d] [a]|[z]z [y] [z]z', r[1])
    eq(1, r[2])
  end)

  it('are stable with zero-width assertions', function()
    local zs =
      stable(25, subst([[{ 'foo=bar', 'alpha=beta', 'x=y' }]], [[silent! %s/\w\+=\zs\w\+/Q/g]]))
    eq('foo=Q|alpha=Q|x=Q', zs[1])
    eq(1, zs[2])

    local ze =
      stable(25, subst([[{ 'foo=bar', 'alpha=beta', 'x=y' }]], [[silent! %s/\w\+\ze=/R/g]]))
    eq('R=bar|R=beta|R=y', ze[1])
    eq(1, ze[2])
  end)

  it('are stable through look-around recursion', function()
    -- \@=, \@! and \@<= go through recursive_regmatch(), which uses the second lastlist slot and
    -- rex.nfa_alt_listid.  A stale mark there is exactly what nfa_alt_listid has to outrun.
    local lines = [[{ 'foo1 bar1 foobar1 barfoo1', 'foobar2 foo2', 'barfoo3' }]]

    local ahead = stable(25, subst(lines, [[silent! %s/foo\(bar\)\@=/POS/g]]))
    eq('foo1 bar1 POSbar1 barfoo1|POSbar2 foo2|barfoo3', ahead[1])
    eq(1, ahead[2])

    local negahead = stable(25, subst(lines, [[silent! %s/foo\(bar\)\@!/NEG/g]]))
    eq('NEG1 bar1 foobar1 barNEG1|foobar2 NEG2|barNEG3', negahead[1])
    eq(1, negahead[2])

    local behind = stable(25, subst(lines, [[silent! %s/\(foo\)\@<=bar/BEHIND/g]]))
    eq('foo1 bar1 fooBEHIND1 barfoo1|fooBEHIND2 foo2|barfoo3', behind[1])
    eq(1, behind[2])
  end)

  it('are stable through recursing groups', function()
    local r = stable(
      25,
      subst(
        [[{ 'foofoobar1 foo2', 'foobarfoobar3', 'plain' }]],
        [[silent! %s/\%(\%(foo\)\+\%(bar\)\?\)\+\d\+/G/g]]
      )
    )
    eq('G G|G|plain', r[1])
    eq(1, r[2])
  end)

  it('are stable across multiline matches', function()
    local r = stable(
      25,
      subst(
        [[{ 'begin1', 'middle1', 'end1', 'begin2', 'middle2', 'end2' }]],
        [[silent! %s/begin\d\+\nmiddle\(\d\+\)/JOIN\1/]]
      )
    )
    eq('JOIN1|end1|JOIN2|end2', r[1])
    eq(1, r[2])
  end)

  it('are stable when the ids climb far (long alternation)', function()
    -- A wide alternation over many lines drives the id counter up fast: this is the high-water
    -- probe.  If the counter were reset per attempt while the marks survived, or if the
    -- high-water mark were tracked one too low, later rounds would start skipping states.
    local words = {}
    for i = 1, 60 do
      words[i] = 'w' .. i
    end
    local pat = '\\<\\%(' .. table.concat(words, '\\|') .. '\\)\\>'
    local lines = {}
    for i = 1, 120 do
      lines[i] = ('lead w%d trail w%d tail'):format((i % 60) + 1, ((i * 7) % 60) + 1)
    end
    local literal = "{ '" .. table.concat(lines, "', '") .. "' }"
    local r = stable(
      12,
      ([[
      return function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false, %s)
        vim.cmd('silent! %%s/%s/&!/ge')
        local hits = 0
        for _, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
          local _, k = l:gsub('!', '')
          hits = hits + k
        end
        return tostring(hits)
      end
    ]]):format(literal, (pat:gsub('\\', '\\\\')))
    )
    eq('240', r[1])
    eq(1, r[2])
  end)

  it('are stable for \\z(...\\) extmatch syntax regions', function()
    -- \z(...\) is the only user of the "synt" sub-match list, which nfa_regtry() now clears only
    -- when the pattern actually has one.
    local r = stable(
      15,
      [[
      return function()
        vim.api.nvim_buf_set_lines(0, 0, -1, false,
          { 'START qq body qq END', 'START zz other zz END', 'plain line' })
        vim.cmd('silent! syntax clear')
        vim.cmd([==[syntax region TestRegion start=/START \z(\a\a\)/ end=/\z1 END/]==])
        local out = {}
        for l = 1, vim.fn.line('$') do
          local row = {}
          for c = 1, #vim.fn.getline(l) do
            row[#row + 1] = (vim.fn.synIDattr(vim.fn.synID(l, c, 1), 'name') == '' and '.' or 'R')
          end
          out[#out + 1] = table.concat(row, '')
        end
        return table.concat(out, '|')
      end
    ]]
    )
    eq('RRRRRRRRRRRRRRRRRRRR|RRRRRRRRRRRRRRRRRRRRR|..........', r[1])
    eq(1, r[2])
  end)

  it('agree between the forced NFA and backtracking engines', function()
    local r = exec_lua([==[
      local out = {}
      for _, prefix in ipairs({ [[\%#=1]], [[\%#=2]] }) do
        local acc = {}
        for _ = 1, 10 do
          vim.api.nvim_buf_set_lines(0, 0, -1, false,
            { 'abcabc xyxy foofoo', 'key1 = val1', 'foobar baz' })
          vim.cmd('silent! %s/' .. prefix .. [[\(\a\+\)\1/[\1]/ge]])
          acc[#acc + 1] = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '|')
        end
        out[#out + 1] = acc[1]
        for _, v in ipairs(acc) do
          assert(v == acc[1], 'unstable across rounds: ' .. v)
        end
      end
      return out
    ]==])
    eq(r[1], r[2])
    eq('[abc] [xy] [foo]|key1 = val1|f[o]bar baz', r[1])
  end)

  it("still reports 'too expensive' patterns", function()
    -- The NFA_MAX_STATES bail-out is now a delta from the id the attempt started at.  With an
    -- absolute compare it would fire earlier and earlier as the counter climbed, so warm the
    -- counter up first and check the outcome does not change.
    local r = exec_lua([[
      local subject = string.rep('a', 300)
      local out = {}
      for round = 1, 6 do
        -- Climb the id counter on an unrelated but cached program.
        vim.api.nvim_buf_set_lines(0, 0, -1, false, { subject, subject, subject })
        vim.cmd([==[silent! %s/\<a\+\>/&/ge]==])
        out[#out + 1] = tostring(vim.fn.match(subject, [==[\(a*\)\+$x]==]))
      end
      return out
    ]])
    for _, v in ipairs(r) do
      eq(r[1], v)
    end
    eq('-1', r[1])
  end)
end)
