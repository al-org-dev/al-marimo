# Changelog

## 1.0.0 — 2026-08-02

- Initial release of `al_marimo`, implementing the plugin proposed in
  [alshedivat/al-folio#3541](https://github.com/alshedivat/al-folio/issues/3541) (source PR
  [#3517](https://github.com/alshedivat/al-folio/pull/3517)).
- `{% al_marimo_embed %}` for hosted notebooks and `.al-marimo-inline` conversion for in-page Python snippets.
- The `marimo-snippets` runtime is **vendored and version-pinned** with recorded provenance, rather than loaded from a
  CDN at an unpinned major version as the source PR did.
- Embedded notebooks are sandboxed **without** `allow-same-origin`.
