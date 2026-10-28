-- Linting

vim.pack.add { 'https://github.com/mfussenegger/nvim-lint' }

local lint = require 'lint'
lint.linters_by_ft = {
  markdown = { 'markdownlint' }, -- Make sure to install `markdownlint` via mason / npm
  go = { 'golangcilint' },
  python = { 'ruff' },
}

-- To allow other plugins to add linters to require('lint').linters_by_ft,
-- instead set linters_by_ft like this:
-- lint.linters_by_ft = lint.linters_by_ft or {}
-- lint.linters_by_ft['markdown'] = { 'markdownlint' }
--
-- However, note that this will enable a set of default linters,
-- which will cause errors unless these tools are available:
-- {
--   clojure = { "clj-kondo" },
--   dockerfile = { "hadolint" },
--   inko = { "inko" },
--   janet = { "janet" },
--   json = { "jsonlint" },
--   markdown = { "vale" },
--   rst = { "vale" },
--   ruby = { "ruby" },
--   terraform = { "tflint" },
--   text = { "vale" }
-- }
--
-- You can disable the default linters by setting their filetypes to nil:
-- lint.linters_by_ft['clojure'] = nil
-- lint.linters_by_ft['dockerfile'] = nil
-- lint.linters_by_ft['inko'] = nil
-- lint.linters_by_ft['janet'] = nil
-- lint.linters_by_ft['json'] = nil
-- lint.linters_by_ft['markdown'] = nil
-- lint.linters_by_ft['rst'] = nil
-- lint.linters_by_ft['ruby'] = nil
-- lint.linters_by_ft['terraform'] = nil
-- lint.linters_by_ft['text'] = nil


-- nvim-lint spawns each configured linter unconditionally, so a tool that
-- isn't installed raises `ENOENT` on every single write -- the linter is
-- named in linters_by_ft above, but nothing checks it actually exists.
-- Filter to the ones on $PATH (Mason's bin directory included) and say so
-- once, rather than failing loudly forever or skipping silently.
local warned = false
local function installed(ft)
  local names, ok = lint.linters_by_ft[ft] or {}, {}
  local missing = {}
  for _, name in ipairs(names) do
    -- Indexing lint.linters requires the linter module, so guard it: a
    -- typo'd name would otherwise throw from inside the autocmd.
    local found, linter = pcall(function() return lint.linters[name] end)
    local cmd = found and type(linter) == 'table' and linter.cmd or nil
    if type(cmd) == 'function' then cmd = cmd() end
    if cmd and vim.fn.executable(cmd) == 1 then
      table.insert(ok, name)
    else
      table.insert(missing, name)
    end
  end
  if #missing > 0 and not warned then
    warned = true
    vim.notify(
      ('lint: not installed, skipping: %s  (:MasonInstall %s)'):format(
        table.concat(missing, ', '),
        table.concat(missing, ' ')
      ),
      vim.log.levels.WARN
    )
  end
  return ok
end

-- Create autocommand which carries out the actual linting
-- on the specified events.
local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
  group = lint_augroup,
  callback = function()
    -- Only run the linter in buffers that you can modify in order to
    -- avoid superfluous noise, notably within the handy LSP pop-ups that
    -- describe the hovered symbol using Markdown.
    if vim.bo.modifiable then lint.try_lint(installed(vim.bo.filetype)) end
  end,
})
