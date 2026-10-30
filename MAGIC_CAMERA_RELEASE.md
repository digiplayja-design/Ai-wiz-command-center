# Korlix Magic Camera — implementation and release gates

This change adds a shared Flutter Magic Camera module, a standalone Android/iOS/web app, and a hub entry. The server lives on the separate current backend branch; do not deploy the app branch's older backend directory.

## Implemented

- Orange/blue Korlix emblem; prompt-first native camera, no captured-original preview or before/after view.
- 30 embedded presets in six categories, custom text and device dictation, optional clothing collection, saved signature looks, Surprise Me, intensity and accent controls.
- Interactive orange/blue orbits, Stardust and Portal modes, pause and OS reduced motion, group countdown and haptics.
- Private durable jobs, final-only gallery, save/share, animated GIF reveal using only the final image, deletion, and a visible Report action on each result and gallery item.
- Account-bound lifetime allowance of two successful free standalone results. Hub Basic cannot generate. Pro: 10/month, max 2/day; Ultra/Enterprise: 40/month, max 5/day. Shared across hub and companion. No extra developer unlimited bypass.
- Standalone Starter: 15/month, proposed US $9.99; Plus: 40/month, proposed US $19.99. Real store prices take precedence. Verified App Store/Google Play purchases; restore and cancellation-management links. No activation from an unverified client receipt.
- Sunburst maximum quality, one render, no automatic provider retry or quality downgrade. Presets avoid an extra planning call. Explicit custom prompts go directly to the image editor too.

## Validation and operational details

`packages/korlix_magic_core` is the shared UI/client. `apps/magic_camera` owns companion authentication and store UI. The companion bundle/package ID is `com.korlixdeveloper.magiccamera`.

The backend PR adds `backend/magic_camera` and its service-only SQL migration. Worker leases are durable and fenced; source photos are stripped of metadata, privately stored, and removed after completion or expiration. Failed results do not consume credits. Generated files are stored before success is committed. Deleted successes remain in the allowance ledger. Reporting copies the actual generated result to the existing private Korlix support review queue.

Allowances use UTC calendar months/days, including standalone subscriptions. The purchase screen explains this. Source uploads expire after 3 minutes, queued jobs after 24 hours, processing leases after 10 minutes. The worker sweeps private files every 5 seconds while the service is running; storage outages delay deletion and are retried. The private gallery pages through older jobs and loads smaller previews only as cards become visible. Signature looks are stored per account on the current device.

Native camera 0.12.2 raises the hub's Android minimum from API 23 to API 24 (Android 7). Android 6 installations need their existing hub version or the web app. iOS camera use and optional dictation permissions are included. This change does not alter Improve My Picture tier rules.

## Before live release

1. Review/merge the separate backend PR into `release/signup-plan-intent-20261021`, apply its migration, and deploy that current backend. The app branch must never replace that backend history.
2. Create the dedicated Apple/Google app records and monthly `magic_camera_starter` / `magic_camera_plus` products at the approved prices. Set real app IDs and provider flags only after signed sandbox purchase/restore/cancel/refund checks. Existing hub store products are unchanged.
3. Review the provided Android and iOS build artifacts. Complete physical-device camera, background/reconnect, rotation, camera-denial, save/share, and group-portrait QA, plus representative real Sunburst quality/latency checks. No latency or perfect-face guarantee is claimed.
4. Confirm original-image retention against the service configuration and include this data flow in the published app privacy disclosures. Confirm the team monitors the existing report review queue.
5. Register signing/provisioning and publish the standalone app through the stores; release the new hub build separately.

## Deliberately not advertised as complete

The proposed 10-photo $6.99 top-up needs consumable purchase verification and refund accounting before it can be offered. Rici's voiced countdown, portable style links, Astra-assisted complex planning, and segmentation/compositing to preserve original face pixels are future extensions. The current Preserve my face option supplies explicit generation constraints; it cannot guarantee identical facial pixels or zero distortion. There is no custom identity recognition or gender inference.
