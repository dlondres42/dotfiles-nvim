-- `:term` inherits the window's cwd, which is wherever nvim was started. These
-- open a terminal rooted at the current buffer's directory instead.

vim.keymap.set('n', '<leader>tt', function()
  local dir = vim.fn.expand '%:p:h'
  if dir == '' then
    dir = vim.fn.getcwd()
  end
  -- `term = true` converts the current buffer, so give it a scratch one to eat
  -- rather than the file buffer the split is still showing.
  vim.cmd 'botright 15new'
  vim.fn.jobstart(vim.o.shell, { term = true, cwd = dir })
  vim.cmd 'startinsert'
end, { desc = '[T]erminal in buffer dir' })

vim.keymap.set('t', '<Esc><Esc>', '<C-\\><C-n>', { desc = 'Exit terminal mode' })
