# frozen_string_literal: true

module Browsable
  # A single feature-usage event discovered in the project's frontend code.
  #
  # A Finding records *what* feature was used, *where*, which browser versions
  # it requires, and how that compares against the project's declared target.
  # It is an immutable value object — analyzers produce them, formatters and
  # the LSP server consume them.
  Finding = Data.define(
    :feature_id,                # e.g. "html.global_attributes.popover"
    :feature_name,              # e.g. "popover"
    :file,                      # absolute path
    :line,                      # 1-based
    :column,                    # 1-based
    :required_browser_versions, # { "firefox" => "125", "safari" => "17" }
    :target_browser_versions,   # { "firefox" => "121", "safari" => "17.2" }
    :severity,                  # :error | :warning | :info
    :message                    # human-readable explanation
  ) do
    def error?   = severity == :error
    def warning? = severity == :warning
    def info?    = severity == :info

    # A stable, JSON-friendly hash. This is the wire format the JSON formatter
    # and the LSP server both rely on.
    def as_json
      {
        feature_id: feature_id,
        feature_name: feature_name,
        file: file,
        line: line,
        column: column,
        required_browser_versions: required_browser_versions,
        target_browser_versions: target_browser_versions,
        severity: severity.to_s,
        message: message
      }
    end
  end
end
