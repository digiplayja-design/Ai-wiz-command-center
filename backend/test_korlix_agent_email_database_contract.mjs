import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const migrationPath = path.resolve(
  here,
  "../supabase/migrations/20260824192007_202608130001_agent_email_build133.sql",
);
const sql = fs.readFileSync(migrationPath, "utf8");

let passed = 0;

function check(_name, assertion) {
  assertion();
  passed += 1;
}

function occurrences(pattern) {
  return [...sql.matchAll(pattern)].length;
}

check("creates the complete five-table foundation", () => {
  for (const table of [
    "korlix_agent_email_settings",
    "korlix_agent_email_recipients",
    "korlix_agent_email_rules",
    "korlix_agent_email_messages",
    "korlix_agent_email_events",
  ]) {
    assert.match(
      sql,
      new RegExp(`create table if not exists public\\.${table}\\s*\\(`, "i"),
    );
  }
});

check("binds email controls to the exact user-owned Agent Hub profile", () => {
  assert.match(
    sql,
    /foreign key\s*\(user_id, agent_id\)[\s\S]*?references public\.korlix_live_convo_agent_profiles\s*\(user_id, agent_id\)/i,
  );
});

check("defaults to disabled draft-only emergency pause", () => {
  assert.match(sql, /enabled boolean not null default false/i);
  assert.match(sql, /operating_mode text not null default 'draft_only'/i);
  assert.match(sql, /emergency_paused boolean not null default true/i);
});

check("requires a bounded daily send cap", () => {
  assert.match(sql, /daily_send_cap integer not null default 25/i);
  assert.match(sql, /daily_send_cap between 1 and 500/i);
});

check("allows only explicit recipient sources and consent states", () => {
  assert.match(
    sql,
    /source_kind in \('user_entered', 'customer_record', 'approved_import'\)/i,
  );
  assert.match(sql, /marketing_opt_in/i);
  assert.match(sql, /unsubscribed_at timestamptz/i);
  assert.match(sql, /suppressed_at timestamptz/i);
});

check("requires preapproval before an autopilot rule exists", () => {
  assert.match(sql, /send_mode in \('draft_only', 'autopilot'\)/i);
  assert.match(
    sql,
    /send_mode <> 'autopilot'[\s\S]*?preapproved_at is not null[\s\S]*?preapproved_by is not null/i,
  );
});

check("requires one-time confirmation or a preapproved rule before send states", () => {
  assert.match(sql, /'one_time_confirmation'/i);
  assert.match(sql, /'preapproved_rule'/i);
  assert.match(
    sql,
    /status not in \('approved', 'queued', 'sending', 'sent'\)[\s\S]*?authorization_type <> 'none'/i,
  );
});

check("requires idempotency and Resend provider identity", () => {
  assert.match(sql, /idempotency_key text not null/i);
  assert.match(sql, /korlix_agent_email_messages_idempotency_uidx/i);
  assert.match(sql, /provider text not null default 'resend'/i);
});

check("requires marketing address and unsubscribe snapshots", () => {
  assert.match(sql, /physical_address_snapshot text not null/i);
  assert.match(sql, /unsubscribe_url_snapshot text not null/i);
  assert.match(
    sql,
    /message_kind <> 'marketing'[\s\S]*?physical_address_snapshot[\s\S]*?unsubscribe_url_snapshot/i,
  );
});

check("enables RLS and blocks direct public authenticated table access", () => {
  assert.equal(
    occurrences(/alter table public\.korlix_agent_email_[a-z_]+ enable row level security;/gi),
    5,
  );
  assert.equal(
    occurrences(/revoke all on table public\.korlix_agent_email_[a-z_]+[\s\S]*?from public, anon, authenticated;/gi),
    5,
  );
  assert.doesNotMatch(sql, /grant[^;]+to authenticated;/i);
});

check("keeps audit events append-only for the service role", () => {
  assert.match(
    sql,
    /grant select, insert\s+on table public\.korlix_agent_email_events to service_role;/i,
  );
  assert.doesNotMatch(
    sql,
    /grant[^;]*(update|delete)[^;]*korlix_agent_email_events[^;]*service_role;/i,
  );
});

check("atomically claims each send behind the per-agent settings lock", () => {
  assert.match(
    sql,
    /create or replace function public\.korlix_agent_email_claim_send_build133\s*\(/i,
  );
  assert.match(
    sql,
    /from public\.korlix_agent_email_settings[\s\S]*?for update;/i,
  );
  assert.match(
    sql,
    /status in \('sending', 'sent'\)[\s\S]*?daily_send_cap/i,
  );
  assert.match(
    sql,
    /v_rule_send_count[\s\S]*?max_sends_per_day/i,
  );
  assert.match(
    sql,
    /v_day_start[\s\S]*?at time zone v_settings\.timezone/i,
  );
  assert.doesNotMatch(sql, /p_day_start/i);
});

check("rechecks the exact approved recipient inside the atomic claim", () => {
  assert.match(
    sql,
    /from public\.korlix_agent_email_recipients[\s\S]*?user_id = p_user_id[\s\S]*?agent_id = p_agent_id[\s\S]*?for update;/i,
  );
  assert.match(
    sql,
    /consent_status in \('unsubscribed', 'suppressed'\)/i,
  );
  assert.match(
    sql,
    /lower\(btrim\(v_message\.to_email\)\)[\s\S]*?lower\(btrim\(v_recipient\.email\)\)/i,
  );
});

check("prevents stale Autopilot approval or recipient-scope reuse", () => {
  assert.match(
    sql,
    /ruleApprovalVersion[\s\S]*?v_rule\.approval_version/i,
  );
  assert.match(
    sql,
    /jsonb_array_elements_text[\s\S]*?recipientIds[\s\S]*?v_message\.recipient_id::text/i,
  );
  assert.match(
    sql,
    /agent_email_rule_approval_stale/i,
  );
  assert.match(
    sql,
    /v_message\.authorized_by is distinct from v_rule\.preapproved_by/i,
  );
  assert.match(
    sql,
    /v_message\.authorized_at is distinct from v_rule\.preapproved_at/i,
  );
});

check("limits safe retries to the provider idempotency window", () => {
  assert.match(
    sql,
    /status = 'sending'[\s\S]*?interval '15 minutes'/i,
  );
  assert.match(
    sql,
    /interval '23 hours'[\s\S]*?agent_email_send_reconciliation_required/i,
  );
  assert.match(
    sql,
    /lastFailureRetryable[\s\S]*?agent_email_message_requires_edit_and_reapproval/i,
  );
  assert.match(
    sql,
    /lastFailureAmbiguous[\s\S]*?agent_email_send_reconciliation_required/i,
  );
  assert.match(
    sql,
    /retryDeadlineAt[\s\S]*?v_retry_deadline/i,
  );
  assert.match(
    sql,
    /status not in \('approved', 'queued', 'failed', 'sending'\)/i,
  );
  assert.match(
    sql,
    /abs\(extract\(epoch from \(p_claimed_at - v_database_now\)\)\) > 300/i,
  );
});

check("atomically verifies the exact one-time approval nonce and approving user", () => {
  assert.match(
    sql,
    /p_confirmation_nonce_hash text/i,
  );
  assert.match(
    sql,
    /v_message\.authorized_by is distinct from p_user_id/i,
  );
  assert.match(
    sql,
    /lower\(btrim\(v_message\.confirmation_nonce_hash\)\)[\s\S]*?lower\(btrim\(p_confirmation_nonce_hash\)\)/i,
  );
  assert.match(
    sql,
    /agent_email_confirmation_nonce_mismatch/i,
  );
});

check("derives the daily cap boundary inside PostgreSQL from the locked timezone", () => {
  assert.match(
    sql,
    /date_trunc\([\s\S]*?p_claimed_at at time zone v_settings\.timezone[\s\S]*?at time zone v_settings\.timezone/i,
  );
  assert.match(
    sql,
    /coalesce\(sent_at, last_attempt_at, updated_at\) >= v_day_start/i,
  );
  assert.match(sql, /agent_email_timezone_invalid/i);
  assert.doesNotMatch(sql, /p_day_start/i);
});

check("keeps the send-claim RPC service-role only", () => {
  assert.match(
    sql,
    /revoke all on function public\.korlix_agent_email_claim_send_build133\([\s\S]*?from public, anon, authenticated;/i,
  );
  assert.match(
    sql,
    /grant execute on function public\.korlix_agent_email_claim_send_build133\([\s\S]*?timestamptz,[\s\S]*?text[\s\S]*?to service_role;/i,
  );
  assert.doesNotMatch(
    sql,
    /grant execute on function public\.korlix_agent_email_claim_send_build133\([\s\S]*?to authenticated;/i,
  );
});

check("contains no destructive or production-execution commands", () => {
  assert.doesNotMatch(sql, /\bdrop\s+table\b/i);
  assert.doesNotMatch(sql, /\btruncate\b/i);
  assert.doesNotMatch(sql, /\bdelete\s+from\b/i);
  assert.doesNotMatch(sql, /\binsert\s+into\b/i);
  assert.doesNotMatch(sql, /supabase\s+(db\s+push|migration\s+up|link)/i);
});

console.log(
  `KORLIX_AGENT_EMAIL_DATABASE_CONTRACT_TEST_COUNT=${passed}`,
);
