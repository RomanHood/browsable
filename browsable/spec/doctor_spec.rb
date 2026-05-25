# frozen_string_literal: true

RSpec.describe Browsable::Doctor do
  subject(:doctor) { described_class.new }

  it "always makes ERB/HTML analysis available (Herb is in-process)" do
    expect(doctor.available_kinds).to include(:erb, :html)
  end

  it "produces a status for every external tool it knows about" do
    keys = doctor.statuses.map { |status| status.tool.key }
    expect(keys).to include(:node, :npm, :stylelint, :eslint, :eslint_plugin_compat,
                            :postcss_scss)
  end

  it "lists postcss-scss as an optional (not required) tool" do
    tool = doctor.statuses.map(&:tool).find { |t| t.key == :postcss_scss }
    expect(tool.required).to be(false)
    expect(tool.enables).to eq([:scss])
  end

  it "renders a human-readable dependency report" do
    expect(doctor.render(color: false)).to include("browsable doctor")
  end

  it "does not flag postcss-scss as needed when the project has no SCSS files" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "app/assets/stylesheets"))
      File.write(File.join(root, "app/assets/stylesheets/application.css"), "/* */\n")

      doc = described_class.new(root: root)
      tool = doc.statuses.map(&:tool).find { |t| t.key == :postcss_scss }
      expect(doc.needs_tool?(tool)).to be(false)
    end
  end

  it "flags postcss-scss as needed when SCSS files are present" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, "app/assets/stylesheets"))
      File.write(File.join(root, "app/assets/stylesheets/application.scss"), "/* */\n")

      doc = described_class.new(root: root)
      tool = doc.statuses.map(&:tool).find { |t| t.key == :postcss_scss }
      expect(doc.needs_tool?(tool)).to be(true)
    end
  end
end
