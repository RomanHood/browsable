# frozen_string_literal: true

require_relative "lib/browsable/lsp/version"

Gem::Specification.new do |spec|
  spec.name        = "browsable-lsp"
  spec.version     = Browsable::LSP::VERSION
  spec.authors     = ["Roman Hood"]
  spec.email       = ["roman.hood@aigility.com"]

  spec.summary     = "Language Server Protocol server for browsable."
  spec.description = <<~DESC
    browsable-lsp exposes browsable's browser-compatibility audit as a Language
    Server Protocol server, so editors can show inline diagnostics as you type.
    It wraps the browsable gem's analyzers and speaks LSP over stdio.
  DESC

  spec.homepage = "https://github.com/romanhood/browsable"
  spec.license  = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri"          => spec.homepage,
    "source_code_uri"       => "https://github.com/romanhood/browsable/tree/main/browsable-lsp",
    "changelog_uri"         => "https://github.com/romanhood/browsable/blob/main/browsable-lsp/CHANGELOG.md",
    "bug_tracker_uri"       => "https://github.com/romanhood/browsable/issues",
    "rubygems_mfa_required" => "true"
  }

  gem_root = File.expand_path(__dir__)
  spec.files = Dir.chdir(gem_root) do
    Dir["lib/**/*", "exe/*", "README.md", "CHANGELOG.md"].select { |f| File.file?(f) }
  end

  spec.bindir        = "exe"
  spec.executables   = ["browsable-lsp"]
  spec.require_paths = ["lib"]

  spec.add_dependency "browsable", ">= 0.1"
  spec.add_dependency "language_server-protocol", "~> 3.17"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.13"
end
