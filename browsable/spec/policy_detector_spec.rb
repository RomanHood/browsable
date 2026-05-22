# frozen_string_literal: true

RSpec.describe Browsable::PolicyDetector do
  # Build a throwaway app root, yield it plus the controller path.
  def with_app
    Dir.mktmpdir do |root|
      controller = File.join(root, "app/controllers/application_controller.rb")
      FileUtils.mkdir_p(File.dirname(controller))
      yield root, controller
    end
  end

  it "resolves a named (:modern) policy" do
    with_app do |root, controller|
      File.write(controller, "class ApplicationController\n  allow_browser versions: :modern\nend\n")
      expect(described_class.call(root).policy).to eq(:modern)
    end
  end

  it "resolves an inline versions hash" do
    with_app do |root, controller|
      File.write(controller, <<~RUBY)
        class ApplicationController
          allow_browser versions: { safari: 16.4, firefox: 121, ie: false }
        end
      RUBY
      # ie: false is blocked, so it is dropped — no version floor to check.
      expect(described_class.call(root).policy).to eq("safari" => "16.4", "firefox" => "121")
    end
  end

  it "resolves a constant defined in the same file" do
    with_app do |root, controller|
      File.write(controller, <<~RUBY)
        class ApplicationController
          BROWSER_VERSIONS = { safari: 16.4, firefox: 121, ie: false }
          allow_browser versions: BROWSER_VERSIONS
        end
      RUBY
      result = described_class.call(root)
      expect(result.policy).to eq("safari" => "16.4", "firefox" => "121")
      expect(result.note).to be_nil
    end
  end

  it "resolves a constant defined in another file" do
    with_app do |root, controller|
      File.write(controller, <<~RUBY)
        class ApplicationController
          allow_browser versions: SupportedBrowsers::VERSIONS
        end
      RUBY
      initializer = File.join(root, "config/initializers/supported_browsers.rb")
      FileUtils.mkdir_p(File.dirname(initializer))
      # `.freeze` is the idiomatic way to write a constant hash — it must be
      # unwrapped, not treated as an opaque method call.
      File.write(initializer, <<~RUBY)
        module SupportedBrowsers
          VERSIONS = { safari: 16, chrome: 118 }.freeze
        end
      RUBY

      expect(described_class.call(root).policy).to eq("safari" => "16", "chrome" => "118")
    end
  end

  it "reports a note when the argument cannot be resolved statically" do
    with_app do |root, controller|
      File.write(controller, "class ApplicationController\n  allow_browser versions: compute_versions\nend\n")
      result = described_class.call(root)

      expect(result.policy).to be_nil
      expect(result.note).to match(/cannot evaluate statically/i)
    end
  end

  it "reports a note when a referenced constant cannot be found" do
    with_app do |root, controller|
      File.write(controller, "class ApplicationController\n  allow_browser versions: MISSING_CONST\nend\n")
      result = described_class.call(root)

      expect(result.policy).to be_nil
      expect(result.note).to match(/MISSING_CONST/)
    end
  end

  it "returns nothing when there is no allow_browser call (or it is commented out)" do
    with_app do |root, controller|
      File.write(controller, "class ApplicationController\n  # allow_browser versions: :modern\nend\n")
      result = described_class.call(root)

      expect(result.policy).to be_nil
      expect(result.note).to be_nil
    end
  end
end
