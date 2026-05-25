# Browsable Sprockets Example

A minimal **Sprockets**-based Rails app, mirroring `examples/rails_app` but using the classic asset pipeline instead of Propshaft + importmaps. It exists as a manual-testing fixture for `browsable audit` — static-mode discovery only; the app is never expected to boot.

## What this fixture exercises

| Stack piece | Choice |
|---|---|
| Asset pipeline | Sprockets (`sprockets-rails`) |
| JS layout | `app/assets/javascripts/application.js` with `//= require` directives |
| Stylesheet layout | `app/assets/stylesheets/application.scss` with `//= require` directives |
| Rails version | 7.1 (Sprockets is still the default for many existing apps) |

The `//= require` and `//= require_tree .` lines are Sprockets manifest directives. They live inside JS and CSS comment syntax, so eslint and stylelint ignore them — `browsable` does the same. There is no manifest parsing.

## Running the audit

From the root of the monorepo:

```bash
cd browsable
bundle exec exe/browsable audit ../examples/sprockets_app
```

You should see `pipeline: sprockets` in the audit header. The findings will look similar to `examples/rails_app` — same `allow_browser :modern`, same modern features used — because the analyzers are pipeline-agnostic; only discovery changes.

## What is *not* supported

- **CoffeeScript** (`.coffee`)
- **ERB-templated JS** (`*.js.erb`)
- **Indented Sass** (`.sass`) — discovered, but `postcss-scss` only parses braced SCSS cleanly

These are documented limitations. Runtime mode (v0.2+) sidesteps all of this by reading whatever HTML/CSS/JS Rails actually renders during a test run.
