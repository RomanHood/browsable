# frozen_string_literal: true

module Browsable
  module Sources
    # First-party JavaScript under app/javascript (importmap-managed apps keep
    # their own source here; pinned vendor code is handled by Sources::Importmap).
    class Javascripts < Base
    end
  end
end
