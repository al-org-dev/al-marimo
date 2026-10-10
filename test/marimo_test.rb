# frozen_string_literal: true

require "digest"
require "json"
require_relative "test_helper"

class MarimoTest < Minitest::Test
  include RenderHelpers

  def on_page
    { "marimo" => true }
  end

  # --- page-level opt-in --------------------------------------------------

  def test_page_opt_in_required
    refute AlMarimo.page_enabled?({})
    refute AlMarimo.page_enabled?(nil)
    refute AlMarimo.page_enabled?({ "marimo" => false })
    assert AlMarimo.page_enabled?({ "marimo" => true })
  end

  def test_string_false_does_not_enable
    # `marimo: "false"` in front matter is a mistake, not an opt-in. Liquid would
    # treat the non-empty string as truthy, so this is checked explicitly.
    refute AlMarimo.page_enabled?({ "marimo" => "false" })
    refute AlMarimo.page_enabled?({ "marimo" => "" })
  end

  def test_scripts_silent_without_page_opt_in
    assert_equal "", render("{% al_marimo_scripts %}", site: site_with, page: {})
    assert_equal "", render("{% al_marimo_styles %}", site: site_with, page: {})
  end

  def test_scripts_emitted_with_page_opt_in
    html = render("{% al_marimo_scripts %}", site: site_with, page: on_page)

    assert_includes html, "/al-folio/assets/al_marimo/js/marimo-init.js"
    assert_includes html, "/al-folio/assets/al_marimo/js/marimo-snippets.js"
  end

  def test_runtime_is_served_locally_not_from_a_cdn
    # The whole point of vendoring: no third-party origin executes script in the
    # visitor's page context.
    html = render("{% al_marimo_scripts %}", site: site_with, page: on_page)

    refute_includes html, "cdn.jsdelivr.net"
    refute_includes html, "unpkg.com"
    # No absolute origin at all: every src must be baseurl-relative.
    refute_match(%r{src="https?://}, html)
  end

  # --- URL building -------------------------------------------------------

  def test_appends_query_params_with_the_right_separator
    assert_equal "https://marimo.app/l/a?embed=true&mode=read", AlMarimo.build_url("https://marimo.app/l/a")
    # A src that already carries a query string must not get a second "?".
    assert_equal "https://marimo.app/l/a?x=1&embed=true&mode=read", AlMarimo.build_url("https://marimo.app/l/a?x=1")
  end

  def test_edit_mode_and_embed_opt_out
    assert_equal "https://m.app/n?embed=true&mode=edit", AlMarimo.build_url("https://m.app/n", mode: "edit")
    assert_equal "https://m.app/n?mode=read", AlMarimo.build_url("https://m.app/n", embed: false)
  end

  def test_unknown_mode_falls_back_to_read
    assert_equal "https://m.app/n?embed=true&mode=read", AlMarimo.build_url("https://m.app/n", mode: "destroy")
  end

  def test_blank_src_yields_no_url
    assert_nil AlMarimo.build_url("")
    assert_nil AlMarimo.build_url(nil)
    assert_nil AlMarimo.build_url("   ")
  end

  # --- embed tag ----------------------------------------------------------

  def test_embed_renders_an_iframe
    html = render(%({% al_marimo_embed src="https://marimo.app/l/abc" %}), site: site_with, page: on_page)

    assert_includes html, "<iframe"
    assert_includes html, "https://marimo.app/l/abc?embed=true&amp;mode=read"
    assert_includes html, 'loading="lazy"'
  end

  def sandbox_of(html)
    html[/sandbox="([^"]*)"/, 1].to_s.split
  end

  def test_cross_origin_embed_keeps_its_own_origin
    # al-org-dev/al-marimo#1: without allow-same-origin the frame gets an opaque
    # origin, marimo's in-browser runtime can't use its own storage, and the
    # notebook body stays blank. For a frame on another origin the token does
    # not expose the embedding page: the browser's cross-origin wall still holds.
    site = site_with("url" => "https://someone.github.io")
    tokens = sandbox_of(render(%({% al_marimo_embed src="https://marimo.app/l/abc" %}), site: site, page: on_page))

    assert_includes tokens, "allow-same-origin"
    # Otherwise "Open in molab" opens a tab that inherits this sandbox.
    assert_includes tokens, "allow-popups-to-escape-sandbox"
    %w[allow-scripts allow-downloads allow-popups allow-forms].each { |t| assert_includes tokens, t }
  end

  def test_same_origin_embed_withholds_same_origin
    # allow-scripts + allow-same-origin on a frame that shares the page's origin
    # can reach frameElement and strip its own sandbox. That is the case the
    # token must stay withheld for: relative URLs and the site's own host.
    site = site_with("url" => "https://someone.github.io")
    [
      "/al-folio/notebooks/demo.html",
      "notebooks/demo.html",
      "https://someone.github.io/al-folio/notebooks/demo.html",
      "https://SOMEONE.github.io:443/notebooks/demo.html",
    ].each do |src|
      tokens = sandbox_of(render(%({% al_marimo_embed src="#{src}" %}), site: site, page: on_page))

      refute_includes tokens, "allow-same-origin", src
      assert_includes tokens, "allow-scripts", src
    end
  end

  def test_origin_comparison_includes_scheme_and_port
    site = site_with("url" => "https://someone.github.io")

    assert AlMarimo.cross_origin?("http://someone.github.io/nb", site.config["url"])
    assert AlMarimo.cross_origin?("https://someone.github.io:8443/nb", site.config["url"])
    assert AlMarimo.cross_origin?("//marimo.app/l/abc", site.config["url"])
  end

  def test_absolute_url_without_a_site_url_counts_as_cross_origin
    # Nothing to compare against, but an absolute URL is by construction not a
    # relative path into this site.
    tokens = sandbox_of(render(%({% al_marimo_embed src="https://marimo.app/l/abc" %}), site: site_with, page: on_page))

    assert_includes tokens, "allow-same-origin"
  end

  def test_unusable_urls_are_treated_as_same_origin
    refute AlMarimo.cross_origin?("javascript:alert(1)", "https://someone.github.io")
    refute AlMarimo.cross_origin?("ftp://files.example.com/nb", "https://someone.github.io")
    refute AlMarimo.cross_origin?("http://exa mple.com/", "https://someone.github.io")
  end

  def test_explicit_sandbox_attribute_overrides_and_is_escaped
    html = render(%({% al_marimo_embed src="/nb.html" sandbox="allow-scripts allow-same-origin" %}), site: site_with, page: on_page)
    assert_equal %w[allow-scripts allow-same-origin], sandbox_of(html)

    html = render(%({% al_marimo_embed src="/nb.html" sandbox='allow-scripts" onload="x' %}), site: site_with, page: on_page)
    refute_includes html, %(" onload=")
  end

  def test_embed_without_src_renders_nothing
    # An iframe with an empty src resolves to the current page, which would embed
    # the post inside itself.
    assert_equal "", render("{% al_marimo_embed %}", site: site_with, page: on_page)
    assert_equal "", render(%({% al_marimo_embed src="" %}), site: site_with, page: on_page)
  end

  def test_embed_honours_dimensions_and_caption
    html = render(
      %({% al_marimo_embed src="https://m.app/n" height="800px" width="90%" caption="A demo" title="Demo" %}),
      site: site_with, page: on_page
    )

    assert_includes html, 'height="800px"'
    assert_includes html, 'width="90%"'
    assert_includes html, 'title="Demo"'
    assert_includes html, "A demo"
  end

  def test_embed_escapes_attacker_controlled_values
    html = render(%({% al_marimo_embed src="https://m.app/n" caption='<img src=x onerror=alert(1)>' %}), site: site_with, page: on_page)

    refute_includes html, "<img src=x"
    assert_includes html, "&lt;img"
  end

  def test_embed_accepts_a_liquid_variable_for_src
    html = render(
      "{% al_marimo_embed src=page.notebook %}",
      site: site_with, page: on_page, assigns: { "page" => { "notebook" => "https://m.app/from-var" } }
    )

    assert_includes html, "https://m.app/from-var"
  end

  # --- vendored runtime ---------------------------------------------------

  def test_vendored_runtime_matches_recorded_provenance
    # Guards against an in-place edit of the vendored file: if it drifts from the
    # published artifact, the recorded hash no longer describes what ships.
    path = ROOT.join("lib/assets/al_marimo/js/marimo-snippets.js")
    assert_path_exists path

    digest = "sha384-#{[Digest::SHA384.digest(File.binread(path))].pack("m0")}"
    assert_equal AlMarimo.provenance["sha384"], digest
    assert_equal AlMarimo.provenance["bytes"], File.size(path)
  end

  def test_provenance_records_a_pinned_version
    provenance = AlMarimo.provenance

    assert_match(/\A\d+\.\d+\.\d+\z/, provenance["version"], "vendored version must be exact, not a range")
    # The package-root jsDelivr URL serves a dynamically minified build that
    # jsDelivr documents as unsafe to pin; the source path is the stable one.
    assert_includes provenance["source_url"], provenance["version"]
    assert_includes provenance["source_url"], "/src/"
  end

  def test_init_script_is_shipped
    assert_path_exists ROOT.join("lib/assets/al_marimo/js/marimo-init.js")
    assert_path_exists ROOT.join("lib/assets/al_marimo/css/marimo.css")
  end

  # --- regression: Jekyll hands us a Drop, not a Hash ---------------------

  def test_page_opt_in_reads_a_drop_not_just_a_hash
    # Jekyll sets registers[:page] to a DocumentDrop. An earlier version tested
    # `page.is_a?(Hash)`, which meant the opt-in never fired on a real page.
    assert AlMarimo.page_enabled?(DropLike.new("marimo" => true))
    refute AlMarimo.page_enabled?(DropLike.new("marimo" => false))
  end

  def test_scripts_emitted_for_a_drop_page
    html = render("{% al_marimo_scripts %}", site: site_with, page: DropLike.new("marimo" => true))

    assert_includes html, "marimo-snippets.js"
  end

  # --- regression: assets must land where the tags point ------------------

  def test_assets_are_published_under_slash_assets
    # Jekyll writes a StaticFile to <dest>/<dir>/<name>. Basing it on the gem
    # root instead of lib/ puts everything under /lib/assets/..., while every
    # tag emits /assets/... — a 404 that only shows up in a real build.
    entries = AlMarimo.asset_entries

    refute_empty entries
    entries.each do |relative_dir, name|
      assert relative_dir.start_with?("assets/al_marimo"),
             "#{relative_dir}/#{name} would be published outside /assets/al_marimo"
      refute_includes relative_dir, "lib/"
    end
  end

  def test_every_referenced_asset_is_actually_published
    published = AlMarimo.asset_entries.map { |dir, name| "/#{dir}/#{name}" }

    assert_includes published, "/assets/al_marimo/js/marimo-snippets.js"
  end
end
