# Business Passport and AI Receptionist

Business Passport is the free public profile inside the existing Business Directory. The owner edits the existing listing, adds a headline and up to 12 service lines, selects a published 2MEETU event, and submits the change through the existing listing review. Public pages, QR images and contacts use only the approved snapshot. Existing links still open the Passport. Free and paid photo counts and optional verified memberships retain their existing rules.

Canonical page: `https://www.korlixdeveloper.com/business-directory/passport.html?business=<slug>`.
The app's Passport card opens the page and previews/downloads a locally generated QR PNG. No third-party QR service receives the link. Visitors can share, copy, print, save the business contact or download the QR. A missing optional booking page does not block the listing editor; hidden/unpublished businesses cannot return a public QR.

## Receptionist setup

Enterprise → AI Receptionist → choose a business, or Business Directory → select a business → AI Receptionist. The owner saves customer-facing answers, a greeting, voice, language, allowed appointment types, monthly phone limit, call duration and processing consent. Text previews use the published Passport and saved settings and never create appointments or caller messages. Live calls require an approved published Passport, an enabled receptionist, an active Enterprise account and a connected business line. Platform support connects the line; ordinary owners cannot claim another business's phone number.

Receptionist reasoning uses `gpt-6-astra` with `max` through the shared Responses adapter. OpenAI transcription and TTS remain specialized media models. A Vapi transient assistant receives a unique call-bound model credential; ordinary account tokens cannot call the provider or model webhook. Model-supplied system messages and owner/customer identifiers are discarded. Events, appointments, usage, inbox data and tools are scoped to the server-resolved business. Provider recording, transcript artifacts and provider-generated analysis are explicitly disabled.

The first message identifies K-Nova as AI and discloses call processing. The owner-approved knowledge is for customer-facing information, not private operational instructions. Caller ID is not verified identity. Only requested contact details/messages and confirmed bookings are saved in the private call inbox. Full transcripts and recordings are not saved by KORLIX. After 90 days caller content is hidden and removed by the minute worker; minimal usage totals remain. Associated appointments retain their own 2MEETU lifecycle.

## Telephone connection

Backend config:

- `KORLIX_RECEPTIONIST_VAPI_KEY` (or existing `VAPI_PRIVATE_KEY` / `VAPI_API_KEY`): server-only Vapi key for listing/connecting existing unused numbers.
- `KORLIX_RECEPTIONIST_SERVER_SECRET` (or existing `KORLIX_VAPI_SERVER_SECRET`): provider authentication secret, never returned to the frontend.
- Optional `KORLIX_RECEPTIONIST_PUBLIC_URL`: HTTPS backend origin; defaults to the existing production backend.
- Existing `OPENAI_API_KEY`, Supabase, Enterprise profiles and 2MEETU configuration apply.

The platform phone-setup button appears only to the server-configured Directory administrators. It lists existing unassigned phone numbers, asks the administrator to review/confirm the chosen number, sets its Vapi server to `/api/receptionist/provider/events`, and binds it to this business. It refuses numbers with an existing assistant, squad, workflow or server route. It does not buy, transfer or reassign numbers. If the private provider key is absent, owners can still configure and test their receptionist; the UI clearly requests phone setup. Existing developer-only NOVA routing is untouched.

Inbound `assistant-request` is resolved using the authenticated provider phone ID, never caller-selected owner IDs. Each call reserves the existing LIVE CONVO session allowance. Duration and Astra tokens are metered server-side; a separate owner-set phone cap and a ten-minute maximum bound phone costs. One active receptionist call per owner prevents overlapping phone reservations. Missing end reports are reconciled at the maximum duration. Account downgrades, a paused receptionist and a hidden Passport stop new call work. No quota is reserved by saving configuration or loading the screen. Text previews use the normal AI allowance. Provider/line fees are a separate phone setup agreement; no new price is invented in this release.

## Booking

The owner explicitly selects their own published 2MEETU appointment types without online-payment requirements. The receptionist uses the existing calendar conflict refresh, scheduling contexts and transactional booking RPC. It prepares a complete readback, and the caller must say “confirm booking”. The server requires the exact current pending readback, a valid unexpired lease and current owner/event permissions before the same database transaction creates and stores the booking. Retries reuse the prepared request and cannot create another booking. Online-payment appointment types continue through their public booking pages. Existing calendar sync and opted-in booking notifications apply.

## Validation and operation

- `node --test backend/test/receptionist_sql.test.mjs backend/test/receptionist_routes.test.mjs backend/test/directory.test.mjs backend/test/directory_routes.test.mjs`
- `flutter test --no-pub test/directory test/home_tool_catalog_test.dart`
- Static Passport browser QA at phone and desktop widths; synthetic data only.
- Apply the migration generated by the Supabase CLI after local PGlite verification, inspect RLS/RPC grants and run Supabase security advisors.
- Deploy backend first, then the frontend; verify public readiness, unauthenticated private routes, published static assets and exact release commits.
- A live telephone acceptance test requires the business owner to connect a dedicated number and place their own test call. A successful text preview alone is not evidence that the telephone line is active.
