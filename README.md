# browsable

**browsable audits a Rails application's frontend code and tells you which
browsers can actually render and run it** — then compares that against the
browser policy your app declares. It is the tool that *informs* Rails 8's
`allow_browser`: instead of declaring what you allow, browsable tells you what
your code is genuinely **browsable by**.

## Why

Rails 8 made browser support a first-class, in-framework concern: a controller
can declare `allow_browser versions: :modern` and Rails will turn away anything
older. But that declaration is a *promise*, not a *measurement*. Nothing checks
that your CSS, ERB, and JavaScript actually stay inside it.

browsable is that check. It reads your `allow_browser` policy, discovers your
frontend code the way Propshaft and importmaps lay it out, and reports every
feature you use that falls outside the browsers you claim to support — with no
`package.json` and no `node_modules` in your Rails repo.

## The three pieces

This one repository publishes two gems and hosts one Neovim plugin:

```
browsable/  (this repo)
│
├── browsable/        ─▶  the core gem        — gem install browsable
│                          the CLI, analyzers, Rails-aware glue
│
├── browsable-lsp/    ─▶  the LSP server gem  — gem install browsable-lsp
│                          wraps the core gem as a Language Server,
│                          depends on  ──────────────┐
│                                                    │
├── browsable.nvim/   ─▶  the Neovim plugin         │
│                          installs from git, talks ─┘ to browsable-lsp
│
└── examples/rails_app/   a tiny Rails app for trying browsable out
```

- **`browsable`** — the core gem. A CLI and a thin Ruby orchestrator over
  best-in-class external tools ([Herb](https://github.com/marcoroth/herb) for
  ERB, [stylelint](https://stylelint.io/) for CSS,
  [eslint-plugin-compat](https://github.com/amilajack/eslint-plugin-compat) for
  JavaScript). browsable owns no parsing or compat-data logic; its value is the
  Rails-aware glue. → [`browsable/README.md`](browsable/README.md)
- **`browsable-lsp`** — a Language Server Protocol server built on the core gem,
  so any LSP-capable editor shows compatibility diagnostics as you type.
  → [`browsable-lsp/README.md`](browsable-lsp/README.md)
- **`browsable.nvim`** — a small pure-Lua Neovim plugin that wires
  `browsable-lsp` into Neovim and adds a few convenience commands.
  → [`browsable.nvim/README.md`](browsable.nvim/README.md)

## Quick start

The 90% case — install the gem, check your tooling, audit:

```bash
gem install browsable
browsable doctor      # checks (and can install) stylelint / eslint / node
browsable audit       # audits the Rails app in the current directory
```

Inside a Rails app, add it to the `Gemfile` instead and run
`bundle exec browsable audit`. browsable runs with **zero configuration** — it
infers everything. A `config/browsable.yml` is only for overriding defaults
(`rails g browsable:install` generates a commented one).

Want to see it work first? The repo ships a fixture:

```bash
cd browsable && bundle install
bundle exec exe/browsable audit ../examples/rails_app
```

## About the monorepo

This single GitHub repository **publishes two independent gems** to
rubygems.org and **is the source** for the Neovim plugin. You do not need to
clone anything to use browsable:

- `gem install browsable` and `gem install browsable-lsp` pull from rubygems.
  Each gem's `.gemspec` declares only the files in its own subdirectory and
  points `source_code_uri` at that subdirectory of this repo.
- The Neovim plugin installs straight from this repo's git URL with a
  subdirectory specifier — see [`browsable.nvim/README.md`](browsable.nvim/README.md).

There are no git submodules and no nested repositories — just subdirectories.

### Releasing

Each gem releases on its own tag. Pushing `browsable-v0.1.0` triggers
[`release-browsable.yml`](.github/workflows/release-browsable.yml); pushing
`browsable-lsp-v0.1.0` triggers
[`release-browsable-lsp.yml`](.github/workflows/release-browsable-lsp.yml). The
tag prefix selects the gem.

> **First release:** the names `browsable` and `browsable-lsp` must be claimed
> on rubygems.org. There is no separate "reserve a name" step — claim each name
> by running `gem push` on it once (a `0.0.1` placeholder, or just the real
> first release).

## Future directions

- **MCP server.** The CLI's `--json` output is a stable, structured interface
  designed to be consumed by tools — the LSP server already does. An MCP server
  exposing the same audit to AI agents is a natural next step; the JSON format
  is the foundation for it.
- **Editor code actions.** "Add an `@supports` fallback" / "Tighten
  `allow_browser` to require Safari 15.4+" as one-click quick fixes.

## License

[MIT](LICENSE) — a single license at the repo root covers every package in the
monorepo.
