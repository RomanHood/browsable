# frozen_string_literal: true

# browsable rake tasks, loaded into a host Rails app by Browsable::Railtie.
#
# browsable never precompiles assets on its own — `audit:fresh` is the opt-in
# task for that. In CI, compose the pipeline explicitly:
#   bundle exec rails assets:precompile && bundle exec browsable audit

require "browsable"

namespace :browsable do
  desc "Audit the app's frontend for browser-compatibility issues"
  task :audit do
    Browsable::CLI.start(["audit", Rails.root.to_s])
  end

  namespace :audit do
    desc "Precompile assets first, then audit the fresh build output"
    task fresh: ["assets:precompile"] do
      Browsable::CLI.start(["audit", Rails.root.to_s])
    end
  end

  desc "Check that browsable's system dependencies are installed"
  task :doctor do
    Browsable::CLI.start(["doctor"])
  end
end
