# K136S-A — Preflight Report

**Project:** K136S — Nova Secure Spoken Learning and Brain Management
**Owner:** Claude (Fable) parallel track. Runs alongside ChatGPT's K135Z (Nova Zoom Meeting Copilot).
**Result:** PASS — cleared to build K136S-B (pure domain model + state machine, tests + local commit only).

## Base commits (verified)

| Role | Commit | Branch |
| --- | --- | --- |
| Production backend (K136S-B base) | `b6de854e1ee1967826650116ab0810508166aa3d` | build131-k134b-authoritative-daily-usage-api-v1-20260903t182314z |
| Production frontend (future K136S frontend base) | `320192a8d65f898fe82786763991d71ffa39f81d` | build132-k134b-authoritative-daily-usage-ui-v1-20260903t182314z |
| K135Z backend (do not touch) | `00c38fbab53019357fca509cc0d6e76f16b67a1c` | b1-zoom-oauth-rtms |
| K135Z frontend (do not touch) | `68ae4b8639c544137975da4f0a4c87b5d47b5767` | b4a-authenticated-meeting-copilot-entry |
| K135Z b2 UI worktree (do not touch) | `2cbac1a` | build135-k135z-b2-nova-meeting-copilot-ui-v1-20260904t170856z |

K136S mirrors the K135Z split: the backend track stages on `b6de854e`, a later frontend track will stage on `320192a8`. Both descend from fork point `5509d04`.

## Ports

K136S reserves `7460`–`7469` (preview servers, used from K136S-C onward). K135Z uses `7357`–`7363`. All were free at preflight. No K136S port is opened in phase B.

## Reuse decisions (do not rebuild)

- **Brain Vault V2 already exists** — reuse it for authentication. Table `korlix_brain_vault_credentials`; scrypt 64-byte hash; password length 12–128; 5 failures → 15-minute lock; routes `GET /api/brain-vault/security-status`, `POST /api/brain-vault/password/{set,verify,change,reset}`. K136S calls `POST /api/brain-vault/password/verify` and stores only a `vault_verified_at` timestamp (15-minute TTL; 60-second freshness required for elevated changes). K136S never stores, forwards, or logs the vault password.
- **Memory / training store already exists** — reuse tables `korlix_live_convo_agent_profiles`, `korlix_live_convo_agent_versions`, `korlix_live_convo_agent_memories`. All are RLS-enabled with `revoke all` (service-role only); authorization is enforced server-side. Memory/training entries become rows in `korlix_live_convo_agent_memories` (new row per approved change; supersede via `enabled`/`active` + `metadata.superseded_by`; rollback copies a prior row; delete sets `deleted_at`/`forgotten_at`; expiry via `expires_at`). Profile changes go through `korlix_live_convo_agent_versions`.
- **Speech is OpenAI Realtime over WebRTC** — transcripts already arrive from OpenAI; the microphone mute control already exists in `lib/live_convo/korlix_live_convo_test_screen.dart`. K136S mutes the mic before showing the vault field and drives the immediate context refresh through the existing realtime context-invalidation path.

## New tables (staged, applied only at K136S-F integration)

`k136s_learning_sessions`, `k136s_approvals`, `k136s_audit_events`. No migration is applied during phase B.

## Guardrails confirmed for phase B

Copy-paste Bash patches only; no file downloads. New files only, under `backend/k136s_learning/**`, `backend/test/k136s_*.test.cjs`, and `docs/k136s/**`. No edits to shared gate files (`lib/main.dart`, `backend/server.js`, root `server.js`, `pubspec.yaml`, `backend/package.json`, `supabase/migrations/**`, plus `lib/live_convo/korlix_live_convo_test_screen.dart` and `backend/korlix_live_convo_agents.js`) until the K136S-F integration gate. No K135Z-owned paths (`backend/k135z_zoom/**`, `lib/meeting_copilot/**`, `test/meeting_copilot/**`, `assets/meeting_copilot/**`) are ever touched. No push, no deploy, no database write, no migration, no Render change, no credential action. Backend tests run with `node --test` (built-ins only; no new dependencies).
