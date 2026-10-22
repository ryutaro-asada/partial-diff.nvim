local helpers = require('helpers')
local ns = helpers.ns

-- Rendering tests need the vscode-diff engine; skip them when it can't run.
local it_vs = helpers.has_vscode_diff() and it or pending

local function render(fixture, opts)
  local pd = helpers.fresh_plugin(opts)
  local from, to = helpers.load_fixture(fixture)
  helpers.open_pair(pd, from, to)
  assert.is_true(pd.apply_diff_highlights(from, to))
  return pd, from, to
end

describe('apply_diff_highlights', function()
  it_vs('highlights changed lines and leaves unchanged lines alone', function()
    local pd = render('01_char_level.js')
    -- line 1 `greet(name)` -> `greet(username)`: the line is marked on both
    -- sides, the inserted `user` only on the To side
    assert.are.same({ 'PartialDiffLineChange' }, helpers.groups_on_row(pd.buf_from, ns.line, 1))
    assert.are.same({}, helpers.groups_on_row(pd.buf_from, ns.char, 1))
    assert.are.same({ 'user' }, helpers.texts(vim.tbl_filter(function(s) return s.row == 1 end,
      helpers.spans(pd.buf_to, ns.char)), 'PartialDiffCharAdd'))
    -- line 4 `return message.length;` is unchanged
    assert.are.same({}, helpers.groups_on_row(pd.buf_from, ns.line, 4))
    assert.are.same({}, helpers.groups_on_row(pd.buf_from, ns.char, 4))
  end)

  it_vs('marks exactly the edited segments of a long line', function()
    local pd = render('06_long_line.rb')
    local texts = helpers.texts(helpers.spans(pd.buf_to, ns.char), 'PartialDiffCharChange')
    assert.are.same({ 'magenta', 'teal', '2', '127.0.0.1', '9090', '5', 'true', 'we', '2' }, texts)
  end)

  it_vs('shows an intra-line reorder as delete (From) and add (To)', function()
    local pd = render('07_inline_move.rb')
    assert.are.same({ ' :gamma,', '-> cart ', ' verbose: true,' },
      helpers.texts(helpers.spans(pd.buf_from, ns.char), 'PartialDiffCharDelete'))
    assert.are.same({ 'gamma, :', '-> cart ', ', verbose: true' },
      helpers.texts(helpers.spans(pd.buf_to, ns.char), 'PartialDiffCharAdd'))
  end)

  it_vs('converts UTF-16 columns to byte offsets for multibyte text', function()
    local pd = helpers.fresh_plugin()
    local from, to = { 'café 🙂 a' }, { 'café 🙂 b' }
    helpers.open_pair(pd, from, to)
    pd.apply_diff_highlights(from, to)
    assert.are.same({ 'a' }, helpers.texts(helpers.spans(pd.buf_from, ns.char), 'PartialDiffCharChange'))
    assert.are.same({ 'b' }, helpers.texts(helpers.spans(pd.buf_to, ns.char), 'PartialDiffCharChange'))
  end)

  it_vs('hides indentation-only changes with ignore_trim_whitespace', function()
    local strict = render('04_whitespace.js')
    assert.is_true(#helpers.spans(strict.buf_to, ns.line) > 0)

    local relaxed = render('04_whitespace.js', { diff = { ignore_trim_whitespace = true } })
    assert.are.same({}, helpers.spans(relaxed.buf_to, ns.line))
    assert.are.same({}, helpers.spans(relaxed.buf_to, ns.char))
  end)

  it_vs('works without vim.hl (Neovim 0.10)', function()
    local saved = vim.hl
    vim.hl = nil
    local ok, pd = pcall(render, '01_char_level.js')
    vim.hl = saved
    assert.is_true(ok, tostring(pd))
    assert.is_true(#helpers.spans(pd.buf_to, ns.char) > 0)
  end)

  describe('with compute_moves', function()
    it_vs('draws moved lines with the move highlight only', function()
      local pd = render('demo.rb', { diff = { compute_moves = true } })
      -- From lines 8-10 (Macchiato, Flat White, Cold Brew) moved without edits
      for row = 8, 10 do
        assert.are.same({ 'PartialDiffLineMove' }, helpers.groups_on_row(pd.buf_from, ns.move, row))
        assert.are.same({}, helpers.groups_on_row(pd.buf_from, ns.line, row))
        assert.are.same({}, helpers.groups_on_row(pd.buf_from, ns.char, row))
      end
    end)

    it_vs('still shows edits inside a moved block', function()
      local pd = render('demo.rb', { diff = { compute_moves = true } })
      -- From line 11 (Affogato) moved and was edited
      assert.are.same({ 'PartialDiffLineMove' }, helpers.groups_on_row(pd.buf_from, ns.move, 11))
      assert.is_true(#helpers.groups_on_row(pd.buf_from, ns.char, 11) > 0)
    end)

    it_vs('keeps regular highlights for edits outside the move', function()
      local pd = render('demo.rb', { diff = { compute_moves = true } })
      -- From line 3 (Espresso price) changed in place
      assert.are.same({ 'PartialDiffLineChange' }, helpers.groups_on_row(pd.buf_from, ns.line, 3))
      assert.is_true(#helpers.groups_on_row(pd.buf_from, ns.char, 3) > 0)
    end)

    it_vs('adds move markers pointing to the counterpart line', function()
      local pd = render('demo.rb', { diff = { compute_moves = true } })
      assert.are.same({ ' ↓ moved to line 5' }, helpers.virt_texts(pd.buf_from, ns.move))
      assert.are.same({ ' ↑ moved from line 8' }, helpers.virt_texts(pd.buf_to, ns.move))
    end)

    it_vs('does not draw moves when compute_moves is off', function()
      local pd = render('demo.rb')
      assert.are.same({}, helpers.spans(pd.buf_from, ns.move))
      assert.are.same({}, helpers.virt_texts(pd.buf_to, ns.move))
    end)
  end)
end)
