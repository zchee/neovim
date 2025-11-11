
local range_mod = require('vim.treesitter._range')

local function debug_log(...)
  local path = vim.g._comment_debug
  if not path then
    return
  end
  local parts = {}
  for i = 1, select('#', ...) do
    parts[i] = tostring(select(i, ...))
  end
  vim.fn.writefile({ table.concat(parts, '	') }, path, 'a')
end

local ft_runtime_templates = {
  'ftplugin/%s.vim',
  'ftplugin/%s.lua',
  'ftplugin/%s_*.vim',
  'ftplugin/%s_*.lua',
  'ftplugin/%s/*.vim',
  'ftplugin/%s/*.lua',
}

local ft_commentstring_cache = {} ---@type table<string,string|false>
local lang_commentstring_cache = {} ---@type table<string,string|false>
local parser_lang_cache = {} ---@type table<integer,string>

local function get_or_start_parser()
  local buf = vim.api.nvim_get_current_buf()
  local parser = vim.treesitter.get_parser(buf, '', { error = false })
  if parser then
    local lang = parser:lang() or parser_lang_cache[buf] or vim.bo.filetype
    parser_lang_cache[buf] = lang
    if lang then
      vim.b[[_comment_last_lang]] = lang
    end
    debug_log('parser_existing', buf, lang or 'nil')
    return parser
  end

  local tried = {}
  local function try_start(lang)
    if not lang or lang == '' or tried[lang] then
      return nil
    end
    tried[lang] = true
    local ok = pcall(vim.treesitter.start, buf, lang)
    if not ok then
      debug_log('parser_start_failed', buf, lang)
      return nil
    end
    local new_parser = vim.treesitter.get_parser(buf, '', { error = false })
    if new_parser then
      local detected = new_parser:lang() or lang
      parser_lang_cache[buf] = detected
      if detected then
        vim.b[[_comment_last_lang]] = detected
      end
      debug_log('parser_started', buf, detected or 'nil')
    end
    return new_parser
  end

  local ft = vim.bo.filetype
  parser = try_start(ft)
  if parser then
    return parser
  end

  local cached_lang = parser_lang_cache[buf] or vim.b._comment_last_lang
  if cached_lang and cached_lang ~= ft then
    parser = try_start(cached_lang)
    if parser then
      return parser
    end
  end

  return nil
end

local function refresh_parser_range(start_row, end_row)
  if not vim.g._comment_debug then
    vim.g._comment_debug = '/tmp/comment_debug.log'
  end
  local ts_parser = get_or_start_parser()
  if not ts_parser then
    debug_log('parser_missing', start_row, end_row, vim.bo.filetype or '', parser_lang_cache[vim.api.nvim_get_current_buf()] or '')
    return
  end

  local ok_invalidate = pcall(ts_parser.invalidate, ts_parser)
  if not ok_invalidate then
    return
  end

  local start = math.max(start_row, 0)
  local stop = math.max(end_row, start)
  local range = { start, 0, stop + 1, 0 }
  debug_log('refresh_parser_range', start, stop)
  ts_parser:parse(range)
  vim.wait(0)
  ts_parser:parse(range)
end

local function load_filetype_commentstring(ft)
  local cached = ft_commentstring_cache[ft]
  if cached ~= nil then
    return cached or nil
  end

  local ok, cs = pcall(vim.filetype.get_option, ft, 'commentstring')
  if ok and cs and cs ~= '' then
    ft_commentstring_cache[ft] = cs
    debug_log('ft_option', ft, cs)
    return cs
  end

  local buf = vim.api.nvim_create_buf(false, true)
  local ok_runtime, runtime_cs = pcall(function()
    return vim.api.nvim_buf_call(buf, function()
      vim.b.did_ftplugin = nil
      vim.bo.commentstring = ''
      vim.bo.filetype = ft

      local patterns = {}
      for i = 1, #ft_runtime_templates do
        patterns[i] = ft_runtime_templates[i]:format(ft)
      end

      local runtime_cmd = 'silent! runtime! ' .. table.concat(patterns, ' ')
      pcall(vim.cmd, runtime_cmd)
      return vim.bo.commentstring
    end)
  end)

  vim.api.nvim_buf_delete(buf, { force = true })

  if ok_runtime and runtime_cs and runtime_cs ~= '' then
    ft_commentstring_cache[ft] = runtime_cs
    debug_log('ft_runtime', ft, runtime_cs)
    return runtime_cs
  end

  ft_commentstring_cache[ft] = false
  debug_log('ft_missing', ft)
  return nil
end

local function commentstring_for_lang(lang)
  local cached = lang_commentstring_cache[lang]
  if cached ~= nil then
    return cached or nil
  end

  local filetypes = vim.treesitter.language.get_filetypes(lang)
  if filetypes then
    for _, ft in ipairs(filetypes) do
      local cs = load_filetype_commentstring(ft)
      if cs and cs ~= '' then
        lang_commentstring_cache[lang] = cs
        return cs
      end
    end
  end

  lang_commentstring_cache[lang] = false
  return nil
end

local function injection_commentstring(lang_tree, ref_range6, row, root_parser)
  if not lang_tree._injection_query then
    return nil
  end

  local ok_all, all_injections = pcall(lang_tree._get_injections, lang_tree, true, {})
  if (not ok_all or not all_injections or not next(all_injections)) and lang_tree == root_parser then
    root_parser:invalidate(true)
    root_parser:parse(true)
    vim.wait(0)
    root_parser:parse(true)
    ok_all, all_injections = pcall(lang_tree._get_injections, lang_tree, true, {})
  end
  if not ok_all or not all_injections then
    all_injections = nil
  end

  if all_injections then
    if next(all_injections) then
      pcall(lang_tree._add_injections, lang_tree, all_injections)
      root_parser:parse(true)
    end
    for lang, regions in pairs(all_injections) do
      if lang and regions then
        for _, region in ipairs(regions) do
          for _, range in ipairs(region) do
            if range_mod.contains(range, ref_range6) then
              local cs = commentstring_for_lang(lang)
              if cs and cs ~= '' then
                return cs
              end
            end
          end
        end
      end
    end
  end

  local children = lang_tree:children()
  if children then
    for _, child in pairs(children) do
      if child:contains(ref_range6) then
        local cs = commentstring_for_lang(child:lang())
        if cs and cs ~= '' then
          return cs
        end
      end
    end
  end

  if lang_tree == root_parser then
    local buf = vim.api.nvim_get_current_buf()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    local line_count = #lines
    local current = row + 1
    local start
    for r = current, 1, -1 do
      local text = lines[r]
      if text and text:match('^%s*lua%s*<<%s*EOF') then
        start = r
        break
      elseif text and text:match('^%s*EOF%s*$') then
        break
      end
    end
    if start then
      local open_long_string = 0
      for r = start, current - 1 do
        local text = lines[r]
        if text then
          local opens = select(2, text:gsub('%[%[', ''))
          local closes = select(2, text:gsub('%]%]', ''))
          open_long_string = open_long_string + opens - closes
        end
      end
      local current_text = lines[current] or ''
      local current_opens = select(2, current_text:gsub('%[%[', ''))
      local current_closes = select(2, current_text:gsub('%]%]', ''))
      local open_after_current = open_long_string + current_opens - current_closes
      if open_long_string > 0 and open_after_current > 0 then
        return nil
      end
      for r = current, line_count do
        local text = lines[r]
        if text and text:match('^%s*EOF%s*$') then
          if open_long_string <= 0 then
            return '-- %s'
          else
            break
          end
        elseif text and text:match('^%s*lua%s*<<%s*EOF') then
          break
        elseif text then
          local opens = select(2, text:gsub('%[%[', ''))
          local closes = select(2, text:gsub('%]%]', ''))
          open_long_string = open_long_string + opens - closes
        end
      end
    end
  end

  return nil
end

---@class vim._comment.Parts
---@field left string Left part of comment
---@field right string Right part of comment

--- Get 'commentstring' at cursor
---@param ref_position [integer,integer]
---@return string
local function get_commentstring(ref_position)
  local buf_cs = vim.bo.commentstring

  local row, col = ref_position[1] - 1, ref_position[2]
  local function ret(cs)
    debug_log('get_commentstring_result', row, col, cs or 'nil')
    return cs
  end

  local ts_parser = vim.treesitter.get_parser(0, '', { error = false })
  if not ts_parser then
    ts_parser = get_or_start_parser()
  end
  if not ts_parser then
    return ret(buf_cs)
  end

  -- Try to get 'commentstring' associated with local tree-sitter language.
  -- This is useful for injected languages (like markdown with code blocks).
  local ref_range = { row, col, row, col + 1 }
  local refreshed = false
  local function refresh_parser()
    if refreshed then
      return false
    end
    refreshed = true
    ts_parser:invalidate(true)
    ts_parser:parse(true)
    vim.wait(0)
    ts_parser:parse(true)
    return true
  end

  ts_parser:parse(true)

  local ref_range6 = range_mod.add_bytes(0, ref_range)

  local function lang_depth(tree)
    local depth = 0
    while tree do
      depth = depth + 1
      tree = tree:parent()
    end
    return depth
  end

  local function pick_best_lang_tree()
    local best_lang_tree, best_depth = nil, -1
    local lang_for_range = ts_parser:language_for_range(ref_range)
    if lang_for_range and lang_for_range:contains(ref_range6) then
      best_lang_tree = lang_for_range
      best_depth = lang_depth(lang_for_range)
    end

    ts_parser:for_each_tree(function(_, lang_tree)
      if lang_tree:contains(ref_range6) then
        local depth = lang_depth(lang_tree)
        if depth > best_depth then
          best_lang_tree = lang_tree
          best_depth = depth
        end
      end
    end)
    return best_lang_tree, best_depth
  end

  local best_lang_tree, best_depth = pick_best_lang_tree()

  -- Get 'commentstring' from tree-sitter captures' metadata.
  -- Traverse backwards to prefer narrower captures.
  local function capture_commentstring(caps)
    for i = #caps, 1, -1 do
      local id, metadata = caps[i].id, caps[i].metadata
      local capture_name = caps[i].capture or ''
      local md_cms = metadata['bo.commentstring'] or metadata[id] and metadata[id]['bo.commentstring']
      debug_log('capture_candidate', row, col, capture_name, md_cms)
      if md_cms and capture_name ~= '_src' then
        debug_log('capture_return', row, col, md_cms)
        return ret(md_cms)
      end
    end
    return nil
  end

  local caps = vim.treesitter.get_captures_at_pos(0, row, col)
  local caps_cs = capture_commentstring(caps)
  if not caps_cs and refresh_parser() then
    caps = vim.treesitter.get_captures_at_pos(0, row, col)
    debug_log('capture_refresh', row, col, #caps)
    caps_cs = capture_commentstring(caps)
  end
  if caps_cs then
    return caps_cs
  end

  local function commentstring_from_highlight(lang_tree)
    local query = vim.treesitter.query.get(lang_tree:lang(), 'highlights')
    if not query then
      return nil
    end

    local source = lang_tree:source()
    local best_cs, best_range
    for _, tree in pairs(lang_tree:trees()) do
      local root = tree:root()
      for capture_id, node, metadata in query:iter_captures(root, source, row, row + 1) do
        local capture_name = query.captures and query.captures[capture_id] or ''
        if capture_name ~= '_src' then
          local md = metadata and (metadata['bo.commentstring']
            or metadata[capture_id] and metadata[capture_id]['bo.commentstring'])
          if md then
            local capture_range = vim.treesitter.get_range(node, source, metadata and metadata[capture_id])
            if capture_range and range_mod.contains(capture_range, ref_range6) then
              if not best_range or range_mod.contains(best_range, capture_range) then
                best_cs = md
                best_range = capture_range
      debug_log('highlight_candidate', lang_tree:lang(), capture_id, vim.inspect(capture_range), md)
              end
            end
          end
        end
      end
    end
    return best_cs
  end

  local function deepest_lang_tree(tree)
    if not tree or not tree:contains(ref_range6) then
      return nil
    end

    local children = tree:children()
    if children then
      for _, child in pairs(children) do
        local child_match = deepest_lang_tree(child)
        if child_match then
          return child_match
        end
      end
    end

    return tree
  end

  best_lang_tree, best_depth = pick_best_lang_tree()

  local lang_tree = best_lang_tree or deepest_lang_tree(ts_parser)

  if lang_tree == ts_parser then
    local inj_cs = injection_commentstring(ts_parser, ref_range6, row, ts_parser)
    if inj_cs and inj_cs ~= '' then
      return ret(inj_cs)
    end
  end

  if not lang_tree then
    local buf = vim.api.nvim_get_current_buf()
    local function detect_lua_heredoc()
      local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local line_count = #lines
      local current = row + 1
      local start
      for r = current, 1, -1 do
        local text = lines[r]
        if text and text:match('^%s*lua%s*<<%s*EOF') then
          start = r
          break
        elseif text and text:match('^%s*EOF%s*$') then
          break
        end
      end
      if not start then
        return nil
      end
      for r = current, line_count do
        local text = lines[r]
        if text and text:match('^%s*EOF%s*$') then
          return '-- %s'
        elseif text and text:match('^%s*lua%s*<<%s*EOF') then
          break
        end
      end
      return nil
    end

    local heredoc_cs = detect_lua_heredoc()
    if heredoc_cs then
      return heredoc_cs
    end

    return ret(buf_cs)
  end

  local seen_langs = {}
  while lang_tree do
    seen_langs[#seen_langs + 1] = lang_tree:lang()

    local hl_cs = commentstring_from_highlight(lang_tree)
    if (hl_cs == nil or hl_cs == '') and refresh_parser() then
      debug_log('highlight_refresh', lang_tree:lang(), row, col)
      hl_cs = commentstring_from_highlight(lang_tree)
    end
    if hl_cs and hl_cs ~= '' then
      debug_log('highlight_return', lang_tree:lang(), row, col, hl_cs)
      return ret(hl_cs)
    end

    local cs = commentstring_for_lang(lang_tree:lang())
    if cs and cs ~= '' then
      debug_log('ft_return', lang_tree:lang(), cs)
      return ret(cs)
    end

    lang_tree = lang_tree:parent()
  end

  debug_log('fallback_buf', row, col, buf_cs)
  return ret(buf_cs)
end

--- Compute comment parts from 'commentstring'
---@param ref_position [integer,integer]
---@return vim._comment.Parts
local function get_comment_parts(ref_position)
  local cs = get_commentstring(ref_position)

  if cs == nil or cs == '' then
    vim.api.nvim_echo({ { "Option 'commentstring' is empty.", 'WarningMsg' } }, true, {})
    return { left = '', right = '' }
  end

  if not (type(cs) == 'string' and cs:find('%%s') ~= nil) then
    error(vim.inspect(cs) .. " is not a valid 'commentstring'.")
  end

  -- Structure of 'commentstring': <left part> <%s> <right part>
  local left, right = cs:match('^(.-)%%s(.-)$')
  assert(left and right)
  return { left = left, right = right }
end

--- Make a function that checks if a line is commented
---@param parts vim._comment.Parts
---@return fun(line: string): boolean
local function make_comment_check(parts)
  local l_esc, r_esc = vim.pesc(parts.left), vim.pesc(parts.right)

  -- Commented line has the following structure:
  -- <whitespace> <trimmed left> <anything> <trimmed right> <whitespace>
  local regex = '^%s-' .. vim.trim(l_esc) .. '.*' .. vim.trim(r_esc) .. '%s-$'

  return function(line)
    local matched = line:find(regex) ~= nil
    debug_log('comment_check', line, parts.left, parts.right, regex, matched)
    return matched
  end
end

--- Compute comment-related information about lines
---@param lines string[]
---@param parts vim._comment.Parts
---@return string indent
---@return boolean is_commented
local function get_lines_info(lines, parts)
  local comment_check = make_comment_check(parts)

  local is_commented = true
  local indent_width = math.huge
  ---@type string
  local indent

  for idx, l in ipairs(lines) do
    -- Update lines indent: minimum of all indents except blank lines
    local _, indent_width_cur, indent_cur = l:find('^(%s*)')
    assert(indent_width_cur and indent_cur)

    -- Ignore blank lines completely when making a decision
    if indent_width_cur < l:len() then
      -- NOTE: Copying actual indent instead of recreating it with `indent_width`
      -- allows to handle both tabs and spaces
      if indent_width_cur < indent_width then
        ---@diagnostic disable-next-line:cast-local-type
        indent_width, indent = indent_width_cur, indent_cur
      end

      -- Update comment info: commented if every non-blank line is commented
      local commented = comment_check(l)
      debug_log('line_check', idx, l, commented, parts.left, parts.right)
      if is_commented then
        is_commented = commented
      end
    end
  end

  -- `indent` can still be `nil` in case all `lines` are empty
  debug_log('lines_info', indent or '', is_commented)
  return indent or '', is_commented
end

--- Compute whether a string is blank
---@param x string
---@return boolean is_blank
local function is_blank(x)
  return x:find('^%s*$') ~= nil
end

--- Make a function which comments a line
---@param parts vim._comment.Parts
---@param indent string
---@return fun(line: string): string
local function make_comment_function(parts, indent)
  local prefix, nonindent_start, suffix = indent .. parts.left, indent:len() + 1, parts.right
  local blank_comment = indent .. vim.trim(parts.left) .. vim.trim(suffix)

  return function(line)
    if is_blank(line) then
      return blank_comment
    end
    local result = prefix .. line:sub(nonindent_start) .. suffix
    debug_log('comment_apply', line, result, prefix, suffix, nonindent_start)
    return result
  end
end

--- Make a function which uncomments a line
---@param parts vim._comment.Parts
---@return fun(line: string): string
local function make_uncomment_function(parts)
  local l_esc, r_esc = vim.pesc(parts.left), vim.pesc(parts.right)
  local regex = '^(%s*)' .. l_esc .. '(.*)' .. r_esc .. '(%s-)$'
  local regex_trimmed = '^(%s*)' .. vim.trim(l_esc) .. '(.*)' .. vim.trim(r_esc) .. '(%s-)$'

  return function(line)
    -- Try regex with exact comment parts first, fall back to trimmed parts
    local indent, new_line, trail = line:match(regex)
    if new_line == nil then
      indent, new_line, trail = line:match(regex_trimmed)
    end

    -- Return original if line is not commented
    if new_line == nil then
      return line
    end

    -- Prevent trailing whitespace
    if is_blank(new_line) then
      indent, trail = '', ''
    end

    return indent .. new_line .. trail
  end
end

--- Comment/uncomment buffer range
---@param line_start integer
---@param line_end integer
---@param ref_position? [integer, integer]
local function toggle_lines(line_start, line_end, ref_position)
  ref_position = ref_position or { line_start, 0 }

  local count = line_end - line_start + 1
  if count <= 0 then
    return
  end

  local lines = vim.api.nvim_buf_get_lines(0, line_start - 1, line_end, false)

  local parts_cache = {}
  local per_line_parts = {}

  local function cache_parts(parts)
    local key = parts.left .. string.char(0) .. parts.right
    local cached = parts_cache[key]
    if cached then
      return cached
    end
    parts_cache[key] = parts
    return parts
  end

  local function position_for_line(idx, line)
    local lnum = line_start + idx - 1
    if idx == 1 and ref_position and ref_position[1] == lnum then
      return { ref_position[1], ref_position[2] }
    end
    local first = line:find('%S')
    local col = first and (first - 1) or 0
    return { lnum, col }
  end

  for idx, line in ipairs(lines) do
    local pos = position_for_line(idx, line)
    local parts = get_comment_parts(pos)
    per_line_parts[idx] = cache_parts(parts)
  end

  local function same_parts(a, b)
    return a.left == b.left and a.right == b.right
  end

  local new_lines = {}
  for i = 1, #lines do
    new_lines[i] = lines[i]
  end

  local i = 1
  while i <= #lines do
    local parts = per_line_parts[i]
    local j = i
    while j + 1 <= #lines and same_parts(per_line_parts[j + 1], parts) do
      j = j + 1
    end

    local slice = {}
    for k = i, j do
      slice[#slice + 1] = lines[k]
    end

    local indent, is_comment = get_lines_info(slice, parts)
    local fn = is_comment and make_uncomment_function(parts) or make_comment_function(parts, indent)
    for k = i, j do
      new_lines[k] = fn(lines[k])
    end

    i = j + 1
  end

  debug_log('toggle_result', line_start, line_end, table.concat(new_lines, '\\n'))
  vim._with({ lockmarks = true }, function()
    vim.api.nvim_buf_set_lines(0, line_start - 1, line_end, false, new_lines)
  end)
end


--- Operator which toggles user-supplied range of lines
---@param mode string?
---|"'line'"
---|"'char'"
---|"'block'"
local function operator(mode)
  -- Used without arguments as part of expression mapping. Otherwise it is
  -- called as 'operatorfunc'.
  if mode == nil then
    vim.o.operatorfunc = "v:lua.require'vim._comment'.operator"
    return 'g@'
  end

  -- Compute target range
  local mark_from, mark_to = "'[", "']"
  local lnum_from, col_from = vim.fn.line(mark_from), vim.fn.col(mark_from)
  local lnum_to, col_to = vim.fn.line(mark_to), vim.fn.col(mark_to)

  -- Do nothing if "from" mark is after "to" (like in empty textobject)
  if (lnum_from > lnum_to) or (lnum_from == lnum_to and col_from > col_to) then
    return
  end

  -- NOTE: use cursor position as reference for possibly computing local
  -- tree-sitter-based 'commentstring'. Recompute every time for a proper
  -- dot-repeat. Use the start of the operator range so Visual selections pick
  -- the left-most language region.
  local ref_col = math.max(col_from - 1, 0)
  local start_row = math.max(lnum_from - 1, 0)
  local end_row = math.max(lnum_to - 1, start_row)
  refresh_parser_range(start_row, end_row)
  debug_log('operator_start', lnum_from, lnum_to, ref_col)
  toggle_lines(lnum_from, lnum_to, { lnum_from, ref_col })
  debug_log('operator_end', lnum_from, lnum_to)
  return ''
end

--- Select contiguous commented lines at cursor
local function textobject()
  local lnum_cur = vim.fn.line('.')
  local parts = get_comment_parts({ lnum_cur, vim.fn.col('.') })
  local comment_check = make_comment_check(parts)

  if not comment_check(vim.fn.getline(lnum_cur)) then
    return
  end

  -- Compute commented range
  local lnum_from = lnum_cur
  while (lnum_from >= 2) and comment_check(vim.fn.getline(lnum_from - 1)) do
    lnum_from = lnum_from - 1
  end

  local lnum_to = lnum_cur
  local n_lines = vim.api.nvim_buf_line_count(0)
  while (lnum_to <= n_lines - 1) and comment_check(vim.fn.getline(lnum_to + 1)) do
    lnum_to = lnum_to + 1
  end

  -- Select range linewise for operator to act upon
  vim.cmd('normal! ' .. lnum_from .. 'GV' .. lnum_to .. 'G')
end

return { operator = operator, textobject = textobject, toggle_lines = toggle_lines }
