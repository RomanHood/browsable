# Browsable Example Rails App

This directory contains a small, intentionally-imperfect Rails 8 application that serves as a **manual-testing fixture** for the `browsable` gem. It is not meant to boot or serve real requests — `browsable` analyzes files statically, so a full Rails environment is never required.

The app is structured like a real Rails project (controllers, views, stylesheets, JavaScript, importmap config) but deliberately uses a handful of browser features that sit at or beyond the edge of common browser-support baselines. That gives `browsable` something meaningful to report when you run the audit.

---

## What the app uses

| Stack piece | Choice |
|---|---|
| Asset pipeline | Propshaft |
| JavaScript loading | importmap-rails (no `package.json`, no bundler) |
| Rails version | 8.x |

There is intentionally **no `package.json`** and no `node_modules` directory. Keeping the Rails project clean of npm artifacts is a core goal of the `browsable` workflow — it audits compatibility without requiring a Node toolchain to be present in the repository.

---

## Running the audit

From the root of the `browsable` monorepo:

```bash
cd browsable
bundle exec exe/browsable audit ../examples/rails_app
```

`browsable` will walk the example app's files, apply the browser policy it finds in `ApplicationController`, and print a structured report.

---

## What findings to expect and why

### Browser policy

`app/controllers/application_controller.rb` declares:

```ruby
allow_browser versions: :modern
```

Rails' `:modern` baseline maps to specific minimum versions for each major browser. `browsable` uses this declaration as the compatibility target for every check.

### HTML / ERB findings

The home view (`app/views/home/index.html.erb`) deliberately exercises a spread of HTML features:

- **`popover` attribute** — used on `<div id="info" popover>` and its trigger `<button popovertarget="info">`. The Popover API became baseline across all major browsers only in late 2024, which is newer than Firefox's `:modern` threshold. Expect `browsable` to **raise an error** here.
- **`<search>` element** — introduced in all major engines by 2023/2024 and classified as "newly available." Expect `browsable` to **raise a warning** (supported but not yet in every LTS release your users might be running).
- **`<details>` and `<dialog>`** — both have been widely available across browsers for several years and fall comfortably within the `:modern` baseline. Expect **no findings** for these elements.

### CSS findings (requires stylelint)

`app/assets/stylesheets/application.css` uses three modern CSS features:

- **`:has()` relational pseudo-class** — e.g., `.card:has(> .card__media)`. Baseline since late 2023; may still be flagged depending on your target.
- **`container-type`** — the CSS containment property that enables `@container` queries. Baseline since early 2023.
- **`aspect-ratio`** — broadly available but absent in some older browser versions still in the `:modern` window.

If `stylelint` (with `stylelint-no-unsupported-browser-features` or equivalent) is installed in your environment, `browsable` will surface CSS-level findings. Without stylelint, these checks are skipped.

### JavaScript findings (requires eslint)

`app/javascript/application.js` calls `Array.prototype.findLast`, which was added to V8, SpiderMonkey, and JavaScriptCore in 2022. Older browser versions in the `:modern` range may not support it. If `eslint` with `eslint-plugin-compat` is installed, `browsable` will flag this call. Without eslint, the JS checks are skipped.

### importmap findings

`config/importmap.rb` pins `@hotwired/stimulus` to a CDN URL. `browsable` inspects importmap pins to detect CDN-loaded packages and can cross-reference them against known compatibility data.

---

## Tool requirements summary

| Finding type | External tool needed |
|---|---|
| HTML / ERB findings | None — the `herb` gem is bundled with `browsable` |
| CSS findings | `stylelint` (with a compat plugin) |
| JavaScript findings | `eslint` with `eslint-plugin-compat` |

You can run the audit without stylelint or eslint installed and still get HTML/ERB findings immediately. CSS and JS analysis activates automatically when the respective tools are present on `PATH`.

---

## Directory structure

```
examples/rails_app/
  Gemfile                                  # Rails 8 + Propshaft + importmap-rails
  config/
    routes.rb                              # Single root route
    importmap.rb                           # Pins application + Stimulus from CDN
  app/
    controllers/
      application_controller.rb           # Declares allow_browser versions: :modern
      home_controller.rb                  # Renders the index view
    assets/stylesheets/
      application.css                      # Uses :has(), container-type, aspect-ratio
    javascript/
      application.js                       # Uses Array.findLast
    views/
      layouts/application.html.erb        # Standard Rails layout
      home/index.html.erb                 # Uses popover, <search>, <dialog>, <details>
```
