# frozen_string_literal: true

require "spec_helper"
require "rack/mock"

RSpec.describe Browsable::Middleware do
  before do
    Browsable::PolicyResolver.configure(
      policies: [],
      default: Browsable::Policy.new(versions: :modern, scope: nil, source: :default)
    )
    Browsable.audit_log = Browsable::AuditLog.new
    Browsable.asset_resolver = Browsable::AssetResolver.new(rails_app: nil, root: "/dev/null")
  end

  after do
    Browsable::PolicyResolver.reset!
    Browsable.audit_log = nil
    Browsable.asset_resolver = nil
  end

  # A stand-in for a Rails controller, just enough to satisfy the middleware.
  let(:controller_class) do
    Class.new { def self.name = "PostsController" }
  end
  let(:controller) do
    klass = controller_class
    Object.new.tap do |c|
      c.define_singleton_method(:class) { klass }
      c.define_singleton_method(:action_name) { "show" }
    end
  end

  # A minimal Rack app: returns an HTML page with two assets and an env hook.
  def html_app(html = '<html><head><link rel="stylesheet" href="/x.css"></head></html>')
    ->(env) {
      env["action_controller.instance"] = controller
      [200, { "Content-Type" => "text/html; charset=utf-8" }, [html]]
    }
  end

  it "refuses to initialize in production" do
    rails = double(env: double(production?: true))
    stub_const("Rails", rails)
    expect { described_class.new(html_app) }.to raise_error(Browsable::Error, /production/)
  end

  it "records a single audit-log entry for a 200 HTML response" do
    rails = double(env: double(production?: false))
    stub_const("Rails", rails)

    mw = described_class.new(html_app)
    Rack::MockRequest.new(mw).get("/posts/42")

    expect(Browsable.audit_log.size).to eq(1)
    entry = Browsable.audit_log.entries.first
    expect(entry.endpoint).to eq("PostsController#show")
    expect(entry.request_path).to eq("/posts/42")
    expect(entry.asset_paths.map(&:url)).to eq(["/x.css"])
  end

  it "leaves the response body intact for downstream middleware" do
    rails = double(env: double(production?: false))
    stub_const("Rails", rails)

    mw = described_class.new(html_app("<html>hello</html>"))
    response = Rack::MockRequest.new(mw).get("/posts/42")

    expect(response.body).to eq("<html>hello</html>")
    expect(response.status).to eq(200)
  end

  it "skips non-GET requests" do
    rails = double(env: double(production?: false))
    stub_const("Rails", rails)

    mw = described_class.new(html_app)
    Rack::MockRequest.new(mw).post("/posts")
    expect(Browsable.audit_log).to be_empty
  end

  it "skips non-200 responses" do
    rails = double(env: double(production?: false))
    stub_const("Rails", rails)

    app = ->(_env) { [404, { "Content-Type" => "text/html" }, ["<html>not found</html>"]] }
    mw = described_class.new(app)
    Rack::MockRequest.new(mw).get("/missing")
    expect(Browsable.audit_log).to be_empty
  end

  it "skips non-HTML responses" do
    rails = double(env: double(production?: false))
    stub_const("Rails", rails)

    app = ->(_env) { [200, { "Content-Type" => "application/json" }, ['{"ok":true}']] }
    mw = described_class.new(app)
    Rack::MockRequest.new(mw).get("/api")
    expect(Browsable.audit_log).to be_empty
  end

  it "skips internal Rails paths like /rails/* and /assets/*" do
    rails = double(env: double(production?: false))
    stub_const("Rails", rails)

    mw = described_class.new(html_app)
    Rack::MockRequest.new(mw).get("/rails/info/routes")
    Rack::MockRequest.new(mw).get("/assets/application.css")
    expect(Browsable.audit_log).to be_empty
  end

  it "skips responses without an action_controller.instance" do
    rails = double(env: double(production?: false))
    stub_const("Rails", rails)

    app = ->(_env) { [200, { "Content-Type" => "text/html" }, ["<html></html>"]] }
    mw = described_class.new(app)
    Rack::MockRequest.new(mw).get("/")
    expect(Browsable.audit_log).to be_empty
  end
end
