# al_marimo

[marimo](https://marimo.io) interactive Python notebooks for [al-folio](https://github.com/alshedivat/al-folio) v1.x.
Implements the plugin proposed in [al-folio#3541](https://github.com/alshedivat/al-folio/issues/3541).

## Install

```ruby
gem "al_marimo", "= 1.0.0"
```

and in `_config.yml` — **both lists, or the plugin is inert**:

```yaml
plugins:
  - al_marimo
```

Then opt in **per page**, in front matter:

```yaml
---
layout: post
title: a notebook post
marimo: true
---
```

Nothing is loaded on pages without that flag, so bundling the plugin costs nothing site-wide.

## Usage

### Embedding a hosted notebook

```liquid
{% al_marimo_embed src="https://marimo.app/l/abc123" height="700px" caption="Sampling demo" %}
```

Accepts `src` (required), `height`, `width`, `mode` (`read` / `edit`), `embed`, `title`, `caption`, `class`. `src` may
be a literal or a Liquid variable.

### Inline runnable snippets

Wrap fenced Python blocks in a container:

<pre>
&lt;div class="al-marimo-inline" markdown="1"&gt;

```python
import marimo as mo
mo.md("Hello from the browser")
```

&lt;/div&gt;
</pre>

The runtime moves those blocks into a `<marimo-iframe>` after load.

## Differences from the source PR

The source PR was explicitly a work in progress. Two things changed:

**The runtime is vendored, not fetched from a CDN.** The PR loaded
`https://cdn.jsdelivr.net/npm/@marimo-team/marimo-snippets@1` — an unpinned major version, with no integrity hash,
executing in every visitor's page. That is the shape of the polyfill.io supply-chain attack. Pinning it with SRI is not
possible either: that URL serves a _dynamically minified_ build, and jsDelivr
[documents that such files must not be used with SRI](https://www.jsdelivr.com/using-sri-with-dynamic-files) because a
minifier upgrade changes the bytes and would break every site at once. So the stable unminified source is vendored at an
exact version, with its digest recorded in [`lib/vendor/provenance.json`](lib/vendor/provenance.json) and a test that
fails if the shipped file drifts from it.

**Embedded notebooks do not get `allow-same-origin`.** The PR's sandbox included it, which lets the embedded
third-party notebook reach the embedding page's storage and cookies — defeating the purpose of the sandbox.

## Note on third-party contact

The notebook itself executes on `marimo.app` (or your own WASM host). Embedding one means your readers' browsers contact
that origin. The vendored runtime also references a marimo-hosted icon. Nothing is sent unless a page opts in.

## Development

```bash
bundle install
bundle exec rake test
npm ci && npm run lint:prettier
```

## License

MIT
