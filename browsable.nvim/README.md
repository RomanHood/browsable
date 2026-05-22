# browsable.nvim

A Neovim plugin that integrates the [`browsable`](https://github.com/romanhood/browsable) Rails browser-compatibility audit toolkit into your editor. The plugin wires `browsable-lsp` (a stdio JSON-RPC language server) into Neovim's built-in LSP client so you get inline diagnostics as you edit CSS, SCSS, HTML, ERB, and JavaScript files. It also exposes three commands that shell out to the `browsable` CLI for project-wide audits, system-dependency checks, and browser-target inspection — all without reimplementing any analysis logic inside Neovim.

---

## Prerequisites

| Dependency | How to install | Purpose |
|---|---|---|
| `browsable-lsp` | `gem install browsable-lsp` | LSP server — **must** be on `PATH` |
| `browsable` | `gem install browsable` | CLI — required for `:Browsable`, `:BrowsableDoctor`, `:BrowsableTarget` |
| Neovim ≥ 0.10 | [neovim.io](https://neovim.io) | Plugin uses `vim.system`, `vim.fs.root`, etc. |

Verify the binaries are reachable before loading the plugin:

```sh
which browsable-lsp
which browsable
```

---

## Installation

Because `browsable.nvim` lives in the `browsable.nvim/` **subdirectory** of the monorepo `https://github.com/romanhood/browsable`, each plugin manager needs a small hint to point at the right subdirectory.

### lazy.nvim

lazy.nvim does not natively resolve a plugin from a repository subdirectory at
install time. The most reliable approach is to clone the repo manually and
point lazy at the local directory with `dir`:

```sh
git clone https://github.com/romanhood/browsable.git ~/.local/share/nvim/browsable-mono
```

Then in your lazy spec:

```lua
{
  dir    = vim.fn.stdpath("data") .. "/browsable-mono/browsable.nvim",
  name   = "browsable.nvim",
  config = function()
    require("browsable").setup()
  end,
}
```

Alternatively, if you prefer sparse-checkout so you only pull the plugin subtree:

```sh
git clone --no-checkout --depth=1 https://github.com/romanhood/browsable.git \
    ~/.local/share/nvim/browsable-mono
cd ~/.local/share/nvim/browsable-mono
git sparse-checkout set browsable.nvim
git checkout
```

> **Note:** lazy.nvim's `url` + `subdir` combination is not a first-class
> feature. The `dir` / sparse-checkout approaches above are the honest,
> practical solutions. A native subdirectory spec (`{ url = "...", subdir =
> "browsable.nvim" }`) is only available in forks / future versions of lazy.

### packer.nvim

packer supports the `rtp` option, which sets the runtime path to a
subdirectory of the cloned repo — exactly what is needed here:

```lua
use {
  "romanhood/browsable",
  rtp    = "browsable.nvim",
  config = function()
    require("browsable").setup()
  end,
}
```

packer clones the full repo to `~/.local/share/nvim/site/pack/packer/start/browsable`
and prepends `browsable.nvim/` to the runtime path, so `lua/browsable/` is
found correctly.

### vim-plug

vim-plug also supports the `rtp` option for subdirectory plugins:

```vim
Plug 'romanhood/browsable', { 'rtp': 'browsable.nvim' }
```

Then in your `init.vim` (or in a `lua heredoc` / separate `init.lua`):

```vim
lua require("browsable").setup()
```

Or if you use `init.lua`:

```lua
require("browsable").setup()
```

---

## Configuration

`setup()` accepts a table of options. All keys are optional — any key you omit
falls back to the default shown below:

```lua
require("browsable").setup({
  -- Neovim filetypes that trigger auto-attachment of browsable-lsp.
  filetypes = { "css", "scss", "html", "eruby", "javascript" },

  -- Command used to launch the LSP server (stdio JSON-RPC).
  cmd = { "browsable-lsp" },

  -- Command used for one-shot CLI operations (audit, doctor, target).
  cli = { "browsable" },

  -- When true, registers a FileType autocmd to auto-attach the LSP after setup().
  auto_start = true,

  -- Markers used to locate the project root (searched upward from current file).
  root_markers = { "Gemfile", ".browsable.yml", "config/browsable.yml" },
})
```

---

## Commands

| Command | Description |
|---|---|
| `:Browsable` | Run `browsable audit --format json`, populate the quickfix list, and open it. |
| `:BrowsableDoctor` | Open a floating terminal running `browsable doctor` (press `q` to close). |
| `:BrowsableTarget` | Notify the resolved browser-support query and browser versions. |

### Quickfix severity mapping

| browsable severity | quickfix type |
|---|---|
| `error` | `E` |
| `warning` | `W` |
| `info` | `I` |

---

## How it works

1. **LSP** — on `FileType` events matching `config.filetypes`, the plugin calls
   `vim.lsp.start` with `browsable-lsp`. Neovim's built-in LSP client handles
   the JSON-RPC transport and displays diagnostics natively. An existing client
   for the same root directory is reused automatically.

2. **Audit** — `:Browsable` shells out to `browsable audit --format json`
   asynchronously (`vim.system` on Neovim 0.10+, `vim.fn.jobstart` fallback),
   decodes the JSON with `vim.json.decode`, converts findings to quickfix items,
   and calls `vim.fn.setqflist`.

3. **Doctor** — `:BrowsableDoctor` opens a centred floating window (~80 % of
   the editor) and runs `browsable doctor` inside a `:terminal`.

4. **Target** — `:BrowsableTarget` shells out to `browsable target --json`,
   decodes the result, and emits a `vim.notify` message with the resolved query
   and per-browser versions.

---

## License

MIT
