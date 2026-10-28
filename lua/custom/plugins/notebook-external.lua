-- Hand .ipynb files off to VS Code instead of editing them in nvim.
--
-- The molten/jupytext stack in notebook.lua is left intact and still reachable;
-- this just makes VS Code the default destination for a notebook:
--
--   nvim foo.ipynb            -> VS Code, nvim exits
--   :e foo.ipynb              -> VS Code (so does neo-tree, telescope, gf)
--   :NotebookOpen [file]      -> send a notebook to VS Code on demand
--   :NotebookEdit <file>      -> open in nvim with molten, bypassing the handoff
--   NB_NVIM=1 nvim foo.ipynb  -> molten for the whole session
--
-- Set `vim.g.notebook_external = false` to turn the handoff off entirely.

if vim.g.notebook_external == nil then vim.g.notebook_external = vim.env.NB_NVIM == nil end

-- VS Code already carries ms-python.python + ms-toolsai.jupyter, so a notebook
-- opens with real cells and a kernel picker.
local EXTERNAL = 'code'

local group = vim.api.nvim_create_augroup('notebook-external', { clear = true })

-- ------------------------------------------------------------ uv project ---
-- The notebook's kernel has to come from the uv venv that owns it, and this is
-- a monorepo -- client_code, dolores-lib and inference-server each have their
-- own .venv -- so "the project" is the nearest directory above the file that
-- has one, not the git root.
local function uv_project(file)
  local venv = vim.fs.find('.venv', {
    path = vim.fn.fnamemodify(file, ':p:h'),
    upward = true,
    type = 'directory',
  })[1]
  if not venv then return nil end
  local root = vim.fn.fnamemodify(venv, ':h')
  return vim.uv.fs_stat(venv .. '/bin/python') and root or nil
end

-- --------------------------------------------------------- vscode settings --
-- Pointing VS Code at the venv is what actually gets the right kernel. The
-- notebooks here carry `metadata.kernelspec.name = "python3"`, which matches
-- nothing in particular, so without this the Jupyter extension falls back to
-- whatever interpreter it happens to find first.
--
-- `python.defaultInterpreterPath` is only consulted when no interpreter has
-- been chosen for the workspace yet, which is exactly the first-open case --
-- once you pick one by hand VS Code remembers it and this stops mattering.
local SETTINGS_KEY = 'python.defaultInterpreterPath'
local SETTINGS_VALUE = '${workspaceFolder}/.venv/bin/python'

-- vim.json.encode emits one long line. settings.json is a file people read and
-- edit by hand, and this one lands in a git repo, so print it properly.
local function encode(value, indent)
  indent = indent or ''
  local pad = indent .. '  '
  if type(value) ~= 'table' then return vim.json.encode(value) end
  if vim.tbl_isempty(value) then return vim.islist(value) and '[]' or '{}' end

  local parts = {}
  if vim.islist(value) then
    for _, v in ipairs(value) do
      table.insert(parts, pad .. encode(v, pad))
    end
    return '[\n' .. table.concat(parts, ',\n') .. '\n' .. indent .. ']'
  end
  -- Stable order, so regenerating the file produces no spurious diff.
  local keys = vim.tbl_keys(value)
  table.sort(keys)
  for _, k in ipairs(keys) do
    table.insert(parts, pad .. vim.json.encode(k) .. ': ' .. encode(value[k], pad))
  end
  return '{\n' .. table.concat(parts, ',\n') .. '\n' .. indent .. '}'
end

local function ensure_vscode_settings(root)
  local path = root .. '/.vscode/settings.json'
  local settings = {}

  local fd = io.open(path, 'r')
  if fd then
    local raw = fd:read 'a'
    fd:close()
    local ok, decoded = pcall(vim.json.decode, raw, { luanil = { object = true, array = true } })
    -- VS Code accepts comments and trailing commas in settings.json; vim.json
    -- does not. Rewriting a file we failed to parse would destroy it, so back
    -- off and let the user add the one key themselves.
    if not ok or type(decoded) ~= 'table' then
      vim.notify(
        ('notebook: could not parse %s -- add "%s": "%s" by hand'):format(path, SETTINGS_KEY, SETTINGS_VALUE),
        vim.log.levels.WARN
      )
      return
    end
    -- Never overwrite a deliberate choice.
    if decoded[SETTINGS_KEY] then return end
    settings = decoded
  end

  settings[SETTINGS_KEY] = SETTINGS_VALUE
  vim.fn.mkdir(root .. '/.vscode', 'p')
  local out = io.open(path, 'w')
  if not out then
    vim.notify('notebook: could not write ' .. path, vim.log.levels.ERROR)
    return
  end
  out:write(encode(settings) .. '\n')
  out:close()
  vim.notify('notebook: pinned VS Code to ' .. vim.fn.fnamemodify(root, ':t') .. '/.venv')
end

-- --------------------------------------------------------------- launch -----
local function open_external(file)
  file = vim.fn.fnamemodify(file, ':p')
  if vim.fn.executable(EXTERNAL) == 0 then
    vim.notify(('notebook: %s is not on $PATH'):format(EXTERNAL), vim.log.levels.ERROR)
    return false
  end

  local cmd = { EXTERNAL }
  -- Opening the uv project as the workspace folder, not just the file, is what
  -- lets the Python extension discover .venv at all -- a lone file argument
  -- gives VS Code no workspace to resolve the interpreter against.
  local root = uv_project(file)
  if root then
    ensure_vscode_settings(root)
    table.insert(cmd, root)
  end
  table.insert(cmd, file)

  -- Detached: `code` forks a long-lived window, and a non-detached child would
  -- keep nvim's job table (and, on the startup path, nvim itself) waiting on it.
  local ok, err = pcall(vim.system, cmd, { detach = true })
  if not ok then
    vim.notify('notebook: could not launch ' .. EXTERNAL .. ': ' .. tostring(err), vim.log.levels.ERROR)
    return false
  end
  return true
end

-- ------------------------------------------------------------- commands -----
local bypass = {}

vim.api.nvim_create_user_command('NotebookOpen', function(opts)
  local file = opts.args ~= '' and opts.args or vim.api.nvim_buf_get_name(0)
  if file == '' then
    vim.notify('NotebookOpen: no file', vim.log.levels.ERROR)
    return
  end
  if open_external(file) then vim.notify('opened ' .. vim.fn.fnamemodify(file, ':t') .. ' in VS Code') end
end, { nargs = '?', complete = 'file', desc = 'Open a notebook in VS Code' })

vim.api.nvim_create_user_command('NotebookEdit', function(opts)
  bypass[vim.fn.fnamemodify(opts.args, ':p')] = true
  vim.cmd.edit(vim.fn.fnameescape(opts.args))
end, { nargs = 1, complete = 'file', desc = 'Open a notebook in nvim (molten), bypassing the VS Code handoff' })

vim.keymap.set('n', '<leader>nv', '<cmd>NotebookOpen<CR>', { silent = true, desc = '[N]otebook open in [V]S Code' })

if not vim.g.notebook_external then return end

-- ------------------------------------------------------------- startup ------
-- Only files named on the command line. `vim.fn.argv()` is the launch arglist,
-- and VimEnter is the first point at which it is populated and the buffers are
-- real -- the in-session intercept below is not installed yet at that stage.
vim.api.nvim_create_autocmd('VimEnter', {
  group = group,
  -- Required for the sidecar cleanup below: autocmds triggered from inside an
  -- autocmd callback are suppressed unless the outer one is nested, so without
  -- this the BufUnload we provoke never reaches jupytext's cleanup hook.
  nested = true,
  callback = function()
    local args = vim.fn.argv()
    if #args == 0 then return end

    local notebooks = {}
    for _, a in ipairs(args) do
      if a:match '%.ipynb$' then table.insert(notebooks, a) end
    end
    -- A mixed invocation (`nvim main.py notes.ipynb`) means the session is
    -- wanted for the other files, so send the notebooks over but stay open.
    if #notebooks == 0 then return end

    local sent = 0
    for _, nb in ipairs(notebooks) do
      if open_external(nb) then sent = sent + 1 end
    end
    if sent == 0 then return end

    -- jupytext round-trips the notebook through a sidecar file on disk and
    -- deletes it from a BufUnload hook. nvim does *not* fire BufUnload for
    -- buffers still loaded at exit, so quitting straight out of the handoff
    -- leaves a stray `.foo.jupytext.py` next to every notebook you open.
    -- Wiping the buffer first fires the hook and cleans it up.
    for _, nb in ipairs(notebooks) do
      local buf = vim.fn.bufnr(vim.fn.fnamemodify(nb, ':p'))
      if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then pcall(vim.cmd, 'bwipeout! ' .. buf) end
    end

    if #notebooks == #args then
      vim.cmd 'qa!'
    else
      vim.notify(('sent %d notebook(s) to VS Code'):format(sent))
    end
  end,
})

-- ---------------------------------------------------------- in-session ------
-- Everything that opens a file in nvim goes through `:edit` -- neo-tree,
-- telescope, gf, `:e` -- and for *.ipynb that read is owned by a BufReadCmd.
-- Wrapping it catches all of them in one place.
--
-- Deferred to the main loop because the load order of custom/plugins/*.lua is
-- whatever `vim.fs.dir` returns: by the time this runs, notebook.lua has
-- installed its own guarded replacement of jupytext's BufReadCmd, so what we
-- capture is the guard, not the raw jupytext read.
vim.schedule(function()
  local existing = vim.api.nvim_get_autocmds { event = 'BufReadCmd', pattern = '*.ipynb' }
  local inner
  for _, au in ipairs(existing) do
    if au.callback then
      inner = au.callback
      break
    end
  end
  -- No jupytext read to wrap means notebook.lua is disabled or failed to load.
  -- Nothing to fall back to, so leave notebooks alone rather than swallowing
  -- them into a handoff with no escape hatch.
  if not inner then return end

  vim.api.nvim_clear_autocmds { event = 'BufReadCmd', pattern = '*.ipynb' }
  vim.api.nvim_create_autocmd('BufReadCmd', {
    pattern = '*.ipynb',
    group = group,
    callback = function(ev)
      local file = vim.fn.fnamemodify(ev.match, ':p')
      if bypass[file] then
        bypass[file] = nil
        return inner(ev)
      end

      if not open_external(file) then return inner(ev) end

      -- A buffer named foo.ipynb holding something that is not the notebook is
      -- the hazard notebook.lua's guard exists to prevent, so make this one
      -- unwritable for the moment it survives. `nofile` also stops nvim
      -- reporting it as unsaved when we wipe it.
      vim.api.nvim_buf_set_lines(ev.buf, 0, -1, false, { '-- opened in VS Code --' })
      vim.bo[ev.buf].buftype = 'nofile'
      vim.bo[ev.buf].modified = false
      vim.bo[ev.buf].modifiable = false

      -- Wiping a buffer from inside its own BufReadCmd is not allowed (E937),
      -- so drop it on the next tick; the window falls back to whatever it was
      -- showing before.
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(ev.buf) then pcall(vim.cmd, 'bwipeout! ' .. ev.buf) end
      end)
    end,
  })
end)
