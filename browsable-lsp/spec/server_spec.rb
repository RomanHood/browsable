# frozen_string_literal: true

RSpec.describe Browsable::LSP::Server do
  it "advertises full-sync capabilities on initialize" do
    result = Browsable::LSP::Handlers::Initialize.new.call({})

    expect(result.dig(:capabilities, :textDocumentSync, :change)).to eq(1)
    expect(result.dig(:serverInfo, :name)).to eq("browsable-lsp")
  end

  it "extracts a workspace root from a rootUri" do
    root = Browsable::LSP::Handlers::Initialize.workspace_root("rootUri" => "file:///srv/app")
    expect(root).to eq("/srv/app")
  end
end
