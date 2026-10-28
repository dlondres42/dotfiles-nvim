-- In-buffer markdown rendering: headings, tables, code blocks and lists are
-- drawn with real styling instead of raw syntax, without leaving the buffer
-- or spawning a browser.
--
-- Requires the `markdown` and `markdown_inline` treesitter parsers, both of
-- which are already installed under ~/.local/share/nvim/site/parser.
--
-- Anti-conceal is the reason this is usable for editing rather than just
-- viewing: the line the cursor is on reverts to raw markdown, so you always
-- edit the real text and only the other lines are decorated.

vim.pack.add { 'https://github.com/MeanderingProgrammer/render-markdown.nvim' }

require('render-markdown').setup {
  -- Deliberately NOT including quarto or the python buffers jupytext
  -- produces: notebook markdown cells live in a python buffer and molten
  -- already owns their display.
  file_types = { 'markdown' },

  anti_conceal = { enabled = true },

  -- Both are off because their treesitter parsers aren't installed, and
  -- render-markdown warns on every :checkhealth otherwise. To turn either
  -- on: :TSInstall yaml latex  (latex additionally needs the `latex2text`
  -- binary from pylatexenc on $PATH to convert $...$ math to unicode).
  latex = { enabled = false },
  yaml = { enabled = false },

  heading = {
    -- Coloured background bar per level, rather than leading '#' characters.
    width = 'block',
    left_pad = 0,
    right_pad = 2,
    icons = { '󰲡 ', '󰲣 ', '󰲥 ', '󰲧 ', '󰲩 ', '󰲫 ' },
  },

  code = {
    style = 'full',
    width = 'block',
    right_pad = 2,
    -- Language name shown in the top-left of the block.
    language_name = true,
    border = 'thin',
  },

  bullet = { icons = { '●', '○', '◆', '◇' } },

  checkbox = {
    unchecked = { icon = '󰄱 ' },
    checked = { icon = '󰱒 ' },
  },

  pipe_table = { style = 'full', alignment_indicator = '━' },

  -- GitHub-style > [!NOTE] / [!WARNING] blocks.
  callout = { note = { raw = '[!NOTE]' }, warning = { raw = '[!WARNING]' } },
}

vim.keymap.set(
  'n',
  '<leader>tm',
  '<cmd>RenderMarkdown toggle<CR>',
  { silent = true, desc = '[T]oggle [m]arkdown rendering' }
)
