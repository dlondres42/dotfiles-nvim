-- LaTeX support: compile with latexmk and preview in a viewer, synced via SyncTeX.
-- Requires `latexmk` (or another engine), plus a viewer vimtex knows how to talk
-- to: zathura on Linux, Skim on macOS (`brew install --cask skim`). Zathura does
-- technically build on macOS but is a GTK app and not worth the trouble there.

vim.pack.add { 'https://github.com/lervag/vimtex' }

vim.g.vimtex_view_method = vim.uv.os_uname().sysname == 'Darwin' and 'skim' or 'zathura'
vim.g.vimtex_compiler_method = 'latexmk'
vim.g.vimtex_quickfix_mode = 0

vim.api.nvim_create_autocmd('FileType', {
  pattern = 'tex',
  callback = function(args)
    local map = function(mode, lhs, rhs, desc)
      vim.keymap.set(mode, lhs, rhs, { buffer = args.buf, desc = desc })
    end

    map('n', '<leader>ll', '<plug>(vimtex-compile)', '[l]atex compile')
    map('n', '<leader>lv', '<plug>(vimtex-view)', '[l]atex [v]iew')
    map('n', '<leader>lc', '<plug>(vimtex-clean)', '[l]atex [c]lean aux files')
  end,
})
