# frozen_string_literal: true

class ApplicationController < ActionController::Base
  # Same allow_browser policy as the Propshaft fixture, so the two example apps
  # produce comparable findings — the difference between them is the asset
  # pipeline, not the browser target.
  allow_browser versions: :modern
end
