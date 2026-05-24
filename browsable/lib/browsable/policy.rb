# frozen_string_literal: true

module Browsable
  # The effective `allow_browser` policy for a specific controller#action.
  #
  # Policy is what runtime mode produces per response — distinct from
  # PolicyScanner::Policy, which is a discovery record for one callsite. A
  # Policy carries enough information to (a) build a Target against which the
  # endpoint's assets are audited, and (b) explain *why* this is the policy in
  # play, when the TestReport renders findings.
  class Policy
    attr_reader :versions, :note, :scope, :only, :except, :source

    # @param versions [Hash, Symbol, nil] the resolved allow_browser argument
    # @param note     [String, nil]       caveat when the versions could not be resolved
    # @param scope    [String, nil]       the owning class name (nil for the fallback)
    # @param only     [Array<String>, nil] action filter from the call
    # @param except   [Array<String>, nil] action filter from the call
    # @param source   [Symbol]            :controller, :ancestor, or :default
    def initialize(versions:, note: nil, scope: nil, only: nil, except: nil, source: :controller)
      @versions = versions
      @note = note
      @scope = scope
      @only = only
      @except = except
      @source = source
    end

    # The Browsable::Target this policy implies. Falls back to the browserslist
    # `defaults` query when no allow_browser versions could be resolved.
    def target
      return Target.from_rails_policy(versions) if versions

      Target.new("defaults")
    end

    # A short human label, e.g. ":modern" or "{ chrome: 120, ... }" — used by
    # the TestReport when it wants to print which policy applied.
    def label
      case versions
      when Symbol then ":#{versions}"
      when Hash   then "{ #{versions.map { |k, v| "#{k}: #{v}" }.join(', ')} }"
      else            "(unresolved)"
      end
    end

    # True when this Policy is the application-wide fallback rather than a
    # specific allow_browser call. Distinguished so reports can say
    # "no controller policy — audited against the project default".
    def default? = source == :default

    def as_json
      {
        versions: versions,
        note: note,
        scope: scope,
        only: only,
        except: except,
        source: source.to_s
      }
    end
  end
end
