# frozen_string_literal: true

module Browsable
  # Maps a `(controller_class, action_name)` pair to the effective Browsable
  # Policy. This is what runtime mode uses, per response, to decide which
  # browsers an endpoint's assets must support.
  #
  # Resolution rules (matching Rails' own filter-callback semantics):
  #
  #   1. Walk the controller's ancestor chain from the most-specific class up
  #      to ApplicationController, ignoring anonymous classes and modules.
  #   2. For each class, look up its allow_browser callsites (PolicyScanner
  #      data) and pick the *last* call whose `only:`/`except:` filter matches.
  #   3. The first ancestor with a matching call wins — its last matching call
  #      becomes the effective policy.
  #   4. If no call matches, return the configured default Policy (the policy
  #      from ApplicationController, falling through to the project default).
  #
  # The scanned policy data is built lazily on first use. Tests can call
  # `.reset!` between examples to swap roots without process restart.
  class PolicyResolver
    class << self
      # Convenience: resolve a single controller#action using the shared state.
      def for(controller_class, action_name)
        new(controller_class, action_name).resolve
      end

      # Inject pre-scanned data — used by drivers (which know the Rails root)
      # and by tests (which want to bypass disk).
      def configure(root: nil, policies: nil, default: nil)
        @root = root
        @policies = policies
        @default = default
        @lookup = nil
      end

      # Forget any cached state. Called between test files.
      def reset!
        @root = nil
        @policies = nil
        @default = nil
        @lookup = nil
      end

      def root
        @root ||= (defined?(Rails) && Rails.application ? Rails.root.to_s : Dir.pwd)
      end

      def policies
        @policies ||= PolicyScanner.call(root)
      end

      def default_policy
        @default ||= build_default_policy
      end

      # { "PostsController" => [PolicyScanner::Policy, ...] }, built once.
      def lookup
        @lookup ||= policies.group_by(&:scope)
      end

      private

      def build_default_policy
        config = Config.load(root: root)
        Policy.new(
          versions: config.detected_policy,
          note: config.policy_note,
          scope: nil,
          source: :default
        )
      rescue StandardError
        Policy.new(versions: nil, note: nil, scope: nil, source: :default)
      end
    end

    attr_reader :controller_class, :action_name

    def initialize(controller_class, action_name)
      @controller_class = controller_class
      @action_name = action_name&.to_s
    end

    def resolve
      return self.class.default_policy if controller_class.nil? || action_name.nil? || action_name.empty?

      ancestor_class_names.each do |name|
        calls = self.class.lookup[name]
        next unless calls && !calls.empty?

        match = calls.reverse.find { |call| applies?(call) }
        next unless match

        return policy_from(match, scope: name, source: same_class?(name) ? :controller : :ancestor)
      end

      self.class.default_policy
    end

    private

    # Most-specific → least-specific class names in the controller's ancestor
    # chain. We stop at ActionController::Base / ActionController::API because
    # nothing above is user code that could carry an allow_browser call.
    def ancestor_class_names
      seen = []
      controller_class.ancestors.each do |ancestor|
        break if action_controller_root?(ancestor)
        next unless ancestor.is_a?(Class)

        name = ancestor.name
        next if name.nil? || name.empty?

        seen << name unless seen.include?(name)
      end
      seen
    end

    def action_controller_root?(ancestor)
      return false unless ancestor.is_a?(Class)

      name = ancestor.name.to_s
      name == "ActionController::Base" || name == "ActionController::API"
    end

    # Does this allow_browser call's only:/except: filter apply to our action?
    def applies?(call)
      return action_in?(call.only) if call.only
      return !action_in?(call.except) if call.except

      true
    end

    def action_in?(list)
      Array(list).map(&:to_s).include?(action_name)
    end

    def same_class?(name)
      name == controller_class.name
    end

    def policy_from(call, scope:, source:)
      Policy.new(
        versions: call.result.policy,
        note: call.result.note,
        scope: scope,
        only: call.only,
        except: call.except,
        source: source
      )
    end
  end
end
