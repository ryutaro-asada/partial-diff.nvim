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

  describe('line highlights', function()
    local function render_lines(from, to)
      local pd = helpers.fresh_plugin()
      helpers.open_pair(pd, from, to)
      assert.is_true(pd.apply_diff_highlights(from, to))
      return pd
    end

    it_vs('uses the add group for purely inserted lines', function()
      local pd = render_lines({ 'a', 'b', 'c' }, { 'a', 'x', 'b', 'c' })
      assert.are.same({ 'PartialDiffLineAdd' }, helpers.groups_on_row(pd.buf_to, ns.line, 2))
      assert.are.same({}, helpers.spans(pd.buf_from, ns.line))
    end)

    it_vs('uses the delete group for purely deleted lines', function()
      local pd = render_lines({ 'a', 'b', 'c' }, { 'a', 'c' })
      assert.are.same({ 'PartialDiffLineDelete' }, helpers.groups_on_row(pd.buf_from, ns.line, 2))
      assert.are.same({}, helpers.spans(pd.buf_to, ns.line))
    end)

    it_vs('uses the change group on both sides for modified lines', function()
      local pd = render_lines({ 'a', 'foo', 'c' }, { 'a', 'bar', 'c' })
      assert.are.same({ 'PartialDiffLineChange' }, helpers.groups_on_row(pd.buf_from, ns.line, 2))
      assert.are.same({ 'PartialDiffLineChange' }, helpers.groups_on_row(pd.buf_to, ns.line, 2))
    end)

    it_vs('highlights inserted and deleted empty lines', function()
      local added = render_lines({ 'a', 'b' }, { 'a', '', 'b' })
      assert.are.same({ 'PartialDiffLineAdd' }, helpers.groups_on_row(added.buf_to, ns.line, 2))

      local deleted = render_lines({ 'a', '', 'b' }, { 'a', 'b' })
      assert.are.same({ 'PartialDiffLineDelete' }, helpers.groups_on_row(deleted.buf_from, ns.line, 2))
    end)

    it_vs('highlights the full line width', function()
      local pd = render_lines({ 'a', 'foo', 'c' }, { 'a', 'bar', 'c' })
      local marks = vim.api.nvim_buf_get_extmarks(pd.buf_to, ns.line, 0, -1, { details = true })
      assert.are.equal(1, #marks)
      local d = marks[1][4]
      assert.are.equal('PartialDiffLineChange', d.hl_group)
      assert.is_true(d.hl_eol)
      assert.are.same({ 1, 2, 0 }, { marks[1][2], d.end_row, d.end_col })
    end)

    -- Reads what is actually drawn, so it catches highlights that exist as
    -- extmarks but are hidden by another highlight.
    describe('on screen', function()
      local function bg_at(pd, win, lnum, col)
        vim.cmd('redraw!')
        local sp = vim.fn.screenpos(win, lnum, col)
        return vim.api.nvim__inspect_cell(1, sp.row - 1, sp.col - 1)[2].background
      end

      before_each(function()
        vim.o.termguicolors = true
        vim.api.nvim_set_hl(0, 'PdTestLine', { bg = '#111111' })
        vim.api.nvim_set_hl(0, 'PdTestChar', { bg = '#222222' })
      end)

      it_vs('draws character highlights on top of the line highlight', function()
        local pd = helpers.fresh_plugin({
          highlights = { line_change = 'PdTestLine', char_change = 'PdTestChar' },
        })
        local from, to = { 'a', 'foo bar', 'c' }, { 'a', 'foo baz', 'c' }
        helpers.open_pair(pd, from, to)
        pd.setup_highlights()
        pd.apply_diff_highlights(from, to)
        assert.are.equal(0x111111, bg_at(pd, pd.win_to, 2, 1)) -- "f": line highlight
        assert.are.equal(0x222222, bg_at(pd, pd.win_to, 2, 7)) -- "z": char highlight
      end)

      it_vs('draws the line highlight on empty and past-the-end cells', function()
        local pd = helpers.fresh_plugin({ highlights = { line_add = 'PdTestLine' } })
        local from, to = { 'a', 'b' }, { 'a', '', 'b' }
        helpers.open_pair(pd, from, to)
        pd.setup_highlights()
        pd.apply_diff_highlights(from, to)
        local row = helpers.row(pd, pd.buf_to, 2)
        vim.cmd('redraw!')
        local top, left = unpack(vim.fn.win_screenpos(pd.win_to))
        local textoff = vim.fn.getwininfo(pd.win_to)[1].textoff
        for _, col in ipairs({ 0, 10 }) do
          local cell = vim.api.nvim__inspect_cell(1, top - 2 + row, left - 1 + textoff + col)
          assert.are.equal(0x111111, cell[2].background, 'screen col ' .. col)
        end
      end)
    end)
  end)

  it('falls back to diff mode with the fallback diffopt when vscode-diff fails', function()
    local pd = helpers.fresh_plugin()
    helpers.open_pair(pd, { 'a' }, { 'b' })
    pd.run_vscode_diff = function() return nil end
    local diffopt = vim.o.diffopt
    assert.is_false(pd.apply_diff_highlights({ 'a' }, { 'b' }))
    assert.is_true(vim.wo[pd.win_from].diff)
    assert.is_true(vim.wo[pd.win_to].diff)
    assert.are.equal(pd.diff.fallback_diffopt, vim.o.diffopt)
    pd.partial_diff_delete()
    assert.are.equal(diffopt, vim.o.diffopt)
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
      for line = 8, 10 do
        local row = helpers.row(pd, pd.buf_from, line)
        assert.are.same({ 'PartialDiffLineMove' }, helpers.groups_on_row(pd.buf_from, ns.move, row))
        assert.are.same({}, helpers.groups_on_row(pd.buf_from, ns.line, row))
        assert.are.same({}, helpers.groups_on_row(pd.buf_from, ns.char, row))
      end
    end)

    it_vs('still shows edits inside a moved block', function()
      local pd = render('demo.rb', { diff = { compute_moves = true } })
      -- From line 11 (Affogato) moved and was edited
      local row = helpers.row(pd, pd.buf_from, 11)
      assert.are.same({ 'PartialDiffLineMove' }, helpers.groups_on_row(pd.buf_from, ns.move, row))
      assert.is_true(#helpers.groups_on_row(pd.buf_from, ns.char, row) > 0)
    end)

    it_vs('keeps regular highlights for edits outside the move', function()
      local pd = render('demo.rb', { diff = { compute_moves = true } })
      -- From line 3 (Espresso price) changed in place
      local row = helpers.row(pd, pd.buf_from, 3)
      assert.are.same({ 'PartialDiffLineChange' }, helpers.groups_on_row(pd.buf_from, ns.line, row))
      assert.is_true(#helpers.groups_on_row(pd.buf_from, ns.char, row) > 0)
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
