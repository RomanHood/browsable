# frozen_string_literal: true

require "spec_helper"

RSpec.describe Browsable::AuditLog do
  subject(:log) { described_class.new }

  let(:policy) { Browsable::Policy.new(versions: :modern, scope: nil, source: :default) }

  def asset(path, kind: :css)
    Browsable::HtmlExtractor::AssetRef.new(url: "/x", resolved_path: path, kind: kind)
  end

  def record(endpoint:, paths: [], html: "<html></html>")
    log.record(
      endpoint: endpoint,
      request_path: "/p",
      policy: policy,
      html: html,
      asset_paths: paths.map { |p| asset(p) },
      inline_blocks: []
    )
  end

  it "appends entries and exposes them in insertion order" do
    record(endpoint: "A#a", paths: ["/x.css"])
    record(endpoint: "B#b", paths: ["/y.css"])
    expect(log.entries.map(&:endpoint)).to eq(%w[A#a B#b])
  end

  it "size and empty? reflect the accumulator state" do
    expect(log).to be_empty
    record(endpoint: "A#a")
    expect(log.size).to eq(1)
    expect(log).not_to be_empty
  end

  it "asset_path_universe deduplicates across entries" do
    record(endpoint: "A#a", paths: ["/app.css", "/lib.css"])
    record(endpoint: "B#b", paths: ["/app.css"])
    expect(log.asset_path_universe).to contain_exactly("/app.css", "/lib.css")
  end

  it "asset_path_universe excludes nil-resolved references" do
    log.record(
      endpoint: "A#a", request_path: "/", policy: policy, html: "",
      asset_paths: [asset(nil), asset("/x.css")], inline_blocks: []
    )
    expect(log.asset_path_universe).to contain_exactly("/x.css")
  end

  it "entries_loading filters by resolved path" do
    record(endpoint: "A#a", paths: ["/x.css"])
    record(endpoint: "B#b", paths: ["/y.css"])
    expect(log.entries_loading("/x.css").map(&:endpoint)).to eq(["A#a"])
  end

  it "clear empties the accumulator" do
    record(endpoint: "A#a")
    log.clear
    expect(log).to be_empty
  end

  it "Browsable.audit_log is a process-wide singleton until replaced" do
    original = Browsable.audit_log
    expect(Browsable.audit_log).to be(original)
  ensure
    Browsable.audit_log = nil
  end
end
