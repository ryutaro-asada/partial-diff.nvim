local api = vim.api
local fn = vim.fn
local M = {}
M.from = {}
M.to = {}
M.buf_from = nil
M.buf_to = nil
M.win_from = nil
M.win_to = nil

M.original_diffopt = nil

M.from_original = {}
M.to_original = {}

M.debug = false
M.log_file = nil
M.log_file_path = fn.stdpath('cache') .. '/partial-diff.log'

-- Default highlight colors
M.highlights = {
  line_change = { bg = nil, fg = nil, link = 'DiffChange' },
  line_add = { bg = nil, fg = nil, link = 'DiffAdd' },
  line_delete = { bg = nil, fg = nil, link = 'DiffDelete' },
  char_change = { bg = nil, fg = nil, link = 'DiffText' },
  char_add = { bg = '#2d5a2d', fg = '#a9dc76', link = nil },
  char_delete = { bg = '#5a2d2d', fg = '#ff6188', link = nil },
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
  return fn.fnamemodify(source, ":h:h")
end

M.check_vscode_diff = function()
  local plugin_root = M.get_plugin_root()
  local wrapper_script = plugin_root .. '/vscode-diff-wrapper.js'
  local node_modules = plugin_root .. '/node_modules'
  return fn.filereadable(wrapper_script) == 1 and fn.isdirectory(node_modules) == 1
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

  local temp_file = fn.tempname()
  local f = io.open(temp_file, 'w')
  if not f then
    return nil
  end

  local input_json = fn.json_encode(input_data)
  f:write(input_json)
  f:close()

  local cmd = string.format('cd %s && cat %s | node vscode-diff-wrapper.js 2>/dev/null',
    fn.shellescape(plugin_root), fn.shellescape(temp_file))

  local result = fn.system(cmd)
  os.remove(temp_file)

  if vim.v.shell_error ~= 0 then
    return nil
  end

  local success, data = pcall(fn.json_decode, result)
  if success then
    return data
  else
    return nil
  end
end

M.apply_diff_highlights = function(lines_from, lines_to)
  if not M.buf_from or not M.buf_to then
    return false
  end

  local result = M.run_vscode_diff(lines_from, lines_to, {
    ignoreTrimWhitespace = false,
    computeMoves = true,
  })

  if not result or not result.success then
    if M.debug then
      M.log("VSCode diff failed, falling back to Neovim diff")
    end
    api.nvim_win_set_option(M.win_from, 'diff', true)
    api.nvim_win_set_option(M.win_to, 'diff', true)
    vim.cmd('diffupdate')
    return false
  end

  api.nvim_win_set_option(M.win_from, 'diff', false)
  api.nvim_win_set_option(M.win_to, 'diff', false)

  local namespaces = {
    line = api.nvim_create_namespace('partial_diff_line'),
    char = api.nvim_create_namespace('partial_diff_char'),
    indent = api.nvim_create_namespace('partial_diff_indent'),
  }

  for _, ns in pairs(namespaces) do
    api.nvim_buf_clear_namespace(M.buf_from, ns, 0, -1)
    api.nvim_buf_clear_namespace(M.buf_to, ns, 0, -1)
  end

  if M.debug then
    M.log(string.format("Processing %d change block(s)", #result.changes))
  end

  -- Convert character position (1-based) to byte offset (0-based)
  -- VSCode uses character positions, Neovim uses byte offsets
  local function char_to_byte_offset(line_str, char_pos)
    if char_pos <= 1 then
      return 0
    end

    -- Use vim.str_byteindex for UTF-8 aware conversion
    -- char_pos is 1-based, vim.str_byteindex expects 0-based character index
    local ok, byte_idx = pcall(vim.str_byteindex, line_str, char_pos - 1)
    if ok then
      return byte_idx
    else
      -- Fallback if character position is out of range
      return math.min(#line_str, (char_pos > 1) and #line_str or 0)
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

    if line_num < 0 or line_num >= #lines then
      return
    end

    local line_content = lines[line_num + 1]
    api.nvim_buf_set_extmark(buf, ns, line_num, 0, {
      end_row = line_num,
      end_col = #line_content,
      hl_group = hl_group,
      hl_mode = 'combine',
      priority = 100,
    })
  end

  local function highlight_range(buf, ns, start_line, start_col, end_line, end_col, lines, hl_group)
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

    if start_line == end_line then
      local line_content = lines[start_line]
      local byte_start = char_to_byte_offset(line_content, start_col)
      local byte_end = char_to_byte_offset(line_content, end_col)

      if M.debug then
        local highlight_text = line_content:sub(byte_start + 1, byte_end)
        M.log(string.format("  %s: line %d, chars [%d-%d], bytes [%d-%d], text: '%s'",
          hl_group, start_line - 1, start_col, end_col, byte_start, byte_end, highlight_text))
      end

      vim.hl.range(
        buf, ns, hl_group,
        { start_line - 1, byte_start },
        { start_line - 1, byte_end },
        { regtype = 'v', inclusive = false, priority = 200 }
      )
    else
      if M.debug then
        M.log(string.format("  %s: multi-line range from line %d to %d", hl_group, start_line - 1, end_line - 1))
      end

      local start_line_content = lines[start_line]
      local end_line_content = lines[end_line]

      local byte_start = char_to_byte_offset(start_line_content, start_col)
      local byte_end = char_to_byte_offset(end_line_content, end_col)

      vim.hl.range(
        buf, ns, hl_group,
        { start_line - 1, byte_start },
        { end_line - 1, byte_end },
        { regtype = 'v', inclusive = false, priority = 200 }
      )
    end
  end

  for _, change in ipairs(result.changes) do
    local orig_start = change.originalRange.startLineNumber
    local orig_end = change.originalRange.endLineNumberExclusive - 1
    local mod_start = change.modifiedRange.startLineNumber
    local mod_end = change.modifiedRange.endLineNumberExclusive - 1

    for line = orig_start, orig_end do
      highlight_line(M.buf_from, namespaces.line, line - 1, lines_from, 'DiffChange')
    end

    for line = mod_start, mod_end do
      highlight_line(M.buf_to, namespaces.line, line - 1, lines_to, 'DiffChange')
    end

    if change.innerChanges and #change.innerChanges > 0 then
      if M.debug then
        M.log(string.format("  Processing %d inner change(s)", #change.innerChanges))
      end

      for _, inner in ipairs(change.innerChanges) do
        local orig = inner.originalRange
        local mod = inner.modifiedRange

        local is_empty_orig = (orig.startColumn == orig.endColumn) and
            (orig.startLineNumber == orig.endLineNumber)
        local is_empty_mod = (mod.startColumn == mod.endColumn) and
            (mod.startLineNumber == mod.endLineNumber)

        if is_empty_orig and not is_empty_mod then
          highlight_range(M.buf_to, namespaces.char,
            mod.startLineNumber, mod.startColumn,
            mod.endLineNumber, mod.endColumn,
            lines_to, 'DiffAdd')
        elseif not is_empty_orig and is_empty_mod then
          highlight_range(M.buf_from, namespaces.char,
            orig.startLineNumber, orig.startColumn,
            orig.endLineNumber, orig.endColumn,
            lines_from, 'DiffDelete')
        elseif not is_empty_orig and not is_empty_mod then
          highlight_range(M.buf_from, namespaces.char,
            orig.startLineNumber, orig.startColumn,
            orig.endLineNumber, orig.endColumn,
            lines_from, 'DiffText')
          highlight_range(M.buf_to, namespaces.char,
            mod.startLineNumber, mod.startColumn,
            mod.endLineNumber, mod.endColumn,
            lines_to, 'DiffText')
        end
      end
    else
      if M.debug then
        M.log("  No inner changes, highlighting entire lines")
      end
      for line = orig_start - 1, orig_end - 1 do
        highlight_line(M.buf_from, namespaces.line, line, lines_from, 'DiffChange')
      end
      for line = mod_start - 1, mod_end - 1 do
        highlight_line(M.buf_to, namespaces.line, line, lines_to, 'DiffChange')
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
  print("Stored " .. #M.from_original .. " lines in From buffer")
end

M.partial_diff_to = function(start_line, end_line)
  -- Clean up existing diff if present
  if M.buf_from and api.nvim_buf_is_valid(M.buf_from) then
    M.partial_diff_delete()
  end

  M.to_original = api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  print("Stored " .. #M.to_original .. " lines in To buffer")

  -- Setup highlights with user configuration
  M.setup_highlights()

  M.original_diffopt = vim.o.diffopt

  M.buf_from = api.nvim_create_buf(false, true)
  M.buf_to = api.nvim_create_buf(false, true)

  api.nvim_buf_set_lines(M.buf_from, 0, -1, false, M.from_original)
  api.nvim_buf_set_lines(M.buf_to, 0, -1, false, M.to_original)

  vim.cmd('tabnew')
  local diff_tabpage = api.nvim_get_current_tabpage()

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

  local original_ft = vim.bo.filetype
  if original_ft and original_ft ~= "" then
    api.nvim_buf_set_option(M.buf_from, 'filetype', original_ft)
    api.nvim_buf_set_option(M.buf_to, 'filetype', original_ft)
  end

  -- Auto cleanup when tab is closed
  api.nvim_create_autocmd("TabClosed", {
    pattern = tostring(diff_tabpage),
    callback = function()
      -- Only cleanup if buffers are still valid
      if M.buf_from and api.nvim_buf_is_valid(M.buf_from) then
        M.partial_diff_delete()
      end
    end,
    once = true,
  })

  if M.check_node() and M.check_vscode_diff() then
    M.apply_diff_highlights(M.from_original, M.to_original)
  else
    print("Using Neovim diff (install Node.js and run :PartialDiffInstallVSCode for better character-level diff)")

    vim.o.diffopt = "internal,filler,closeoff,hiddenoff,algorithm:patience,context:3,indent-heuristic"
    api.nvim_win_set_option(M.win_from, 'diff', true)
    api.nvim_win_set_option(M.win_to, 'diff', true)
    vim.cmd('diffupdate')
  end
end

M.partial_diff_delete = function()
  M.close_log()

  if M.original_diffopt then
    vim.o.diffopt = M.original_diffopt
    M.original_diffopt = nil
  end

  -- Close windows and tab
  if M.win_from and api.nvim_win_is_valid(M.win_from) then
    local tabs = api.nvim_list_tabpages()
    if #tabs > 1 then
      -- Disable autocmd to prevent infinite loop
      vim.cmd('noautocmd tabclose')
    else
      if api.nvim_win_is_valid(M.win_from) then
        api.nvim_win_close(M.win_from, true)
      end
      if M.win_to and api.nvim_win_is_valid(M.win_to) then
        api.nvim_win_close(M.win_to, true)
      end
    end
    M.win_from = nil
    M.win_to = nil
  end

  -- Delete buffers
  if M.buf_from and api.nvim_buf_is_valid(M.buf_from) then
    api.nvim_buf_delete(M.buf_from, { force = true })
    M.buf_from = nil
  end
  if M.buf_to and api.nvim_buf_is_valid(M.buf_to) then
    api.nvim_buf_delete(M.buf_to, { force = true })
    M.buf_to = nil
  end

  M.from_original = {}
  M.to_original = {}
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

  -- Highlight customization
  if opts.highlights then
    -- Merge user highlights with defaults
    for key, value in pairs(opts.highlights) do
      if M.highlights[key] then
        -- If user provides a table, merge it with defaults
        if type(value) == 'table' then
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
