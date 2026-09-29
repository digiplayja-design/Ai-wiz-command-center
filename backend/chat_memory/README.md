# Main chat long-term memory

Explicit, account-owned notes for `/api/generate` requests with `mainChatMemory: true`. Resume/tool requests and account-memory-disabled requests cannot inherit notes. No prior chats, Social data, agent memories or attachments are harvested.

- `GET /api/chat-memory/list`: current settings and at most 100 notes.
- `POST .../save`: UUID, body (1–500 characters), category; an existing note also requires its current version. Conflicting edits return 409. Repeated identical notes deduplicate within an account.
- `POST .../settings`: boolean `enabled`. Pause suppresses future retrieval and “Remember that…” saves; management remains available.
- `POST .../delete`: UUID. `POST .../clear`: `confirm: true` after UI confirmation.
- Save commands return only after the database confirms the write and do not use AI credits. Ordinary chat never automatically writes memory. Natural-language deletion directs users to the Memory screen.

`requireUser` verifies the bearer token through Supabase. The server supplies the actor UUID. The service-only RPC, RLS and browser-role privilege revocations keep other accounts and browser API calls out. All reads and writes are uncached. Only the creating account can poll a resumable generation job. All saved notes fit the bounded context (100 × 500 characters); they are quoted as data with instructions to ignore embedded instructions and prefer current facts.

Deleting a note prevents its inclusion in future memory context; it does not delete historical conversation messages or retract in-flight model requests. Account deletion cascades to both new tables. The client clears loaded notes on session changes and rejects late responses.

New local chat/history caches are namespaced by account issuer + subject, not a token. Legacy unowned browser caches are preserved on disk but not automatically imported: ownership cannot safely be inferred. Saved notes sync through the database; entire chat histories remain device-local.

Apply the generated Supabase migration before deploying the backend, then publish the updated frontend. No additional services, secrets or paid tiers are needed. Old clients remain on their existing selected-topic context until updated.

Validation: `node --test backend/test/chat_memory.test.mjs backend/test/chat_quality.test.cjs backend/test/resume_studio.test.mjs`. Tests use isolated PGlite identities and fixture AI output; no user messages, emails or real provider generation calls are sent.
