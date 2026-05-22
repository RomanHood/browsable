--- browsable.nvim config module
--- Manages default configuration and user option merging.

local M = {}

M.defaults = {
  --- Filetypes that trigger LSP auto-attach.
  filetypes = { "css", "scss", "html", "eruby", "javascript" },

  --- Command used to start the browsable-lsp server (stdio JSON-RPC).
  cmd = { "browsable-lsp" },

  --- CLI command for one-shot audit/doctor/target operations.
  cli = { "browsable" },

  --- When true, automatically attach the LSP on matching filetypes after setup().
  auto_start = true,

  --- Files / directories used to locate the project root.
  root_markers = { "Gemfile", ".browsable.yml", "config/browsable.yml" },
}

--- Deep-merge user-supplied opts over the defaults.
--- @param opts table|nil  User options (partial or nil).
--- @return table          Merged configuration table.
function M.merge(opts)
  return vim.tbl_deep_extend("force", M.defaults, opts or {})
end

return M
