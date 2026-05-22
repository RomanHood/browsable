# browsable

**Rails-aware browser-compatibility auditing for your frontend code.**

`browsable` audits a Rails application's CSS, HTML, ERB, and JavaScript and
reports which browsers can actually render and run it — then compares that
against the project's declared `allow_browser` policy.

The name is a play on Rails 8's `allow_browser` controller API. Instead of
*declaring* which browsers you allow, `browsable` tells you which browsers your
code is actually **browsable by**.

> This is the core gem of the [`browsable` monorepo](https://github.com/romanhood/browsable).
> See also [`browsable-lsp`](../browsable-lsp) (editor diagnostics) and
> [`browsable.nvim`](../browsable.nvim) (Neovim plugin).

## Philosophy

- **The gem owns no parsing or compat-data logic.** It shells out to mature
  tools that already do this well — [Herb](https://github.com/marcoroth/herb)
  for ERB, [stylelint](https://stylelint.io/) for CSS,
  [eslint-plugin-compat](https://github.com/amilajack/eslint-plugin-compat) for
  JavaScript. The gem's value is the Rails-aware glue.
- **No `package.json`, no `node_modules` in your Rails repo.** The external
  tools live globally on your machine. `browsable doctor` detects them and
  guides installation.
- **It reports, it doesn't decide.** It tells you what your code requires and
  what your config permits. You decide what to do.
- **Configuration is optional.** `browsable` runs with zero config.

## Installation

Add it to your Rails app's `Gemfile`:

```ruby
group :development, :test do
  gem "browsable"
end
```

Then `bundle install`. Or install it standalone:

```bash
gem install browsable
```

## System dependencies — the `doctor` workflow

`browsable` shells out to `stylelint` and `eslint` (and the `node` runtime they
need). Those are *not* gem dependencies — they live globally on your machine.
Check what you have:

```bash
bundle exec browsable doctor
```

`doctor` prints, for each missing tool, the exact command to install it. Let it
do the work for you:

```bash
bundle exec browsable doctor --fix   # installs missing tools via brew / npm
```

ERB and HTML analysis needs nothing extra — the `herb` gem is a dependency and
runs in-process.

## Quick start

```bash
bundle exec browsable audit
```

That's it. With no configuration, `browsable`:

1. reads `ApplicationController`'s `allow_browser` policy to learn your target,
2. discovers your stylesheets, views, JavaScript, and importmap pins,
3. audits each against that target, and
4. prints a report grouped by file.

## CLI reference

| Command | Purpose |
| --- | --- |
| `browsable` / `browsable audit [PATH]` | Full project audit |
| `browsable doctor` | Check system dependencies |
| `browsable doctor --fix` | Install missing dependencies (opt-in) |
| `browsable check FILE [FILE...]` | Audit specific files (used by editors) |
| `browsable target [PATH]` | Show the inferred browser-support target |
| `browsable init` | Generate a `.browsable.yml` (non-Rails projects) |
| `browsable version` | Print the version |

### Flags

| Flag | Effect |
| --- | --- |
| `--target QUERY` | Override the inferred browserslist query |
| `--json` | Emit findings as JSON (shortcut for `--format json`) |
| `--format human\|json\|github` | Choose the output formatter |
| `--no-build` | Scan only what is on disk (`browsable` never builds assets itself) |
| `--include GLOB` | Add a path glob to the audit (repeatable) |
| `--exclude GLOB` | Exclude a path glob (repeatable) |
| `--fail-on warning\|error` | Exit-code policy for CI |
| `--config PATH` | Override the config file location |

The `--json` output is the universal interface: the LSP server (and any future
MCP server) consume exactly that structure. The human and GitHub formatters are
just alternate presentations of the same data.

## Rails generator

```bash
rails g browsable:install
```

This writes a fully-commented `config/browsable.yml` — every option present,
commented out, set to its default. It is a self-documenting reference: uncomment
a line to override it. Flags: `--minimal`, `--target QUERY`, `--force`.

Non-Rails projects use `browsable init`, which writes `.browsable.yml` instead.

## Configuration

`browsable` needs no config file. When one is present it is discovered in this
order:

1. the path passed to `--config`
2. `config/browsable.yml` (preferred in Rails apps)
3. `.browsable.yml` in the working directory

Resolution precedence (highest wins): **CLI flags → config file → inferred Rails
config → gem defaults**. See the generated `config/browsable.yml` for the full,
commented option reference.

## How it works — the inference chain

```
ApplicationController.allow_browser  →  Target (browserslist query)  →  Analyzers
        :modern                          chrome 120, safari 17.2          │
                                                                          ▼
   config/importmap.rb ─┐                                         CSS  → stylelint
   app/assets/**       ─┼─→  Sources  ─→  files by kind  ─────────  ERB  → Herb + BCD
   app/views/**        ─┤                                          HTML → Herb + BCD
   app/javascript/**   ─┘                                          JS   → eslint
                                                                          │
                                                                          ▼
                                                            Report → Formatter
```

`browsable` translates between Rails-land and browserslist-land: it reads
`allow_browser :modern`, expands it to concrete browser versions, configures
stylelint/eslint with that target, and runs Herb against the bundled MDN
browser-compat-data snapshot for ERB/HTML.

### Partial `allow_browser` policies

If your `allow_browser` policy is a hash that pins only some browsers — say
`versions: { safari: 16.4, firefox: 121 }` — Rails leaves every browser you
*don't* list allowed at **any** version (it only blocks a browser it was given a
minimum, or `false`, for). browsable audits exactly the browsers you pinned and
prints a note naming the rest. To audit against more, set an explicit `target:`
in `config/browsable.yml`. The same note-and-fall-back-to-`defaults` behaviour
applies when browsable cannot resolve your policy statically.

### Where `defaults` comes from

When there is no `allow_browser` policy at all, browsable audits against the
[browserslist](https://github.com/browserslist/browserslist) `defaults` query —
the "reasonable broad support" baseline the wider frontend ecosystem uses. It is
resolved **live** from caniuse data when the `browserslist` CLI is installed
(`npm install -g browserslist`); otherwise browsable uses a small **built-in
approximation** and says so in a note. Either way these versions are *not* a
Rails concept — Rails blocks nothing unless you call `allow_browser` — and they
are not derived from stylelint or eslint. For a precise, stable target, set
`target:` in `config/browsable.yml`.

### Suggested `allow_browser` fix

When an audit finds errors that are purely a version conflict — your code needs
a browser version newer than your policy permits — browsable prints a ready-to-paste
`allow_browser` line that raises *only* the offending browsers to the minimum
those features require, leaving every other browser untouched:

```
Suggested allow_browser policy
    allow_browser versions: { chrome: 120, edge: 120, firefox: 125, safari: 17.2, opera: 106 }
    firefox: 121 → 125
```

It is a suggestion, not an instruction: tightening the policy is one fix, changing
the code (a fallback, a `@supports` rule) is another. browsable reports; you
decide. The suggestion is derived from HTML/ERB findings, which carry exact
version data; it also appears in `--json` (`suggested_policy`) and as a GitHub
Actions notice.

## Rake tasks

Inside a Rails app, the railtie registers:

- `rake browsable:audit` — audit `app/assets/builds/` as it stands
- `rake browsable:audit:fresh` — run `assets:precompile` first, then audit
- `rake browsable:doctor` — run the dependency check

`browsable` never precompiles assets on its own. In CI, compose the pipeline
explicitly: `bundle exec rails assets:precompile && bundle exec browsable audit`.

## Contributing

This gem lives in the `browsable/` subdirectory of the
[monorepo](https://github.com/romanhood/browsable). To work on it:

```bash
cd browsable
bundle install
bundle exec rspec
```

Refresh the bundled compat data with `ruby bin/update-bcd-snapshot`.

## License

MIT — see the [LICENSE](../LICENSE) at the monorepo root.
