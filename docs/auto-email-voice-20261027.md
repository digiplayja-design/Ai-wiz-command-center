# Auto-Email Rici voice pilot

The standalone app can now open the existing Rici Realtime service and prepare a transactional email for a saved contact. Audio is started only by the user. The one available voice tool returns an unsaved proposal; the user reviews it in the ordinary draft editor and explicitly saves. Sending, approval, scheduling, new-recipient access, and general business provisioning remain disabled in this companion.

## Backend contract

`GET /api/auto-email/voice/status` reports readiness. Namespaced session and usage operations retain the verified Auto-Email session scope and existing approved owner/agent check. Query-string mode mixing is rejected. The normal KORLIX voice reservation and allowance apply; no new subscription, provider key, or database migration is introduced.

The Rici session bypasses general agent-memory attachment and receives an email-specific prompt with only `prepare_email_draft(subject,textBody)`. The selected contact is shared by the browser only after Start conversation. Tool arguments cannot change the recipient or trigger a cloud mutation.

The shared service issues a signed proof after a successful provider connection. Usage and hangup require this proof, bound to the app, authenticated user, installation, usage session, provider call and expiry. Its HMAC key is purpose-derived from the existing server-only provider credential; rotating that credential invalidates outstanding proofs. The proof never carries the credential itself. Provider hangup destinations are constructed from a validated provider Location header and fixed OpenAI origin.

Pilot sessions are capped in the UI at 180 seconds and 20 responses, additionally bounded by the existing allowance. The server schedules provider hangup after the time cap; explicit end also requests hangup. This timer is in process, so a server restart can interrupt that deadline. Existing usage reporting remains client cumulative reporting, not independent provider reconciliation. Durable call control and provider usage reconciliation are required before broad paid business access; this pilot is limited to the existing approved owner.

## Validation

56 backend tests passed, covering account/session regressions, owner authorization, mode mixing, scope, proof tampering, wrong installation/session, proof expiry, provider URL confinement, and deadline hangup. The standalone client has 16 passing tests covering its API boundary, refresh lifecycle, draft-only tool processing, duplicate events, permission refusal, late connections, mute/stop cleanup, and usage failures.

No real microphone audio, customer contact data, provider call, or email was used during automated tests. The account-specific microphone-to-Rici path still requires a first live pilot call. The UI test fixture uses example.test data and an injected simulated session, and is excluded from deployment.

## Official API references reviewed

- https://developers.openai.com/api/docs/guides/voice-webrtc?voice-api=realtime
- https://developers.openai.com/api/docs/guides/realtime-conversations
- https://developers.openai.com/api/docs/guides/voice-server-controls
- https://developers.openai.com/api/reference/resources/realtime/subresources/calls/methods/hangup

The existing configured Realtime model, voice, and transcription model are retained.
