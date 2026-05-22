# frozen_string_literal: true

RSpec.describe Browsable::Doctor do
  subject(:doctor) { described_class.new }

  it "always makes ERB/HTML analysis available (Herb is in-process)" do
    expect(doctor.available_kinds).to include(:erb, :html)
  end

  it "produces a status for every external tool it knows about" do
    keys = doctor.statuses.map { |status| status.tool.key }
    expect(keys).to include(:node, :npm, :stylelint, :eslint, :eslint_plugin_compat)
  end

  it "renders a human-readable dependency report" do
    expect(doctor.render(color: false)).to include("browsable doctor")
  end
end
