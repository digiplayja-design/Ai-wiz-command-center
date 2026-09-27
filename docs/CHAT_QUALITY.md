# KORLIX chat and picture quality — September 27, 2026

## Behavior

The active `backend/server.js` chat route now requests `gpt-6-astra` with `reasoning.effort: xhigh`, a 32,768-token output/reasoning budget and `store: false`. Web search and the existing search-failure fallback retain the same model and reasoning effort. This is scoped to main chat: the shared Astra adapter still defaults to low effort for latency-sensitive callers, including Nova voice. No model change was made to telephone, Zoom speech, Live Convo, document engines or bookkeeping.

Chat requires the existing verified sign-in and usage checks before requesting a model. Failed/incomplete responses do not increment usage. The existing Enterprise rewrite client's `prompt` alias is accepted. Normal replies are no longer forced into a four-part answer/verdict template.

The client sends up to 16 selected-topic user/assistant messages, capped at 12,000 characters each and 96,000 in aggregate. The server validates role, shape and size and no longer loads account-wide generation history into this route. Empty history starts a new conversation. This is bounded conversational context, not unlimited memory or a new database migration. Old open clients without the new history payload must reload for follow-up context.

Main picture creation and Improve Picture use GPT Image 2.5 Sunburst with `quality: xhigh` and PNG output. One image is generated per request. New pictures support square, portrait, landscape and automatic dimensions plus prompt-led, photographic, illustration, graphic-design and cinematic styles. Edits preserve defining identity details and honor explicit requested changes; automatic dimensions avoid a forced square crop. Existing editing tier restrictions and credit rules remain. Requests have a 240-second provider deadline; the client allows 260 seconds. A failure never silently substitutes a lower-quality model. `KORLIX_CHAT_IMAGE_MODEL` is an optional server-owned rollback override; older supported GPT Image models use compatible `high` quality. Legacy global image variables do not override this scoped upgrade.

The frontend now offers Chat/Create image controls, picture starters, clearer waiting text, selectable answers, per-answer Copy, Open image and Save image. Questions precede answers; all existing turns remain scrollable. Image previews use contain fitting. Old answers stay visible during generation. Completed pictures are added to the selected topic and explicit image saving uses the existing download flow. Existing local storage limits and abrupt browser closure still apply; this release does not add durable background image jobs or cross-device image storage. Topic switches do not place a completed text/image response in an unrelated topic. A draft typed while a text request runs is retained.

## Verification

- 353 backend checks passed, including actual route handlers with an injected provider, model/effort and tool payloads, history isolation/validation, sign-in and credit gates, provider/incomplete failures, PNG/size/style settings, image edits, and Nova recording/voice regressions.
- 255 frontend checks passed: 7 focused chat tests plus 248 Meeting Co-Pilot regressions. Layout coverage includes question/answer order, older turns, pending input, copy, image controls and selection changes at a narrow width.
- The JavaScript release build passed. The existing optional Wasm dry-run warnings are unrelated to this JavaScript deployment. Analysis of the large existing main file has legacy lint warnings; no compiler errors were reported.
- A local phone-width widget render was inspected. The cloud browser reached the production sign-in page; no user credentials were requested or entered, and no live user prompt/image was submitted by the assistant.
- Startup performs two bounded read-only model-catalog checks using the existing server credential. `/api/health` reports configured models/quality and `chatModelAccess` values. `visible` proves model-catalog access, not successful generation or subjective picture quality.

## Deployment and rollback

Publish only the isolated changes on the existing backend and frontend release branches, preserving the accepted Nova recording fix and paused bookkeeping work. No database, credential, pricing, service-plan or environment mutations are required. Backend root directory is `backend`; the legacy repository-root `server.js` is not the Render entry point and is unchanged. Keep both services' automatic deployment setting off.

Pre-release production commits: backend `a1459f0daaa7ff95806b2a6ce9d13eca46f086e9`; frontend `f462ee45012f4eb46dfd4a490bbff92f99282afb`. If provider access is unavailable, do not claim a successful model upgrade; report the access failure and retain a usable prior release or a disclosed, compatible image override.

After deployment, refresh KORLIX. Check that Chat shows “Astra · Extra high”; ask a question and a follow-up in one topic, then start a separate topic. Choose Create image, select shape/style, generate one picture, and check Open/Save. User confirmation of actual answer and picture quality remains a live acceptance step.

## Official API references

- https://developers.openai.com/api/docs/models/gpt-6-astra
- https://developers.openai.com/api/docs/guides/reasoning
- https://developers.openai.com/api/docs/guides/image-generation
- https://developers.openai.com/api/reference/resources/images/methods/generate/
