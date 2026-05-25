# frozen_string_literal: true

RSpec.describe Browsable::AssetPipeline do
  def write_lockfile(root, gems)
    File.write(File.join(root, "Gemfile.lock"), <<~LOCK)
      GEM
        remote: https://rubygems.org/
        specs:
      #{gems.map { |gem| "    #{gem} (0.0.0)" }.join("\n")}

      PLATFORMS
        ruby

      DEPENDENCIES
      #{gems.map { |gem| "  #{gem}" }.join("\n")}

      BUNDLED WITH
         2.5.6
    LOCK
  end

  it "reports 'none' when no asset-pipeline gem is in the lockfile" do
    Dir.mktmpdir do |root|
      write_lockfile(root, %w[rails])
      expect(described_class.detect(root: root).name).to eq("none")
    end
  end

  it "reports 'propshaft' when only Propshaft is in the lockfile" do
    Dir.mktmpdir do |root|
      write_lockfile(root, %w[rails propshaft])
      pipeline = described_class.detect(root: root)
      expect(pipeline.name).to eq("propshaft")
      expect(pipeline.propshaft?).to be(true)
      expect(pipeline.sprockets?).to be(false)
    end
  end

  it "reports 'sprockets' when only sprockets-rails is in the lockfile" do
    Dir.mktmpdir do |root|
      write_lockfile(root, %w[rails sprockets-rails])
      pipeline = described_class.detect(root: root)
      expect(pipeline.name).to eq("sprockets")
      expect(pipeline.sprockets?).to be(true)
      expect(pipeline.propshaft?).to be(false)
    end
  end

  it "reports 'sprockets+propshaft' when both gems are in the lockfile" do
    Dir.mktmpdir do |root|
      write_lockfile(root, %w[rails sprockets-rails propshaft])
      pipeline = described_class.detect(root: root)
      expect(pipeline.name).to eq("sprockets+propshaft")
      expect(pipeline.sprockets?).to be(true)
      expect(pipeline.propshaft?).to be(true)
      # When both are loaded the broader (Sprockets) discovery wins.
      expect(pipeline.prefer_sprockets_layout?).to be(true)
    end
  end

  it "falls back to 'none' when no Gemfile.lock exists" do
    Dir.mktmpdir do |root|
      expect(described_class.detect(root: root).name).to eq("none")
    end
  end

  # The example fixtures commit a Gemfile but not a Gemfile.lock (gem repo
  # convention — gems don't pin host lockfiles). When a developer runs `bundle
  # install` locally the lockfile appears and these specs become useful end-to-
  # end sanity checks; in CI they're skipped.
  it "matches the bundled Sprockets example fixture as 'sprockets'" do
    fixture = File.expand_path("../../examples/sprockets_app", __dir__)
    skip "fixture missing" unless File.directory?(fixture)
    skip "fixture has no Gemfile.lock (run `bundle install` in the fixture)" \
      unless File.file?(File.join(fixture, "Gemfile.lock"))

    expect(described_class.detect(root: fixture).name).to eq("sprockets")
  end

  it "matches the bundled Propshaft example fixture as 'propshaft'" do
    fixture = File.expand_path("../../examples/rails_app", __dir__)
    skip "fixture missing" unless File.directory?(fixture)
    skip "fixture has no Gemfile.lock (run `bundle install` in the fixture)" \
      unless File.file?(File.join(fixture, "Gemfile.lock"))

    expect(described_class.detect(root: fixture).name).to eq("propshaft")
  end
end
