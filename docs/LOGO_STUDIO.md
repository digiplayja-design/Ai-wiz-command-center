# Logo Studio workspace upgrade

The studio uses the existing local logo engine, account-scoped project store,
AI consent/credit flow, and PNG/SVG/PDF/ZIP export pipeline.

## Interface

- Wide screens have a navigation rail, a split brand brief, a canvas with a
  separate inspector, and side-by-side export configuration/downloads.
- Phones retain the live canvas and inspector tabs while the controls scroll.
  Short viewports, keyboards, and enlarged text use a fully scrollable layout.
- Brand, Shape, Type, and Color controls include visual symbol and palette
  pickers. There are 16 symbols and 10 coordinated palettes.
- Six initial directions are created locally without an AI credit. More
  directions explore the expanded symbol collection without replacing edits.
- In-use previews, three-item shortlists, undo/redo, saved-project updates,
  save-as-copy, import, and independent AI artwork downloads remain available.
- The export preview continues to match PNG/SVG size, background, and ink.
  The complete kit reports progress across its 26 files.

## Performance

- Brief typing only rebuilds the live identity preview.
- Immutable design values avoid repeated JSON comparisons and unnecessary
  canvas repainting. Each canvas retains its composition and cached text fit;
  vector paths are parsed once per shape. Paint boundaries isolate previews.
- One slider gesture produces one undo step, including a no-op return gesture.
- SVG font embedding is reused. ZIP files are encoded individually with an
  event-loop yield between files, rather than one final synchronous archive
  compression step. Session guards run between files.
- AI history thumbnails decode at a bounded display size.

The diagnostic `test/logo_render_benchmark_test.dart` recorded 174 ms before
and 26 ms after for 300 warmed preview paints in the same local Flutter test
environment (baseline `fd9338a`). This measures repeated rendering, not AI
service latency, browser frame rate, or Samsung hardware performance. Timings
are diagnostic and are not used as CI pass/fail thresholds.

## Verification

The four Logo Studio test suites are included in the Render release gate.
They cover account changes, consent, failed persistence, save/copy/reopen,
undo, export pixels/dimensions, SVG layout, font embedding, ZIP contents,
responsive layout, and enlarged text.

The browser fixture runs the production screen with an in-memory store and
a local HTTP mock for AI artwork. It does not sign in or spend credits.

```sh
flutter build web --release --no-pub --no-web-resources-cdn \
  --no-wasm-dry-run --base-href=/ \
  --target=test/fixtures/logo_studio_browser.dart \
  --output=build/logo_studio_browser
node --test test/web/logo_studio_browser_test.cjs
```

The browser tests require Playwright. `KORLIX_CHROME_PATH` may point to an
installed Chromium executable. `LOGO_BROWSER_ARTIFACTS` sets the screenshot
directory. Tests exercise phone and desktop viewports, visual editing, saving
and reopening, reduced viewport height, and real project/SVG/PNG/ZIP downloads.
Browser semantics controls are activated with the keyboard; widget tests cover
touch interactions, including the inspector controls and live canvas.

Publishing the web build updates the browser app. Native store packages require
their normal separate build and release.
