# frozen_string_literal: true

require "cgi"
require "json"
require "jekyll"
require "liquid"
require_relative "al_marimo/version"

# Embeds marimo notebooks, and turns Python code blocks into runnable snippets.
#
# Two-layer gating, per the al-folio contract: the gem must be loaded *and* the
# page must opt in with `marimo: true` in its front matter. Without the page
# opt-in every tag renders an empty string, so a site that bundles this plugin
# pays nothing on pages that do not use it.
module AlMarimo
  PLUGIN_ROOT = File.expand_path("..", __dir__)
  # Jekyll writes a StaticFile to <dest>/<dir>/<name>, where <dir> is relative
  # to the base below. That base must be lib/, not the gem root, or assets land
  # at /lib/assets/... while every tag in this file points at /assets/... .
  LIB_ROOT = __dir__
  ASSETS_ROOT = File.join(LIB_ROOT, "assets")
  VENDOR_ROOT = File.join(PLUGIN_ROOT, "lib", "vendor")

  # marimo runs the notebook itself; only these origins are ever contacted.
  DEFAULT_PLAYGROUND = "https://marimo.app"

  class PluginStaticFile < Jekyll::StaticFile; end

  module_function

  def config(site)
    return {} unless site

    site.config["al_marimo"] || {}
  end

  # Page-level opt-in. Anything truthy other than the string "false" counts, so
  # `marimo: true` and `marimo: snippets` both work.
  #
  # Reads through `[]` rather than testing for Hash: at render time Jekyll hands
  # `registers[:page]` a Drop (Jekyll::Drops::DocumentDrop), not a Hash, so an
  # `is_a?(Hash)` guard silently discards the front matter and the feature never
  # switches on for any real page.
  def page_enabled?(page)
    value = begin
      page.respond_to?(:[]) ? page["marimo"] : nil
    rescue StandardError
      nil
    end
    return false if value.nil? || value == false
    return false if value.respond_to?(:strip) && ["", "false"].include?(value.strip.downcase)

    true
  end

  def provenance
    @provenance ||= JSON.parse(File.read(File.join(VENDOR_ROOT, "provenance.json")))
  end

  def escape(value)
    CGI.escapeHTML(value.to_s)
  end

  # Builds the notebook URL, folding in the query parameters marimo understands.
  #
  # Appends with the correct separator rather than assuming the caller passed a
  # bare URL: `?embed=true` on a URL that already has a query string produces a
  # link that silently loads the wrong notebook.
  def build_url(src, embed: true, mode: "read")
    url = src.to_s.strip
    return nil if url.empty?

    separator = url.include?("?") ? "&" : "?"
    if embed
      url = "#{url}#{separator}embed=true"
      separator = "&"
    end
    "#{url}#{separator}mode=#{mode == "edit" ? "edit" : "read"}"
  end

  # [relative_dir, filename] for everything this gem publishes. Exposed so the
  # destination path can be asserted without booting a full Jekyll site.
  def asset_entries
    Dir.glob(File.join(ASSETS_ROOT, "**", "*")).sort.reject { |p| File.directory?(p) }.map do |source_path|
      [File.dirname(source_path).sub("#{LIB_ROOT}/", ""), File.basename(source_path)]
    end
  end

  class AssetsGenerator < Jekyll::Generator
    safe true
    priority :low

    def generate(site)
      Dir.glob(File.join(ASSETS_ROOT, "**", "*")).sort.each do |source_path|
        next if File.directory?(source_path)

        relative_dir = File.dirname(source_path).sub("#{LIB_ROOT}/", "")
        site.static_files << PluginStaticFile.new(site, LIB_ROOT, relative_dir, File.basename(source_path))
      end
    end
  end

  # {% al_marimo_scripts %} — emits the runtime, only on pages that opted in.
  class ScriptsTag < Liquid::Tag
    def render(context)
      site = context.registers[:site]
      page = context.registers[:page]
      return "" unless site && AlMarimo.page_enabled?(page)

      baseurl = site.config["baseurl"] || ""
      # Vendored rather than pulled from a CDN. jsDelivr serves a dynamically
      # minified build at the package root and documents that it must not be
      # used with SRI; loading it unpinned would hand every al-folio site's
      # execution context to whatever that URL returns tomorrow.
      <<~HTML
        <script defer src="#{baseurl}/assets/al_marimo/js/marimo-init.js"></script>
        <script defer src="#{baseurl}/assets/al_marimo/js/marimo-snippets.js"></script>
      HTML
    end
  end

  class StylesTag < Liquid::Tag
    def render(context)
      site = context.registers[:site]
      page = context.registers[:page]
      return "" unless site && AlMarimo.page_enabled?(page)

      baseurl = site.config["baseurl"] || ""
      %(<link rel="stylesheet" href="#{baseurl}/assets/al_marimo/css/marimo.css">\n)
    end
  end

  # {% al_marimo_embed src="https://marimo.app/l/abc" height="600px" caption="..." %}
  class EmbedTag < Liquid::Tag
    ATTRIBUTES = /(\w+)\s*=\s*("[^"]*"|'[^']*'|[^\s]+)/.freeze

    def initialize(tag_name, markup, options)
      super
      @attributes = {}
      markup.scan(ATTRIBUTES) do |key, value|
        @attributes[key] = value.gsub(/\A["']|["']\z/, "")
      end
    end

    def render(context)
      site = context.registers[:site]
      return "" unless site

      src = resolve(@attributes["src"], context)
      url = AlMarimo.build_url(
        src,
        embed: @attributes.fetch("embed", "true") != "false",
        mode: @attributes["mode"] || "read"
      )
      # A missing or empty src is an authoring mistake. Emit nothing rather than
      # an iframe pointed at the site itself, which would silently render the
      # page inside its own post.
      return "" if url.nil?

      height = @attributes["height"] || "600px"
      width = @attributes["width"] || "100%"
      title = @attributes["title"] || "marimo notebook"
      caption = @attributes["caption"]
      extra_class = @attributes["class"]

      figure = +%(<figure class="al-marimo">)
      figure << %(<div class="al-marimo-embed">)
      figure << %(<iframe src="#{AlMarimo.escape(url)}")
      figure << %( class="#{AlMarimo.escape(extra_class)}") if extra_class
      # Deliberately omits allow-same-origin: the notebook is third-party code,
      # and granting it same-origin access to the embedding site would let it
      # read the parent document's storage and cookies.
      figure << %( sandbox="allow-scripts allow-downloads allow-popups allow-forms")
      figure << %( width="#{AlMarimo.escape(width)}" height="#{AlMarimo.escape(height)}")
      figure << %( title="#{AlMarimo.escape(title)}" loading="lazy" frameborder="0" allowfullscreen></iframe>)
      figure << %(</div>)
      figure << %(<figcaption class="caption">#{AlMarimo.escape(caption)}</figcaption>) if caption
      figure << %(</figure>)
      figure
    end

    private

    # Allows both a literal (src="https://…") and a variable (src=page.notebook).
    def resolve(value, context)
      return nil if value.nil?

      looked_up = context[value]
      looked_up.nil? ? value : looked_up
    end
  end
end

Liquid::Template.register_tag("al_marimo_scripts", AlMarimo::ScriptsTag)
Liquid::Template.register_tag("al_marimo_styles", AlMarimo::StylesTag)
Liquid::Template.register_tag("al_marimo_embed", AlMarimo::EmbedTag)
