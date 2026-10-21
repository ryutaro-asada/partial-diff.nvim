# Diff test fixtures

Sample files for manually exercising `partial-diff.nvim` and feeling what each
improvement does.

Each fixture is a **single file written as a Git conflict**: the `FROM` version
(between `<<<<<<< FROM` and `=======`) and the `TO` version (between `=======`
and `>>>>>>> TO`) live in the same file, like an unresolved merge conflict.

## How to run a fixture

1. Open the file, e.g. `:e test/demo.rb`.
2. Select the **FROM** block — the lines between `<<<<<<< FROM` and `=======`
   (exclude the marker lines) — in visual mode, then run `:PartialDiffFrom`.
3. Select the **TO** block — the lines between `=======` and `>>>>>>> TO`
   (exclude the marker lines) — in visual mode, then run `:PartialDiffTo`.
4. View the diff; close it with `:PartialDiffDelete`.

Tip: put the cursor on the first code line of a block, `V`, then move to the
last code line of that block to select it.

## The fixtures

| File | What it demonstrates | Try with |
|------|----------------------|----------|
| `01_char_level.js` | Character-level highlighting inside changed lines | default settings |
| `02_add_delete.js` | Pure additions and deletions (new / removed functions) | default settings |
| `03_moves.js` | **Move detection** — a block is moved, not changed | `diff.compute_moves = true` |
| `04_whitespace.js` | **Trim-whitespace option** — indentation-only changes | toggle `diff.ignore_trim_whitespace` |
| `05_histogram.js` | Repeated lines (`}`, blank lines) — histogram vs patience | fallback diff (no Node.js) |
| `demo.rb` | ~10-item Ruby list where a few entries move/change | default; also try `compute_moves` |

## Recommended setup to see everything

```lua
require('partial-diff').setup({
  diff = {
    compute_moves = true,           -- see 03_moves and demo move markers
    ignore_trim_whitespace = false, -- flip to true to see 04_whitespace change
  },
})
```

Run `03_moves.js` once with `compute_moves = false` and once with `true` to
feel the difference: with it off the moved block shows up as a big delete+add;
with it on it is highlighted as a move with a `↑ moved from line N` /
`↓ moved to line N` marker.
