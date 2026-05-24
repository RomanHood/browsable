# frozen_string_literal: true

require "spec_helper"

RSpec.describe Browsable::Drivers::RSpec do
  before do
    described_class.reset!
    Browsable.audit_log = Browsable::AuditLog.new
  end

  after do
    described_class.reset!
    Browsable.audit_log = nil
  end

  describe "Configuration" do
    it "exposes editable defaults" do
      config = described_class.configuration
      expect(config.fail_on).to eq(:error)
      expect(config.format).to eq(:human)
      expect(config.output).to eq(:stdout)
      expect(config.enabled).to be(true)
    end

    it "yields the config object via .configure" do
      described_class.configure { |c| c.fail_on = :warning }
      expect(described_class.configuration.fail_on).to eq(:warning)
    end
  end

  describe ".before_suite" do
    it "clears the audit log" do
      Browsable.audit_log.record(
        endpoint: "X#x", request_path: "/", html: "",
        policy: Browsable::Policy.new(versions: :modern, source: :default),
        asset_paths: [], inline_blocks: []
      )
      expect(Browsable.audit_log).not_to be_empty

      described_class.before_suite
      expect(Browsable.audit_log).to be_empty
    end
  end

  describe ".after_suite" do
    it "is a no-op when nothing was recorded" do
      expect { described_class.after_suite }.not_to raise_error
    end

    it "renders to the configured output stream" do
      Browsable.audit_log.record(
        endpoint: "X#x", request_path: "/",
        policy: Browsable::Policy.new(versions: :modern, source: :default),
        html: "", asset_paths: [], inline_blocks: []
      )

      io = StringIO.new
      described_class.configure { |c| c.output = io; c.fail_on = :never }
      report = instance_double(Browsable::TestReport, render: "RENDERED", fail_suite_if_errors!: nil)
      allow(Browsable::TestReport).to receive(:new).and_return(report)

      described_class.send(:emit, report)
      expect(io.string).to include("RENDERED")
    end
  end
end
