local api = vim.api
local fn = vim.fn
local M = {}
M.from = {}
M.to = {}
M.buf_from = nil
M.buf_to = nil
M.win_from = nil
M.win_to = nil
-- Tabpage handle of the open diff view, and the augroup that cleans it up.
M.tab = nil
M.augroup = nil
-- Filetype of the buffer the From range was taken from.
M.from_ft = nil
-- Per diff buffer: buffer row -> original line number (nil for filler rows),
-- used by the line-number column. See M.line_label().
M.row_lines = {}
M.lnum_width = 3

M.original_diffopt = nil

M.from_original = {}
M.to_original = {}
M.has_from = false

M.debug = false
M.log_file = nil
M.log_file_path = fn.stdpath('cache') .. '/partial-diff.log'

-- Diff computation options
M.diff = {
  -- Ignore leading/trailing whitespace differences (vscode-diff).
  ignore_trim_whitespace = false,
  -- Detect moved code blocks (vscode-diff). Enables the `moves` output and
  -- a dedicated "moved" highlight/marker instead of change highlighting.
  compute_moves = false,
  -- Align corresponding lines between From and To by inserting filler rows
  -- (like diff mode), so both windows scroll in lockstep. Applies to the
  -- vscode-diff path.
  align = true,
  -- Keep the From/To windows scroll- and cursor-synced (like diff mode).
  -- Applies to the vscode-diff path; the built-in diff fallback already
  -- syncs scrolling on its own.
  sync_scroll = true,
  -- When sync_scroll is on, also turn off 'wrap' in both windows so that
  -- horizontal scrolling actually happens (and stays mirrored). Set to
  -- false to keep your wrap setting at the cost of no horizontal sync.
  sync_scroll_nowrap = true,
  -- diffopt used for the built-in Neovim diff fallback.
  fallback_diffopt =
  "internal,filler,closeoff,hiddenoff,algorithm:histogram,linematch:60,context:3,indent-heuristic",
}

-- Default highlight colors
M.highlights = {
  line_change = { bg = nil, fg = nil, link = 'DiffChange' },
  line_add = { bg = nil, fg = nil, link = 'DiffAdd' },
  line_delete = { bg = nil, fg = nil, link = 'DiffDelete' },
  char_change = { bg = nil, fg = nil, link = 'DiffText' },
  char_add = { bg = '#2d5a2d', fg = '#a9dc76', link = nil },
  char_delete = { bg = '#5a2d2d', fg = '#ff6188', link = nil },
  line_move = { bg = '#2d3a5a', fg = '#78a9ff', link = nil },
  filler = { bg = nil, fg = nil, link = 'DiffDelete' },
}

-- Setup highlight groups based on user configuration
M.setup_highlights = function()
  local groups = {
    { name = 'PartialDiffLineChange', config = M.highlights.line_change },
    { name = 'PartialDiffLineAdd',    config = M.highlights.line_add },
    { name = 'PartialDiffLineDelete', config = M.highlights.line_delete },
    { name = 'PartialDiffCharChange', config = M.highlights.char_change },
    { name = 'PartialDiffCharAdd',    config = M.highlights.char_add },
    { name = 'PartialDiffCharDelete', config = M.highlights.char_delete },
    { name = 'PartialDiffLineMove',   config = M.highlights.line_move },
    { name = 'PartialDiffFiller',     config = M.highlights.filler },
  }

  for _, group in ipairs(groups) do
    local hl_def = {}

    if group.config.link then
      vim.api.nvim_set_hl(0, group.name, { link = group.config.link })
    else
      if group.config.bg then
        hl_def.bg = group.config.bg
      end
      if group.config.fg then
        hl_def.fg = group.config.fg
      end
      if group.config.bold ~= nil then
        hl_def.bold = group.config.bold
      end
      if group.config.italic ~= nil then
        hl_def.italic = group.config.italic
      end
      if group.config.underline ~= nil then
        hl_def.underline = group.config.underline
      end

      if next(hl_def) ~= nil then
        vim.api.nvim_set_hl(0, group.name, hl_def)
      end
    end
  end
end

M.init_log = function()
  if M.debug and not M.log_file then
    M.log_file = io.open(M.log_file_path, 'a')
    if M.log_file then
      M.log_file:write("\n=== Partial Diff Session Started: " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
      M.log_file:flush()
    end
  end
end

M.close_log = function()
  if M.log_file then
    M.log_file:write("=== Session Ended: " .. os.date("%Y-%m-%d %H:%M:%S") .. " ===\n")
    M.log_file:close()
    M.log_file = nil
  end
end

M.log = function(msg)
  if M.debug then
    M.init_log()
    if M.log_file then
      M.log_file:write(os.date("[%H:%M:%S] ") .. msg .. "\n")
      M.log_file:flush()
    else
      print("[PartialDiff] " .. msg)
    end
  end
end

M.get_plugin_root = function()
  local source = debug.getinfo(1, "S").source
  if source:sub(1, 1) == "@" then
    source = source:sub(2)
  end
  -- Resolve to an absolute path first so that a relative 'runtimepath'
  -- entry (e.g. ".") does not produce a broken plugin root. The file lives
  -- at <root>/lua/partial-diff/init.lua, so strip three path components.
  return fn.fnamemodify(source, ":p:h:h:h")
end

M.check_vscode_diff = function()
  local plugin_root = M.get_plugin_root()
  local wrapper_script = plugin_root .. '/vscode-diff-wrapper.js'
  -- Check for the actual vscode-diff package rather than just the
  -- node_modules directory, which may exist but be empty/incomplete.
  local vscode_diff_pkg = plugin_root .. '/node_modules/vscode-diff/package.json'
  return fn.filereadable(wrapper_script) == 1 and fn.filereadable(vscode_diff_pkg) == 1
end

M.check_node = function()
  return fn.executable('node') == 1
end

M.install_vscode_diff = function()
  if not M.check_node() then
    print("Error: Node.js is required but not found. Please install Node.js first.")
    return false
  end

  local plugin_root = M.get_plugin_root()
  local package_file = plugin_root .. '/package.json'
  local wrapper_script = plugin_root .. '/vscode-diff-wrapper.js'

  if fn.filereadable(package_file) == 0 then
    print("Error: package.json not found in plugin root: " .. plugin_root)
    print("Please ensure package.json and vscode-diff-wrapper.js are in the repository root.")
    return false
  end

  if fn.filereadable(wrapper_script) == 0 then
    print("Error: vscode-diff-wrapper.js not found in plugin root: " .. plugin_root)
    print("Please ensure package.json and vscode-diff-wrapper.js are in the repository root.")
    return false
  end

  local cmd = string.format('cd %s && npm install 2>&1', fn.shellescape(plugin_root))
  local result = fn.system(cmd)

  if vim.v.shell_error == 0 then
    print("vscode-diff installed successfully!")
    return true
  else
    print("Failed to install vscode-diff: " .. result)
    return false
  end
end

M.run_vscode_diff = function(lines_from, lines_to, options)
  local plugin_root = M.get_plugin_root()
  local wrapper_script = plugin_root .. '/vscode-diff-wrapper.js'

  if fn.filereadable(wrapper_script) == 0 then
    print("VSCode diff not installed. Run :PartialDiffInstallVSCode first")
    return nil
  end

  local input_data = {
    original = lines_from,
    modified = lines_to,
    options = options or {}
  }

  local input_json = fn.json_encode(input_data)

  -- Call node directly with the wrapper script as an argument and feed the
  -- JSON payload via stdin. Using the list form of vim.fn.system avoids
  -- shell interpretation (no quoting/injection issues) and does not depend
  -- on the current working directory.
  local result = fn.system({ 'node', wrapper_script }, input_json)

  if vim.v.shell_error ~= 0 then
    if M.debug then
      M.log("vscode-diff-wrapper exited with error: " .. tostring(result))
    end
    return nil
  end

  local success, data = pcall(fn.json_decode, result)
  if success then
    return data
  else
    if M.debug then
      M.log("Failed to decode vscode-diff output: " .. tostring(result))
    end
    return nil
  end
end

-- Build row-aligned copies of both sides from vscode-diff's `changes`.
-- Unchanged lines are paired 1:1; within a change block the shorter side is
-- padded with filler rows at the end of the block, so line N on the left
-- always corresponds to line N on the right (like diff mode's filler lines).
--
-- Returns a table with:
--   from, to             aligned buffer contents (filler rows are "")
--   from_rows, to_rows   original line -> 1-based buffer row
--   from_filler, to_filler  list of 1-based buffer rows that are filler
M.align_lines = function(lines_from, lines_to, changes)
  local r = { from = {}, to = {}, from_rows = {}, to_rows = {}, from_filler = {}, to_filler = {} }

  -- Emit one aligned row; `fl` / `tl` are original line numbers or nil.
  local function emit(fl, tl)
    r.from[#r.from + 1] = fl and lines_from[fl] or ''
    r.to[#r.to + 1] = tl and lines_to[tl] or ''
    local row = #r.from
    if fl then r.from_rows[fl] = row else r.from_filler[#r.from_filler + 1] = row end
    if tl then r.to_rows[tl] = row else r.to_filler[#r.to_filler + 1] = row end
  end

  -- Emit original lines [i, i_end) and [j, j_end) side by side, padding the
  -- shorter side with filler rows.
  local function emit_block(i, i_end, j, j_end)
    local n = math.max(i_end - i, j_end - j)
    for k = 0, n - 1 do
      emit(i + k < i_end and i + k or nil, j + k < j_end and j + k or nil)
    end
  end

  local i, j = 1, 1
  for _, c in ipairs(changes or {}) do
    local os, oe = c.originalRange.startLineNumber, c.originalRange.endLineNumberExclusive
    local ms, me = c.modifiedRange.startLineNumber, c.modifiedRange.endLineNumberExclusive
    emit_block(i, os, j, ms) -- unchanged lines before the block
    emit_block(os, oe, ms, me) -- the change block itself
    i, j = oe, me
  end
  emit_block(i, #lines_from + 1, j, #lines_to + 1) -- unchanged tail

  return r
end

-- Text for the line-number column of a diff window: the original line
-- number of `row` in `buf`, or blank for filler rows.
M.line_label = function(buf, row)
  local map = M.row_lines[buf]
  local line
  if map then
    line = map[row]
  else
    line = row
  end
  return string.format('%' .. M.lnum_width .. 's', line and tostring(line) or '')
end

-- 'statuscolumn' callback for the diff windows. It runs inside a %{}
-- item, where the window being drawn is temporarily the current window
-- (g:statusline_winid is only set for %! expressions).
M.statuscolumn = function()
  if vim.v.virtnum ~= 0 then
    return string.rep(' ', M.lnum_width)
  end
  local win = vim.g.statusline_winid
  local buf = (win and api.nvim_win_is_valid(win)) and api.nvim_win_get_buf(win) or api.nvim_get_current_buf()
  return M.line_label(buf, vim.v.lnum)
end

M.apply_diff_highlights = function(lines_from, lines_to)
  if not M.buf_from or not M.buf_to then
    return false
  end

  local result = M.run_vscode_diff(lines_from, lines_to, {
    ignoreTrimWhitespace = M.diff.ignore_trim_whitespace,
    computeMoves = M.diff.compute_moves,
  })

  if not result or not result.success then
    if M.debug then
      M.log("VSCode diff failed, falling back to Neovim diff")
    end
    -- Use the same diffopt as the regular fallback path.
    M.original_diffopt = M.original_diffopt or vim.o.diffopt
    vim.o.diffopt = M.diff.fallback_diffopt
    vim.wo[M.win_from].diff = true
    vim.wo[M.win_to].diff = true
    vim.cmd('diffupdate')
    return false
  end

  vim.wo[M.win_from].diff = false
  vim.wo[M.win_to].diff = false

  local namespaces = {
    line = api.nvim_create_namespace('partial_diff_line'),
    char = api.nvim_create_namespace('partial_diff_char'),
    indent = api.nvim_create_namespace('partial_diff_indent'),
    move = api.nvim_create_namespace('partial_diff_move'),
    filler = api.nvim_create_namespace('partial_diff_filler'),
  }

  for _, ns in pairs(namespaces) do
    api.nvim_buf_clear_namespace(M.buf_from, ns, 0, -1)
    api.nvim_buf_clear_namespace(M.buf_to, ns, 0, -1)
  end

  -- Row alignment. All highlights below are computed on original line
  -- numbers and placed via these maps (original line -> 1-based buffer row).
  local from_rows, to_rows = {}, {}
  M.row_lines[M.buf_from] = nil
  M.row_lines[M.buf_to] = nil
  if M.diff.align then
    local aligned = M.align_lines(lines_from, lines_to, result.changes)
    api.nvim_buf_set_lines(M.buf_from, 0, -1, false, aligned.from)
    api.nvim_buf_set_lines(M.buf_to, 0, -1, false, aligned.to)
    from_rows, to_rows = aligned.from_rows, aligned.to_rows

    -- Draw filler rows like diff mode: filled with the 'fillchars' diff
    -- character, fixed to the window so it doesn't scroll horizontally.
    local fill = (vim.opt.fillchars:get().diff or '-'):rep(500)
    for _, side in ipairs({ { M.buf_from, aligned.from_filler }, { M.buf_to, aligned.to_filler } }) do
      for _, row in ipairs(side[2]) do
        api.nvim_buf_set_extmark(side[1], namespaces.filler, row - 1, 0, {
          line_hl_group = 'PartialDiffFiller',
          virt_text = { { fill, 'PartialDiffFiller' } },
          virt_text_win_col = 0,
          priority = 100,
        })
      end
    end

    -- Show original line numbers (blank on filler rows) in windows that
    -- display line numbers.
    local function invert(map)
      local inv = {}
      for line, row in pairs(map) do inv[row] = line end
      return inv
    end
    M.row_lines[M.buf_from] = invert(from_rows)
    M.row_lines[M.buf_to] = invert(to_rows)
    M.lnum_width = math.max(#tostring(#lines_from), #tostring(#lines_to),
      vim.wo[M.win_from].numberwidth - 1)
    for _, win in ipairs({ M.win_from, M.win_to }) do
      if vim.wo[win].number or vim.wo[win].relativenumber then
        vim.wo[win].statuscolumn = "%s%#LineNr#%{v:lua.require'partial-diff'.statuscolumn()} "
      end
    end
  else
    for l = 1, #lines_from do from_rows[l] = l end
    for l = 1, #lines_to do to_rows[l] = l end
  end

  local function rows_for(buf)
    return buf == M.buf_from and from_rows or to_rows
  end

  if M.debug then
    M.log(string.format("Processing %d change block(s)", #result.changes))
  end

  -- Convert a VSCode column (1-based) to a Neovim byte offset (0-based).
  -- VSCode columns are counted in UTF-16 code units, whereas Neovim's
  -- extmark/highlight APIs expect byte offsets. We therefore ask
  -- vim.str_byteindex to interpret the index as UTF-16.
  local function char_to_byte_offset(line_str, char_pos)
    if char_pos <= 1 then
      return 0
    end

    local utf16_index = char_pos - 1

    -- Neovim 0.11+ signature: str_byteindex(s, encoding, index[, strict])
    local ok, byte_idx = pcall(vim.str_byteindex, line_str, 'utf-16', utf16_index, false)
    if not ok then
      -- Neovim 0.10 signature: str_byteindex(s, index[, use_utf16])
      ok, byte_idx = pcall(vim.str_byteindex, line_str, utf16_index, true)
    end

    if ok and byte_idx then
      return byte_idx
    else
      -- Fallback: clamp to end of line if the position is out of range
      return #line_str
    end
  end

  local function highlight_line(buf, ns, line_num, lines, hl_group)
    -- Map diff highlight groups to our custom groups
    local group_map = {
      DiffChange = 'PartialDiffLineChange',
      DiffAdd = 'PartialDiffLineAdd',
      DiffDelete = 'PartialDiffLineDelete',
    }
    hl_group = group_map[hl_group] or hl_group

    local row = rows_for(buf)[line_num + 1]
    if not row then
      return
    end

    -- line_hl_group colors the whole screen line (like diff mode), so empty
    -- lines and the area past the end of the text are highlighted too.
    api.nvim_buf_set_extmark(buf, ns, row - 1, 0, {
      line_hl_group = hl_group,
      priority = 100,
    })
  end

  -- vim.hl is the 0.11+ name; 0.10 only has vim.highlight.
  local hl = vim.hl or vim.highlight

  -- Highlight a (possibly multi-line) character range. The range is drawn
  -- line by line so that lines listed in `skip` (1-based line -> true) can be
  -- left alone, e.g. lines that belong to a detected move.
  local function highlight_range(buf, ns, start_line, start_col, end_line, end_col, lines, hl_group, skip)
    -- Map diff highlight groups to our custom groups
    local group_map = {
      DiffText = 'PartialDiffCharChange',
      DiffAdd = 'PartialDiffCharAdd',
      DiffDelete = 'PartialDiffCharDelete',
    }
    hl_group = group_map[hl_group] or hl_group

    if start_line < 1 or end_line < 1 or start_line > #lines or end_line > #lines then
      if M.debug then
        M.log(string.format("Invalid range: lines %d-%d (total: %d)", start_line, end_line, #lines))
      end
      return
    end

    for line = start_line, end_line do
      if not (skip and skip[line]) then
        local content = lines[line]
        local byte_start = (line == start_line) and char_to_byte_offset(content, start_col) or 0
        local byte_end = (line == end_line) and char_to_byte_offset(content, end_col) or #content

        if M.debug then
          M.log(string.format("  %s: line %d, bytes [%d-%d], text: '%s'",
            hl_group, line - 1, byte_start, byte_end, content:sub(byte_start + 1, byte_end)))
        end

        if byte_end > byte_start then
          local row = rows_for(buf)[line] - 1
          hl.range(
            buf, ns, hl_group,
            { row, byte_start },
            { row, byte_end },
            { regtype = 'v', inclusive = false, priority = 200 }
          )
        end
      end
    end
  end

  -- Render one character-level change (an `innerChanges` entry).
  local function render_inner(inner, skip_from, skip_to)
    local orig = inner.originalRange
    local mod = inner.modifiedRange

    local is_empty_orig = (orig.startColumn == orig.endColumn) and
        (orig.startLineNumber == orig.endLineNumber)
    local is_empty_mod = (mod.startColumn == mod.endColumn) and
        (mod.startLineNumber == mod.endLineNumber)

    if is_empty_orig and not is_empty_mod then
      highlight_range(M.buf_to, namespaces.char,
        mod.startLineNumber, mod.startColumn, mod.endLineNumber, mod.endColumn,
        lines_to, 'DiffAdd', skip_to)
    elseif not is_empty_orig and is_empty_mod then
      highlight_range(M.buf_from, namespaces.char,
        orig.startLineNumber, orig.startColumn, orig.endLineNumber, orig.endColumn,
        lines_from, 'DiffDelete', skip_from)
    elseif not is_empty_orig and not is_empty_mod then
      highlight_range(M.buf_from, namespaces.char,
        orig.startLineNumber, orig.startColumn, orig.endLineNumber, orig.endColumn,
        lines_from, 'DiffText', skip_from)
      highlight_range(M.buf_to, namespaces.char,
        mod.startLineNumber, mod.startColumn, mod.endLineNumber, mod.endColumn,
        lines_to, 'DiffText', skip_to)
    end
  end

  -- Lines covered by a detected move. The regular change list still reports
  -- these lines as deleted/inserted; we skip them there and let the move
  -- renderer below draw them instead, so the move highlight stays visible.
  local moved_from, moved_to = {}, {}
  if M.diff.compute_moves and result.moves then
    for _, move in ipairs(result.moves) do
      local lrm = move.lineRangeMapping
      if lrm and lrm.original and lrm.modified then
        for l = lrm.original.startLineNumber, lrm.original.endLineNumberExclusive - 1 do
          moved_from[l] = true
        end
        for l = lrm.modified.startLineNumber, lrm.modified.endLineNumberExclusive - 1 do
          moved_to[l] = true
        end
      end
    end
  end

  for _, change in ipairs(result.changes) do
    local orig_start = change.originalRange.startLineNumber
    local orig_end = change.originalRange.endLineNumberExclusive - 1
    local mod_start = change.modifiedRange.startLineNumber
    local mod_end = change.modifiedRange.endLineNumberExclusive - 1

    -- A block with an empty original range is a pure insertion (only the To
    -- side has lines); an empty modified range is a pure deletion.
    local from_group, to_group = 'DiffChange', 'DiffChange'
    if orig_start > orig_end then
      to_group = 'DiffAdd'
    elseif mod_start > mod_end then
      from_group = 'DiffDelete'
    end

    for line = orig_start, orig_end do
      if not moved_from[line] then
        highlight_line(M.buf_from, namespaces.line, line - 1, lines_from, from_group)
      end
    end

    for line = mod_start, mod_end do
      if not moved_to[line] then
        highlight_line(M.buf_to, namespaces.line, line - 1, lines_to, to_group)
      end
    end

    if change.innerChanges and #change.innerChanges > 0 then
      if M.debug then
        M.log(string.format("  Processing %d inner change(s)", #change.innerChanges))
      end

      for _, inner in ipairs(change.innerChanges) do
        render_inner(inner, moved_from, moved_to)
      end
    elseif M.debug then
      -- No inner changes: the line-level highlights applied above are sufficient.
      M.log("  No inner changes, line-level highlight only")
    end
  end

  -- Render detected moves (only populated when compute_moves is enabled).
  if M.diff.compute_moves and result.moves and #result.moves > 0 then
    if M.debug then
      M.log(string.format("Processing %d move(s)", #result.moves))
    end

    for move_idx, move in ipairs(result.moves) do
      local lrm = move.lineRangeMapping
      if lrm and lrm.original and lrm.modified then
        local orig_start = lrm.original.startLineNumber
        local orig_end = lrm.original.endLineNumberExclusive - 1
        local mod_start = lrm.modified.startLineNumber
        local mod_end = lrm.modified.endLineNumberExclusive - 1

        -- Highlight the moved block on both sides with the move group.
        for line = orig_start, orig_end do
          highlight_line(M.buf_from, namespaces.move, line - 1, lines_from, 'PartialDiffLineMove')
        end
        for line = mod_start, mod_end do
          highlight_line(M.buf_to, namespaces.move, line - 1, lines_to, 'PartialDiffLineMove')
        end

        -- A moved block may also contain edits. vscode-diff reports these as
        -- `move.changes` (with character-level `innerChanges`). Render them on
        -- top of the move highlight so "moved + modified" is distinguishable
        -- from a pure move.
        for _, mchange in ipairs(move.changes or {}) do
          for _, inner in ipairs(mchange.innerChanges or {}) do
            render_inner(inner, nil, nil)
          end
        end

        -- Add a virtual-text marker pointing to the counterpart location.
        -- The text uses original line numbers (as shown in the number column).
        if from_rows[orig_start] then
          api.nvim_buf_set_extmark(M.buf_from, namespaces.move, from_rows[orig_start] - 1, 0, {
            virt_text = { { string.format(' ↓ moved to line %d', mod_start), 'PartialDiffLineMove' } },
            virt_text_pos = 'eol',
            priority = 250,
          })
        end
        if to_rows[mod_start] then
          api.nvim_buf_set_extmark(M.buf_to, namespaces.move, to_rows[mod_start] - 1, 0, {
            virt_text = { { string.format(' ↑ moved from line %d', orig_start), 'PartialDiffLineMove' } },
            virt_text_pos = 'eol',
            priority = 250,
          })
        end

        if M.debug then
          M.log(string.format("  Move %d: original %d-%d -> modified %d-%d",
            move_idx, orig_start, orig_end, mod_start, mod_end))
        end
      end
    end
  end

  if M.debug then
    local summary = string.format("Diff complete: %d change block(s) processed", #result.changes)
    print(summary)
    M.log(summary)

    local direction
    if #lines_from < #lines_to then
      direction = "Direction: From → To (additions detected)"
    elseif #lines_from > #lines_to then
      direction = "Direction: From → To (deletions detected)"
    else
      direction = "Direction: From → To (modifications only)"
    end
    print(direction)
    M.log(direction)
  end

  return true
end

-- Keep the From/To windows scrolling (and cursor) in sync in the
-- vscode-diff path, mimicking what diff mode does automatically.
M.enable_scroll_sync = function()
  if not M.diff.sync_scroll then
    return
  end
  if not (M.win_from and api.nvim_win_is_valid(M.win_from)
        and M.win_to and api.nvim_win_is_valid(M.win_to)) then
    return
  end

  -- scrollbind needs 'ver' in scrollopt for vertical sync and 'hor' for
  -- horizontal sync. Ensure both are present.
  M.original_scrollopt = vim.o.scrollopt
  local function ensure_scrollopt(flag)
    if not string.find(vim.o.scrollopt, flag) then
      vim.o.scrollopt = (vim.o.scrollopt == '' and flag) or (vim.o.scrollopt .. ',' .. flag)
    end
  end
  ensure_scrollopt('ver')
  ensure_scrollopt('hor')

  for _, win in ipairs({ M.win_from, M.win_to }) do
    vim.wo[win].scrollbind = true
    vim.wo[win].cursorbind = true
    -- Horizontal scrollbind only has an effect when lines are not wrapped;
    -- with 'wrap' on there is no horizontal scroll to mirror.
    if M.diff.sync_scroll_nowrap then
      vim.wo[win].wrap = false
    end
  end

  -- Align both windows to the top and resync their scroll positions.
  api.nvim_win_call(M.win_from, function()
    vim.cmd('normal! gg')
    vim.cmd('syncbind')
  end)
end

M.show_log = function()
  if fn.filereadable(M.log_file_path) == 1 then
    vim.cmd('split ' .. M.log_file_path)
    vim.cmd('setlocal autoread')
    vim.cmd('normal G')
  else
    print("No log file found. Enable debug mode and run a diff first.")
  end
end

M.clear_log = function()
  M.close_log()
  local f = io.open(M.log_file_path, 'w')
  if f then
    f:close()
    print("Log file cleared: " .. M.log_file_path)
  end
end

M.partial_diff_from = function(start_line, end_line)
  M.from_original = api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  M.from_ft = vim.bo.filetype
  M.has_from = true
  print("Stored " .. #M.from_original .. " lines in From buffer")
end

M.partial_diff_to = function(start_line, end_line)
  -- Require a source range to have been marked first
  if not M.has_from then
    api.nvim_echo({ {
      "[PartialDiff] No source range marked. Run :PartialDiffFrom first.",
      "ErrorMsg",
    } }, true, {})
    return
  end

  -- Capture the To range from the current buffer before touching any
  -- windows: closing a previous diff view could change the current buffer.
  local to_lines = api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  local to_ft = vim.bo.filetype

  -- Close a previous diff view if one is open. This keeps the marked From
  -- range (unlike :PartialDiffDelete, which also forgets it).
  M.close_view()

  M.to_original = to_lines
  print("Stored " .. #M.to_original .. " lines in To buffer")

  -- Setup highlights with user configuration
  M.setup_highlights()

  M.original_diffopt = vim.o.diffopt

  M.buf_from = api.nvim_create_buf(false, true)
  M.buf_to = api.nvim_create_buf(false, true)

  api.nvim_buf_set_lines(M.buf_from, 0, -1, false, M.from_original)
  api.nvim_buf_set_lines(M.buf_to, 0, -1, false, M.to_original)

  vim.cmd('tabnew')
  M.tab = api.nvim_get_current_tabpage()

  api.nvim_set_current_buf(M.buf_from)
  M.win_from = api.nvim_get_current_win()

  M.win_to = api.nvim_open_win(M.buf_to, true, {
    split = 'right',
    win = M.win_from
  })
  api.nvim_set_current_buf(M.buf_to)
  M.win_to = api.nvim_get_current_win()

  vim.cmd('wincmd h')

  api.nvim_buf_set_name(M.buf_from, "[Partial Diff From]")
  api.nvim_buf_set_name(M.buf_to, "[Partial Diff To]")

  -- Use the filetypes of the buffers the ranges were taken from, so the diff
  -- gets syntax highlighting.
  if M.from_ft and M.from_ft ~= "" then
    vim.bo[M.buf_from].filetype = M.from_ft
  end
  if to_ft ~= "" then
    vim.bo[M.buf_to].filetype = to_ft
  end

  -- Clean up when the diff tab is closed by any means (:tabclose, :q, ...).
  -- TabClosed's pattern is a tab *number*, which does not match the tabpage
  -- handle, so listen to every TabClosed and check whether our tab is gone.
  -- The closed tab's handle is still valid while TabClosed runs, so the
  -- check is deferred until after the close has completed.
  local diff_tab = M.tab
  M.augroup = api.nvim_create_augroup('PartialDiffCleanup', { clear = true })
  api.nvim_create_autocmd("TabClosed", {
    group = M.augroup,
    callback = function()
      vim.schedule(function()
        if M.tab == diff_tab and not api.nvim_tabpage_is_valid(diff_tab) then
          M.partial_diff_delete()
        end
      end)
    end,
  })

  if M.check_node() and M.check_vscode_diff() then
    M.apply_diff_highlights(M.from_original, M.to_original)
    M.enable_scroll_sync()
  else
    print("Using Neovim diff (install Node.js and run :PartialDiffInstallVSCode for better character-level diff)")

    vim.o.diffopt = M.diff.fallback_diffopt
    vim.wo[M.win_from].diff = true
    vim.wo[M.win_to].diff = true
    vim.cmd('diffupdate')
  end
end

-- Close the diff view (its tab, windows and scratch buffers) and restore the
-- global options we changed. Keeps the marked From range.
M.close_view = function()
  M.close_log()

  if M.augroup then
    pcall(api.nvim_del_augroup_by_id, M.augroup)
    M.augroup = nil
  end

  if M.original_diffopt then
    vim.o.diffopt = M.original_diffopt
    M.original_diffopt = nil
  end

  if M.original_scrollopt ~= nil then
    vim.o.scrollopt = M.original_scrollopt
    M.original_scrollopt = nil
  end

  -- Close only the diff's own tab, never whichever tab happens to be current.
  if M.tab and api.nvim_tabpage_is_valid(M.tab) then
    if #api.nvim_list_tabpages() > 1 then
      vim.cmd('noautocmd tabclose ' .. api.nvim_tabpage_get_number(M.tab))
    else
      -- The diff tab is the only tab left: close its extra windows, and swap
      -- the last one to an empty buffer instead of closing it (closing the
      -- last window is an error). That window stays around as a normal
      -- window, so undo the diff-view window options we set on it.
      for _, win in ipairs({ M.win_to, M.win_from }) do
        if win and api.nvim_win_is_valid(win) then
          if #api.nvim_tabpage_list_wins(M.tab) > 1 then
            api.nvim_win_close(win, true)
          else
            api.nvim_win_call(win, function()
              vim.cmd('enew')
              vim.cmd('diffoff')
            end)
            vim.wo[win].scrollbind = false
            vim.wo[win].cursorbind = false
            vim.wo[win].wrap = vim.go.wrap
            vim.wo[win].statuscolumn = vim.go.statuscolumn
          end
        end
      end
    end
  end
  M.tab = nil
  M.win_from = nil
  M.win_to = nil

  -- Delete buffers
  if M.buf_from and api.nvim_buf_is_valid(M.buf_from) then
    api.nvim_buf_delete(M.buf_from, { force = true })
  end
  if M.buf_to and api.nvim_buf_is_valid(M.buf_to) then
    api.nvim_buf_delete(M.buf_to, { force = true })
  end
  M.buf_from = nil
  M.buf_to = nil
  M.row_lines = {}
end

-- :PartialDiffDelete — close the view and forget the marked ranges.
M.partial_diff_delete = function()
  M.close_view()

  M.from_original = {}
  M.to_original = {}
  M.from_ft = nil
  M.has_from = false
end

M.setup = function(opts)
  opts = opts or {}
  M.config = opts

  -- Debug settings
  if opts.debug ~= nil then
    M.debug = opts.debug
  end
  if opts.log_file_path then
    M.log_file_path = opts.log_file_path
  end

  -- Diff computation settings
  if opts.diff then
    for key, value in pairs(opts.diff) do
      if M.diff[key] ~= nil then
        M.diff[key] = value
      end
    end
  end

  -- Highlight customization
  if opts.highlights then
    -- Merge user highlights with defaults
    for key, value in pairs(opts.highlights) do
      if M.highlights[key] then
        -- If user provides a table, merge it with defaults
        if type(value) == 'table' then
          -- Explicit colors/styles must replace the default link; otherwise
          -- setup_highlights() would apply the link and ignore them.
          if value.link == nil and next(value) ~= nil then
            M.highlights[key].link = nil
          end
          for k, v in pairs(value) do
            M.highlights[key][k] = v
          end
          -- If user provides a string, treat it as a link
        elseif type(value) == 'string' then
          M.highlights[key] = { link = value }
        end
      end
    end
  end

  -- Setup highlights immediately if plugin is already loaded
  if vim.fn.has('vim_starting') == 0 then
    M.setup_highlights()
  end
end

M.setup({})

return M
