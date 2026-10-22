local helpers = require('helpers')

-- These tests drive the real Node.js wrapper; skip them when it can't run.
local it_vs = helpers.has_vscode_diff() and it or pending

describe('run_vscode_diff', function()
  local pd

  before_each(function()
    pd = helpers.fresh_plugin()
  end)

  it_vs('reports no changes for identical input', function()
    local res = pd.run_vscode_diff({ 'a', 'b' }, { 'a', 'b' }, {})
    assert.is_true(res.success)
    assert.are.same({}, res.changes)
  end)

  it_vs('returns line ranges with character-level innerChanges', function()
    local res = pd.run_vscode_diff({ 'foo bar' }, { 'foo baz' }, {})
    assert.are.equal(1, #res.changes)
    local change = res.changes[1]
    assert.are.equal(1, change.originalRange.startLineNumber)
    assert.are.equal(2, change.originalRange.endLineNumberExclusive)
    assert.is_true(#change.innerChanges >= 1)
    assert.are.equal(1, change.innerChanges[1].originalRange.startLineNumber)
  end)

  it_vs('honours ignoreTrimWhitespace', function()
    local from, to = helpers.load_fixture('04_whitespace.js')
    local strict = pd.run_vscode_diff(from, to, { ignoreTrimWhitespace = false })
    local relaxed = pd.run_vscode_diff(from, to, { ignoreTrimWhitespace = true })
    assert.is_true(#strict.changes > 0)
    assert.are.equal(0, #relaxed.changes)
  end)

  it_vs('reports moves only when computeMoves is set', function()
    local from, to = helpers.load_fixture('03_moves.js')
    local without = pd.run_vscode_diff(from, to, { computeMoves = false })
    local with = pd.run_vscode_diff(from, to, { computeMoves = true })
    assert.are.equal(0, #without.moves)
    assert.are.equal(1, #with.moves)
    -- validateInput (lines 1-9) moved to the end of the To side (lines 10-18)
    local lrm = with.moves[1].lineRangeMapping
    assert.are.same({ 10, 19 }, { lrm.original.startLineNumber, lrm.original.endLineNumberExclusive })
    assert.are.same({ 1, 10 }, { lrm.modified.startLineNumber, lrm.modified.endLineNumberExclusive })
  end)

  it('returns nil when the wrapper script is missing', function()
    pd.get_plugin_root = function() return vim.fn.tempname() end
    assert.is_nil(pd.run_vscode_diff({ 'a' }, { 'b' }, {}))
  end)
end)
