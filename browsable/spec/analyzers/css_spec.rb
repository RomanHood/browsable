# frozen_string_literal: true

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
end
