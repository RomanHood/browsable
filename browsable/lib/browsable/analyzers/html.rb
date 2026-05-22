# frozen_string_literal: true

module Browsable
  module Analyzers
    # Audits static .html files. Herb parses HTML and ERB with the same API, so
    # the only difference from the ERB analyzer is intent — this exists as a
    # distinct class so the orchestrator can route plain-HTML sources explicitly.
    class HTML < ERB
    end
  end
end
