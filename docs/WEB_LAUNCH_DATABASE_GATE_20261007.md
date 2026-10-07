# Web launch: isolated PostgreSQL test gate

Checked October 7, 2026 against the current backend checkout. **This gate remains unverified.** No native PostgreSQL test was reported as passing and no production database was contacted.

## Scope

The two suites are:

- `backend/test/k135z_b5b_storage_rpc.test.cjs`: 32 declared tests.
- `backend/test/k135z_workspace_storage_rpc.test.cjs`: 51 declared tests.

The earlier audit's **33 failures** describe the result of that run: failed setup for 32 B5B cases plus the workspace test-file initialization failure. They are not a count of all logical SQL cases. The current source contains 83 declared tests across the two suites.

## Verified environment blocker

This execution workspace runs Ubuntu 24.04 with no installed `psql`, `postgres`, `initdb`, or `pg_ctl` binaries. Its user namespace exposes only root:

```text
/proc/self/uid_map: 0 0 1
/proc/self/gid_map: 0 0 1
/proc/self/setgroups: deny
```

A single attempt to use the normally configured package manager failed before package retrieval:

```text
apt-get update -o Acquire::Retries=0 -o Acquire::http::Timeout=15 -o Acquire::https::Timeout=15
exit 100
setgroups (1: Operation not permitted)
seteuid (22: Invalid argument)
Method https has died unexpectedly
```

A direct check of the existing nonroot account also failed:

```text
runuser -u nobody -- id
exit 1
runuser: cannot set groups: Operation not permitted
```

Having root's UID in this restricted namespace does not provide the ability to run an actual PostgreSQL server as another user. Installing a binary alone would not resolve that requirement. No alternative identity spoofing, altered PostgreSQL binary, guard removal, TCP connection, production URL, or emulated SQL fallback was attempted.

## Required isolated runner

Use a Linux CI runner or local VM that can run a real unprivileged PostgreSQL process, with PostgreSQL 15, 16, 17, or 18 installed at its normal distribution path. PostgreSQL 17 is the closest supported major to the deployed service. The suite checks accept only `/usr/lib/postgresql/<major>/bin/psql`.

The harness must:

1. Create separate fresh, nonsymlinked roots owned by the unprivileged test runner, including `data` and `socket` directories, all mode `0700`.
2. For Gate6A, use `/tmp/k135z-g6a-<safe-suffix>`, database `k135z_gate6a_local`, a random 48-character lowercase hexadecimal nonce, and `INSTANCE.json` containing the matching `nonce` and `database`.
3. For Gate6G, use `/tmp/k135z-g6g-<24-lowercase-hex>`, database `k135z_gate6g_local`, and a separate random 48-character lowercase hexadecimal nonce.
4. Start with TCP listening disabled, only the harness's private Unix socket, port 5432, database administrator `k135z_local_admin`, and the matching `k135z.gate6a_instance` or `k135z.gate6g_instance` server setting.
5. Bootstrap only synthetic users, roles and prerequisite schemas, then apply the relevant checked-in Zoom migrations in the isolated databases. The Gate6A local-only bootstrap is `backend/test/fixtures/k135z_b5b_storage_rpc.sql`; it must never be applied to production. Gate6G needs its own complete prerequisite fixture, including the agent-profile and entitlement tables used by the workspace RPC.
6. Run each suite with its unchanged isolation guards under that same unprivileged OS account with its matching `K135Z_G6A_*` or `K135Z_G6G_*` environment variables. Do not inherit production credentials or database connection settings.
7. Preserve the complete TAP output, PostgreSQL version, checkout commit and fixture/migration list, then stop and remove the isolated database directories.

Successful execution must demonstrate the database nonce, expected data directory and database name, and `inet_server_addr() IS NULL`, as the test guards already require.

## Corrected stale schema assertion

The B5B suite previously asserted exactly four private tables, while `202609170001_k135z_b5b_storage_v1.sql` declares six. The added `stream_terminals` and `capture_sources` tables are intentional: the migration uses them for terminal-state fencing and host-bound capture sources, and later workspace cases test them explicitly.

The test now verifies the exact six intended table names, RLS on every table, and denied direct reads for all six tables under each of `service_role`, `anon`, `authenticated` and the ungranted test role. This strengthens the former count-only check and the single-table access check. The nonce, filesystem, Unix-socket, SQL role, timeout and RPC guards are unchanged. `node --check` and patch whitespace validation passed; native SQL execution remains blocked and is not claimed as passing.

## CI inventory and next runner work

The checkout has two GitHub workflows: `.github/workflows/build-web.yml` and `.github/workflows/android-debug-apk.yml`. Both build Flutter artifacts. Neither starts PostgreSQL, installs backend test prerequisites, or runs these suites. There is no checked-in isolated native PostgreSQL harness script; only the Gate6A SQL bootstrap exists. The existing web workflow's push trigger also targets an older feature branch, not the current release branch. Therefore, dispatching either existing workflow will not close this gate.

The next concrete step is a dedicated manual CI job or a local Linux VM run, with the harness requirements above:

1. Check out the exact candidate backend commit. Use Node 22 or later and install locked backend dependencies with `npm ci --prefix backend`.
2. Confirm the test account is unprivileged and can own a private `/tmp` directory. Install a supported PostgreSQL distribution package if needed, then use its real `initdb`, `pg_ctl`, `createdb` and `psql` binaries. Do not launch the tests against a container's TCP service or a hosted database URL.
3. Create the two isolated clusters described above. A reviewed harness must trap shutdown/cleanup on both success and failure, disable TCP listening, and verify instance identity before loading fixtures.
4. Gate6A fixture order: its checked-in local bootstrap, `202609040001_k135z_zoom_b1_foundation.sql`, `202609170001_k135z_b5b_storage_v1.sql`, then `20260919155618_k135z_transcript_scope_correction.sql`.
5. Gate6G requires a separately reviewed bootstrap that checks its own database name, nonce and Unix-socket connection before creating only synthetic fixtures: `auth.users`; `anon`, `authenticated`, `service_role` and `gate6g_untrusted`; `public.user_profiles(id,tier)` seeded with the two fixture UUIDs as Enterprise; and `public.korlix_live_convo_agent_profiles(user_id,agent_id,active,deleted_at)` with the current expected defaults and service-role read access. Apply the B5B migration, workspace commands migration, transcript-scope correction and abandoned-session recovery migration in chronological order. Do not alter production migrations to accommodate the fixture.
6. After verified setup, execute `node --test backend/test/k135z_b5b_storage_rpc.test.cjs` and `node --test backend/test/k135z_workspace_storage_rpc.test.cjs` separately, each with its own `K135Z_G6A_LOCAL_ROOT` / `K135Z_G6A_NONCE` / `K135Z_G6A_PSQL` or `K135Z_G6G_LOCAL_ROOT` / `K135Z_G6G_NONCE` / `K135Z_G6G_PSQL` values. No account, provider or production database secrets are needed.
7. Retain complete TAP output and setup/cleanup logs as the release evidence. Resolve any real failures without removing negative authorization cases or weakening the isolation checks. Do not equate workflow completion with a passing gate unless all declared SQL cases actually execute and pass.

No CI workflow was created, dispatched or charged by this investigation. The runner setup described here remains work to implement and validate.

## Effect on launch readiness

This check does not change the previous live RLS/storage metadata verification or the already runnable backend results. It also does not certify the current SQL concurrency, rollback, authorization lease and terminal-state paths covered by these two native suites. Keep this isolated database gate open until supported-runner results are recorded.

Only this evidence document and the stale B5B table assertion were changed by this investigation. No application code, isolation guards, migrations, production records, or historical commit checks were changed.
