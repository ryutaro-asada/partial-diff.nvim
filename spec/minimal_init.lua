-- Minimal init for running the test suite in headless Neovim.
-- Usage: make test   (see Makefile)

local root = vim.fn.fnamemodify(debug.getinfo(1, 'S').source:sub(2), ':p:h:h')
local plenary = os.getenv('PLENARY_DIR') or (root .. '/.deps/plenary.nvim')

vim.opt.runtimepath:prepend(plenary)
vim.opt.runtimepath:prepend(root)
package.path = root .. '/spec/?.lua;' .. package.path

vim.o.swapfile = false
vim.o.more = false
vim.opt.shortmess:append('F')

vim.cmd('runtime plugin/plenary.vim')
vim.cmd('runtime plugin/partial-diff.vim')
