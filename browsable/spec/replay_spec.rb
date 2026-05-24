# frozen_string_literal: true

require "spec_helper"
require "tempfile"

RSpec.describe Browsable::Replay do
  let(:dump) do
    {
      "target" => { "query" => "modern", "browsers" => { "chrome" => "120" } },
      "notes" => ["a caveat"],
      "summary" => { "errors" => 1, "warnings" => 0, "infos" => 0, "files" => 1 },
      "findings" => [
        {
          "feature_id" => "html.global_attributes.popover",
          "feature_name" => "popover",
          "file" => "app/views/x.html.erb",
          "line" => 4,
          "column" => 1,
          "required_browser_versions" => { "firefox" => "125" },
          "target_browser_versions" => { "chrome" => "120" },
          "severity" => "error",
          "message" => "the 'popover' attribute …"
        }
      ],
      "skips" => [],
      "policies" => []
    }
  end

  it "rebuilds findings from the JSON dump" do
    replay = described_class.new(dump)
    finding = replay.findings.first
    expect(finding.feature_name).to eq("popover")
    expect(finding.severity).to eq(:error)
  end

  it "preserves the human-format error count" do
    replay = described_class.new(dump)
    expect(replay.errors.size).to eq(1)
    expect(replay.exit_code(fail_on: "error")).to eq(1)
    expect(replay.exit_code(fail_on: "warning")).to eq(1)
  end

  it "is renderable through every v0.1 formatter" do
    replay = described_class.new(dump)
    expect(Browsable::Formatters::Human.new(replay).render).to include("popover")
    expect { Browsable::Formatters::Json.new(replay).render }.not_to raise_error
    expect(Browsable::Formatters::Github.new(replay).render).to include("::error")
  end

  it "loads from disk via .from_file" do
    Tempfile.open(["replay", ".json"]) do |f|
      f.write(JSON.generate(dump))
      f.flush
      replay = described_class.from_file(f.path)
      expect(replay.findings.size).to eq(1)
    end
  end
end
