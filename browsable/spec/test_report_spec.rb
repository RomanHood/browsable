# frozen_string_literal: true

require "spec_helper"

RSpec.describe Browsable::TestReport do
  let(:root) { Dir.mktmpdir("browsable-test-report") }
  let(:config) { Browsable::Config.load(root: root) }

  before do
    FileUtils.mkdir_p(File.join(root, "config"))
    Browsable.audit_log = Browsable::AuditLog.new
  end

  after do
    Browsable.audit_log = nil
    FileUtils.remove_entry(root) if File.directory?(root)
  end

  def asset_ref(path, kind: :css)
    Browsable::HtmlExtractor::AssetRef.new(url: "/x", resolved_path: path, kind: kind)
  end

  def record(endpoint:, paths:, policy: modern_policy, html: "")
    Browsable.audit_log.record(
      endpoint: endpoint,
      request_path: "/p",
      policy: policy,
      html: html,
      asset_paths: paths.map { |p| asset_ref(p, kind: :css) },
      inline_blocks: []
    )
  end

  def modern_policy
    Browsable::Policy.new(versions: :modern, scope: nil, source: :default)
  end

  it "produces an empty report when nothing was recorded" do
    report = described_class.new(audit_log: Browsable.audit_log, config: config, root: root)
    expect(report.findings).to be_empty
    expect(report.errors?).to be(false)
    expect(report.endpoint_reports).to be_empty
  end

  it "invokes the CSS analyzer exactly once for a multi-entry audit log" do
    css1 = File.join(root, "a.css"); File.write(css1, "")
    css2 = File.join(root, "b.css"); File.write(css2, "")
    record(endpoint: "A#a", paths: [css1])
    record(endpoint: "B#b", paths: [css1, css2])

    report = described_class.new(audit_log: Browsable.audit_log, config: config, root: root)

    invocations = 0
    fake_analyzer = double("CSS")
    allow(fake_analyzer).to receive(:analyze) { invocations += 1; [] }
    allow(Browsable::Analyzers::CSS).to receive(:new).and_return(fake_analyzer)
    allow(Browsable::Doctor).to receive(:new).and_return(double(available_kinds: %i[css erb html js]))

    report.findings # triggers analysis

    expect(invocations).to eq(1)
  end

  it "attributes a finding to every endpoint that loaded the offending asset" do
    css = File.join(root, "a.css"); File.write(css, "")
    record(endpoint: "A#a", paths: [css])
    record(endpoint: "B#b", paths: [css])

    finding = Browsable::Finding.new(
      feature_id: "css.x", feature_name: "x", file: css, line: 1, column: 1,
      required_browser_versions: {}, target_browser_versions: {}, severity: :warning,
      message: "demo"
    )
    fake_analyzer = double("CSS"); allow(fake_analyzer).to receive(:analyze).and_return([finding])
    allow(Browsable::Analyzers::CSS).to receive(:new).and_return(fake_analyzer)
    allow(Browsable::Doctor).to receive(:new).and_return(double(available_kinds: %i[css erb html js]))

    report = described_class.new(audit_log: Browsable.audit_log, config: config, root: root)
    endpoints = report.endpoint_reports.map(&:endpoint)
    expect(endpoints).to contain_exactly("A#a", "B#b")
  end

  it "tracks unresolved asset URLs as skipped entries" do
    Browsable.audit_log.record(
      endpoint: "X#x", request_path: "/", policy: modern_policy, html: "",
      asset_paths: [Browsable::HtmlExtractor::AssetRef.new(url: "https://cdn/x.css", resolved_path: nil, kind: :css)],
      inline_blocks: []
    )

    allow(Browsable::Doctor).to receive(:new).and_return(double(available_kinds: %i[css erb html js]))
    report = described_class.new(audit_log: Browsable.audit_log, config: config, root: root)
    expect(report.skipped_assets).to contain_exactly(
      hash_including(url: "https://cdn/x.css", endpoint: "X#x")
    )
  end

  it "writes inline blocks to disk for batch analysis and labels findings clearly" do
    Browsable.audit_log.record(
      endpoint: "Y#y", request_path: "/", policy: modern_policy, html: "",
      asset_paths: [],
      inline_blocks: [
        Browsable::HtmlExtractor::InlineBlock.new(content: ".x { color: red }", kind: :css)
      ]
    )

    captured_files = nil
    fake_analyzer = double("CSS")
    allow(fake_analyzer).to receive(:analyze) do |files|
      captured_files = files
      [Browsable::Finding.new(
        feature_id: "css.x", feature_name: "x", file: files.first, line: 1, column: 1,
        required_browser_versions: {}, target_browser_versions: {}, severity: :warning,
        message: "inline"
      )]
    end
    allow(Browsable::Analyzers::CSS).to receive(:new).and_return(fake_analyzer)
    allow(Browsable::Doctor).to receive(:new).and_return(double(available_kinds: %i[css erb html js]))

    report = described_class.new(audit_log: Browsable.audit_log, config: config, root: root)
    findings = report.findings
    expect(captured_files).not_to be_empty
    expect(findings.first.file).to eq("(inline <style> block)")
  end

  it "computes a runtime-union target as the most-strict floor across endpoint policies" do
    record(
      endpoint: "Old#a", paths: [],
      policy: Browsable::Policy.new(
        versions: { "chrome" => "100" }, source: :controller
      )
    )
    record(
      endpoint: "New#b", paths: [],
      policy: Browsable::Policy.new(
        versions: { "chrome" => "120" }, source: :controller
      )
    )

    report = described_class.new(audit_log: Browsable.audit_log, config: config, root: root)
    expect(report.send(:batch_target).browsers["chrome"]).to eq("100")
  end
end
