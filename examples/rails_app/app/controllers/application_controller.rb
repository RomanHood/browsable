# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Rails 8 ships `allow_browser`. `browsable` reads this policy to learn which
  # browsers your code is *expected* to support, then checks your code against it.
  allow_browser versions: :modern
end
