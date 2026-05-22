--- browsable.nvim — auto-loaded plugin entry point.
--- Registers user commands. Does NOT call setup(); the user does that.

if vim.g.loaded_browsable then
  return
end
vim.g.loaded_browsable = true

vim.api.nvim_create_user_command(
  "Browsable",
  function()
    require("browsable").audit()
  end,
  {
    desc = "Run browsable audit and populate the quickfix list",
  }
)

vim.api.nvim_create_user_command(
  "BrowsableDoctor",
  function()
    require("browsable").doctor()
  end,
  {
    desc = "Open a floating terminal running `browsable doctor`",
  }
)

vim.api.nvim_create_user_command(
  "BrowsableTarget",
  function()
    require("browsable").target()
  end,
  {
    desc = "Show the inferred browser-support target",
  }
)
