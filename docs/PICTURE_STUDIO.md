# Improve My Picture — October 2, 2026

The main Improve my picture button opens a dedicated photo workspace. Upload one JPG, PNG or WEBP (up to 15 MB), choose Natural polish, Restore a photo, Studio headshot, Product photo, Remove background, or My own edit, and optionally add instructions. Preservation is enabled by default. Subtle, Balanced and Creative finishes describe the intended degree of editing; they do not lower model quality. Standard and detailed output shapes are available, with automatic framing by default.

The workspace supports camera capture, before/after viewing, zoom, PNG saving, refining the current result, and returning to the original uploaded photo. Existing portrait templates remain available through Explore portrait templates. Generated versions are held in the open workspace, not a new cloud gallery; save a favorite before leaving. Refine uses the current result as the new source. Preservation instructions reduce unwanted changes but do not promise identical pixels or perfect identity retention.

## Color, lighting and output reliability

The optional `look` field accepts `original`, `vivid`, `warm`, `cool`, `cinematic`, or `mono`. The optional `lighting` field accepts `original`, `brighten`, `soft`, `golden`, or `studio`. Both default to `original`, so earlier callers, including the shared Virtual Closet client, do not add a new color grade or lighting instruction. Unknown values are rejected before provider calls.

Selected controls are included in both the image analysis and final editing request. They preserve subject identity, fine texture, geometry, branding and lettering; color looks other than monochrome explicitly protect natural skin and product colors. A monochrome restoration stays monochrome unless colorization is explicitly requested. The user's written request takes priority over generic treatment, color and lighting suggestions. These controls do not themselves request a new background or remove transparency, and Remove background still requires actual transparent pixels in the result.

Provider output is bounded to 64 MB before decoding and must contain canonical base64 and a supported still PNG. The complete pixel stream is decoded before returning success, saving history, or incrementing credits: a readable PNG header alone is insufficient. Returned dimensions and transparency describe the decoded pixels, rather than unchecked provider metadata. Broken analysis envelopes fail with a controlled error before image editing. Existing models, quality, timeouts, entitlements and credit prices are unchanged.

October 2 backend validation: 17 picture-workspace tests and 12 chat-quality regressions passed. These cover every new look and lighting choice in both model requests, invalid options, preservation, styled cutouts, truncated RGB PNGs, malformed analysis envelopes, output size/encoding/format checks, access gates and failure-without-credit paths. Providers are injected fixtures; subjective photo quality still requires a live signed-in edit.

## Model pipeline

The active `backend/server.js` `/api/image/improve` route uses `picture_studio.cjs`. After existing sign-in, Ultra/Enterprise and usage checks:

1. Decode the actual image with Sharp, enforce supported still formats and a 45-megapixel limit, and create an orientation-correct analysis copy bounded to 2048 pixels on each edge. Preserve the original upload bytes for image editing.
2. Ask `gpt-6-astra` to inspect that copy with `detail: original`, `reasoning.effort: xhigh`, `store: false`, structured JSON output and a 32,768-token output/reasoning budget. The result is a concise edit plan and user-facing description of the intended edit, not hidden reasoning or a quality-verification claim.
3. Submit the original image plus the original user instructions, treatment, preservation rules and grounded plan to `gpt-image-2.5-sunburst` with `quality: max`, `output_format: png`, and one output. Do not set the legacy `input_fidelity` parameter. Background removal explicitly requests transparency. Existing transparent inputs retain transparency unless a new setting/background is requested.
4. Require a fully decoded PNG within the output limit. If transparency is requested, check that actual alpha values are present, not merely an opaque PNG with an alpha channel. Only then save history and increment the existing one-credit usage charge.

The analysis call has a 120-second timeout, the image edit a 280-second timeout, and no automatic provider retries. The new client allows 430 seconds for the entire response. Extra-high reasoning plus maximum image quality can take several minutes. Analysis refusal, incomplete output, malformed plans, provider errors, empty images or invalid output fail without a successful history entry or user-credit increment. This is a synchronous request, not a durable background job; closing the browser can lose an in-flight result. Duplicate submissions are disabled while the workspace is busy.

The optional existing `KORLIX_CHAT_IMAGE_MODEL` server override is honored for rollback. GPT Image 2.5 models use `max`; older supported image models use compatible `high`, reported in response metadata. Detailed dimensions are rejected when incompatible with an older configured model. No fallback silently replaces a failed provider request.

The prior `CHAT_QUALITY.md` describes the earlier release: main Create image stays at extra-high quality, while this later Improve Picture release upgrades edits to maximum quality and adds Astra planning. Nova voice, meeting recordings and bookkeeping are unchanged.

## September 27 checks and release

- 363 backend checks passed, including image-specific planning, original-byte preservation, transparency, options, malformed uploads, access/credit gates, failure paths, the active upload route, earlier chat behavior and Nova regressions.
- 262 frontend checks passed: 7 photo-workspace checks, 7 earlier chat checks and 248 Meeting Co-Pilot regressions. The focused photo tests exercise authenticated multipart uploads, invalid results, phone layout, selection/instructions, duplicate prevention, consent denial, before/after, saving, refinement, original restoration and retry state.
- Phone and desktop widget renders were visually inspected. Production photo quality requires an actual signed-in photo edit; local tests use synthetic image fixtures and injected providers.
- Deploy only the existing backend and frontend release branches/services. No database, credential, plan, pricing or environment changes are required. Public health adds `pictureStudio` with the configured analysis model, reasoning effort, image model and image quality.

Acceptance: refresh KORLIX, open Improve my picture, upload a familiar portrait, use Natural polish, compare the face/hairline and lighting, and save. Optionally test Remove background and Refine this image. Model settings and automated tests do not establish subjective picture quality; record the user's live result separately.

## Official API references

- https://developers.openai.com/api/docs/models/gpt-6-astra
- https://developers.openai.com/api/docs/models/gpt-image-2.5-sunburst
- https://developers.openai.com/api/docs/guides/image-prompting
- https://developers.openai.com/api/docs/guides/images-vision
- https://developers.openai.com/api/docs/guides/structured-outputs
- https://developers.openai.com/api/reference/resources/images/methods/edit
