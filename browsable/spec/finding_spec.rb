# frozen_string_literal: true

RSpec.describe Browsable::Finding do
  def build(severity: :error)
    described_class.new(
      feature_id: "html.global_attributes.popover",
      feature_name: "popover",
      file: "/app/views/home/index.html.erb",
      line: 12,
      column: 6,
      required_browser_versions: { "firefox" => "125" },
      target_browser_versions: { "firefox" => "121" },
      severity: severity,
      message: "the 'popover' attribute requires Firefox 125+"
    )
  end

  it "answers questions about its severity" do
    expect(build(severity: :error)).to be_error
    expect(build(severity: :warning)).to be_warning
    expect(build(severity: :info)).to be_info
  end

  it "is an immutable, comparable value object" do
    expect(build).to eq(build)
    expect(build).to be_frozen
  end

  it "serializes to a JSON-friendly hash" do
    json = build.as_json
    expect(json[:feature_name]).to eq("popover")
    expect(json[:severity]).to eq("error")
    expect(json[:required_browser_versions]).to eq("firefox" => "125")
  end
end
