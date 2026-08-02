# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require "al_marimo"

ROOT = Pathname.new(File.expand_path("..", __dir__))

FakeSite = Struct.new(:config)

module RenderHelpers
  def render(template, site: nil, page: nil, assigns: {})
    Liquid::Template.parse(template).render(assigns, registers: { site: site, page: page })
  end

  def site_with(config = {})
    FakeSite.new({ "baseurl" => "/al-folio" }.merge(config))
  end
end

# Stands in for Jekyll::Drops::DocumentDrop: supports [] but is NOT a Hash.
# The real `registers[:page]` is a Drop, and code that tests `is_a?(Hash)`
# silently ignores front matter on every real page while passing Hash tests.
class DropLike
  def initialize(data) = @data = data
  def [](key) = @data[key.to_s]
end
