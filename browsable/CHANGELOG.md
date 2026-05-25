# Changelog

All notable changes to the `browsable` gem are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.1] - 2026-05-25

### Added — Sprockets asset-pipeline support

- **Pipeline detection (`Browsable::AssetPipeline`).** Identifies whether the
  project uses Propshaft, Sprockets, both, or neither. Surfaces the name in the
  audit header (`pipeline: sprockets`) and as a top-level field in `--json`
  output (`"pipeline": "sprockets"`). Live `defined?` checks win when available;
  otherwise the `Gemfile.lock` is the fallback.
- **Sprockets-layout JS discovery.** Default JS globs now include
  `app/assets/javascripts/**/*.{js,mjs}` alongside the Propshaft/importmap
  `app/javascript/**`. Sprockets directives (`//= require`, `*= require_tree`)
  live inside comments and are passed through untouched — no preprocessing.
- **SCSS routing.** `.scss` and `.sass` are discovered and routed to stylelint
  with `--customSyntax postcss-scss` when any are present.
- **`postcss-scss` in `doctor`.** Listed as an optional dependency, only flagged
  as missing when the project actually has SCSS files on disk.
- **`examples/sprockets_app`.** New fixture mirroring `examples/rails_app` with
  the Sprockets layout.

## [0.2.0] - 2026-05-25

### Added — Runtime response auditing

- **Runtime mode.** A Rack middleware (`Browsable::Middleware`) observes HTML
  responses during a test run, records the controller#action, the effective
  `allow_browser` policy, and every asset the response loaded, into a
  thread-safe `Browsable::AuditLog`. Test-suite integration is opt-in via a
  single `require`: `browsable/rspec` or `browsable/minitest`.
- **End-of-suite analysis (`Browsable::TestReport`).** The middleware records;
  it never analyzes. At suite end, stylelint and eslint are invoked **once**
  each over the deduplicated union of every asset loaded across the suite —
  not per request. A 500-spec suite that loads 10 unique CSS files spawns
  exactly one stylelint process.
- **Per-endpoint policy resolution (`Browsable::PolicyResolver`).** Walks the
  controller's ancestor chain, applies each `allow_browser` call's
  `only:`/`except:` filter to the action, and the last matching call wins —
  matching Rails' filter-callback semantics.
- **Asset URL → on-disk path resolution (`Browsable::AssetResolver`).** Strips
  digests, honors the configured asset host, and walks Propshaft and Sprockets
  search paths with a public/ fallback. The ≥95% resolution bar is enforced by
  the new `bin/benchmark-asset-resolution` script.
- **`browsable replay PATH`** — re-renders a JSON audit dump through any
  formatter, suitable for emitting GitHub annotations in CI from a saved
  test-suite report.
- **Dependencies.** Adds `nokogiri` (response HTML parsing), `concurrent-ruby`
  (thread-safe `AuditLog`), and `rack` (Rack body handling) as runtime gem
  dependencies. **The user's Rails app still has no `package.json` and no
  `node_modules`.** Runtime mode shells out to the same globally-installed
  `stylelint` and `eslint` as static mode.

### Unchanged

- Static `browsable audit` and the v0.1 CLI surface are fully backwards
  compatible. Runtime mode is purely additive.

## [0.1.0]

- Initial release.
