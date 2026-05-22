# frozen_string_literal: true

module Browsable
  module Sources
    # Compiled CSS under app/assets/builds — typically Tailwind output produced
    # by the tailwindcss-rails gem. This is what Propshaft actually serves.
    class Builds < Base
    end
  end
end
