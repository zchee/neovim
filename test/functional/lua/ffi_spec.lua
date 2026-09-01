local t = require('test.testutil')
local n = require('test.functional.testnvim')()

local describe, it, before_each, pending = t.describe, t.it, t.before_each, t.pending
local eq = t.eq
local exec_lua = n.exec_lua
local clear = n.clear

-- Reaching into nvim's internals through ffi.C only works while the binary
-- exports them. On macOS it ships an explicit export list instead
-- (src/nvim/exported_symbols.txt) unless configured with ENABLE_EXPORTS=ON, so
-- probe before depending on them. One internal answers for all of them: they
-- are either all exported or none are.
local probe_ffi_internals = [[
  local ok, ffi = pcall(require, 'ffi')
  if not ok then
    return false
  end
  ffi.cdef('void block_autocmds(void);')
  return pcall(function()
    return ffi.C.block_autocmds
  end)
]]

before_each(clear)

describe('ffi.cdef', function()
  it('can use Neovim core functions', function()
    if not exec_lua(probe_ffi_internals) then
      pending('N/A: missing LuaJIT FFI, or nvim internals not exported')
    end

    eq(
      12,
      exec_lua(function()
        local ffi = require('ffi')

        ffi.cdef [[
        typedef struct window_S win_T;
        int win_col_off(win_T *wp);
        extern win_T *curwin;
      ]]

        vim.cmd('set number numberwidth=4 signcolumn=yes:4')

        return ffi.C.win_col_off(ffi.C.curwin)
      end)
    )

    eq(
      20,
      exec_lua(function()
        local ffi = require('ffi')

        ffi.cdef [[
        typedef struct {} stl_hlrec_t;
        typedef struct {} StlClickRecord;
        typedef struct {} statuscol_T;
        typedef struct {} Error;

        win_T *find_window_by_handle(int Window, Error *err);

        int build_stl_str_hl(
          win_T *wp,
          char *out,
          size_t outlen,
          char *fmt,
          int opt_idx,
          int opt_scope,
          int fillchar,
          int maxwidth,
          stl_hlrec_t **hltab,
          StlClickRecord **tabtab,
          statuscol_T *scp
        );
      ]]

        return ffi.C.build_stl_str_hl(
          ffi.C.find_window_by_handle(0, ffi.new('Error')),
          ffi.new('char[1024]'),
          1024,
          ffi.cast('char*', 'StatusLineOfLength20'),
          -1,
          0,
          0,
          0,
          nil,
          nil,
          nil
        )
      end)
    )

    -- Check that extern symbols are exported and accessible
    eq(
      true,
      exec_lua(function()
        local ffi = require('ffi')

        ffi.cdef('uint64_t display_tick;')

        return ffi.C.display_tick >= 0
      end)
    )
  end)
end)
