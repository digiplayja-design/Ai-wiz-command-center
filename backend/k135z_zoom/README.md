# K135Z Zoom OAuth and RTMS foundation

This directory is an isolated, dependency-free security foundation for K135Z.

It is intentionally not wired into the production server yet.

Part 1 provides:

- fail-closed Zoom configuration parsing without printing secret values;
- signed, short-lived OAuth state bound to a KORLIX user and agent;
- Zoom webhook signature verification using the exact raw request body;
- Zoom endpoint URL-validation challenge responses;
- unit tests that make no network, Zoom, Render, Supabase or email calls.

Part 1 does not exchange OAuth codes, store tokens, open RTMS sockets, collect
meeting media, modify Supabase, alter Render, deploy or touch K134B routes.

## B1 core contracts

OAuth is bound to the authenticated KORLIX user and selected agent. Tokens use AES-256-GCM envelopes. RTMS session state and active-time usage are replay-safe. No route is mounted, no Zoom request is sent and no media is collected in this stage.

## B1 route and storage scaffold

Framework-neutral handlers cover OAuth start, OAuth callback, connection status and verified Zoom webhooks. Authentication and agent ownership remain mandatory injected dependencies. The migration is additive, RLS-enabled and unapplied. Raw meeting audio remains disabled.
