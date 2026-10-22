-- Shared helpers for the partial-diff test suite.
local M = {}

M.root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')

M.ns = {
  line = vim.api.nvim_create_namespace('partial_diff_line'),
  char = vim.api.nvim_create_namespace('partial_diff_char'),
  move = vim.api.nvim_create_namespace('partial_diff_move'),
}

--- True when the vscode-diff engine can run (Node.js + installed package).
function M.has_vscode_diff()
  return vim.fn.executable('node') == 1
      and vim.fn.filereadable(M.root .. '/node_modules/vscode-diff/package.json') == 1
end

--- Load a fresh copy of the plugin module (module state is global) after
--- tearing down any diff view left by a previous test.
function M.fresh_plugin(opts)
  local old = package.loaded['partial-diff']
  if old then
    pcall(old.partial_diff_delete)
  end
  vim.cmd('silent! tabonly!')
  vim.cmd('silent! only!')
  vim.cmd('enew!')
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= vim.api.nvim_get_current_buf() then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
  package.loaded['partial-diff'] = nil
  local pd = require('partial-diff')
  if opts then
    pd.setup(opts)
  end
  return pd
end

--- Read a conflict-style fixture from test/ and return its FROM and TO lines.
function M.load_fixture(name)
  local all = vim.fn.readfile(M.root .. '/test/' .. name)
  local s, sep, e
  for i, l in ipairs(all) do
    if l == '<<<<<<< FROM' then
      s = i
    elseif l == '=======' then
      sep = i
    elseif l == '>>>>>>> TO' then
      e = i
    end
  end
  assert(s and sep and e, 'fixture ' .. name .. ' is missing conflict markers')
  return vim.list_slice(all, s + 1, sep - 1), vim.list_slice(all, sep + 1, e - 1)
end

--- Put `from` / `to` into two scratch buffers shown side by side and wire
--- them into the plugin state, without going through the commands.
function M.open_pair(pd, from, to)
  pd.buf_from = vim.api.nvim_create_buf(false, true)
  pd.buf_to = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(pd.buf_from, 0, -1, false, from)
  vim.api.nvim_buf_set_lines(pd.buf_to, 0, -1, false, to)
  vim.api.nvim_win_set_buf(0, pd.buf_from)
  pd.win_from = vim.api.nvim_get_current_win()
  vim.cmd('vsplit')
  pd.win_to = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(pd.win_to, pd.buf_to)
end

--- Highlighted text spans in `buf` for namespace `ns`.
--- Returns a list of { row = 1-based, text = string, group = hl_group }.
function M.spans(buf, ns)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    local row, col, d = m[2], m[3], m[4]
    if d.line_hl_group then
      -- full-line highlight
      out[#out + 1] = { row = row + 1, text = lines[row + 1] or '', group = d.line_hl_group, line = true }
    elseif d.hl_group then
      local end_col = d.end_col or col
      local text
      if (d.end_row or row) == row then
        text = (lines[row + 1] or ''):sub(col + 1, end_col)
      else
        text = (lines[row + 1] or ''):sub(col + 1)
      end
      out[#out + 1] = { row = row + 1, text = text, group = d.hl_group }
    end
  end
  return out
end

--- Highlight groups present on a 1-based `row` of `buf` in namespace `ns`.
function M.groups_on_row(buf, ns, row)
  local groups = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, { row - 1, 0 }, { row - 1, -1 }, { details = true })) do
    local group = m[4].line_hl_group or m[4].hl_group
    if group then
      groups[#groups + 1] = group
    end
  end
  return groups
end

--- Texts of all spans with the given group.
function M.texts(spans, group)
  local out = {}
  for _, s in ipairs(spans) do
    if s.group == group then
      out[#out + 1] = s.text
    end
  end
  return out
end

--- Virtual-text strings attached in namespace `ns` of `buf`.
function M.virt_texts(buf, ns)
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    if m[4].virt_text then
      out[#out + 1] = m[4].virt_text[1][1]
    end
  end
  return out
end

return M
