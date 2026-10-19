# Image report update — 12.0.2

Both generated-image reporting entry points now submit the selected image bytes, including locally stored data URLs. The confirmation sheet discloses that an image preview and prompt are shared with support. Images are decoded, metadata is removed, and a bounded PNG review copy is sent. Remote URLs are fetched without account credentials and with a byte cap. A changed session aborts submission after image preparation. Preparation failures state that no report was sent.

The existing text report budget and single-request/durable-receipt behavior are preserved. No automatic retry is added. The server re-validates/re-encodes the image, saves it privately with the report, and attaches the saved JPEG to support email.

Backend commit `92cad91d290d4ac93d273960c1144798f3afd14f` is live on the existing Render service. Migration `20261019211556_private_report_image_evidence.sql` is applied. Live report health is v5, anonymous image reads return 401 with no-store/nosniff, and the table remains inaccessible to anon/authenticated database roles.

Validation: 42 backend/database checks and 18 Flutter report checks pass. The support client and tests analyze without issues. Whole main.dart analysis reports no errors; existing unrelated warnings/informational findings remain. No real support test email was sent.

Release candidate: 12.0.2. Google Play's highest uploaded code was verified as 139 on October 19, so the next signed internal build is 140. iOS CI selects a fresh build number from App Store Connect. Both build workflows run the report checks. Flutter 3.44.0 requires four local SDK-pinned dependency resolutions for Android; the shared 3.47.7 iOS lockfile is preserved.

Acceptance: install the updated test build, generate an image, report it, and open the resulting support email. Confirm an image preview and reported-image.jpg attachment. Older reports whose original images were never uploaded cannot be reconstructed from server records.
