local helpers = require('helpers')
local ns = helpers.ns
local filler_ns = vim.api.nvim_create_namespace('partial_diff_filler')

local it_vs = helpers.has_vscode_diff() and it or pending

-- A change block in vscode-diff's format (1-based, end exclusive).
local function change(os, oe, ms, me)
  return {
    originalRange = { startLineNumber = os, endLineNumberExclusive = oe },
    modifiedRange = { startLineNumber = ms, endLineNumberExclusive = me },
  }
end

describe('align_lines', function()
  local pd

  before_each(function()
    pd = helpers.fresh_plugin()
  end)

  it('leaves identical input untouched', function()
    local r = pd.align_lines({ 'a', 'b' }, { 'a', 'b' }, {})
    assert.are.same({ 'a', 'b' }, r.from)
    assert.are.same({ 'a', 'b' }, r.to)
    assert.are.same({}, r.from_filler)
    assert.are.same({}, r.to_filler)
  end)

  it('pads the From side for an insertion', function()
    local r = pd.align_lines({ 'a', 'b' }, { 'a', 'x', 'b' }, { change(2, 2, 2, 3) })
    assert.are.same({ 'a', '', 'b' }, r.from)
    assert.are.same({ 'a', 'x', 'b' }, r.to)
    assert.are.same({ 2 }, r.from_filler)
    assert.are.same({ [1] = 1, [2] = 3 }, r.from_rows)
  end)

  it('pads the To side for a deletion', function()
    local r = pd.align_lines({ 'a', 'x', 'b' }, { 'a', 'b' }, { change(2, 3, 2, 2) })
    assert.are.same({ 'a', '', 'b' }, r.to)
    assert.are.same({ 2 }, r.to_filler)
    assert.are.same({ [1] = 1, [2] = 3 }, r.to_rows)
  end)

  it('pads the shorter side at the end of a modified block', function()
    local r = pd.align_lines({ 'a', 'p', 'q', 'z' }, { 'a', 'r', 'z' }, { change(2, 4, 2, 3) })
    assert.are.same({ 'a', 'p', 'q', 'z' }, r.from)
    assert.are.same({ 'a', 'r', '', 'z' }, r.to)
    assert.are.same({ 3 }, r.to_filler)
  end)

  it('keeps unchanged lines paired across several blocks', function()
    local from = { 'a', 'del', 'b', 'c', 'd' }
    local to = { 'a', 'b', 'c', 'ins1', 'ins2', 'd' }
    local r = pd.align_lines(from, to, { change(2, 3, 2, 2), change(5, 5, 4, 6) })
    assert.are.equal(#r.from, #r.to)
    for _, l in ipairs({ 'a', 'b', 'c', 'd' }) do
      assert.are.equal(vim.fn.index(r.from, l), vim.fn.index(r.to, l), 'row of ' .. l)
    end
  end)
end)

describe('row alignment in the diff view', function()
  local function render(from, to, opts)
    local pd = helpers.fresh_plugin(opts)
    helpers.open_pair(pd, from, to)
    assert.is_true(pd.apply_diff_highlights(from, to))
    return pd
  end

  it_vs('gives both buffers the same number of rows', function()
    local from, to = helpers.load_fixture('demo.rb')
    local pd = render(from, to, { diff = { compute_moves = true } })
    assert.are.equal(vim.api.nvim_buf_line_count(pd.buf_from), vim.api.nvim_buf_line_count(pd.buf_to))
    assert.is_true(vim.api.nvim_buf_line_count(pd.buf_from) > #from)
  end)

  it_vs('puts unchanged lines on the same row on both sides', function()
    local pd = render({ 'a', 'b', 'c' }, { 'a', 'x', 'y', 'b', 'c' })
    local left = vim.api.nvim_buf_get_lines(pd.buf_from, 0, -1, false)
    local right = vim.api.nvim_buf_get_lines(pd.buf_to, 0, -1, false)
    assert.are.same({ 'a', '', '', 'b', 'c' }, left)
    assert.are.same({ 'a', 'x', 'y', 'b', 'c' }, right)
  end)

  it_vs('marks filler rows with the filler highlight', function()
    local pd = render({ 'a', 'b' }, { 'a', 'x', 'b' })
    local marks = vim.api.nvim_buf_get_extmarks(pd.buf_from, filler_ns, 0, -1, { details = true })
    assert.are.equal(1, #marks)
    assert.are.equal(1, marks[1][2]) -- 0-based row 1 = second row
    assert.are.equal('PartialDiffFiller', marks[1][4].line_hl_group)
    assert.are.same({}, vim.api.nvim_buf_get_extmarks(pd.buf_to, filler_ns, 0, -1, {}))
  end)

  it_vs('places highlights on the shifted rows', function()
    -- An insertion after 'a', then 'c' -> 'C': the change is on original
    -- line 3 of From, which is buffer row 4 once the filler row is inserted.
    local pd = render({ 'a', 'b', 'c' }, { 'a', 'x', 'b', 'C' })
    local row = helpers.row(pd, pd.buf_from, 3)
    assert.are.equal(4, row)
    assert.are.equal('c', vim.api.nvim_buf_get_lines(pd.buf_from, row - 1, row, false)[1])
    assert.are.same({ 'PartialDiffLineChange' }, helpers.groups_on_row(pd.buf_from, ns.line, row))
    assert.are.same({ 'PartialDiffLineChange' }, helpers.groups_on_row(pd.buf_to, ns.line, row))
  end)

  it_vs('labels rows with original line numbers and blanks filler rows', function()
    local pd = render({ 'a', 'b' }, { 'a', 'x', 'b' })
    assert.are.equal('1', vim.trim(pd.line_label(pd.buf_from, 1)))
    assert.are.equal('', vim.trim(pd.line_label(pd.buf_from, 2)))
    assert.are.equal('2', vim.trim(pd.line_label(pd.buf_from, 3)))
    assert.are.equal('3', vim.trim(pd.line_label(pd.buf_to, 3)))
  end)

  it_vs('sets a statuscolumn only in windows that show line numbers', function()
    local pd = helpers.fresh_plugin()
    helpers.open_pair(pd, { 'a', 'b' }, { 'a', 'x', 'b' })
    vim.wo[pd.win_from].number = true
    vim.wo[pd.win_to].number = false
    pd.apply_diff_highlights({ 'a', 'b' }, { 'a', 'x', 'b' })
    assert.truthy(vim.wo[pd.win_from].statuscolumn:find('partial-diff', 1, true))
    assert.are.equal('', vim.wo[pd.win_to].statuscolumn)
  end)

  it_vs('draws original line numbers in the number column', function()
    local pd = helpers.fresh_plugin()
    helpers.open_pair(pd, { 'a', 'b' }, { 'a', 'x', 'b' })
    vim.wo[pd.win_from].number = true
    pd.apply_diff_highlights({ 'a', 'b' }, { 'a', 'x', 'b' })
    vim.v.errmsg = ''
    vim.cmd('redraw!')
    assert.are.equal('', vim.v.errmsg)
    local top, left = unpack(vim.fn.win_screenpos(pd.win_from))
    local function number_column(screen_row)
      local s = ''
      for c = left, left + pd.lnum_width - 1 do s = s .. vim.fn.screenstring(top + screen_row - 1, c) end
      return vim.trim(s)
    end
    assert.are.same({ '1', '', '2' }, { number_column(1), number_column(2), number_column(3) })
  end)

  it_vs('keeps move markers on original line numbers', function()
    local from, to = helpers.load_fixture('demo.rb')
    local pd = render(from, to, { diff = { compute_moves = true } })
    assert.are.same({ ' ↓ moved to line 5' }, helpers.virt_texts(pd.buf_from, ns.move))
    assert.are.same({ ' ↑ moved from line 8' }, helpers.virt_texts(pd.buf_to, ns.move))
    -- and the From marker sits on the row that shows original line 8
    local mark = vim.api.nvim_buf_get_extmarks(pd.buf_from, ns.move, 0, -1, { details = true })
    for _, m in ipairs(mark) do
      if m[4].virt_text then
        assert.are.equal(helpers.row(pd, pd.buf_from, 8), m[2] + 1)
      end
    end
  end)

  it_vs('leaves the buffers verbatim when align is off', function()
    local pd = render({ 'a', 'b' }, { 'a', 'x', 'b' }, { diff = { align = false } })
    assert.are.same({ 'a', 'b' }, vim.api.nvim_buf_get_lines(pd.buf_from, 0, -1, false))
    assert.are.same({}, vim.api.nvim_buf_get_extmarks(pd.buf_from, filler_ns, 0, -1, {}))
    assert.is_nil(pd.row_lines[pd.buf_from])
  end)
end)
