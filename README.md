# partial-diff.nvim

This repository contains a set of commands for Neovim that allow you to perform partial diffs on your code.

## Commands

- `PartialDiffA`: Marks a range of lines as the first part of the diff.
- `PartialDiffB`: Marks a range of lines as the second part of the diff.
- `PartialDiffDelete`: Deletes the current partial diff.

## Usage

Follow the steps below to use these commands:

1. Select the range of lines with visual mode.
2. Type `:PartialDiffA`.
3. Select another range of lines with visual mode.
4. Type `:PartialDiffB`.
5. View the diff.

```vim
:'<,'>PartialDiffA
:'<,'>PartialDiffB
```

To delete the current diff, use the `PartialDiffDelete` command.


## Installation

To install the `partial-diff` Lua module, you can use your preferred Lua package manager. For example, if you're using `luarocks`, you can install it like this:

```bash
luarocks install partial-diff
```

Once you have the module installed, you can add the commands to your Neovim configuration file.

## Contributing

If you have any suggestions or improvements, feel free to open an issue or submit a pull request.

## License

This project is licensed under the MIT License.

