# Changelog

## 1.0.1 — 2026-10-10

- Fixed `{% al_marimo_embed %}` notebooks rendering blank (#1). 1.0.0 withheld `allow-same-origin` from every embed on the mistaken belief that it would expose the embedding page; it only lets a frame keep its own origin, and without it marimo's in-browser runtime can't use storage. The token is now granted when the notebook is on a different origin from the site (with `allow-popups-to-escape-sandbox`), and still withheld for relative or same-origin URLs, where `allow-scripts` + `allow-same-origin` could remove the sandbox.
- Added a `sandbox` attribute to `{% al_marimo_embed %}` to set the token list explicitly.

## 1.0.0 — 2026-08-02

- Initial release of `al_marimo`, implementing the plugin proposed in
  [alshedivat/al-folio#3541](https://github.com/alshedivat/al-folio/issues/3541) (source PR
  [#3517](https://github.com/alshedivat/al-folio/pull/3517)).
- `{% al_marimo_embed %}` for hosted notebooks and `.al-marimo-inline` conversion for in-page Python snippets.
- The `marimo-snippets` runtime is **vendored and version-pinned** with recorded provenance, rather than loaded from a
  CDN at an unpinned major version as the source PR did.
- Embedded notebooks are sandboxed **without** `allow-same-origin`.
