# frozen_string_literal: true

require "browsable/cli"

RSpec.describe "Sprockets-layout discovery" do
  # Reach the CLI's private route/discover methods so we can exercise discovery
  # in isolation without spawning a subprocess and without needing the
  # external CSS/JS tooling to be present on this machine.
  let(:cli) { Browsable::CLI.new }

  def write(root, relative, contents)
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
    path
  end

  it "discovers JS under app/assets/javascripts (the Sprockets layout)" do
    Dir.mktmpdir do |root|
      js = write(root, "app/assets/javascripts/application.js", "console.log('hi');\n")

      config = Browsable::Config.load(root: root)
      files_by_kind = cli.send(:discover_files, root: root, config: config)

      expect(files_by_kind[:js]).to include(js)
    end
  end

  it "still discovers JS under app/javascript (the Propshaft/importmap layout)" do
    Dir.mktmpdir do |root|
      js = write(root, "app/javascript/application.js", "console.log('hi');\n")

      config = Browsable::Config.load(root: root)
      files_by_kind = cli.send(:discover_files, root: root, config: config)

      expect(files_by_kind[:js]).to include(js)
    end
  end

  it "routes .scss files to the CSS analyzer bucket" do
    Dir.mktmpdir do |root|
      scss = write(root, "app/assets/stylesheets/application.scss",
                   "/*\n *= require_tree .\n */\n.card { color: red; }\n")

      config = Browsable::Config.load(root: root)
      files_by_kind = cli.send(:discover_files, root: root, config: config)

      expect(files_by_kind[:css]).to include(scss)
    end
  end

  it "discovers SCSS sources in the Sprockets example fixture" do
    fixture = File.expand_path("../../examples/sprockets_app", __dir__)
    skip "fixture missing" unless File.directory?(fixture)

    config = Browsable::Config.load(root: fixture)
    files_by_kind = cli.send(:discover_files, root: fixture, config: config)

    expect(files_by_kind[:js].any? { |f| f.include?("app/assets/javascripts/") }).to be(true)
    expect(files_by_kind[:css].any? { |f| f.end_with?(".scss") }).to be(true)
  end

  it "leaves Sprockets directives inside JS comments alone" do
    # `//= require ...` is a JS line comment and a Sprockets directive. eslint
    # (and any JS parser) treats it as a comment. We pass the file through
    # untouched — no preprocessing — so this stays true.
    Dir.mktmpdir do |root|
      js = write(root, "app/assets/javascripts/application.js", <<~JS)
        //= require rails-ujs
        //= require_tree .
        console.log("ok");
      JS

      contents_before = File.read(js)
      config = Browsable::Config.load(root: root)
      cli.send(:discover_files, root: root, config: config)
      contents_after = File.read(js)

      expect(contents_after).to eq(contents_before)
      expect(contents_after).to include("//= require")
    end
  end
end
