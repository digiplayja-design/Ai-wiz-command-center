# Agent Studio and reviewed workflows

Open Live Convo and choose **Agents** at the top right to open Agent Studio, before or during a voice session. This shortcut stays visible while scrolling. The existing **Make it yours** section also contains a clearly named **Agent Studio** entry. Paused sessions retain their lock; focused Inventory voice retains its separate tools. The frontend and API remain on their existing, separate Render release branches. No additional service, secret, or provider connection is required.

## User experience

- Agents: responsive searchable gallery, built-in/custom/trained filters, capability badges, activation and existing tool access.
- Brain Management: selected-agent overview, draggable projected 3D brain, memory library, training studio, version history, and protected Brain Vault.
- Memory: content/label/tag search, type and sensitivity filters, priority/recent ordering, confirmed additions, file learning, and existing confirmed cleanup operations. The library stays open for multiple additions. Closing applies saved updates through the existing runtime refresh path.
- Training: document-derived drafts, append/replace modes, explicit publishing consent, memory and permitted capability settings. No model-weight fine-tuning is implied. The brain is a visual depiction of knowledge; activity reflects real draft, analysis, pending save, and confirmed save states.
- Workflows: 1–8 ordered agent assignments; plan/create/review, creative-brief, and learning templates; reorder steps before creation; priority labels; explicit run, review, approval, feedback, pause/resume, cancellation, retry, reuse, export, and activity history.

## Execution contract

Workflows generate written deliverables with the configured `chat_quality.cjs` model and reasoning policy. They have **no external tools**. They do not send emails, browse, generate files through Live Docs, change inventory, or execute code. Existing connected tools retain their own permissions and approval flows.

Each step is explicitly started by the user and consumes one standard generation credit. Its result pauses for review. Only approved earlier results enter subsequent step context. Approving a result does not start another paid run. Requesting changes preserves the earlier output and records feedback; the next explicit run revises that step.

Published training applies to the assigned agent. Approved memory is optional and defaults off. When enabled, only that agent's non-sensitive records are selected, bounded to 16 records / 8,000 characters. Memory-derived facts may enter later steps through an explicitly approved result. Sensitive records are excluded from workflow memory. This is not a new export route for the protected Brain Vault.

## Storage and concurrency

Migration: `*_agent_studio_workflows.sql`, created using the Supabase CLI and applied with the connected migration API. Match the checked-in timestamp to the applied database version.

- `korlix_agent_workflows`: owner, plan, steps/results, state, cursor, revision, attempt, and bounded event history.
- `korlix_agent_workflow_attempts`: execution lease, generation charge, captured training version, and outcome.
- Both tables enable RLS and grant access only to `service_role`. The invoker RPC has a fixed search path; PUBLIC/anon/authenticated execution is revoked. Authenticated API handlers supply the verified account ID.
- Account advisory locks plus row locks serialize transitions. Revision checks reject stale changes. Run request UUIDs are idempotent, including after completion. One active step per account, three in-process global starts/runs, 30 attempts/hour/account, 200 saved workflows/account, and 200 retained workflow events bound resources.
- Failures, cancellation during execution, and runs orphaned for five minutes return the generation credit once. Late results cannot resurrect an old, failed, or cancelled attempt. Recovery runs when the owner lists/opens workflows. No automatic retry or automatic charge occurs.
- Existing account clients reject requests and late responses after a different account/session is observed. JWT refresh within the same issuer/user/session remains valid. The hub closes its nested routes after an account change.

## Verification and rollout

Run `node --test backend/test/agent_studio.test.mjs` for the actual SQL state machine in PGlite and authenticated Express route tests. Existing agent and training-file regression scripts must still pass. Frontend tests in `test/agent_studio_test.dart` cover mobile/desktop layouts, themes, reduced motion, search/filtering, memory consent and save states, workflow building/run/review, and account changes. Existing vault, agent email access, enterprise hub, and Live Convo transport suites are regression gates. Build the Flutter web release after analysis.

Roll out the additive migration, then the backend release, then the frontend release. Verify both Render deployments report live, `/api/health` returns 200, unauthenticated workflow routes return 401, public database roles cannot access the new objects, and the served app bundle contains the new interface. A real signed-in generation with the configured provider is a separate device/account smoke check; fixture tests do not establish its result quality.
