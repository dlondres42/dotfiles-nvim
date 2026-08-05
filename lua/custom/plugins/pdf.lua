-- Opening a .pdf in Neovim (:e, netrw, neo-tree, etc.) hands it off to an
-- external viewer instead of loading the binary into a text buffer.
-- zathura on Linux; on macOS `open` defers to whatever the system default is.

local viewer = vim.uv.os_uname().sysname == 'Darwin' and 'open' or 'zathura'

vim.api.nvim_create_autocmd('BufReadCmd', {
  pattern = { '*.pdf', '*.PDF' },
  callback = function(args)
    vim.fn.jobstart({ viewer, args.file }, { detach = true })
    vim.schedule(function()
      vim.cmd.bwipeout { args.buf, bang = true }
    end)
  end,
})
