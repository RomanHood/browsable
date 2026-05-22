# frozen_string_literal: true

module Browsable
  module Analyzers
    # Audits ERB templates (and plain HTML) by parsing them in-process with the
    # Herb gem, then looking up every HTML element and global attribute against
    # the bundled MDN browser-compat-data snapshot.
    #
    # No external tools are needed — Herb is a gem dependency — so ERB/HTML
    # analysis works on a machine with nothing else installed.
    class ERB < Base
      Usage = Data.define(:kind, :name, :line, :column)

      def required_tools = [] # Herb is in-process

      def analyze(files)
        files.flat_map do |file|
          analyze_source(File.read(file), file: file)
        rescue StandardError
          []
        end
      end

      # Analyze one template's source text. Exposed directly for the LSP server,
      # which audits unsaved, in-memory buffer contents.
      def analyze_source(source, file:)
        extract_usages(source)
          .uniq { |usage| [usage.kind, usage.name, usage.line] }
          .filter_map { |usage| build_finding(usage, file: file) }
      end

      private

      # --- feature extraction --------------------------------------------------

      def extract_usages(source)
        # Trust Herb's result, including an empty one: a template with no HTML
        # (all-ERB partials, comment-only files) legitimately yields no usages.
        # The coarse scan runs *only* when Herb actually raises — e.g. the gem
        # is somehow missing — never because Herb returned nothing.
        herb_usages(source)
      rescue StandardError
        scan_usages(source)
      end

      def herb_usages(source)
        require "herb"

        result = ::Herb.parse(source)
        root = result.respond_to?(:value) ? result.value : result
        usages = []
        walk(root) { |node| collect_usage(node, usages) }
        usages
      end

      def walk(node, &block)
        return unless node

        block.call(node)
        children_of(node).each { |child| walk(child, &block) }
      end

      def children_of(node)
        %i[child_nodes compact_child_nodes children].each do |accessor|
          next unless node.respond_to?(accessor)

          kids = node.public_send(accessor)
          return Array(kids).compact if kids
        end
        []
      end

      def collect_usage(node, usages)
        class_name = node.class.name.to_s

        if class_name.include?("HTMLOpenTag") && node.respond_to?(:tag_name)
          name = token_text(node.tag_name)
          line, column = node_position(node)
          usages << Usage.new(kind: :element, name: name.to_s.downcase, line: line, column: column) if name
        elsif class_name.include?("HTMLAttribute") &&
              !class_name.include?("Name") && !class_name.include?("Value")
          name = token_text(node.respond_to?(:name) ? node.name : node)
          line, column = node_position(node)
          usages << Usage.new(kind: :attribute, name: name.to_s.downcase, line: line, column: column) if name
        end
      end

      # Extract the text of a Herb token or name node. Herb represents a tag or
      # attribute name as a Token (#value), a LiteralNode (#content), or a
      # composite name node that wraps a LiteralNode in its children.
      def token_text(obj)
        return nil if obj.nil?
        return obj if obj.is_a?(String)
        return obj.value if obj.respond_to?(:value) && obj.value.is_a?(String)
        return obj.content if obj.respond_to?(:content) && obj.content.is_a?(String)

        if obj.respond_to?(:child_nodes)
          Array(obj.child_nodes).compact.each do |child|
            text = token_text(child)
            return text if text
          end
        end
        nil
      end

      def node_position(node)
        loc = node.location if node.respond_to?(:location)
        start = nil
        start = loc.start if loc.respond_to?(:start)
        start ||= loc.start_position if loc.respond_to?(:start_position)
        line = start.respond_to?(:line) ? start.line : 1
        column = start.respond_to?(:column) ? start.column.to_i + 1 : 1
        [line, column]
      rescue StandardError
        [1, 1]
      end

      # Degraded extraction: a line-by-line scan for opening tags and bare
      # attribute names. Noise is mostly harmless — only names present in the
      # BCD snapshot survive the lookup in #build_finding — but ERB tags must be
      # blanked first so Ruby code and comment prose are never read as markup.
      # Blanking (rather than deleting) preserves line and column numbers.
      def scan_usages(source)
        usages = []
        erb_blanked(source).each_line.with_index(1) do |line, number|
          line.scan(/<([a-zA-Z][a-zA-Z0-9-]*)/) do
            usages << Usage.new(kind: :element, name: Regexp.last_match(1).downcase,
                                line: number, column: (Regexp.last_match.begin(1) || 0))
          end
          line.scan(/[\s"']([a-zA-Z][a-zA-Z0-9-]*)(?==|>|\s|\z)/) do
            usages << Usage.new(kind: :attribute, name: Regexp.last_match(1).downcase,
                                line: number, column: (Regexp.last_match.begin(1) || 0) + 1)
          end
        end
        usages
      end

      # Replace every ERB tag (<% %>, <%= %>, <%# %>) with spaces, keeping
      # newlines so line/column positions are unchanged. The contents of an ERB
      # tag — Ruby code or comment text — are never HTML.
      def erb_blanked(source)
        source.gsub(/<%.*?%>/m) { |tag| tag.gsub(/[^\n]/, " ") }
      end

      # --- compat lookup -------------------------------------------------------

      def build_finding(usage, file:)
        compat = compat_for(usage)
        return nil unless compat

        feature_id = feature_id_for(usage)
        return nil if ignored_feature?(feature_id)

        support = compat["support"] || {}
        required = required_versions(support)
        below = browsers_below_target(required, unsupported_browsers(support))
        baseline = compat.dig("status", "baseline")

        category = categorize(below, baseline)
        return nil unless category # widely available — nothing worth reporting

        Finding.new(
          feature_id: feature_id,
          feature_name: usage.name,
          file: file,
          line: usage.line,
          column: usage.column,
          required_browser_versions: required,
          target_browser_versions: target.browsers,
          severity: severity_for(category),
          message: message_for(usage, category, below, required)
        )
      end

      def compat_for(usage)
        table =
          if usage.kind == :element
            compat_data.dig("html", "elements")
          else
            compat_data.dig("html", "global_attributes")
          end
        entry = table&.dig(usage.name)
        entry && entry["__compat"]
      end

      def feature_id_for(usage)
        segment = usage.kind == :element ? "elements" : "global_attributes"
        "html.#{segment}.#{usage.name}"
      end

      def categorize(below, baseline)
        return "below_target" if below.any?
        return "baseline_limited" if baseline == false
        return "baseline_newly_available" if baseline == "low"

        nil
      end

      def required_versions(support)
        support.each_with_object({}) do |(browser, info), out|
          added = support_version(info)
          out[browser] = added if added.is_a?(String)
        end
      end

      def support_version(info)
        entry = info.is_a?(Array) ? info.first : info
        entry && entry["version_added"]
      end

      def unsupported_browsers(support)
        support.select { |_browser, info| support_version(info) == false }.keys
      end

      def browsers_below_target(required, unsupported)
        target.browsers.filter_map do |browser, floor|
          if unsupported.include?(browser)
            browser
          elsif (req = required[browser]) && version_gt?(req, floor)
            browser
          end
        end
      end

      def version_gt?(left, right)
        Gem::Version.new(left.to_s) > Gem::Version.new(right.to_s)
      rescue ArgumentError
        false
      end

      def message_for(usage, category, below, required)
        label = usage.kind == :element ? "<#{usage.name}>" : "the '#{usage.name}' attribute"

        case category
        when "below_target"
          clauses = below.map do |browser|
            name = titleize(browser)
            required_version = required[browser]
            if required_version
              "needs #{name} #{required_version}+, but your target allows #{name} #{target.minimum_version(browser)}"
            else
              "is not supported by #{name} at any version"
            end
          end
          "#{label} #{clauses.join('; ')}."
        when "baseline_limited"
          "#{label} has limited availability (not Baseline) — provide a fallback."
        else
          "#{label} is newly available (Baseline low) — confirm it covers the browsers you support."
        end
      end

      def titleize(browser)
        browser.split("_").first.capitalize
      end
    end
  end
end
