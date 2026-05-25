# frozen_string_literal: true

require "tempfile"

RSpec.describe Browsable::Analyzers::CSS do
  # BROWSABLE_DRY_RUN replaces the stylelint shell-out with injected JSON, so
  # this spec runs with nothing installed.
  around do |example|
    ENV["BROWSABLE_DRY_RUN"] = "1"
    example.run
  ensure
    ENV.delete("BROWSABLE_DRY_RUN")
    ENV.delete("BROWSABLE_DRY_RUN_CSS")
  end

  let(:config) { Browsable::Config.load(root: Dir.mktmpdir) }
  let(:target) { Browsable::Target.modern }
  subject(:analyzer) { described_class.new(target: target, config: config) }

  it "turns injected stylelint JSON into findings" do
    ENV["BROWSABLE_DRY_RUN_CSS"] = JSON.generate(
      [{
        "source" => "/app/assets/stylesheets/application.css",
        "warnings" => [{
          "line" => 4, "column" => 3, "severity" => "warning",
          "rule" => "plugin/no-unsupported-browser-features",
          "text" => 'Unexpected browser feature "css-has" (plugin/no-unsupported-browser-features)'
        }]
      }]
    )

    findings = analyzer.analyze(["/app/assets/stylesheets/application.css"])

    expect(findings.size).to eq(1)
    expect(findings.first.feature_name).to eq("css-has")
    expect(findings.first.line).to eq(4)
  end

  it "produces no findings when stylelint reports nothing" do
    ENV["BROWSABLE_DRY_RUN_CSS"] = "[]"
    expect(analyzer.analyze(["/x.css"])).to be_empty
  end

  it "declares stylelint as a required tool" do
    expect(analyzer.required_tools).to eq(["stylelint"])
  end

  describe "SCSS routing" do
    it "treats .scss and .sass extensions as scss-like" do
      expect(described_class.scss_like?("/x.scss")).to be(true)
      expect(described_class.scss_like?("/x.sass")).to be(true)
      expect(described_class.scss_like?("/x.css")).to be(false)
    end

    it "passes --customSyntax postcss-scss to stylelint when SCSS is in the input" do
      captured = nil
      allow(analyzer).to receive(:shell_out) do |argv, **_kwargs|
        captured = argv
        "[]"
      end

      analyzer.analyze(["/app/assets/stylesheets/application.scss"])

      expect(captured).to include("--customSyntax", "postcss-scss")
    end

    it "omits --customSyntax for a pure-CSS input list" do
      captured = nil
      allow(analyzer).to receive(:shell_out) do |argv, **_kwargs|
        captured = argv
        "[]"
      end

      analyzer.analyze(["/app/assets/stylesheets/application.css"])

      expect(captured).not_to include("--customSyntax")
    end
  end

  describe "Sprockets directive tolerance" do
    # Sprockets directives like `*= require_tree .` live inside CSS comment
    # syntax. Stylelint treats them as comments and never reports them — we
    # verify that the analyzer passes such files through without mutation.
    it "passes the source file to stylelint untouched, directives and all" do
      file = Tempfile.new(["app", ".scss"])
      file.write(<<~SCSS)
        /*
         *= require_tree .
         *= require_self
         */
        .card { color: red; }
      SCSS
      file.flush

      captured_files = nil
      allow(analyzer).to receive(:shell_out) do |argv, **_kwargs|
        captured_files = argv.last(1)
        "[]"
      end

      findings = analyzer.analyze([file.path])

      expect(findings).to be_empty
      expect(captured_files).to eq([file.path])
    ensure
      file&.close
      file&.unlink
    end
  end
end
