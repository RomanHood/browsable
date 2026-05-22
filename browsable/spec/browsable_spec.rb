# frozen_string_literal: true

RSpec.describe Browsable do
  it "exposes a semantic version" do
    expect(Browsable::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  it "autoloads its constants through Zeitwerk" do
    expect(Browsable::Finding).to be_a(Class)
    expect(Browsable::Analyzers::CSS).to be < Browsable::Analyzers::Base
  end

  it "points at the bundled compat-data directory" do
    expect(File).to exist(File.join(Browsable.data_dir, "bcd-snapshot.json"))
  end
end
