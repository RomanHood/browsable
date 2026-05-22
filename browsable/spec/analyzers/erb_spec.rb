# frozen_string_literal: true

RSpec.describe Browsable::Analyzers::ERB do
  let(:config) { Browsable::Config.load(root: Dir.mktmpdir) }
  let(:target) { Browsable::Target.modern }
  subject(:analyzer) { described_class.new(target: target, config: config) }

  it "flags the popover attribute as below the :modern target" do
    findings = analyzer.analyze_source("<div popover>hello</div>", file: "/x.html.erb")
    popover = findings.find { |finding| finding.feature_name == "popover" }

    expect(popover).not_to be_nil
    expect(popover.severity).to eq(:error)
    expect(popover.feature_id).to eq("html.global_attributes.popover")
  end

  it "stays quiet about widely-available elements" do
    findings = analyzer.analyze_source("<details><summary>x</summary></details>", file: "/x.html.erb")
    expect(findings).to be_empty
  end

  it "warns about newly-available elements" do
    findings = analyzer.analyze_source("<search><input type=\"search\"></search>", file: "/x.html.erb")
    search = findings.find { |finding| finding.feature_name == "search" }

    expect(search&.severity).to eq(:warning)
  end

  it "respects the ignore.features list" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".browsable.yml"),
                 "ignore:\n  features: [\"html.global_attributes.popover\"]\n")
      ignoring = described_class.new(target: target, config: Browsable::Config.load(root: root))

      expect(ignoring.analyze_source("<div popover></div>", file: "/x.html.erb")).to be_empty
    end
  end
end
