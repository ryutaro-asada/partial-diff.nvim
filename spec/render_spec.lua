-- Rendering tests: these read the colors Neovim actually draws, so they catch
-- highlights that exist as extmarks but are hidden by another highlight
-- (e.g. a line highlight covering character highlights, fixed in #17).
--
-- Every highlight option is linked to a test group with a distinct bg, so a
-- drawn color tells exactly which highlight won on that cell.
local helpers = require('helpers')

local it_vs = helpers.has_vscode_diff() and it or pending

local C = {
  line_change = 0x111111,
  line_add = 0x121212,
  line_delete = 0x131313,
  char_change = 0x222222,
  char_add = 0x232323,
  char_delete = 0x242424,
  line_move = 0x333333,
  filler = 0x444444,
}

local function hex(n)
  return n and string.format('#%06x', n) or 'none'
end

local function render(from, to, diff_opts)
  vim.o.termguicolors = true
  local highlights = {}
  for name, bg in pairs(C) do
    local group = 'PdRender_' .. name
    vim.api.nvim_set_hl(0, group, { bg = bg })
    highlights[name] = group
  end
  local pd = helpers.fresh_plugin({ diff = diff_opts, highlights = highlights })
  vim.o.columns = 200
  helpers.open_pair(pd, from, to)
  vim.wo[pd.win_from].wrap = false
  vim.wo[pd.win_to].wrap = false
  pd.setup_highlights()
  assert.is_true(pd.apply_diff_highlights(from, to))
  return pd
end

local function assert_bg(expected, win, row, col, what)
  local got = helpers.drawn_bg(win, row, col)
  assert(got == expected, ('%s: expected %s, drawn %s'):format(what, hex(expected), hex(got)))
end

-- 0-based text column of `needle` in buffer row `row` of `buf`.
local function col_of(buf, row, needle)
  local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
  local s = assert(line:find(needle, 1, true), needle .. ' not found in ' .. line)
  return s - 1
end

describe('rendering', function()
  describe('changed lines', function()
    it_vs('draws character highlights on top of the line highlight', function()
      local pd = render({ 'a', 'foo bar', 'c' }, { 'a', 'foo baz', 'c' })
      assert_bg(C.line_change, pd.win_to, 2, 0, '"f" (line only)')
      assert_bg(C.char_change, pd.win_to, 2, 6, '"z" (changed char)')
      assert_bg(C.char_change, pd.win_from, 2, 6, '"r" on From (changed char)')
      assert_bg(C.line_change, pd.win_to, 2, 20, 'past the end of the text')
    end)

    it_vs('draws nothing on unchanged lines', function()
      local pd = render({ 'a', 'foo bar', 'c' }, { 'a', 'foo baz', 'c' })
      assert_bg(nil, pd.win_to, 1, 0, 'unchanged line')
      assert_bg(nil, pd.win_to, 1, 20, 'unchanged line, past the end')
    end)
  end)

  describe('added and deleted lines', function()
    it_vs('draws the add color on an inserted line, past the end too', function()
      local pd = render({ 'a', 'b' }, { 'a', 'new', 'b' })
      local row = helpers.row(pd, pd.buf_to, 2)
      assert_bg(C.line_add, pd.win_to, row, 20, 'inserted line, past the end')
    end)

    it_vs('draws the delete color on a deleted line, past the end too', function()
      local pd = render({ 'a', 'gone', 'b' }, { 'a', 'b' })
      local row = helpers.row(pd, pd.buf_from, 2)
      assert_bg(C.line_delete, pd.win_from, row, 20, 'deleted line, past the end')
    end)

    it_vs('draws the line color on inserted and deleted empty lines', function()
      local added = render({ 'a', 'b' }, { 'a', '', 'b' })
      local arow = helpers.row(added, added.buf_to, 2)
      assert_bg(C.line_add, added.win_to, arow, 0, 'inserted empty line')

      local deleted = render({ 'a', '', 'b' }, { 'a', 'b' })
      local drow = helpers.row(deleted, deleted.buf_from, 2)
      assert_bg(C.line_delete, deleted.win_from, drow, 0, 'deleted empty line')
    end)
  end)

  describe('filler rows', function()
    it_vs('draws the filler color across the whole row', function()
      local pd = render({ 'a', 'b' }, { 'a', 'new', 'b' })
      -- From row 2 is the filler opposite the inserted line
      assert.is_nil(pd.row_lines[pd.buf_from][2])
      assert_bg(C.filler, pd.win_from, 2, 0, 'filler row, first column')
      assert_bg(C.filler, pd.win_from, 2, 30, 'filler row, far right')
    end)
  end)

  describe('moved blocks', function()
    local from, to = helpers.load_fixture('demo.rb')

    it_vs('draws a pure move with the move color only', function()
      local pd = render(from, to, { compute_moves = true })
      -- From line 8 (Macchiato) moved without edits
      local row = helpers.row(pd, pd.buf_from, 8)
      assert_bg(C.line_move, pd.win_from, row, col_of(pd.buf_from, row, 'Macchiato'), 'moved text')
      assert_bg(C.line_move, pd.win_from, row, 60, 'moved line, past the end')
    end)

    it_vs('draws edits inside a moved block on top of the move color', function()
      local pd = render(from, to, { compute_moves = true })
      -- To line 8 is the moved Affogato entry, renamed to "Affogato Deluxe"
      local row = helpers.row(pd, pd.buf_to, 8)
      assert_bg(C.line_move, pd.win_to, row, col_of(pd.buf_to, row, 'name'), 'unchanged text in the move')
      assert_bg(C.char_change, pd.win_to, row, col_of(pd.buf_to, row, 'Deluxe'), 'edited text in the move')
    end)

    it_vs('keeps the regular colors for edits outside the move', function()
      local pd = render(from, to, { compute_moves = true })
      -- From line 3 (Espresso) changed price 300 -> 320 in place
      local row = helpers.row(pd, pd.buf_from, 3)
      assert_bg(C.line_change, pd.win_from, row, col_of(pd.buf_from, row, 'Espresso'), 'unchanged text')
      assert_bg(C.char_change, pd.win_from, row, col_of(pd.buf_from, row, '300') + 1, 'changed digit')
    end)
  end)

  describe('with treesitter highlighting', function()
    it_vs('still shows line and character colors over syntax colors', function()
      local pd = render({ 'local foo = 1', 'return foo' }, { 'local foo = 2', 'return foo' })
      vim.bo[pd.buf_to].filetype = 'lua'
      if not pcall(vim.treesitter.start, pd.buf_to, 'lua') then
        pending('lua treesitter parser not available')
        return
      end
      assert.is_not_nil(vim.treesitter.highlighter.active[pd.buf_to])
      assert_bg(C.line_change, pd.win_to, 1, 0, '"local" (keyword, line only)')
      assert_bg(C.char_change, pd.win_to, 1, 12, '"2" (number, changed)')
    end)
  end)
end)
