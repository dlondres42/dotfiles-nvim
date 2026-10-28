-- Jupyter notebook support: open a .ipynb as a normal python buffer, run cells
-- against a real kernel, and see the output (text and plots) inline.
--
-- Three plugins stacked:
--   jupytext.nvim  converts .ipynb <-> `# %%` percent-format python on read/write,
--                  so LSP, treesitter, conform and everything else just work.
--   molten-nvim    attaches a Jupyter kernel to the buffer and renders cell output.
--   image.nvim     draws the plots; molten delegates all image rendering to it.
--
-- External requirements:
--   ~/.venvs/neovim  a python env holding pynvim + jupyter_client + friends.
--                    Molten is a remote plugin, so it runs inside *this* python,
--                    not the one your project uses. Kernels are separate.
--   jupytext         must be on $PATH (symlinked into ~/.local/bin).
--   magick           ImageMagick, only needed for plots. `sudo apt install imagemagick`.
--
-- After installing or updating molten, run `:UpdateRemotePlugins` and restart.

local venv = vim.fn.expand '~/.venvs/neovim'

-- Molten's python host. Must have pynvim; without this it falls back to the
-- system python, which is PEP-668 externally-managed and has no jupyter_client.
vim.g.python3_host_prog = venv .. '/bin/python'

vim.pack.add {
  'https://github.com/GCBallesteros/jupytext.nvim',
  'https://github.com/benlubas/molten-nvim',
  'https://github.com/3rd/image.nvim',
}

-- ---------------------------------------------------------------- images ---
-- Which graphics protocol the terminal speaks. Kitty's is the better one (real
-- placement and cropping); sixel is the fallback that Konsole, xterm and foot
-- understand. `crop = false` on the sixel backend means images can bleed when
-- scrolled partly off screen -- that's a backend limitation, not a config bug.
local function image_backend()
  local term, prog = vim.env.TERM or '', vim.env.TERM_PROGRAM or ''
  local kitty = vim.env.KITTY_WINDOW_ID
    or vim.env.GHOSTTY_RESOURCES_DIR
    or term:match 'kitty'
    or term:match 'ghostty'
    or prog == 'WezTerm'
    or prog == 'ghostty'
  return kitty and 'kitty' or 'sixel'
end

local has_magick = vim.fn.executable 'magick' == 1 or vim.fn.executable 'convert' == 1

if has_magick then
  -- Exposed so `:echo g:notebook_image_backend` says which protocol is in use;
  -- that plus $TERM is the whole diagnosis when plots don't show up.
  vim.g.notebook_image_backend = image_backend()
  require('image').setup {
    backend = vim.g.notebook_image_backend,
    processor = 'magick_cli', -- shells out to `magick`; avoids the luarocks dep
    -- Molten places every image itself. Leaving the file-type integrations on
    -- would double-render plots in markdown cells.
    integrations = {},
    max_width_window_percentage = math.huge,
    max_height_window_percentage = math.huge,
    window_overlap_clear_enabled = true,
    window_overlap_clear_ft_ignore = { 'cmp_menu', 'cmp_docs', '' },
  }
end

-- ---------------------------------------------------------------- molten ---
vim.g.molten_image_provider = has_magick and 'image.nvim' or 'none'

-- Show output as virtual lines under the cell rather than in a floating window,
-- so results stay visible while you keep editing. Text output renders fine this
-- way even with no image support at all.
vim.g.molten_virt_text_output = true
-- Only for markdown/quarto, where a cell ends in a closing fence and output has
-- to clear it. Percent-format python has no fence, so leaving this on renders
-- every output one line below the cell it belongs to.
vim.g.molten_virt_lines_off_by_1 = false
vim.g.molten_auto_open_output = false
vim.g.molten_output_virt_lines = false

vim.g.molten_output_win_max_height = 20
vim.g.molten_wrap_output = true
vim.g.molten_output_show_more = true
vim.g.molten_use_border_highlights = true
vim.g.molten_enter_output_behavior = 'open_then_enter'

-- -------------------------------------------------------------- jupytext ---
require('jupytext').setup {
  -- "hydrogen" writes markdown cells as `# %% [markdown]` comment blocks inside
  -- a .py file. The alternative ("markdown") gives prettier prose but turns the
  -- buffer into markdown, which costs you python LSP everywhere.
  style = 'hydrogen',
  output_extension = 'auto',
  force_ft = nil,
}

-- -------------------------------------------------------------- keymaps ----
require('which-key').add { { '<leader>n', group = '[N]otebook', mode = { 'n', 'v' } } }

local map = function(mode, lhs, rhs, desc) vim.keymap.set(mode, lhs, rhs, { silent = true, desc = desc }) end

-- Prefer the kernel belonging to the project this buffer lives in. uv writes the
-- project name into pyproject.toml, and `ipykernel install --name <that>` puts a
-- kernelspec of the same name in ~/.local/share/jupyter/kernels pointing at the
-- project's .venv -- so the name in the toml is enough to find the right kernel.
-- Falls back to molten's picker when the project has no kernel registered yet.
local function project_kernel()
  local start = vim.fn.expand '%:p:h'
  if start == '' then start = vim.uv.cwd() end
  local toml = vim.fs.find('pyproject.toml', { path = start, upward = true })[1]
  if not toml then return nil end
  -- Only [project].name identifies the distribution; a `name` under [tool.*] or
  -- [build-system] is something else entirely, so track which table we're in.
  local in_project = false
  for line in io.lines(toml) do
    local header = line:match '^%s*%[%s*([^%]]-)%s*%]'
    if header then in_project = header == 'project' end
    if in_project then
      local name = line:match '^%s*name%s*=%s*["\']([^"\']+)["\']'
      if name then
        return vim.uv.fs_stat(vim.fn.expand '~/.local/share/jupyter/kernels/' .. name) and name or nil
      end
    end
  end
  return nil
end

map('n', '<leader>ni', function()
  local kernel = project_kernel()
  vim.cmd(kernel and ('MoltenInit ' .. kernel) or 'MoltenInit')
end, '[N]otebook [i]nit kernel (project venv if registered)')
map('n', '<leader>ne', ':MoltenEvaluateOperator<CR>', '[N]otebook [e]valuate operator')
map('n', '<leader>nl', ':MoltenEvaluateLine<CR>', '[N]otebook evaluate [l]ine')
map('n', '<leader>nc', ':MoltenReevaluateCell<CR>', '[N]otebook re-evaluate [c]ell')
map('v', '<leader>ne', ':<C-u>MoltenEvaluateVisual<CR>gv', '[N]otebook [e]valuate selection')
map('n', '<leader>nd', ':MoltenDelete<CR>', '[N]otebook [d]elete cell')
map('n', '<leader>no', ':MoltenShowOutput<CR>', '[N]otebook show [o]utput')
map('n', '<leader>nO', ':MoltenHideOutput<CR>', '[N]otebook hide [O]utput')
map('n', '<leader>nn', ':noautocmd MoltenEnterOutput<CR>', '[N]otebook e[n]ter output window')
map('n', '<leader>nj', ':MoltenNext<CR>', '[N]otebook next cell')
map('n', '<leader>nk', ':MoltenPrev<CR>', '[N]otebook prev cell')
map('n', '<leader>nx', ':MoltenInterrupt<CR>', '[N]otebook interrupt (e[x]it run)')
map('n', '<leader>nR', ':MoltenRestart!<CR>', '[N]otebook [R]estart kernel')
map('n', '<leader>ns', ':MoltenImportOutput<CR>', '[N]otebook [s]lurp saved output')
map('n', '<leader>nS', ':MoltenExportOutput!<CR>', '[N]otebook [S]ave output to .ipynb')

-- ------------------------------------------------------------ autocmds -----
-- Molten stores output against the *python* buffer jupytext hands us, but the
-- outputs live in the .ipynb on disk. Pull them in once the kernel is up so a
-- reopened notebook shows its previous results.
vim.api.nvim_create_autocmd('User', {
  pattern = 'MoltenInitPost',
  callback = function()
    -- A scaffolded notebook has no file on disk until its first :w, and molten
    -- prints its own error if you ask it to import from one that isn't there.
    local file = vim.api.nvim_buf_get_name(0)
    if file:match '%.ipynb$' and vim.uv.fs_stat(file) then pcall(vim.cmd, 'MoltenImportOutput') end
  end,
})

-- Write output back into the notebook whenever you save it, so results survive
-- outside nvim (in JupyterLab, in a diff, on GitHub).
vim.api.nvim_create_autocmd('BufWritePost', {
  pattern = '*.ipynb',
  callback = function()
    -- MoltenStatusLineInit only exists once the remote plugin host has started,
    -- so guard the whole probe rather than just the export.
    local ok, status = pcall(function() return require('molten.status').initialized() end)
    if ok and status == 'Molten' then pcall(vim.cmd, 'MoltenExportOutput!') end
  end,
})

-- ------------------------------------------------------------- repair ------
-- Two ways a .ipynb ends up unopenable, both fixed by `:NotebookRepair [file]`:
--
--   1. Valid notebook JSON with no `metadata.kernelspec`. jupytext.nvim indexes
--      that key unconditionally and throws; notebooks built by nbformat,
--      papermill and the nbconvert exporters often don't carry one. Stamp in a
--      default so they open.
--   2. The file is not JSON at all -- it holds the percent-format *python* text
--      that should have been converted back on save. That is what a raw `:w`
--      over a half-read notebook buffer leaves behind (see the guard below).
--      The cells are all still there in text form, so convert them back.
-- Kernel stamped into notebooks this config creates or rebuilds. Prefer the one
-- belonging to the project so the .ipynb opens against its own venv elsewhere
-- (JupyterLab, VSCode); the shared neovim env is only the fallback.
local fallback_kernel = 'neovim'

-- Appends `--set-kernel <name>` when a matching kernelspec is actually
-- installed -- jupytext errors out rather than warning if it isn't.
local function add_set_kernel(args)
  local name = project_kernel() or fallback_kernel
  if vim.uv.fs_stat(vim.fn.expand('~/.local/share/jupyter/kernels/' .. name)) then
    vim.list_extend(args, { '--set-kernel', name })
  end
end

local function repair_kernelspec(file)
  local script = [[
import json, sys
p = sys.argv[1]
nb = json.load(open(p))
md = nb.setdefault("metadata", {})
if "kernelspec" in md:
    print("already has kernelspec")
else:
    md["kernelspec"] = {"display_name": "Python 3", "language": "python", "name": "python3"}
    md.setdefault("language_info", {"name": "python", "file_extension": ".py"})
    json.dump(nb, open(p, "w"), indent=1)
    print("added kernelspec")
]]
  local res = vim.system({ vim.g.python3_host_prog, '-c', script, file }, { text = true }):wait()
  return res.code == 0, vim.trim((res.stdout or '') .. (res.stderr or ''))
end

-- Turn percent-format text back into a notebook. Outputs are gone either way --
-- they never survived the bad write -- but the code does.
local function repair_from_text(file, content)
  -- An interrupted read leaves jupytext.nvim's sentinel blank line at the top.
  -- It has to go: with a leading blank, jupytext stops recognising the `# ---`
  -- YAML block as metadata and folds the whole header into a code cell.
  content = content:gsub('^\n', '')

  local backup = file .. '.corrupt.bak'
  local fd = io.open(backup, 'w')
  if not fd then return false, 'could not write backup ' .. backup end
  fd:write(content)
  fd:close()

  local args = { 'jupytext', '--from', 'py:hydrogen', '--to', 'ipynb' }
  add_set_kernel(args)
  vim.list_extend(args, { '-o', file, '-' })

  local res = vim.system(args, { stdin = content, text = true }):wait()
  if res.code ~= 0 then return false, vim.trim((res.stderr or '') .. (res.stdout or '')) end
  return true, ('rebuilt notebook from percent-format text (previous contents kept in %s)'):format(
    vim.fn.fnamemodify(backup, ':t')
  )
end

vim.api.nvim_create_user_command('NotebookRepair', function(opts)
  local file = opts.args ~= '' and opts.args or vim.fn.expand '%:p'
  if not file:match '%.ipynb$' then
    vim.notify('NotebookRepair: not an .ipynb: ' .. file, vim.log.levels.ERROR)
    return
  end

  local fd = io.open(file, 'r')
  if not fd then
    vim.notify('NotebookRepair: cannot read ' .. file, vim.log.levels.ERROR)
    return
  end
  local content = fd:read 'a'
  fd:close()

  local is_json = pcall(vim.json.decode, content)
  local ok, msg = (is_json and repair_kernelspec or repair_from_text)(file, content)

  vim.notify('NotebookRepair: ' .. msg, ok and vim.log.levels.INFO or vim.log.levels.ERROR)

  -- Reload so the fixed file goes through the jupytext read path. `:edit!`
  -- discards the protected plain-text buffer we were most likely sitting in.
  if ok and vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ':p') == vim.fn.fnamemodify(file, ':p') then
    vim.cmd 'edit!'
  end
end, { nargs = '?', complete = 'file', desc = 'Repair an .ipynb that jupytext cannot open' })

-- --------------------------------------------------------------- guard -----
-- jupytext.nvim's BufReadCmd owns the read for every *.ipynb, and it assumes the
-- file is always a well-formed notebook: it json-decodes it and indexes
-- metadata.kernelspec with no checks. Two cases blow up with a stack trace, and
-- because BufReadCmd owns the read you can't even open the file to fix it.
--
--   1. The file doesn't exist yet, or exists but is empty (neo-tree's "add file"
--      and `touch` both create it on disk first). BufReadCmd still fires.
--      Worse, jupytext's write-back hook is only registered by a *successful*
--      read, so a new notebook is a blank buffer whose `:w` dumps raw text into
--      the .ipynb and corrupts it. Scaffold a real cell and convert on save.
--   2. The file has content but isn't a usable notebook (truncated, not JSON, or
--      missing kernelspec). Fall back to a plain buffer that cannot be saved.
--   3. The read starts but doesn't finish. jupytext.nvim fills the buffer with
--      the converted .py text *before* it registers the BufWriteCmd that turns
--      it back into a notebook, so anything that throws in between -- in
--      practice E325, the swap-file prompt you get from a second nvim or a
--      crashed session -- leaves percent-format text sitting in a buffer named
--      `foo.ipynb` with no write hook on it. The next `:w` writes that text
--      straight over the notebook. Detect the half-read buffer and lock it.
do
  local group = 'jupytext-nvim'
  local existing = vim.api.nvim_get_autocmds { group = group, event = 'BufReadCmd' }
  local jupytext_read = existing[1] and existing[1].callback

  -- ------------------------------------------------------------ sidecar ----
  -- jupytext.nvim round-trips through a real file on disk, and names it by
  -- swapping the extension: foo.ipynb <-> foo.py. That collides with an
  -- ordinary foo.py sitting in the same directory, and the collision is silent
  -- and destructive in both directions -- opening foo.ipynb shows you foo.py's
  -- contents, and saving overwrites foo.py with the notebook. It normally
  -- deletes the file on BufUnload, but a read that throws never registers that
  -- cleanup, so crashes leave one behind and every later open reads the stale
  -- copy. Move the sidecar to a hidden name nothing else can claim.
  local jt_utils = require 'jupytext.utils'

  local function sidecar_path(ipynb, extension)
    local dir = vim.fn.fnamemodify(ipynb, ':h')
    local stem = vim.fn.fnamemodify(ipynb, ':t:r')
    return ('%s/.%s.jupytext.%s'):format(dir, stem, extension)
  end

  jt_utils.get_jupytext_file = sidecar_path

  -- Every sidecar that could belong to this notebook, whatever the language.
  local function sidecars(ipynb)
    local dir = vim.fn.fnamemodify(ipynb, ':h')
    local stem = vim.fn.fnamemodify(ipynb, ':t:r')
    return vim.fn.glob(('%s/.%s.jupytext.*'):format(dir, stem), false, true)
  end

  -- Returns nil when jupytext can handle the file, 'new' when it doesn't exist
  -- yet, or a reason string explaining why it has to be opened as plain text.
  local function classify(file)
    local stat = vim.uv.fs_stat(file)
    if not stat or stat.type ~= 'file' then return 'new' end
    local fd = io.open(file, 'r')
    if not fd then return 'unreadable' end
    local content = fd:read 'a'
    fd:close()
    -- An empty .ipynb is a file someone just created, not a corrupt notebook --
    -- neo-tree's "add file" and `touch` both make it on disk before opening it.
    -- Treat it like a new file and scaffold; there is no content to lose.
    if content:match '^%s*$' then return 'new' end
    local ok, nb = pcall(vim.json.decode, content)
    if not ok or type(nb) ~= 'table' then return 'not valid JSON' end
    if not vim.tbl_get(nb, 'metadata', 'kernelspec') then return 'no metadata.kernelspec, try :NotebookRepair' end
    return nil
  end

  -- Percent-format buffer that writes itself back out as a real notebook. Nothing
  -- touches disk until you actually `:w`, matching what nvim does for any new file.
  local function scaffold(buf)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { '# %%', '' })
    vim.bo[buf].filetype = 'python'
    vim.bo[buf].modified = false

    vim.api.nvim_create_autocmd({ 'BufWriteCmd', 'FileWriteCmd' }, {
      buffer = buf,
      group = group,
      callback = function(w)
        local file = vim.api.nvim_buf_get_name(w.buf)
        local body = table.concat(vim.api.nvim_buf_get_lines(w.buf, 0, -1, false), '\n') .. '\n'
        local args = { 'jupytext', '--from', 'py:hydrogen', '--to', 'ipynb' }
        -- Without a kernelspec the notebook lands unopenable, so this matters.
        add_set_kernel(args)
        vim.list_extend(args, { '-o', file, '-' })

        local res = vim.system(args, { stdin = body, text = true }):wait()
        if res.code ~= 0 then
          vim.notify('jupytext: ' .. vim.trim((res.stderr or '') .. (res.stdout or '')), vim.log.levels.ERROR)
          return
        end
        vim.bo[w.buf].modified = false
        vim.api.nvim_exec_autocmds('BufWritePost', { pattern = file })
      end,
    })
  end

  -- A buffer named *.ipynb whose contents are not backed by a converting write
  -- hook is a loaded gun: `:w` would replace the notebook with plain text. Show
  -- the text -- it is the only copy of the cells in a half-read buffer -- but
  -- make saving impossible. BufWriteCmd owns the write, so a callback that does
  -- nothing is a hard block; `:w!` and `:wq` go through it too.
  local function lock(buf, why)
    vim.bo[buf].filetype = 'python'
    vim.bo[buf].modified = false
    vim.bo[buf].modifiable = false
    vim.bo[buf].readonly = true

    vim.api.nvim_create_autocmd({ 'BufWriteCmd', 'FileWriteCmd' }, {
      buffer = buf,
      group = group,
      callback = function()
        vim.notify('refusing to save: this buffer is not a notebook. Run :NotebookRepair', vim.log.levels.ERROR)
      end,
    })

    vim.notify(
      ('%s: %s -- read-only, run :NotebookRepair to fix'):format(vim.fn.fnamemodify(vim.api.nvim_buf_get_name(buf), ':t'), why),
      vim.log.levels.WARN
    )
  end

  if jupytext_read then
    vim.api.nvim_clear_autocmds { group = group, event = 'BufReadCmd' }
    vim.api.nvim_create_autocmd('BufReadCmd', {
      pattern = '*.ipynb',
      group = group,
      callback = function(ev)
        local reason = classify(ev.match)
        if reason == 'new' then return scaffold(ev.buf) end

        if not reason then
          -- Clear any sidecar a previously crashed read left behind, so the
          -- notebook -- not a stale .py -- is always what gets read. jupytext
          -- silently prefers an existing sidecar over the .ipynb next to it.
          for _, stale in ipairs(sidecars(ev.match)) do
            vim.fn.delete(stale)
          end

          local ok, err = pcall(jupytext_read, ev)
          -- The converting BufWriteCmd is installed near the end of a
          -- successful read, so its presence is the signal that the read got
          -- all the way through. pcall returning true is not enough on its own.
          local hooked = #vim.api.nvim_get_autocmds { event = 'BufWriteCmd', buffer = ev.buf } > 0
          if ok and hooked then return end
          return lock(ev.buf, ok and 'read did not complete' or vim.trim(tostring(err):gsub('%s+', ' ')))
        end

        local lines = {}
        for line in io.lines(ev.match) do
          table.insert(lines, line)
        end
        vim.api.nvim_buf_set_lines(ev.buf, 0, -1, false, lines)
        lock(ev.buf, reason)
      end,
    })
  end
end

-- ----------------------------------------------------------- ruff/ipynb ----
-- The jupytext buffer holds plain python, but its name still ends in .ipynb and
-- ruff keys off the extension: handed a .ipynb it tries to parse the text as
-- notebook JSON and reports `invalid-syntax` at line 1 column 1 for the whole
-- file. Both nvim-lint and conform hand ruff the buffer name via
-- --stdin-filename, so show it a .py name and the cells lint and format normally.
local function as_py(name) return (name:gsub('%.ipynb$', '.py')) end

do
  -- Mutating the linter table in place is safe: nvim-lint's `linters` metatable
  -- `require`s the module, and require caches, so every lookup sees this change.
  local ruff = require('lint').linters.ruff
  for i, arg in ipairs(ruff.args) do
    if type(arg) == 'function' then -- the callable supplying --stdin-filename
      ruff.args[i] = function() return as_py(vim.api.nvim_buf_get_name(0)) end
    end
  end
end

-- conform inherits from the built-in config and merges these over it, so
-- `command`, `stdin` and `cwd` are all kept as-is.
require('conform').formatters.ruff_format = {
  args = function(_, ctx) return { 'format', '--force-exclude', '--stdin-filename', as_py(ctx.filename), '-' } end,
  range_args = function(_, ctx)
    return {
      'format',
      '--force-exclude',
      '--range',
      ('%d:%d-%d:%d'):format(ctx.range.start[1], ctx.range.start[2] + 1, ctx.range['end'][1], ctx.range['end'][2] + 1),
      '--stdin-filename',
      as_py(ctx.filename),
      '-',
    }
  end,
}

-- ------------------------------------------------------------- cells -------
-- Molten evaluates lines, visual selections and motions, but has no notion of a
-- `# %%` cell -- that lives in the text, not in molten. These give the VSCode
-- loop: run the cell under the cursor, and step to the next one (creating it
-- when you're at the bottom) so repeated runs walk down the notebook.
local CELL_PAT = '^#%s*%%%%'

local function cell_range(lnum)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local first = 1
  for i = math.min(lnum, #lines), 1, -1 do
    if lines[i]:match(CELL_PAT) then
      first = i
      break
    end
  end
  local last = #lines
  for i = lnum + 1, #lines do
    if lines[i]:match(CELL_PAT) then
      last = i - 1
      break
    end
  end
  -- Trailing blanks belong to the gap between cells, not the cell. Molten pins
  -- output to the end of the evaluated span, so including them would float the
  -- output away from the code that produced it.
  while last > first and lines[last]:match '^%s*$' do
    last = last - 1
  end
  return first, last
end

local function run_cell()
  local first, last = cell_range(vim.api.nvim_win_get_cursor(0)[1])
  -- MoltenEvaluateVisual reads the '< and '> marks, which are only set once
  -- visual mode has been left.
  vim.api.nvim_win_set_cursor(0, { first, 0 })
  vim.cmd 'normal! V'
  vim.api.nvim_win_set_cursor(0, { last, 0 })
  vim.cmd 'normal! \27'
  vim.cmd 'MoltenEvaluateVisual'
  return last
end

local function goto_next_cell(after)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i = after + 1, #lines do
    if lines[i]:match(CELL_PAT) then
      vim.api.nvim_win_set_cursor(0, { math.min(i + 1, #lines), 0 })
      return
    end
  end
  -- Nothing below: append a fresh cell, the way shift+enter does in VSCode.
  vim.api.nvim_buf_set_lines(0, -1, -1, false, { '', '# %%', '' })
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(0), 0 })
end

local function new_cell(above)
  local first, last = cell_range(vim.api.nvim_win_get_cursor(0)[1])
  local at = above and first - 1 or last
  vim.api.nvim_buf_set_lines(0, at, at, false, { '# %%', '' })
  vim.api.nvim_win_set_cursor(0, { at + 2, 0 })
end

map('n', '<leader>nr', function() run_cell() end, '[N]otebook [r]un cell')
map('n', '<leader><CR>', function() goto_next_cell(run_cell()) end, '[N]otebook run cell and advance')
map('n', '<leader>nb', function() new_cell(false) end, '[N]otebook new cell [b]elow')
map('n', '<leader>na', function() new_cell(true) end, '[N]otebook new cell [a]bove')

-- Konsole does not implement the kitty keyboard protocol, so it cannot tell
-- shift+enter from enter and these will simply never fire there. They cost
-- nothing, and work as-is under kitty/ghostty/wezterm. Plain <CR> is left alone.
map('n', '<S-CR>', function() goto_next_cell(run_cell()) end, '[N]otebook run cell and advance')
map('n', '<C-CR>', function() run_cell() end, '[N]otebook run cell')
