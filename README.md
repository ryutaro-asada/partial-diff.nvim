# partial-diff.nvim

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)


A Neovim plugin for performing partial diffs on selected code regions with advanced character-level diff highlighting powered by VSCode's diff algorithm.

## Features

- 🎯 **Partial Diff**: Compare any two selected regions of code
- 🔤 **Character-level highlighting**: Powered by VSCode's diff algorithm
- 🔀 **Move detection** (optional): Recognize moved code blocks instead of showing them as unrelated changes
- 🧹 **Whitespace-aware** (optional): Ignore pure indentation / trailing-space changes
- 📐 **Histogram fallback**: Cleaner built-in diff when the VSCode algorithm is unavailable

## Demo


https://github.com/user-attachments/assets/fcd3acfd-855b-4b54-a988-6bd2371344ba



https://github.com/ryutaro-asada/partial-diff.nvim/assets/58899265/6eaae6a9-2ecb-489e-8d38-c4bd9ff41690

## Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
  {
    "ryutaro-asada/partial-diff.nvim",
  },
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'ryutaro-asada/partial-diff.nvim',
  config = function()
    require('partial-diff').setup()
  end
}
```
## Configuration

```lua
require('partial-diff').setup({
  -- Debug options
  debug = false,
  -- Diff computation options
  diff = {
    -- Ignore leading/trailing whitespace differences (vscode-diff).
    -- Set to true to hide pure indentation / trailing-space changes.
    ignore_trim_whitespace = false,
    -- Detect moved code blocks (vscode-diff). When enabled, moved blocks are
    -- highlighted with the `line_move` group and marked with virtual text
    -- pointing to their counterpart location, instead of being shown as a
    -- change.
    compute_moves = false,
    -- Keep the From/To windows scroll- and cursor-synced (like diff mode).
    -- Applies to the vscode-diff path; the built-in diff fallback already
    -- syncs scrolling on its own.
    sync_scroll = true,
    -- When sync_scroll is on, also turn off 'wrap' in both windows so that
    -- horizontal scrolling actually happens (and stays mirrored). Set to
    -- false to keep wrap at the cost of no horizontal sync.
    sync_scroll_nowrap = true,
    -- diffopt used for the built-in Neovim diff fallback (when Node.js /
    -- vscode-diff are unavailable). Defaults to the histogram algorithm with
    -- linematch for cleaner results on refactored code.
    fallback_diffopt =
      "internal,filler,closeoff,hiddenoff,algorithm:histogram,linematch:60,context:3,indent-heuristic",
  },
  -- Highlight customization
  highlights = {
    -- Link to existing highlight groups
    line_change = 'DiffChange',
    line_add = 'DiffAdd',
    line_delete = 'DiffDelete',
    -- Specify custom colors
    char_add = {
      bg = '#2d5a2d',   -- Background color
      fg = '#a9dc76',   -- Foreground color
      bold = true,      -- Bold
      italic = false,   -- Italic
      underline = false -- Underline
    },
    char_delete = {
      bg = '#5a2d2d',
      fg = '#ff6188',
    },
    char_change = {
      bg = '#4a4a0e',
      fg = '#ffd866',
      bold = true
    },
    -- Highlight for moved blocks (used when diff.compute_moves = true)
    line_move = {
      bg = '#2d3a5a',
      fg = '#78a9ff',
    }
  }
})
```

### VSCode Diff Algorithm (Optional but Recommended)

For better character-level diff highlighting, install the VSCode diff algorithm:

1. Ensure Node.js is installed on your system
2. Run `:PartialDiffInstallVSCode` in Neovim
3. This will install the required npm packages in the plugin directory

Without this, the plugin will fall back to Neovim's built-in diff.

## Commands

### Primary Commands

- `:PartialDiffFrom` - Mark a range of lines as the source (what you're diffing from)
- `:PartialDiffTo` - Mark a range of lines as the target (what you're diffing to) and display the diff
- `:PartialDiffDelete` - Close the current diff view
- `:PartialDiffInstallVSCode` - Install VSCode diff algorithm dependencies

### Legacy Commands (Backward Compatibility)

- `:PartialDiffA` - Alias for `:PartialDiffFrom`
- `:PartialDiffB` - Alias for `:PartialDiffTo`

### Debug Commands

- `:PartialDiffShowLog` - Show the debug log file
- `:PartialDiffClearLog` - Clear the debug log file

## Usage

### Basic Workflow

1. Select the first range of lines in visual mode
2. Execute `:PartialDiffFrom` (or use your keymap)
3. Select the second range of lines in visual mode
4. Execute `:PartialDiffTo` (or use your keymap)
5. View the diff in a new tab with side-by-side comparison

### Example

```vim
" Select lines 10-20 in visual mode
:'<,'>PartialDiffFrom

" Select lines 30-40 in visual mode
:'<,'>PartialDiffTo

" Close the diff when done
:PartialDiffDelete
```

## Using

- [vscode-diff](https://github.com/micnil/vscode-diff) - Advanced character-level diff computation

## Requirements

- Neovim 0.10.0 or later
- (Optional) Node.js for VSCode diff algorithm

## Contributing

If you have any suggestions or improvements, feel free to open an issue or submit a pull request.

## License

This project is licensed under the MIT License.
