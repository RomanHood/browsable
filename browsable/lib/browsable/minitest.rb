# frozen_string_literal: true

# Opt-in entry point for runtime-mode auditing inside a Minitest suite.
#
# Place this at the top of `test/test_helper.rb`:
#
#   require "browsable/minitest"
#
# After loading Rails. The driver inserts Browsable::Middleware into the
# Rails app's middleware stack and uses Minitest.after_run to render the
# report at the end of the suite.
#
# Customize via Browsable::Drivers::Minitest.configure:
#
#   Browsable::Drivers::Minitest.configure do |c|
#     c.fail_on = :error
#     c.format  = :github
#   end
require_relative "../browsable"

Browsable::Drivers::Minitest.install!

module Browsable
  Minitest = Drivers::Minitest
end
