# frozen_string_literal: true

require "browsable-lsp"
require "tmpdir"
require "fileutils"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.order = :random
  Kernel.srand(config.seed)
end
