# frozen_string_literal: true

require_relative "lib/al_marimo/version"

Gem::Specification.new do |spec|
  spec.name = "al_marimo"
  spec.version = AlMarimo::VERSION
  spec.authors = ["al-folio maintainers"]
  spec.email = ["maintainers@al-folio.dev"]

  spec.summary = "Marimo interactive notebook plugin for al-folio v1.x"
  spec.description = "Embeds marimo notebooks and turns Python code blocks into runnable in-browser snippets."
  spec.homepage = "https://github.com/al-org-dev/al-marimo"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7"

  spec.metadata = {
    "allowed_push_host" => "https://rubygems.org",
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
  }

  spec.files = Dir["lib/**/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "jekyll", ">= 3.9", "< 5.0"
  spec.add_dependency "liquid", ">= 4.0", "< 6.0"

  spec.add_development_dependency "bundler", ">= 2.0", "< 3.0"
  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "minitest", "~> 5.0"
end
