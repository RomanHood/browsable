# frozen_string_literal: true

require_relative "lib/browsable/version"

Gem::Specification.new do |spec|
  spec.name        = "browsable"
  spec.version     = Browsable::VERSION
  spec.authors     = ["Roman Hood"]
  spec.email       = ["roman.hood@aigility.com"]

  spec.summary     = "Rails-aware browser-compatibility audit for your frontend code."
  spec.description = <<~DESC
    browsable audits a Rails application's CSS, HTML, ERB, and JavaScript and
    reports which browsers can actually render and run it, then compares that
    against the project's declared allow_browser policy. It is a thin Ruby
    orchestrator over best-in-class external tools (Herb, stylelint, eslint).
  DESC

  spec.homepage = "https://github.com/romanhood/browsable"
  spec.license  = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri"          => spec.homepage,
    "source_code_uri"       => "https://github.com/romanhood/browsable/tree/main/browsable",
    "changelog_uri"         => "https://github.com/romanhood/browsable/blob/main/browsable/CHANGELOG.md",
    "bug_tracker_uri"       => "https://github.com/romanhood/browsable/issues",
    "rubygems_mfa_required" => "true"
  }

  # Only the files inside this subdirectory belong to this gem. The monorepo's
  # other packages (browsable-lsp, browsable.nvim) are published separately.
  gem_root = File.expand_path(__dir__)
  spec.files = Dir.chdir(gem_root) do
    Dir["lib/**/*", "exe/*", "data/*", "bin/*", "README.md", "CHANGELOG.md"]
      .select { |f| File.file?(f) }
  end

  spec.bindir       = "exe"
  spec.executables  = ["browsable"]
  spec.require_paths = ["lib"]

  spec.add_dependency "concurrent-ruby", ">= 1.2"  # thread-safe AuditLog accumulator
  spec.add_dependency "herb", ">= 0.1"             # in-process ERB/HTML parsing
  spec.add_dependency "nokogiri", ">= 1.13"        # parses response HTML in runtime mode
  spec.add_dependency "pastel", "~> 0.8"           # terminal colour
  spec.add_dependency "prism", ">= 1.0"            # parses allow_browser policy statically
  spec.add_dependency "rack", ">= 2.2"             # Rack::Response in runtime mode
  spec.add_dependency "thor", "~> 1.3"             # CLI framework
  spec.add_dependency "zeitwerk", "~> 2.6"         # autoloading

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.13"

  spec.post_install_message = <<~MSG
    Thanks for installing browsable. Run `browsable doctor` to verify your
    system dependencies, then `rails g browsable:install` (optional) to customize.
  MSG
end
