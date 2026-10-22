local helpers = require('helpers')

local it_vs = helpers.has_vscode_diff() and it or pending

-- A source buffer with two 10-line ranges: lines 1-10 and 11-20.
local function source_buffer(ft)
  local buf = vim.api.nvim_get_current_buf()
  local lines = {}
  for i = 1, 10 do lines[#lines + 1] = 'a' .. i end
  for i = 1, 10 do lines[#lines + 1] = 'b' .. i end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = ft or 'ruby'
  return buf
end

local function open_diff(pd)
  pd.partial_diff_from(1, 10)
  pd.partial_diff_to(11, 20)
end

describe('diff view', function()
  local pd, src, src_tab

  before_each(function()
    pd = helpers.fresh_plugin()
    src = source_buffer()
    src_tab = vim.api.nvim_get_current_tabpage()
  end)

  it('refuses :PartialDiffTo before a From range is marked', function()
    pd.partial_diff_to(11, 20)
    assert.are.equal(1, #vim.api.nvim_list_tabpages())
    assert.is_nil(pd.buf_from)
  end)

  it('opens a side-by-side view in a new tab via the commands', function()
    vim.cmd('1,10PartialDiffFrom')
    vim.cmd('11,20PartialDiffTo')
    assert.are.equal(2, #vim.api.nvim_list_tabpages())
    assert.are.equal(pd.tab, vim.api.nvim_get_current_tabpage())
    assert.are.equal('a1', vim.api.nvim_buf_get_lines(pd.buf_from, 0, 1, false)[1])
    assert.are.equal('b1', vim.api.nvim_buf_get_lines(pd.buf_to, 0, 1, false)[1])
    assert.truthy(vim.api.nvim_buf_get_name(pd.buf_from):find('[Partial Diff From]', 1, true))
  end)

  it('gives the diff buffers the source filetypes', function()
    open_diff(pd)
    assert.are.equal('ruby', vim.bo[pd.buf_from].filetype)
    assert.are.equal('ruby', vim.bo[pd.buf_to].filetype)
  end)

  it('uses each side\'s own filetype when ranges come from different buffers', function()
    pd.partial_diff_from(1, 10)
    vim.cmd('enew')
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { 'x', 'y' })
    vim.bo.filetype = 'lua'
    pd.partial_diff_to(1, 2)
    assert.are.equal('ruby', vim.bo[pd.buf_from].filetype)
    assert.are.equal('lua', vim.bo[pd.buf_to].filetype)
  end)

  it('re-running From/To from the source tab keeps that tab and diffs correctly', function()
    open_diff(pd)
    vim.api.nvim_set_current_tabpage(src_tab)
    open_diff(pd)
    assert.is_true(vim.api.nvim_tabpage_is_valid(src_tab))
    assert.is_true(#vim.fn.win_findbuf(src) > 0)
    assert.are.equal(2, #vim.api.nvim_list_tabpages())
    assert.are.equal('a1', vim.api.nvim_buf_get_lines(pd.buf_from, 0, 1, false)[1])
    assert.are.equal('b1', vim.api.nvim_buf_get_lines(pd.buf_to, 0, 1, false)[1])
  end)

  it(':PartialDiffDelete from another tab closes only the diff tab', function()
    open_diff(pd)
    vim.api.nvim_set_current_tabpage(src_tab)
    vim.cmd('PartialDiffDelete')
    assert.are.same({ src_tab }, vim.api.nvim_list_tabpages())
    assert.is_nil(pd.buf_from)
    assert.is_false(pd.has_from)
  end)

  describe('when the diff tab is closed with :tabclose', function()
    before_each(function()
      -- make the tab handle differ from the tab number
      vim.cmd('tabnew')
      vim.cmd('tabclose')
    end)

    it('cleans up buffers and restores scrollopt', function()
      local scrollopt = vim.o.scrollopt
      open_diff(pd)
      assert.are_not.equal(pd.tab, vim.api.nvim_tabpage_get_number(pd.tab))
      local buf_from = pd.buf_from
      vim.cmd('tabclose')
      vim.wait(100, function() return pd.buf_from == nil end)
      assert.is_nil(pd.buf_from)
      assert.is_false(vim.api.nvim_buf_is_valid(buf_from))
      assert.are.equal(scrollopt, vim.o.scrollopt)
      local leftover = vim.tbl_filter(function(a) return a.group_name == 'PartialDiffCleanup' end,
        vim.api.nvim_get_autocmds({ event = 'TabClosed' }))
      assert.are.same({}, leftover)
    end)

    it('is not triggered by closing an unrelated tab', function()
      open_diff(pd)
      local buf_from = pd.buf_from
      vim.cmd('tabnew')
      vim.cmd('tabclose')
      vim.wait(50)
      assert.are.equal(buf_from, pd.buf_from)
      assert.is_true(vim.api.nvim_buf_is_valid(buf_from))
    end)

    it('can be reopened afterwards', function()
      open_diff(pd)
      vim.cmd('tabclose')
      vim.wait(100, function() return pd.buf_from == nil end)
      vim.api.nvim_set_current_tabpage(src_tab)
      assert.has_no.errors(function() open_diff(pd) end)
      assert.is_true(vim.api.nvim_buf_is_valid(pd.buf_from))
    end)
  end)

  it('closing does not error when the diff tab is the only tab', function()
    open_diff(pd)
    vim.cmd('noautocmd tabclose ' .. vim.api.nvim_tabpage_get_number(src_tab))
    assert.has_no.errors(pd.partial_diff_delete)
    assert.is_true(#vim.api.nvim_list_wins() >= 1)
    -- the window left behind must not keep the diff view's window options
    local win = vim.api.nvim_get_current_win()
    assert.is_false(vim.wo[win].scrollbind)
    assert.is_false(vim.wo[win].cursorbind)
    assert.is_false(vim.wo[win].diff)
    assert.are.equal(vim.go.wrap, vim.wo[win].wrap)
  end)

  describe('scroll sync', function()
    it_vs('binds both windows and restores scrollopt on close', function()
      local scrollopt = vim.o.scrollopt
      open_diff(pd)
      for _, win in ipairs({ pd.win_from, pd.win_to }) do
        assert.is_true(vim.wo[win].scrollbind)
        assert.is_true(vim.wo[win].cursorbind)
        assert.is_false(vim.wo[win].wrap)
      end
      assert.truthy(vim.o.scrollopt:find('ver', 1, true))
      assert.truthy(vim.o.scrollopt:find('hor', 1, true))
      pd.partial_diff_delete()
      assert.are.equal(scrollopt, vim.o.scrollopt)
    end)

    it_vs('is skipped when sync_scroll is off', function()
      pd.setup({ diff = { sync_scroll = false } })
      open_diff(pd)
      assert.is_false(vim.wo[pd.win_from].scrollbind)
      assert.is_false(vim.wo[pd.win_to].scrollbind)
    end)
  end)

  describe('built-in diff fallback', function()
    before_each(function()
      pd.check_vscode_diff = function() return false end
    end)

    it('uses diff mode with the fallback diffopt and restores it on close', function()
      local diffopt = vim.o.diffopt
      open_diff(pd)
      assert.is_true(vim.wo[pd.win_from].diff)
      assert.is_true(vim.wo[pd.win_to].diff)
      assert.are.equal(pd.diff.fallback_diffopt, vim.o.diffopt)
      pd.partial_diff_delete()
      assert.are.equal(diffopt, vim.o.diffopt)
    end)
  end)
end)
