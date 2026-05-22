# frozen_string_literal: true

RSpec.describe Browsable::LSP::Diagnostics do
  it "converts a popover finding into an LSP error diagnostic" do
    Dir.mktmpdir do |root|
      diagnostics = described_class.for(
        uri: "file://#{root}/app/views/home/index.html.erb",
        content: "<div popover>hello</div>",
        root: root
      )

      popover = diagnostics.find { |d| d[:code] == "html.global_attributes.popover" }
      expect(popover).not_to be_nil
      expect(popover[:severity]).to eq(1) # LSP DiagnosticSeverity::ERROR
      expect(popover[:source]).to eq("browsable")
      expect(popover[:range][:start]).to be_a(Hash)
    end
  end

  it "produces no diagnostics for widely-available markup" do
    Dir.mktmpdir do |root|
      diagnostics = described_class.for(
        uri: "file://#{root}/index.html.erb",
        content: "<details><summary>x</summary></details>",
        root: root
      )

      expect(diagnostics).to eq([])
    end
  end

  it "ignores file types it has no analyzer for" do
    diagnostics = described_class.for(uri: "file:///tmp/notes.txt", content: "hello", root: Dir.pwd)
    expect(diagnostics).to eq([])
  end
end
