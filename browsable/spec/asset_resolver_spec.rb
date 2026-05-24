# frozen_string_literal: true

require "spec_helper"

RSpec.describe Browsable::AssetResolver do
  let(:root) { Dir.mktmpdir("browsable-asset-resolver") }

  after { FileUtils.remove_entry(root) if File.directory?(root) }

  def write(relative)
    absolute = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(absolute))
    File.write(absolute, "")
    absolute
  end

  subject(:resolver) { described_class.new(rails_app: nil, root: root) }

  describe "#resolve" do
    it "resolves a digested filename to its undigested source on disk" do
      expected = write("app/assets/builds/application.css")
      expect(resolver.resolve("/assets/application-abcdef1234567.css")).to eq(expected)
    end

    it "resolves a root-relative cssbundling asset under app/assets/builds" do
      expected = write("app/assets/builds/application.css")
      expect(resolver.resolve("/application.css")).to eq(expected)
    end

    it "resolves an esbuild-style asset under app/javascript" do
      expected = write("app/javascript/application.js")
      expect(resolver.resolve("/application.js")).to eq(expected)
    end

    it "falls back to public/ for precompiled static files" do
      expected = write("public/favicon.png")
      expect(resolver.resolve("/favicon.png")).to eq(expected)
    end

    it "returns nil for absolute URLs without a matching asset host" do
      expect(resolver.resolve("https://cdn.example.com/x.js")).to be_nil
    end

    it "returns nil for data: URLs" do
      expect(resolver.resolve("data:image/png;base64,iVBORw0KGgo")).to be_nil
    end

    it "returns nil when the file cannot be located" do
      expect(resolver.resolve("/nonexistent.css")).to be_nil
    end

    it "returns nil for nil or empty input" do
      expect(resolver.resolve(nil)).to be_nil
      expect(resolver.resolve("")).to be_nil
    end

    it "strips a query string before resolving" do
      expected = write("public/app.js")
      expect(resolver.resolve("/app.js?v=4")).to eq(expected)
    end
  end

  describe "#detailed_resolve" do
    it "labels which strategy matched" do
      write("app/assets/builds/application.css")
      result = resolver.detailed_resolve("/application.css")
      expect(result.strategy).to eq(:filesystem)
      expect(result).to be_resolved
    end

    it "reports :external for unmatched absolute URLs" do
      result = resolver.detailed_resolve("https://other.example.com/x.js")
      expect(result.strategy).to eq(:external)
      expect(result).not_to be_resolved
    end

    it "reports :unresolved when nothing matched" do
      result = resolver.detailed_resolve("/missing.css")
      expect(result.strategy).to eq(:unresolved)
    end
  end
end
