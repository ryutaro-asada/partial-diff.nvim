local api = vim.api
local M = {}

M.a = {}
M.b = {}
M.buf_a = nil
M.buf_b = nil

M.partial_diff_a = function(start_line, end_line)
  M.a = api.nvim_buf_get_lines(0, start_line-1, end_line, false)
end

M.partial_diff_b = function(start_line, end_line)
  M.b = api.nvim_buf_get_lines(0, start_line-1, end_line, false)

  -- Create two new buffers
  M.buf_a = api.nvim_create_buf(false, true)
  M.buf_b = api.nvim_create_buf(false, true)

  -- Set the lines in the buffers
  api.nvim_buf_set_lines(M.buf_a, 0, -1, false, M.a)
  api.nvim_buf_set_lines(M.buf_b, 0, -1, false, M.b)

  -- Open the buffers in new split windows
  api.nvim_command('vnew +' .. 'setl\\ buftype=nofile | buffer ' .. M.buf_a) -- A buffer
  local win_a = api.nvim_get_current_win()
  
  api.nvim_command('vsplit +' .. 'setl\\ buftype=nofile | buffer ' .. M.buf_b) -- B buffer
  local win_b = api.nvim_get_current_win()

  -- Start diff mode for each window
  api.nvim_win_set_option(win_a, 'diff', true)
  api.nvim_win_set_option(win_b, 'diff', true)
end

M.partial_diff_delete = function()
  if M.buf_a then
    api.nvim_buf_delete(M.buf_a, { force = true })
    M.buf_a = nil
  end
  if M.buf_b then
    api.nvim_buf_delete(M.buf_b, { force = true })
    M.buf_b = nil
  end
end

return M
