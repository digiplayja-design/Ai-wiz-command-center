# Nova live meeting discovery repair

September 27, 2026. The reported symptom was an empty meeting list and disabled Start listening/Start Nova controls after the recording release. Read-only production evidence showed successful sign-in/account requests, completed Zoom reconnections, and signed meeting-start events. The account and meeting GET routes were repeatedly revalidated as HTTP 304. No backend crash was found. These observations identify discovery/recovery gaps; they do not prove a successful live-device repair before the owner retries.

## Changes

Meeting discovery and the explicit RTMS Start verification now request the connected host's live meetings with `GET https://api.zoom.us/v2/users/me/meetings?type=live&page_size=100`, even if `upcoming_meetings` is empty. The calendar endpoint alone is insufficient for ongoing meetings. Live entries come first and replace the calendar version of the same meeting ID with the current instance UUID. An ID is never substituted for a UUID. Invited calendar entries cannot grant host authority. Start still verifies the exact UUID, actual host ID, live status, current owner/agent and listening consent before requesting RTMS.

Live discovery shares the existing eight-second provider deadline, uses only fixed Zoom endpoints, and allows at most three live pages. Repeated page tokens, malformed responses and conflicting instance UUIDs fail without partial bindings. Permission errors remain errors rather than misleading empty lists. Existing non-live hosted UUID lookup remains bounded. The current connected account already has `meeting:read:list_meetings`; no new scope, environment change or migration is required.

Connection status, meeting discovery and OAuth preparation responses use private no-store caching. Frontend requests explicitly require fresh, non-stored responses. This avoids relying on stale browser status/list responses after a meeting starts or authorization completes.

The main startup controls now include **Refresh meetings**. Empty results explain that the host should start the Zoom meeting and refresh. A single live hosted meeting is selected when no explicit meeting choice applies; multiple live meetings require a choice. Live options are labeled **Live**. Refresh never starts capture or recording automatically.

An expired renewable Zoom access token previously blocked initialization before the discovery endpoint could renew it. Refresh now lets that endpoint use the existing server-side refresh grant, then rechecks status before enabling Start. Missing refresh grants, failed renewal, sign-out or agent changes continue to block listening.

## Validation

Backend checks cover empty-calendar live discovery, recurring instance replacement, host scope, privacy filtering, bounded pagination, provider denial, Start using live discovery, HTTP cache behavior and existing recording/voice/authority regressions. Frontend checks cover live selection, visible refresh recovery, expired-token renewal and refusal, existing Silence/Resume, recording controls and responsive layouts. Local tests use synthetic provider responses; no assistant-initiated meeting join, listening or recording is performed.

The official Zoom reference documents the calendar endpoint's 24-hour upcoming window and the hosted meeting-list endpoint: https://developers.zoom.us/docs/api/meetings/ . Zoom's maintained API collection documents `type=live`: https://www.postman.com/zoom-developer/zoom-public-workspace/request/u1a4m9n/list-meetings . Zoom documents limits on instant-meeting discovery; if a meeting still does not appear, the next diagnostic is its meeting type and connected host account, not another blind OAuth reset.

## Deployment and live acceptance

Deploy the backend before the frontend. Keep the recording storage and existing service settings intact. After the updated app loads, the owner should leave their hosted meeting running, open Meeting Co-Pilot, tap **Refresh meetings**, confirm the displayed meeting, then tap **Start Nova** or **Start listening only**. The audio meter and a spoken reply verify the live path. Recording acceptance remains a separate explicit opt-in test.
