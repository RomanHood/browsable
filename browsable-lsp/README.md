# browsable-lsp

**A Language Server Protocol server for [`browsable`](../browsable).**

`browsable-lsp` exposes browsable's browser-compatibility audit to your editor.
As you open and edit CSS, ERB, HTML, and JavaScript files, it reports — inline —
which features your code uses that fall outside your project's `allow_browser`
target.

> Part of the [`browsable` monorepo](https://github.com/romanhood/browsable).
> Neovim users want [`browsable.nvim`](../browsable.nvim) instead — it bundles
> this server's wiring.

## What is a language server?

A *language server* is a background program your editor talks to over a small
JSON-RPC protocol (the [Language Server Protocol](https://microsoft.github.io/language-server-protocol/)).
The editor tells the server which files you open and edit; the server tells the
editor what to underline. One server works in every LSP-capable editor, so
browsable's analysis is written once and reused everywhere.

`browsable-lsp` communicates over stdio and pushes **diagnostics** — the
squiggly underlines — for each document you touch.

## Installation

```bash
gem install browsable-lsp
```

This installs the `browsable-lsp` executable. Confirm it is on your `PATH`:

```bash
which browsable-lsp
```

ERB and HTML are audited in-process and need nothing else. For CSS and
JavaScript diagnostics, install stylelint and eslint as described in the
[`browsable` README](../browsable/README.md#system-dependencies--the-doctor-workflow)
(`browsable doctor` will guide you).

## Severity mapping

| browsable category          | LSP severity   |
| --------------------------- | -------------- |
| `below_target`              | Error          |
| `baseline_newly_available`  | Warning        |
| `baseline_widely_available` | Information    |

A diagnostic reads, for example:

> The `popover` attribute requires Firefox 125+, but your `:modern`
> `allow_browser` policy permits Firefox 121.

## Editor setup

Configuration is **inherited from the browsable gem** — `browsable-lsp` discovers
`config/browsable.yml` / `.browsable.yml` from the workspace root exactly as the
CLI does. There is nothing to configure in the server itself.

### VS Code

There is no dedicated extension yet. Use a generic LSP bridge such as
[`vscode-glspc`](https://marketplace.visualstudio.com/items?itemName=qugu.glspc)
and point it at the executable:

```jsonc
// settings.json
{
  "glspc.languageServerPath": "browsable-lsp",
  "glspc.languageId": ["css", "html", "erb", "javascript"]
}
```

### Helix

Add to `~/.config/helix/languages.toml`:

```toml
[language-server.browsable]
command = "browsable-lsp"

[[language]]
name = "erb"
language-servers = ["browsable"]

[[language]]
name = "css"
language-servers = ["browsable"]
```

### Zed

In your Zed settings, register the server (Zed discovers stdio servers via an
extension or the `lsp` settings block):

```jsonc
{
  "lsp": {
    "browsable-lsp": {
      "binary": { "path": "browsable-lsp" }
    }
  }
}
```

### Neovim

Don't wire this up by hand — install [`browsable.nvim`](../browsable.nvim),
which configures the client, the filetypes, and the root-directory detection for
you.

## How it works

```
editor  ──(LSP/JSON-RPC over stdio)──▶  browsable-lsp
                                            │
                                            ▼
                            Browsable::Analyzers (the core gem)
                                            │
                                            ▼
                            Findings ──▶ LSP diagnostics
```

On `textDocument/didOpen` and `textDocument/didChange`, the server runs
browsable's analyzers against the buffer's *in-memory* contents (no need to
save), converts the Findings to LSP diagnostics, and publishes them.

## Contributing

This gem lives in the `browsable-lsp/` subdirectory of the
[monorepo](https://github.com/romanhood/browsable):

```bash
cd browsable-lsp
bundle install
bundle exec rspec
```

## License

MIT — see the [LICENSE](../LICENSE) at the monorepo root.
