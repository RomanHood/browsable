--- browsable.nvim public API
--- Exposes setup(), audit(), doctor(), and target().

local M = {}

local _config = nil -- set by setup()

--- ─── helpers ───────────────────────────────────────────────────────────────

--- Build the base CLI argv from config.
local function cli_cmd(config, ...)
  local cmd = vim.deepcopy(config.cli)
  for _, arg in ipairs({ ... }) do
    table.insert(cmd, arg)
  end
  return cmd
end

--- Map a browsable severity string to a quickfix type character.
local severity_map = { error = "E", warning = "W", info = "I" }

--- Convert findings array to quickfix items.
--- @param findings table[]
--- @return table[]
local function findings_to_qflist(findings)
  local items = {}
  for _, f in ipairs(findings) do
    items[#items + 1] = {
      filename = f.file or "",
      lnum     = f.line or 1,
      col      = f.column or 1,
      text     = ("[%s] %s"):format(f.feature_name or f.feature_id or "?", f.message or ""),
      type     = severity_map[f.severity] or "W",
    }
  end
  return items
end

--- Run a CLI command asynchronously, collect stdout, then call on_exit(stdout, code).
--- Uses vim.system (Neovim 0.10+) with a vim.fn.jobstart fallback.
--- @param cmd      string[]
--- @param on_exit  fun(stdout: string, code: integer)
local function run_async(cmd, on_exit)
  if vim.system then
    -- Neovim 0.10+ path
    vim.system(cmd, { text = true }, function(result)
      vim.schedule(function()
        on_exit(result.stdout or "", result.code or 0)
      end)
    end)
  else
    -- Fallback for older Neovim builds
    local stdout_buf = {}
    vim.fn.jobstart(cmd, {
      stdout_buffered = true,
      on_stdout = function(_, data)
        if data then
          for _, line in ipairs(data) do
            stdout_buf[#stdout_buf + 1] = line
          end
        end
      end,
      on_exit = function(_, code)
        vim.schedule(function()
          on_exit(table.concat(stdout_buf, "\n"), code)
        end)
      end,
    })
  end
end

--- ─── public API ─────────────────────────────────────────────────────────────

--- Initialize the plugin with user options.
--- @param opts table|nil  Partial configuration overrides.
function M.setup(opts)
  local cfg = require("browsable.config")
  local lsp = require("browsable.lsp")

  _config = cfg.merge(opts)

  if _config.auto_start then
    lsp.attach(_config)
  end
end

--- Run `browsable audit --format json` over the project, populate the quickfix
--- list, open the quickfix window, and display a summary notification.
function M.audit()
  local config = _config or require("browsable.config").merge()
  local cmd = cli_cmd(config, "audit", "--format", "json")

  if vim.fn.executable(config.cli[1]) == 0 then
    vim.notify(
      ("browsable.nvim: %q not found on PATH."):format(config.cli[1]),
      vim.log.levels.ERROR
    )
    return
  end

  run_async(cmd, function(stdout, code)
    if code ~= 0 and stdout == "" then
      vim.notify(
        ("browsable audit exited with code %d."):format(code),
        vim.log.levels.ERROR
      )
      return
    end

    local ok, data = pcall(vim.json.decode, stdout)
    if not ok or type(data) ~= "table" then
      vim.notify("browsable.nvim: failed to parse audit JSON output.", vim.log.levels.ERROR)
      return
    end

    local findings = data.findings or {}
    local items = findings_to_qflist(findings)
    vim.fn.setqflist(items, "r")

    if #items > 0 then
      vim.cmd("copen")
    end

    local summary = data.summary or {}
    vim.notify(
      ("browsable audit: %d error(s), %d warning(s), %d info(s) across %d file(s)."):format(
        summary.errors or 0,
        summary.warnings or 0,
        summary.infos or 0,
        summary.files or 0
      ),
      (#items > 0) and vim.log.levels.WARN or vim.log.levels.INFO
    )
  end)
end

--- Open a floating terminal window running `browsable doctor`.
function M.doctor()
  local config = _config or require("browsable.config").merge()

  if vim.fn.executable(config.cli[1]) == 0 then
    vim.notify(
      ("browsable.nvim: %q not found on PATH."):format(config.cli[1]),
      vim.log.levels.ERROR
    )
    return
  end

  -- Calculate ~80 % of editor dimensions, centered.
  local width  = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines   * 0.8)
  local row    = math.floor((vim.o.lines   - height) / 2)
  local col    = math.floor((vim.o.columns - width)  / 2)

  local buf = vim.api.nvim_create_buf(false, true) -- scratch, unlisted
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width    = width,
    height   = height,
    row      = row,
    col      = col,
    style    = "minimal",
    border   = "rounded",
    title    = " browsable doctor ",
    title_pos = "center",
  })

  -- Build the shell command string for termopen.
  local shell_cmd = table.concat(vim.list_extend(vim.deepcopy(config.cli), { "doctor" }), " ")
  vim.fn.termopen(shell_cmd, {
    on_exit = function()
      -- Pressing any key closes the float when the command finishes.
      vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>bdelete!<CR>", { noremap = true, silent = true })
      vim.api.nvim_buf_set_keymap(buf, "t", "q", "<cmd>bdelete!<CR>", { noremap = true, silent = true })
    end,
  })
  vim.cmd("startinsert")
end

--- Run `browsable target --json` and notify the resolved target + browsers.
function M.target()
  local config = _config or require("browsable.config").merge()
  local cmd = cli_cmd(config, "target", "--json")

  if vim.fn.executable(config.cli[1]) == 0 then
    vim.notify(
      ("browsable.nvim: %q not found on PATH."):format(config.cli[1]),
      vim.log.levels.ERROR
    )
    return
  end

  run_async(cmd, function(stdout, code)
    if code ~= 0 and stdout == "" then
      vim.notify(
        ("browsable target exited with code %d."):format(code),
        vim.log.levels.ERROR
      )
      return
    end

    local ok, data = pcall(vim.json.decode, stdout)
    if not ok or type(data) ~= "table" then
      vim.notify("browsable.nvim: failed to parse target JSON output.", vim.log.levels.ERROR)
      return
    end

    local query    = data.query or "(unknown)"
    local browsers = data.browsers or {}
    local lines    = { ("Target query: %s"):format(query) }
    for browser, version in pairs(browsers) do
      lines[#lines + 1] = ("  %s %s"):format(browser, version)
    end
    vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
  end)
end

return M
