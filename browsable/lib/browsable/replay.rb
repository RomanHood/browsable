# frozen_string_literal: true

require "json"

module Browsable
  # Rehydrates a JSON audit dump (the kind produced by
  # `Browsable::TestReport#to_json`) into a Report-shaped object that any v0.1
  # formatter can render. Used by the `browsable replay` CLI to translate
  # a test-suite report into a different format in CI without re-running tests.
  class Replay
    Suggestion = Data.define(:line, :bumps)

    attr_reader :data

    def self.from_file(path)
      raw = File.read(path)
      data = JSON.parse(raw)
      new(data)
    end

    def initialize(data)
      @data = data
    end

    def render(format: :human, io: $stdout)
      io.puts(formatter_for(format).new(self).render)
    end

    # ---- Report-compatible interface -----------------------------------------
    # Browsable::Formatters::* call these on the report they're handed. We
    # implement the same surface here so the same formatters work for replay.

    def findings
      @findings ||= Array(data["findings"]).map do |f|
        Finding.new(
          feature_id: f["feature_id"],
          feature_name: f["feature_name"],
          file: f["file"],
          line: (f["line"] || 1).to_i,
          column: (f["column"] || 1).to_i,
          required_browser_versions: f["required_browser_versions"] || {},
          target_browser_versions: f["target_browser_versions"] || {},
          severity: (f["severity"] || "warning").to_sym,
          message: f["message"].to_s
        )
      end
    end

    def errors   = findings.select(&:error?)
    def warnings = findings.select(&:warning?)
    def infos    = findings.select(&:info?)
    def empty?   = findings.empty?

    def findings_by_file
      findings
        .group_by(&:file)
        .sort_by(&:first)
        .to_h
        .transform_values { |g| g.sort_by { |f| [f.line, f.column] } }
    end

    def skips
      Array(data["skips"]).map do |skip|
        Report::Skip.new(kind: skip["kind"].to_sym, reason: skip["reason"])
      end
    end

    def notes      = Array(data["notes"])
    def policies   = []
    def root       = data.dig("target", "root") || Dir.pwd
    def config_file = nil

    def target
      tdata = data["target"]
      return nil unless tdata

      Target.new(tdata["query"] || "replay", resolved: tdata["browsers"])
    end

    def suggestion
      s = data["suggested_policy"]
      return nil unless s

      Suggestion.new(line: s["line"].to_s, bumps: symbolize_bumps(s["bumps"]))
    end

    def as_json = data

    def exit_code(fail_on:)
      case fail_on.to_s
      when "warning" then errors.any? || warnings.any? ? 1 : 0
      when "error"   then errors.any? ? 1 : 0
      else                0
      end
    end

    private

    def symbolize_bumps(bumps)
      return {} unless bumps.is_a?(Hash)

      bumps.each_with_object({}) do |(browser, change), out|
        out[browser] = { from: change["from"], to: change["to"] }
      end
    end

    def formatter_for(format)
      case format.to_sym
      when :json   then Formatters::Json
      when :github then Formatters::Github
      else              Formatters::Human
      end
    end
  end
end
