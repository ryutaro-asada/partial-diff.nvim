# Diff test fixtures

Sample files for manually exercising `partial-diff.nvim` and feeling what each
improvement does. Each pair is `*_from.*` / `*_to.*`: select the whole `from`
file, run `:PartialDiffFrom`, then select the whole `to` file and run
`:PartialDiffTo`.

## Quick way to open a pair side by side

```vim
:tabnew test/01_char_level_from.js
:vsplit test/01_char_level_to.js
```

Then select all lines in the left window (`ggVG`) → `:PartialDiffFrom`,
switch to the right window, select all (`ggVG`) → `:PartialDiffTo`.

## The fixtures

| Pair | What it demonstrates | Try with |
|------|----------------------|----------|
| `01_char_level` | Character-level highlighting inside changed lines | default settings |
| `02_add_delete` | Pure additions and deletions (new / removed functions) | default settings |
| `03_moves` | **Move detection** — a block is moved, not changed | `diff.compute_moves = true` |
| `04_whitespace` | **Trim-whitespace option** — indentation-only changes | toggle `diff.ignore_trim_whitespace` |
| `05_histogram` | Repeated lines (`}`, blank lines) — histogram vs patience | fallback diff (no Node.js) |
| `demo` | Recreation of the README demo (JS refactor) | default; also try `compute_moves` |

## Recommended setup to see everything

```lua
require('partial-diff').setup({
  diff = {
    compute_moves = true,          -- see 03_moves and demo move markers
    ignore_trim_whitespace = false, -- flip to true to see 04_whitespace change
  },
})
```

Run the pair in `03_moves` once with `compute_moves = false` and once with
`true` to feel the difference: with it off the moved block shows up as a big
delete+add; with it on it is highlighted as a move with a
`↑ moved from line N` / `↓ moved to line N` marker.
