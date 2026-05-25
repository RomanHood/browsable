# frozen_string_literal: true

RSpec.describe Browsable::Formatters::Human do
  it "prints the detected asset pipeline in the header" do
    report = Browsable::Report.new(target: Browsable::Target.modern, pipeline: "sprockets")
    output = described_class.new(report, color: false).render

    expect(output).to include("pipeline: sprockets")
  end

  it "reports the migration state when both pipelines are loaded" do
    report = Browsable::Report.new(target: Browsable::Target.modern,
                                   pipeline: "sprockets+propshaft")
    output = described_class.new(report, color: false).render

    expect(output).to include("pipeline: sprockets+propshaft")
  end

  it "omits the pipeline line entirely when no pipeline was detected" do
    report = Browsable::Report.new(target: Browsable::Target.modern)
    output = described_class.new(report, color: false).render

    expect(output).not_to include("pipeline:")
  end
end
