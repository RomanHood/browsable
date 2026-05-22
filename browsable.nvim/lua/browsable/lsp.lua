--- browsable.nvim LSP module
--- Handles starting browsable-lsp and auto-attaching it to matching buffers.

local M = {}

--- Resolve the project root for the given buffer using root_markers.
--- Prefers vim.fs.root (Neovim 0.10+); falls back to vim.fs.find.
--- @param bufnr  integer  Buffer handle.
--- @param markers string[]  List of marker filenames / dirs.
--- @return string|nil  Absolute path to the root, or nil if not found.
local function find_root(bufnr, markers)
  -- vim.fs.root is available in Neovim 0.10+
  if vim.fs.root then
    return vim.fs.root(bufnr, markers)
  end

  -- Fallback: walk up from the buffer's file directory.
  local bufpath = vim.api.nvim_buf_get_name(bufnr)
  local start_dir = bufpath ~= "" and vim.fn.fnamemodify(bufpath, ":h") or vim.fn.getcwd()
  local found = vim.fs.find(markers, {
    upward = true,
    path = start_dir,
    limit = 1,
  })
  if found and found[1] then
    return vim.fn.fnamemodify(found[1], ":h")
  end
  return nil
end

--- Start (or re-attach) the browsable-lsp server for the given buffer.
--- @param config table  Merged configuration from config.lua.
--- @param bufnr  integer  Buffer handle (defaults to current buffer).
function M.start(config, bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Guard: ensure the server executable exists.
  local exe = config.cmd[1]
  if vim.fn.executable(exe) == 0 then
    vim.notify(
      ("browsable.nvim: %q not found on PATH. Install it with `gem install browsable-lsp`."):format(exe),
      vim.log.levels.WARN
    )
    return
  end

  local root_dir = find_root(bufnr, config.root_markers)

  vim.lsp.start({
    name = "browsable",
    cmd = config.cmd,
    root_dir = root_dir,
    -- Pass the buffer so Neovim knows which buffer to attach immediately.
    -- vim.lsp.start will reuse an existing client with the same root_dir.
  }, { bufnr = bufnr })
end

--- Set up a FileType autocmd that auto-attaches browsable-lsp to matching buffers.
--- @param config table  Merged configuration from config.lua.
function M.attach(config)
  local group = vim.api.nvim_create_augroup("browsable", { clear = true })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = config.filetypes,
    desc = "Auto-attach browsable-lsp",
    callback = function(ev)
      M.start(config, ev.buf)
    end,
  })
end

return M
