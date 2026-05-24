# frozen_string_literal: true

require "spec_helper"

RSpec.describe Browsable::PolicyResolver do
  before { described_class.reset! }
  after  { described_class.reset! }

  def call_info(policy:, only: nil, except: nil)
    Browsable::PolicyDetector::CallInfo.new(
      result: Browsable::PolicyDetector::Result.new(policy: policy, note: nil),
      only: only,
      except: except
    )
  end

  def scanner_policy(scope:, call:, file: "app/controllers/x.rb", concern: false)
    Browsable::PolicyScanner::Policy.new(
      scope: scope,
      file: file,
      result: call.result,
      only: call.only,
      except: call.except,
      concern: concern
    )
  end

  let(:default_policy) do
    Browsable::Policy.new(versions: :modern, scope: nil, source: :default)
  end

  describe ".for" do
    it "returns a controller-specific policy when one exists" do
      controller = Class.new
      stub_const("PostsController", controller)
      described_class.configure(
        policies: [
          scanner_policy(scope: "PostsController",
                         call: call_info(policy: { "chrome" => "100" }))
        ],
        default: default_policy
      )

      policy = described_class.for(PostsController, :index)
      expect(policy.scope).to eq("PostsController")
      expect(policy.versions).to eq({ "chrome" => "100" })
      expect(policy.source).to eq(:controller)
    end

    it "honors only: scoping (matches the listed action, falls back otherwise)" do
      controller = Class.new
      stub_const("PostsController", controller)
      described_class.configure(
        policies: [
          scanner_policy(scope: "PostsController",
                         call: call_info(policy: :modern, only: %w[show]))
        ],
        default: default_policy
      )

      expect(described_class.for(PostsController, :show).versions).to eq(:modern)
      expect(described_class.for(PostsController, :index).source).to eq(:default)
    end

    it "honors except: scoping (skips the listed action, applies otherwise)" do
      controller = Class.new
      stub_const("PostsController", controller)
      described_class.configure(
        policies: [
          scanner_policy(scope: "PostsController",
                         call: call_info(policy: :modern, except: %w[embed]))
        ],
        default: default_policy
      )

      expect(described_class.for(PostsController, :show).versions).to eq(:modern)
      expect(described_class.for(PostsController, :embed).source).to eq(:default)
    end

    it "picks the last matching call when several apply" do
      controller = Class.new
      stub_const("PostsController", controller)
      described_class.configure(
        policies: [
          scanner_policy(scope: "PostsController",
                         call: call_info(policy: :first)),
          scanner_policy(scope: "PostsController",
                         call: call_info(policy: :second))
        ],
        default: default_policy
      )

      expect(described_class.for(PostsController, :index).versions).to eq(:second)
    end

    it "walks the ancestor chain to find an inherited policy" do
      parent = Class.new
      child = Class.new(parent)
      stub_const("ApplicationController", parent)
      stub_const("PostsController", child)
      described_class.configure(
        policies: [
          scanner_policy(scope: "ApplicationController",
                         call: call_info(policy: :modern))
        ],
        default: default_policy
      )

      policy = described_class.for(PostsController, :index)
      expect(policy.scope).to eq("ApplicationController")
      expect(policy.source).to eq(:ancestor)
    end

    it "returns the default when no call matches" do
      controller = Class.new
      stub_const("LonelyController", controller)
      described_class.configure(policies: [], default: default_policy)

      expect(described_class.for(LonelyController, :index)).to eq(default_policy)
    end

    it "returns the default when controller or action is nil/empty" do
      described_class.configure(policies: [], default: default_policy)
      expect(described_class.for(nil, :show)).to eq(default_policy)

      controller = Class.new { def self.name = "X" }
      stub_const("X", controller)
      expect(described_class.for(X, "")).to eq(default_policy)
    end
  end
end
