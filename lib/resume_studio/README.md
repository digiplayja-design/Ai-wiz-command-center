# KORLIX Resume Studio

The home **Write my Resume** action opens a dedicated Flutter workspace. The French and Spanish home actions use the same workspace. The studio supports guided contact/profile/experience/education/skills/project editing, reviewed Rici rewrites, cover letters, job-description notes with explicit phrase matching, three styles, section and entry ordering, preview, PDF/DOCX/text export, and up to 30 device-local drafts with duplication and removal.

## Data and generation

- Drafts are manually saved in SharedPreferences under an issuer + account key. The UI states that storage is on this device and does not claim cloud synchronization. A failed load never overwrites stored drafts.
- An open client is bound to issuer + subject + session ID. Token refresh retains access. Sign-out, account switch, or a new sign-in invalidates it, clears private UI, closes previews, and rejects late generation/export responses.
- AI requests use the existing authenticated generation endpoint and its normal usage allowance. `purpose: resume_studio` disables inferred web searches and file-generation intent in the matching backend update. Rewriting supplies professional facts without contact details.
- PDF/DOCX/TXT import uses `/api/analyze-document`, preserving the existing upload plan restrictions and generation allowance. Typed import uses the text-only generation path. Imported fields are validated and shown for review before becoming a new, unsaved draft.
- Generation requires the existing third-party AI consent. Suggestions never silently replace content. Apply creates an undo point; the user reviews facts. Job descriptions are reference material, not evidence of qualifications.
- Phrase matching is deterministic and explicitly labeled as literal matching, not an ATS score or hiring prediction. It never adds missing terms to a resume automatically.

## Exports

All formats share `ResumeDraft.blocks()`. Job descriptions, keyword notes, draft names, and target company metadata are excluded from the resume. Cover-letter exports are separate. Empty sections disappear, PDFs flow across pages, and Word files are genuine OOXML ZIP packages with escaped text. Existing platform file-save/share handling is reused. No paid generation is needed to edit or export locally.

## Validation

`flutter test --no-pub test/resume_studio_test.dart` covers content isolation, draft identities, import validation, stale responses, responsive layouts, editing and saving, reviewed AI changes, failure preservation, and real PDF/Word exports. `RESUME_EXPORT_QA` writes synthetic export fixtures and `AGENT_STUDIO_SCREENSHOTS` captures rendered UI for review. Backend policy checks live in `backend/test/resume_studio.test.mjs` on the backend release branch.
