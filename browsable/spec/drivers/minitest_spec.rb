# frozen_string_literal: true

require "spec_helper"

RSpec.describe Browsable::Drivers::Minitest do
  before do
    described_class.reset!
    Browsable.audit_log = Browsable::AuditLog.new
  end

  after do
    described_class.reset!
    Browsable.audit_log = nil
  end

  it "ships matching defaults to the RSpec driver" do
    config = described_class.configuration
    expect(config.fail_on).to eq(:error)
    expect(config.format).to eq(:human)
  end

  it "is a no-op when nothing was recorded" do
    expect { described_class.after_run }.not_to raise_error
  end

  it "renders into the configured output stream" do
    Browsable.audit_log.record(
      endpoint: "X#x", request_path: "/",
      policy: Browsable::Policy.new(versions: :modern, source: :default),
      html: "", asset_paths: [], inline_blocks: []
    )

    io = StringIO.new
    described_class.configure { |c| c.output = io; c.fail_on = :never }
    report = instance_double(Browsable::TestReport, render: "OUTPUT", fail_suite_if_errors!: nil)
    allow(Browsable::TestReport).to receive(:new).and_return(report)

    described_class.send(:emit, report)
    expect(io.string).to include("OUTPUT")
  end
end
