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
