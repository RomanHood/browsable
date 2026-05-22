# frozen_string_literal: true

require "prism"

module Browsable
  # Understands Rails `allow_browser` call sites.
  #
  # Parses controller source with Prism (no Rails boot, no eval) and resolves a
  # call's `versions:` argument — following a constant into the same file, then
  # across the app. It is used two ways:
  #
  #   * PolicyDetector.call(root) — ApplicationController's policy, which drives
  #     the audit target (see Config).
  #   * #scan_calls(source) — every allow_browser call in one file, for the
  #     project-wide policy landscape (see PolicyScanner).
  #
  # When an argument cannot be resolved statically the Result carries a `note`
  # instead of a policy.
  class PolicyDetector
    # policy: Symbol (a named policy, e.g. :modern)
    #         | Hash ("browser" => "version")
    #         | nil
    # note:   why an allow_browser call could not be resolved; nil otherwise.
    Result = Data.define(:policy, :note) do
      def resolved? = !policy.nil?
    end

    # One allow_browser call: its resolved versions plus any only:/except: scope.
    CallInfo = Data.define(:result, :only, :except)

    # The "nothing found" result.
    NONE = Result.new(policy: nil, note: nil)

    # Where to look for a constant defined outside the file being scanned.
    SEARCH_GLOBS = ["app/**/*.rb", "config/**/*.rb", "lib/**/*.rb"].freeze
    MAX_SEARCH_FILES = 600

    def self.call(root) = new(root).application_policy

    def initialize(root)
      @root = root
    end

    # The policy declared on ApplicationController — the app-wide audit target.
    # When the controller has several allow_browser calls, the first wins.
    def application_policy
      return NONE unless File.file?(controller_path)

      calls = scan_calls(File.read(controller_path))
      calls.empty? ? NONE : calls.first.result
    rescue StandardError => e
      Result.new(policy: nil, note: "could not read the allow_browser policy: #{e.message}")
    end

    # Every allow_browser call in a single source file, each resolved.
    def scan_calls(source)
      allow_browser_calls(parse(source)).map do |call|
        CallInfo.new(
          result: resolve(versions_argument(call), controller_source: source),
          only:   action_names(keyword_argument(call, :only)),
          except: action_names(keyword_argument(call, :except))
        )
      end
    rescue StandardError
      []
    end

    private

    def controller_path
      @controller_path ||= File.join(@root, "app/controllers/application_controller.rb")
    end

    def parse(source)
      Prism.parse(source).value
    end

    # --- locating calls and arguments ----------------------------------------

    def allow_browser_calls(root_node)
      each_node(root_node).select do |node|
        node.is_a?(Prism::CallNode) && %i[allow_browser allow_browsers].include?(node.name)
      end
    end

    def versions_argument(call_node)
      keyword_argument(call_node, :versions) || positional_symbol(call_node)
    end

    # The value node of a keyword argument, e.g. `only:` in an allow_browser call.
    def keyword_argument(call_node, name)
      Array(call_node.arguments&.arguments).each do |arg|
        next unless arg.is_a?(Prism::KeywordHashNode) || arg.is_a?(Prism::HashNode)

        assoc = arg.elements.find do |element|
          element.is_a?(Prism::AssocNode) && symbol_name(element.key) == name
        end
        return assoc.value if assoc
      end
      nil
    end

    def positional_symbol(call_node)
      Array(call_node.arguments&.arguments).find { |arg| arg.is_a?(Prism::SymbolNode) }
    end

    # A `:show` or `[:show, :edit]` argument as an array of action-name strings.
    def action_names(node)
      case node
      when Prism::SymbolNode
        [node.value]
      when Prism::ArrayNode
        names = node.elements.filter_map { |e| e.value if e.is_a?(Prism::SymbolNode) }
        names.empty? ? nil : names
      end
    end

    # --- resolving the versions argument -------------------------------------

    def resolve(node, controller_source:)
      # A literal hash — possibly wrapped in .freeze/.dup — short-circuits here.
      if (hash = hash_node(node))
        return from_hash(hash)
      end

      case node
      when nil
        Result.new(policy: nil, note: "an allow_browser call was found but has no versions: argument")
      when Prism::SymbolNode
        Result.new(policy: node.value.to_sym, note: nil)
      when Prism::ConstantReadNode, Prism::ConstantPathNode
        resolve_constant(node, controller_source: controller_source)
      else
        Result.new(policy: nil, note: unresolved_note(describe(node)))
      end
    end

    # The literal HashNode behind a node, unwrapping a no-argument .freeze/.dup/
    # .clone call. Returns nil when there is no literal hash.
    def hash_node(node)
      case node
      when Prism::HashNode
        node
      when Prism::CallNode
        if %i[freeze dup clone].include?(node.name) && node.receiver
          hash_node(node.receiver)
        end
      end
    end

    def from_hash(hash_node)
      versions = read_versions_hash(hash_node)
      if versions
        Result.new(policy: versions, note: nil)
      else
        Result.new(policy: nil, note: "the allow_browser versions hash contained no numeric versions")
      end
    end

    def resolve_constant(node, controller_source:)
      name = node.name # the leaf segment, for a namespaced ConstantPathNode
      return Result.new(policy: nil, note: unresolved_note(describe(node))) unless name

      hash = find_constant_hash(controller_source, name) || search_constant(name)
      return Result.new(policy: hash, note: nil) if hash

      Result.new(
        policy: nil,
        note: "allow_browser references the constant #{name}, which browsable could not " \
              "resolve to a literal versions hash. Set `target:` in config/browsable.yml " \
              "or pass --target to be explicit."
      )
    end

    # --- reading a versions hash ---------------------------------------------

    def read_versions_hash(hash_node)
      versions = {}
      hash_node.elements.each do |element|
        next unless element.is_a?(Prism::AssocNode)

        browser = symbol_name(element.key)
        version = numeric_literal(element.value)
        # A browser mapped to false (blocked) or true (any version) has no
        # version floor, so it is left out of the target entirely.
        versions[browser.to_s] = version if browser && version
      end
      versions.empty? ? nil : versions
    end

    def numeric_literal(node)
      node.value.to_s if node.is_a?(Prism::IntegerNode) || node.is_a?(Prism::FloatNode)
    end

    # --- constant lookup -----------------------------------------------------

    def find_constant_hash(source, name)
      write = each_node(parse(source)).find { |node| constant_write?(node, name) }
      return nil unless write

      hash = hash_node(write.value)
      hash && read_versions_hash(hash)
    rescue StandardError
      nil
    end

    def constant_write?(node, name)
      case node
      when Prism::ConstantWriteNode
        node.name == name
      when Prism::ConstantPathWriteNode
        node.target.respond_to?(:name) && node.target.name == name
      else
        false
      end
    end

    # Scan the app for the constant's definition. Files are filtered by a cheap
    # string match before the relatively expensive Prism parse.
    def search_constant(name)
      needle = name.to_s
      candidate_files.each do |file|
        text = File.read(file)
        next unless text.include?(needle)

        hash = find_constant_hash(text, name)
        return hash if hash
      end
      nil
    rescue StandardError
      nil
    end

    def candidate_files
      SEARCH_GLOBS
        .flat_map { |glob| Dir.glob(File.join(@root, glob)) }
        .select { |path| File.file?(path) }
        .reject { |path| path == controller_path }
        .first(MAX_SEARCH_FILES)
    end

    # --- helpers -------------------------------------------------------------

    # Depth-first enumeration of every node in a Prism tree.
    def each_node(node, &block)
      return enum_for(:each_node, node) unless block

      return unless node.is_a?(Prism::Node)

      block.call(node)
      node.compact_child_nodes.each { |child| each_node(child, &block) }
    end

    def symbol_name(node)
      node.is_a?(Prism::SymbolNode) ? node.value&.to_sym : nil
    end

    def describe(node)
      node.class.name.to_s.split("::").last.sub(/Node\z/, "")
    end

    def unresolved_note(kind)
      "allow_browser's versions: argument is a #{kind} expression that browsable cannot " \
      "evaluate statically. Set `target:` in config/browsable.yml or pass --target."
    end
  end
end
