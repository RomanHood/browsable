# frozen_string_literal: true

RSpec.describe Browsable::PolicyScanner do
  def write(root, relative, content)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  it "discovers allow_browser calls across controllers and concerns" do
    Dir.mktmpdir do |root|
      write(root, "app/controllers/application_controller.rb", <<~RUBY)
        class ApplicationController < ActionController::Base
          allow_browser versions: :modern
        end
      RUBY
      write(root, "app/controllers/legacy_controller.rb", <<~RUBY)
        class LegacyController < ApplicationController
          allow_browser versions: { safari: 12 }, only: [:show]
        end
      RUBY
      write(root, "app/controllers/concerns/embeddable.rb", <<~RUBY)
        module Embeddable
          extend ActiveSupport::Concern
          included do
            allow_browser versions: :modern, except: :raw
          end
        end
      RUBY
      # A controller with no policy contributes nothing.
      write(root, "app/controllers/home_controller.rb", "class HomeController < ApplicationController\nend\n")

      policies = described_class.call(root)

      expect(policies.map(&:scope)).to contain_exactly(
        "ApplicationController", "LegacyController", "Embeddable"
      )

      legacy = policies.find { |policy| policy.scope == "LegacyController" }
      expect(legacy.result.policy).to eq("safari" => "12")
      expect(legacy.only).to eq(["show"])
      expect(legacy.scoped?).to be(true)

      concern = policies.find { |policy| policy.scope == "Embeddable" }
      expect(concern.concern).to be(true)
      expect(concern.except).to eq(["raw"])
    end
  end

  it "namespaces a controller scope from its path" do
    Dir.mktmpdir do |root|
      write(root, "app/controllers/api/posts_controller.rb", <<~RUBY)
        class Api::PostsController < ApplicationController
          allow_browser versions: :modern
        end
      RUBY

      expect(described_class.call(root).first.scope).to eq("Api::PostsController")
    end
  end

  it "returns nothing for an app with no controllers" do
    Dir.mktmpdir { |root| expect(described_class.call(root)).to be_empty }
  end
end
