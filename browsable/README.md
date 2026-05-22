<div align="center">

# Browsable

**Rails-aware browser-compatibility auditing for your frontend.**

Find out which browsers your Rails app is actually *browsable by* — before your users do.

[![Gem Version](https://img.shields.io/gem/v/browsable.svg)](https://rubygems.org/gems/browsable)
[![CI](https://github.com/romanhood/browsable/actions/workflows/ci.yml/badge.svg)](https://github.com/romanhood/browsable/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](../LICENSE)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.2-CC342D.svg)](https://www.ruby-lang.org/)

</div>

---

Browsable audits a Rails application's CSS, HTML, ERB, and JavaScript and reports which browsers can actually render and run it — then compares the answer against the `allow_browser` policy you've declared.

The name is a play on Rails 8's `allow_browser` controller API. Instead of *declaring* which browsers you allow, `browsable` tells you which browsers your code is actually browsable by.

> 📦 This is the core gem of the [`browsable` monorepo][monorepo].
> See also [`browsable-lsp`][lsp] for editor diagnostics and [`browsable.nvim`][nvim] for Neovim.

## Table of contents

- [Why Browsable?](#why-browsable)
- [Installation](#installation)
- [Quick start](#quick-start)
- [System dependencies](#system-dependencies)
- [CLI reference](#cli-reference)
- [Configuration](#configuration)
- [How it works](#how-it-works)
- [Per-controller policies](#per-controller-and-per-action-policies)
- [Suggested policy fixes](#suggested-allow_browser-fix)
- [Rake tasks](#rake-tasks)
- [Contributing](#contributing)
- [License](#license)

## Why Browsable?

Rails 8 made browser support a first-class concern with `allow_browser`. But the framework has no opinion on whether your CSS actually works in the browsers you allowed. You can declare `allow_browser :modern` and silently ship `:has()` selectors that break in Safari 15. There was no tool that closed that loop — until now.

Browsable closes it by:

- 🔍 **Reading your `allow_browser` policy** straight from `ApplicationController`
- 🎯 **Translating it** into a precise browserslist query
- 📂 **Discovering** your stylesheets, views, JavaScript, and importmap pins
- ✅ **Auditing each** against best-in-class compat databases (MDN BCD, caniuse)
- 📋 **Reporting** by file, with exact lines and suggested fixes

No `package.json`. No `node_modules`. No build-system pollution in your Rails repo.

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

> 💡 **Heads up:** Browsable shells out to `stylelint` and `eslint` for CSS and JS analysis. These live globally on your machine — *not* in your Rails repo. Run `browsable doctor` to check and install them.

## Quick start

```bash
bundle exec browsable audit
```

That's it. With zero configuration, Browsable will:

1. **Read** `ApplicationController`'s `allow_browser` policy to learn your target
2. **Discover** your stylesheets, views, JavaScript, and importmap pins
3. **Audit** each against that target
4. **Report** the findings, grouped by file

### Example output

```
$ bundle exec browsable audit

✓ Target inferred from ApplicationController.allow_browser :modern
  → chrome 120, edge 120, firefox 121, safari 17.2, opera 106

⚠ app/assets/stylesheets/cards.css
    42:3   :has() selector requires Safari 15.4+ (policy allows 17.2 ✓)
    87:5   @container query requires Firefox 110+ (policy allows 121 ✓)

✗ app/views/legacy/embed.html.erb
    14:22  <dialog> element requires Safari 15.4+, but the LegacyController
           policy allows Safari 12.0

Browser policies (2 found)
    ApplicationController             :modern
    LegacyController                  { safari: 12, chrome: 60 }  (only: embed)

1 error, 0 warnings — exit 1
```

## System dependencies

Browsable shells out to a few external tools that live globally on your machine:

| Tool | Purpose | Required? |
| --- | --- | --- |
| `node` | JavaScript runtime for `stylelint` & `eslint` | Yes |
| `stylelint` | CSS compatibility analysis | Yes (CSS audits) |
| `eslint` + `eslint-plugin-compat` | JavaScript compatibility analysis | Yes (JS audits) |
| `browserslist` | Live resolution of `defaults` queries | Optional |
| `herb` | ERB parsing | Bundled (gem dep) |

### The `doctor` workflow

```bash
bundle exec browsable doctor
```

For each missing tool, `doctor` prints the exact command to install it. Or let it do the work:

```bash
bundle exec browsable doctor --fix
```

This installs missing tools via `brew` or `npm` — opt-in, never automatic.

## CLI reference

### Commands

| Command | Purpose |
| --- | --- |
| `browsable` *(or `browsable audit`)* | Full project audit |
| `browsable audit [PATH]` | Audit a specific directory |
| `browsable check FILE [FILE...]` | Audit specific files *(used by editors)* |
| `browsable doctor` | Check system dependencies |
| `browsable doctor --fix` | Install missing dependencies |
| `browsable target [PATH]` | Show the inferred browser-support target |
| `browsable init` | Generate `.browsable.yml` *(non-Rails projects)* |
| `browsable version` | Print the version |

### Flags

| Flag | Effect |
| --- | --- |
| `--target QUERY` | Override the inferred browserslist query |
| `--json` | Emit findings as JSON *(shortcut for `--format json`)* |
| `--format human\|json\|github` | Choose the output formatter |
| `--no-build` | Scan only what's on disk *(Browsable never builds assets itself)* |
| `--include GLOB` | Add a path glob *(repeatable)* |
| `--exclude GLOB` | Exclude a path glob *(repeatable)* |
| `--fail-on warning\|error` | Exit-code policy for CI |
| `--config PATH` | Override the config file location |

> 💡 The `--json` output is the universal interface. The LSP server and any future MCP server consume that exact structure. The `human` and `github` formatters are just alternate presentations of the same data.

## Configuration

**Browsable needs no config file.** Configuration is for overrides only.

When a file is present, it's discovered in this order:

1. The path passed to `--config`
2. `config/browsable.yml` *(preferred in Rails apps)*
3. `.browsable.yml` in the working directory

Resolution precedence (highest wins):

```
CLI flags  →  config file  →  inferred Rails config  →  gem defaults
```

### Generating a config file

```bash
rails g browsable:install
```

This writes a fully-commented `config/browsable.yml` — every option present, commented out, set to its default. It's a self-documenting reference: uncomment a line to override it.

| Flag | Effect |
| --- | --- |
| `--minimal` | Section headers only, no option reference |
| `--target QUERY` | Pre-populate the target |
| `--force` | Overwrite an existing config |

Non-Rails projects use `browsable init`, which writes `.browsable.yml` instead.

## How it works

### The inference chain

```
   ApplicationController.allow_browser           →    Target
       :modern                                        chrome 120, safari 17.2, ...
                                                          │
                                                          ▼
   config/importmap.rb ─┐                              Sources
   app/assets/**       ─┼─→   discovered files   ─→     │
   app/views/**        ─┤                               │
   app/javascript/**   ─┘                               ▼
                                                     Analyzers
                                                        │
                                              CSS  → stylelint
                                              ERB  → Herb + MDN BCD
                                              HTML → Herb + MDN BCD
                                              JS   → eslint + eslint-plugin-compat
                                                        │
                                                        ▼
                                                     Report → Formatter
```

Browsable's job is the **glue between Rails-land and browserslist-land**. It reads `allow_browser :modern`, expands it to concrete browser versions, configures stylelint and eslint with that target, and runs Herb against a bundled MDN browser-compat-data snapshot for ERB and HTML.

### Partial `allow_browser` policies

If your `allow_browser` policy is a hash that pins only some browsers — say `versions: { safari: 16.4, firefox: 121 }` — Rails leaves every browser you *don't* list allowed at any version. It only blocks a browser it was explicitly given a minimum (or `false`) for.

Browsable audits exactly the browsers you pinned and prints a note naming the rest. To audit against more, set an explicit `target:` in `config/browsable.yml`. The same note-and-fall-back-to-`defaults` behavior applies when Browsable can't resolve your policy statically.

### Where `defaults` comes from

When there's no `allow_browser` policy at all, Browsable audits against the [browserslist `defaults`][browserslist] query — the "reasonable broad support" baseline the wider frontend ecosystem uses.

- **With `browserslist` installed** *(`npm install -g browserslist`)*: resolved live from caniuse data
- **Without it**: a small built-in approximation, with a note saying so

Either way, these versions are *not* a Rails concept — Rails blocks nothing unless you call `allow_browser` — and they aren't derived from stylelint or eslint. For a precise, stable target, set `target:` in `config/browsable.yml`.

## Suggested `allow_browser` fix

When an audit finds errors that are purely a version conflict — your code needs a browser version newer than your policy permits — Browsable prints a ready-to-paste `allow_browser` line that raises *only* the offending browsers to the minimum those features require:

```
💡 Suggested allow_browser policy

   allow_browser versions: {
     chrome:  120,
     edge:    120,
     firefox: 125,    # ← was 121
     safari:  17.2,
     opera:   106
   }
```

It's a suggestion, not an instruction. Tightening the policy is one fix; changing the code (a fallback, a `@supports` rule) is another. **Browsable reports — you decide.**

The suggestion is derived from HTML/ERB findings, which carry exact version data. It also appears in `--json` output as `suggested_policy` and as a GitHub Actions notice.

## Per-controller and per-action policies

Rails lets any controller override `allow_browser` and scope the override to certain actions with `only:` / `except:`. Browsable scans every file under `app/controllers/` (including `concerns/`) and lists each `allow_browser` call it finds — with its versions and any action scope — under **Browser policies** in the report.

The audit itself runs against a **single target** (`ApplicationController`'s policy, or your `config/browsable.yml`). Browsable does **not** try to map each frontend asset to the exact endpoints that serve it.

Why? CSS and importmap JavaScript are *global* assets, included via layout helpers on nearly every page. They have no single owning controller action — and a per-asset policy graph would be guesswork. Instead, Browsable shows you the whole policy landscape:

- If a controller serves shared assets to a broader range of browsers than `ApplicationController`, audit against that policy explicitly with `--target` or `config/browsable.yml`.
- Per-action auditing of `app/views/<controller>/` templates against their controller's policy is a planned refinement (see [v0.2 roadmap][roadmap]).

## Rake tasks

Inside a Rails app, the railtie registers three tasks:

| Task | Behavior |
| --- | --- |
| `rake browsable:audit` | Audit `app/assets/builds/` as it stands |
| `rake browsable:audit:fresh` | Run `assets:precompile` first, then audit |
| `rake browsable:doctor` | Run the dependency check |

> ⚠️ **Browsable never precompiles assets on its own.** In CI, compose the pipeline explicitly:
> ```bash
> bundle exec rails assets:precompile && bundle exec browsable audit
> ```

## Contributing

This gem lives in the `browsable/` subdirectory of the [monorepo][monorepo]. To work on it:

```bash
git clone https://github.com/romanhood/browsable
cd browsable/browsable
bundle install
bundle exec rspec
```

Refresh the bundled MDN browser-compat-data snapshot:

```bash
ruby bin/update-bcd-snapshot
```

Bug reports and pull requests welcome. The monorepo has a [CONTRIBUTING.md][contributing] with the broader workflow.

## License

[MIT][license] — see the LICENSE file at the monorepo root.

---

<div align="center">

Made with care for Rails developers who refuse to add a `package.json` to their app. 🛤️

[Monorepo][monorepo] · [LSP server][lsp] · [Neovim plugin][nvim] · [Report an issue][issues]

</div>

[monorepo]: https://github.com/romanhood/browsable
[lsp]: https://github.com/romanhood/browsable/tree/main/browsable-lsp
[nvim]: https://github.com/romanhood/browsable/tree/main/browsable.nvim
[roadmap]: https://github.com/romanhood/browsable/blob/main/ROADMAP.md
[contributing]: https://github.com/romanhood/browsable/blob/main/CONTRIBUTING.md
[license]: https://github.com/romanhood/browsable/blob/main/LICENSE
[issues]: https://github.com/romanhood/browsable/issues
[browserslist]: https://github.com/browserslist/browserslist
