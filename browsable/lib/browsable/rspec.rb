# frozen_string_literal: true

# Opt-in entry point for runtime-mode auditing inside an RSpec suite.
#
# Place this at the top of `spec/rails_helper.rb`:
#
#   require "browsable/rspec"
#
# After loading Rails. The driver inserts Browsable::Middleware into the
# Rails app's middleware stack (idempotent — safe to require twice) and
# registers before(:suite) / after(:suite) hooks so the audit log is reset
# and the report rendered automatically.
#
# Customize via Browsable::Drivers::RSpec.configure:
#
#   Browsable::Drivers::RSpec.configure do |c|
#     c.fail_on = :error
#     c.output  = "tmp/browsable_report.json"
#     c.format  = :json
#   end
require_relative "../browsable"

Browsable::Drivers::RSpec.install!

# Convenience shim so `Browsable::RSpec.configure { ... }` works at top level.
module Browsable
  RSpec = Drivers::RSpec
end
