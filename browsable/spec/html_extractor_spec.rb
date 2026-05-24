# frozen_string_literal: true

require "spec_helper"

RSpec.describe Browsable::HtmlExtractor do
  let(:resolver) do
    Class.new do
      def initialize(map) = @map = map
      def resolve(url) = @map[url]
    end.new(
      "/application.css" => "/abs/app/assets/builds/application.css",
      "/application.js"  => "/abs/app/javascript/application.js"
    )
  end

  def extract(html)
    described_class.extract(html, asset_resolver: resolver)
  end

  it "extracts stylesheet links and resolves them" do
    html = <<~HTML
      <!doctype html>
      <html>
        <head>
          <link rel="stylesheet" href="/application.css">
        </head>
        <body></body>
      </html>
    HTML

    result = extract(html)
    expect(result.asset_paths.size).to eq(1)
    expect(result.asset_paths.first.url).to eq("/application.css")
    expect(result.asset_paths.first.kind).to eq(:css)
    expect(result.asset_paths.first.resolved_path).to eq("/abs/app/assets/builds/application.css")
  end

  it "extracts external script sources" do
    html = '<html><body><script src="/application.js"></script></body></html>'
    result = extract(html)

    js = result.asset_paths.find { |a| a.kind == :js }
    expect(js).not_to be_nil
    expect(js.resolved_path).to eq("/abs/app/javascript/application.js")
  end

  it "captures inline <style> and <script> blocks" do
    html = <<~HTML
      <html><head>
        <style>.x { color: red }</style>
      </head><body>
        <script>console.log("hi")</script>
      </body></html>
    HTML

    result = extract(html)
    kinds = result.inline_blocks.map(&:kind).sort
    expect(kinds).to eq(%i[css js])
  end

  it "skips inert script blocks (importmap JSON, application/json)" do
    html = <<~HTML
      <html><body>
        <script type="importmap">{ "imports": {} }</script>
        <script type="application/json">{}</script>
        <script>real();</script>
      </body></html>
    HTML

    result = extract(html)
    expect(result.inline_blocks.size).to eq(1)
    expect(result.inline_blocks.first.content).to include("real()")
  end

  it "preserves unresolved asset references with a nil path" do
    html = '<html><head><link rel="stylesheet" href="https://cdn.example.com/x.css"></head></html>'
    result = extract(html)

    expect(result.asset_paths.size).to eq(1)
    expect(result.asset_paths.first.resolved_path).to be_nil
  end

  it "returns the empty extraction for blank input" do
    result = described_class.extract("", asset_resolver: resolver)
    expect(result.asset_paths).to be_empty
    expect(result.inline_blocks).to be_empty
  end

  it "deduplicates repeated identical references" do
    html = <<~HTML
      <html><head>
        <link rel="stylesheet" href="/application.css">
        <link rel="stylesheet" href="/application.css">
      </head></html>
    HTML

    expect(extract(html).asset_paths.size).to eq(1)
  end

  describe "Extraction#resolved_paths" do
    it "returns the deduplicated list of resolved paths" do
      html = <<~HTML
        <html><head>
          <link rel="stylesheet" href="/application.css">
          <script src="/application.js"></script>
        </head></html>
      HTML

      paths = extract(html).resolved_paths
      expect(paths.size).to eq(2)
      expect(paths).to include("/abs/app/assets/builds/application.css")
    end
  end
end
