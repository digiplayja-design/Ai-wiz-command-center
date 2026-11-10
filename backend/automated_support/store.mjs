import {fail} from './config.mjs';

const PREFIX = 'korlix_support_';
export const SUPPORT_TABLES = Object.freeze({profiles: `${PREFIX}profiles`, intake: `${PREFIX}intake`, cases: `${PREFIX}cases`, messages: `${PREFIX}messages`});
const caseView = row => row ? {
  id: row.id, profileId: row.profile_id, ownerUid: row.owner_uid, reportId: row.report_id,
  reporterUid: row.reporter_uid, reporterEmail: row.reporter_email, reporterVerified: row.reporter_verified,
  appKey: row.app_key, subject: row.subject, details: row.details, appArea: row.app_area, appVersion: row.app_version, platform: row.platform,
  state: row.state, automationPaused: row.automation_paused, resolutionNote: row.resolution_note,
  reportCreatedAt: row.report_created_at, createdAt: row.created_at, updatedAt: row.updated_at,
} : null;
const messageView = row => row ? {
  id: row.id, caseId: row.case_id, profileId: row.profile_id, ownerUid: row.owner_uid,
  direction: row.direction, actionKey: row.action_key, kind: row.kind, subject: row.subject, text: row.text,
  status: row.status, profileFingerprint: row.profile_fingerprint, providerMessageId: row.provider_message_id,
  internetMessageId: row.internet_message_id, errorCode: row.error_code, attachments: row.attachments || [],
  inReplyTo: row.in_reply_to,
  authentication: row.authentication, createdAt: row.created_at, claimedAt: row.claimed_at, sentAt: row.sent_at,
} : null;

/** Server-role adapter. Every owner-facing lookup includes owner_uid in SQL. */
export function createAutomatedSupportStore(database) {
  async function run(query) {
    if (!database) fail('Support storage is not configured.', 503, 'support_storage_unavailable');
    let result;
    try { result = await query.abortSignal(AbortSignal.timeout(10000)); } catch { fail('Support storage is temporarily unavailable.', 503, 'support_storage_unavailable'); }
    if (result.error) {
      if (/SUPPORT_(OWNER|FINGERPRINT|CASE|PROFILE|RECIPIENT)/.test(String(result.error.message || ''))) fail('This support operation is no longer available. Refresh the case.', 409, 'support_state_changed');
      fail('Support storage is temporarily unavailable.', 503, 'support_storage_unavailable');
    }
    return result.data;
  }
  function rpc(name, args) { if (!database) fail('Support storage is not configured.', 503, 'support_storage_unavailable'); return run(database.rpc(`${PREFIX}${name}`, args)); }
  function table(name) { if (!database) fail('Support storage is not configured.', 503, 'support_storage_unavailable'); return database.from(SUPPORT_TABLES[name]); }
  return Object.freeze({
    async syncProfile(profile, now) {
      const row = await rpc('sync_profile', {p_id: profile.id, p_owner: profile.ownerUid, p_fingerprint: profile.fingerprint, p_now: now});
      return {mode: row.mode, automaticSince: row.automatic_since};
    },
    async setMode(profile, mode, now) { return rpc('set_mode', {p_id: profile.id, p_owner: profile.ownerUid, p_fingerprint: profile.fingerprint, p_mode: mode, p_now: now}); },
    async listCases(ownerUid, profileIds, state) {
      let query = table('cases').select('*').eq('owner_uid', ownerUid).in('profile_id', profileIds);
      if (state) query = query.eq('state', state);
      const rows = await run(query.order('updated_at', {ascending: false}).order('id', {ascending: false}).limit(100));
      return (rows || []).map(caseView);
    },
    async getCase(ownerUid, caseId) { return caseView(await run(table('cases').select('*').eq('owner_uid', ownerUid).eq('id', caseId).maybeSingle())); },
    async listMessages(ownerUid, caseId) {
      const rows = await run(table('messages').select('*').eq('owner_uid', ownerUid).eq('case_id', caseId).order('created_at', {ascending: false}).order('id', {ascending: false}).limit(200));
      return (rows || []).reverse().map(messageView);
    },
    async updateCase(ownerUid, caseId, patch, now) { return caseView(await rpc('update_case', {p_owner: ownerUid, p_case: caseId, p_patch: patch, p_now: now})); },
    async queueReply({ownerUid, caseId, text, fingerprint, now}) { return messageView(await rpc('queue_reply', {p_owner: ownerUid, p_case: caseId, p_text: text, p_fingerprint: fingerprint, p_now: now})); },
    async claimMessage({profile, caseId, token, now}) {
      const data = await rpc('claim_message', {p_owner: profile.ownerUid, p_profile: profile.id, p_case: caseId, p_fingerprint: profile.fingerprint, p_daily_cap: profile.dailyCap, p_token: token, p_now: now});
      return data ? {caseRecord: caseView(data.case), message: messageView(data.message)} : null;
    },
    async finishMessage({ownerUid, messageId, token, status, errorCode = null, providerMessageId = null, internetMessageId = null, now}) {
      return rpc('finish_message', {p_owner: ownerUid, p_message: messageId, p_token: token, p_status: status, p_error: errorCode, p_provider_id: providerMessageId, p_internet_id: internetMessageId, p_now: now});
    },
    async settleStale(now) { return rpc('settle_stale', {p_now: now}); },
    async pendingCases(profile, limit) {
      return rpc('pending_cases', {p_owner: profile.ownerUid, p_profile: profile.id, p_limit: limit});
    },
    async claimIntake(token, now) {
      const row = await rpc('claim_intake', {p_token: token, p_now: now});
      return row ? {reportId: row.report_id, report: row.report} : null;
    },
    async completeIntake({intake, token, profile, caseData, messageData, now}) {
      return caseView(await rpc('complete_intake', {p_report: intake.reportId, p_token: token, p_profile: profile.id, p_owner: profile.ownerUid, p_case: caseData, p_message: messageData, p_fingerprint: profile.fingerprint, p_now: now}));
    },
    async releaseIntake(reportId, token, now) { return rpc('release_intake', {p_report: reportId, p_token: token, p_now: now}); },
    async receiveReply({profile, caseId, fromEmail, text, providerMessageId, internetMessageId, inReplyTo, attachments, authentication, now}) {
      return rpc('receive_reply', {p_owner: profile.ownerUid, p_profile: profile.id, p_case: caseId, p_from: fromEmail, p_text: text, p_provider_id: providerMessageId, p_internet_id: internetMessageId, p_in_reply_to: inReplyTo, p_attachments: attachments, p_authentication: authentication, p_now: now});
    },
    async lookupReply(profile, messageIds) {
      const rows = await run(table('messages').select('case_id').eq('owner_uid', profile.ownerUid).eq('profile_id', profile.id).eq('direction', 'outbound').eq('status', 'sent').in('internet_message_id', messageIds).limit(2));
      const ids = [...new Set((rows || []).map(row => row.case_id))];
      return ids.length === 1 ? this.getCase(profile.ownerUid, ids[0]) : null;
    },
  });
}
