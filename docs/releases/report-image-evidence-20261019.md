# Reported image review copies

The previous Android app sent the prompt and the label “Imagined picture” but omitted locally generated image bytes. Neither the report queue nor generation history contains those omitted images. They cannot be recovered from those records.

Image reports now accept a bounded PNG/JPEG/WebP data URL separately from the existing 32 KiB metadata budget. The server verifies the raster, rejects animation and oversized inputs, strips metadata, and creates a JPEG review copy (maximum 1280 pixels per side / 512 KiB). It never downloads submitted URLs.

Apply `20261019211556_private_report_image_evidence.sql` before deploying this backend. The private copy is inserted in the existing report row in the same transaction as its metadata. Existing RLS/grants remain server-only, and account deletion cascades remove the copy. Legacy clients may still submit reports without images.

Support emails include `reported-image.jpg` as a CID attachment and inline preview. Reviewer listing returns image metadata, not bytes. `GET /api/report-output/:id/image` requires either the existing report admin credential in a header or the reporting user's authenticated session. Owner filtering is applied before reading bytes. Image responses are `no-store` and `nosniff`.

Validation: 42 focused Node/PGlite checks pass, including attachment contents, malformed/oversized images, atomic persistence failures, browser-role denial, owner-scoped reads, rate limits, legacy intake, and deletion cascade. Email delivery is mocked in tests; no test mail is sent to a person.

Rollout: deploy schema, then backend, then the app update. Existing reports without images remain unchanged. Users need the updated app to attach an image when reporting it.
