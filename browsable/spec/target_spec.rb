# frozen_string_literal: true

RSpec.describe Browsable::Target do
  describe ".modern" do
    it "resolves the Rails :modern baseline without shelling out" do
      target = described_class.modern
      expect(target.minimum_version("safari")).to eq("17.2")
      expect(target.minimum_version("chrome")).to eq("120")
    end
  end

  describe "#includes?" do
    let(:target) { described_class.modern }

    it "accepts versions at or above the floor" do
      expect(target.includes?("safari", "17.2")).to be(true)
      expect(target.includes?("safari", "18.0")).to be(true)
    end

    it "rejects versions below the floor" do
      expect(target.includes?("safari", "16")).to be(false)
    end
  end

  describe ".from_rails_policy" do
    it "maps :modern to the modern baseline" do
      target = described_class.from_rails_policy(:modern)
      expect(target.minimum_version("firefox")).to eq("121")
    end

    it "accepts an explicit version hash" do
      target = described_class.from_rails_policy(safari: 16, chrome: 118)
      expect(target.minimum_version("safari")).to eq("16")
    end
  end

  it "renders itself as browserslist fragments for stylelint/eslint" do
    expect(described_class.modern.to_browserslist).to include("safari >= 17.2")
  end

  describe "#resolved_via and #note" do
    it "marks a Rails-supplied target as explicit, with no caveat" do
      target = described_class.modern
      expect(target.resolved_via).to eq(:explicit)
      expect(target.note).to be_nil
    end

    it "flags a target that fell back to the built-in table" do
      target = described_class.new("defaults")
      allow(target).to receive(:from_browserslist_cli).and_return(nil)

      expect(target.resolved_via).to eq(:builtin)
      expect(target.note).to include("browserslist")
    end

    it "adds no caveat when browserslist resolved the target" do
      target = described_class.new("last 2 versions")
      allow(target).to receive(:from_browserslist_cli).and_return("chrome" => "120")

      expect(target.resolved_via).to eq(:browserslist)
      expect(target.note).to be_nil
    end
  end
end
