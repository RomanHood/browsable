# frozen_string_literal: true

RSpec.describe Browsable::Config do
  it "runs zero-config, supplying defaults when no file is present" do
    config = described_class.load(root: Dir.mktmpdir)

    expect(config.file_present?).to be(false)
    expect(config.severity["below_target"]).to eq("error")
    expect(config.importmap_enabled?).to be(true)
  end

  it "infers the target from ApplicationController's allow_browser policy" do
    Dir.mktmpdir do |root|
      controller = File.join(root, "app/controllers/application_controller.rb")
      FileUtils.mkdir_p(File.dirname(controller))
      File.write(controller, <<~RUBY)
        class ApplicationController < ActionController::Base
          allow_browser versions: :modern
        end
      RUBY

      config = described_class.load(root: root)
      expect(config.detected_policy).to eq(:modern)
      expect(config.target.minimum_version("safari")).to eq("17.2")
    end
  end

  it "infers the target from a multi-line allow_browser versions hash" do
    Dir.mktmpdir do |root|
      controller = File.join(root, "app/controllers/application_controller.rb")
      FileUtils.mkdir_p(File.dirname(controller))
      File.write(controller, <<~RUBY)
        class ApplicationController < ActionController::Base
          allow_browser versions: {
            safari: 16.4,
            firefox: 121,
            ie: false
          }
        end
      RUBY

      config = described_class.load(root: root)
      # `ie: false` is blocked, so it carries no version floor and is dropped.
      expect(config.detected_policy).to eq("safari" => "16.4", "firefox" => "121")
      expect(config.target.minimum_version("safari")).to eq("16.4")
      expect(config.target.minimum_version("ie")).to be_nil
    end
  end

  it "records a note (and falls back to defaults) when the policy is unresolvable" do
    Dir.mktmpdir do |root|
      controller = File.join(root, "app/controllers/application_controller.rb")
      FileUtils.mkdir_p(File.dirname(controller))
      File.write(controller, "class ApplicationController\n  allow_browser versions: runtime_policy\nend\n")

      config = described_class.load(root: root)
      expect(config.detected_policy).to be_nil
      expect(config.policy_note).not_to be_nil
      expect(config.target.query).to eq("defaults")
    end
  end

  it "ignores an allow_browser line that is commented out" do
    Dir.mktmpdir do |root|
      controller = File.join(root, "app/controllers/application_controller.rb")
      FileUtils.mkdir_p(File.dirname(controller))
      File.write(controller, <<~RUBY)
        class ApplicationController < ActionController::Base
          # allow_browser versions: :modern
        end
      RUBY

      config = described_class.load(root: root)
      expect(config.detected_policy).to be_nil
    end
  end

  it "merges a config file over the defaults" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".browsable.yml"), "severity:\n  below_target: warning\n")

      config = described_class.load(root: root)
      expect(config.severity["below_target"]).to eq("warning") # overridden
      expect(config.severity["baseline_limited"]).to eq("error") # default preserved
    end
  end

  it "raises a ConfigError on malformed YAML" do
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".browsable.yml"), "severity: [unterminated\n")
      expect { described_class.load(root: root) }.to raise_error(Browsable::ConfigError)
    end
  end
end
