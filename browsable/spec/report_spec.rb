# frozen_string_literal: true

RSpec.describe Browsable::Report do
  let(:target) { Browsable::Target.modern }

  def finding(required:, severity: :error, feature: "html.global_attributes.popover")
    Browsable::Finding.new(
      feature_id: feature,
      feature_name: feature.split(".").last,
      file: "/app/views/home/index.html.erb",
      line: 1, column: 1,
      required_browser_versions: required,
      target_browser_versions: target.browsers,
      severity: severity,
      message: "x"
    )
  end

  describe "#suggestion" do
    it "raises only the offending browsers, leaving the others unchanged" do
      report = described_class.new(
        findings: [finding(required: { "chrome" => "114", "firefox" => "125", "safari" => "17" })],
        target: target
      )

      expect(report.suggestion.line).to eq(
        "allow_browser versions: { chrome: 120, edge: 120, firefox: 125, safari: 17.2, opera: 106 }"
      )
      expect(report.suggestion.bumps).to eq("firefox" => { from: "121", to: "125" })
    end

    it "takes the highest required version when several errors offend one browser" do
      report = described_class.new(
        findings: [
          finding(required: { "firefox" => "125" }),
          finding(required: { "firefox" => "130" }, feature: "html.elements.somenew")
        ],
        target: target
      )

      expect(report.suggestion.bumps["firefox"]).to eq(from: "121", to: "130")
    end

    it "is nil when nothing is below target" do
      expect(described_class.new(findings: [], target: target).suggestion).to be_nil
    end

    it "ignores warnings — only error-severity conflicts drive the suggestion" do
      report = described_class.new(
        findings: [finding(required: { "firefox" => "125" }, severity: :warning)],
        target: target
      )

      expect(report.suggestion).to be_nil
    end

    it "is nil when error findings carry no version data (CSS/JS)" do
      report = described_class.new(
        findings: [finding(required: {}, feature: "css.css-has")],
        target: target
      )

      expect(report.suggestion).to be_nil
    end
  end
end
