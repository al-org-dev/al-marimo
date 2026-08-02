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

  def test_embed_sandbox_withholds_same_origin
    # The notebook is third-party code. allow-same-origin would let it reach the
    # embedding page's storage and cookies, which is exactly what a sandbox on an
    # untrusted frame exists to prevent.
    html = render(%({% al_marimo_embed src="https://marimo.app/l/abc" %}), site: site_with, page: on_page)

    assert_includes html, "sandbox="
    refute_includes html, "allow-same-origin"
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
end
