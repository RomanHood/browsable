# frozen_string_literal: true

RSpec.describe Browsable::Formatters::Json do
  let(:finding) do
    Browsable::Finding.new(
      feature_id: "html.global_attributes.popover",
      feature_name: "popover",
      file: "/app/views/home/index.html.erb",
      line: 12, column: 6,
      required_browser_versions: { "firefox" => "125" },
      target_browser_versions: { "firefox" => "121" },
      severity: :error,
      message: "the 'popover' attribute requires Firefox 125+"
    )
  end

  it "renders a parseable report that matches the wire format" do
    report = Browsable::Report.new(findings: [finding], target: Browsable::Target.modern)
    json = JSON.parse(described_class.new(report).render)

    expect(json["summary"]["errors"]).to eq(1)
    expect(json["findings"].first["feature_name"]).to eq("popover")
    expect(json["target"]["query"]).to eq("modern")
  end

  it "renders an empty-but-valid report when there are no findings" do
    report = Browsable::Report.new(target: Browsable::Target.modern)
    json = JSON.parse(described_class.new(report).render)

    expect(json["findings"]).to eq([])
    expect(json["summary"]["errors"]).to eq(0)
  end

  it "includes the detected asset pipeline as a top-level field" do
    report = Browsable::Report.new(target: Browsable::Target.modern, pipeline: "sprockets")
    json = JSON.parse(described_class.new(report).render)

    expect(json["pipeline"]).to eq("sprockets")
  end

  it "emits a null pipeline when none was detected" do
    report = Browsable::Report.new(target: Browsable::Target.modern)
    json = JSON.parse(described_class.new(report).render)

    expect(json.key?("pipeline")).to be(true)
    expect(json["pipeline"]).to be_nil
  end
end
