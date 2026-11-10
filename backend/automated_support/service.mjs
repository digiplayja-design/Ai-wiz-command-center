import {randomUUID} from 'node:crypto';
import {SUPPORT_STATES, SUPPORT_MODES, UUID, fail, emailAddress, boundedText, supportReadiness} from './config.mjs';

const genericAreas = new Set(['', 'app_wide_ai_reporting', 'ai_generated_content_report', 'saved_history']);
const asTime = value => value instanceof Date ? value : new Date(value);
const validDate = value => typeof value === 'string' && Number.isFinite(Date.parse(value));

/** These are reviewed templates. User report text is data, never instructions. */
export function supportAcknowledgment(report, profile) {
  const safety = /unsafe|harm|hate|harass|sexual|privacy/i.test(String(report.reason || ''));
  const questions = [];
  if (!safety && genericAreas.has(String(report.appArea || ''))) questions.push('Which feature or screen were you using?');
  if (!safety) questions.push('What happened when you tried it? Please include the exact error message or a screenshot if available.');
  if (!safety && !String(report.appVersion || '').trim()) questions.push('Which app version are you using?');
  if (!safety && !String(report.platform || '').trim()) questions.push('Are you using Android, iPhone, or the web app?');
  const body = [
    'Hello,', '',
    `I’m Rici, the automated support assistant for ${profile.displayName}.`, '',
    safety ? 'Thank you for reporting this content. Your report has been recorded for review.' : 'Thank you for reporting a problem. Your report has been recorded.',
    '', ...questions.map((question, index) => `${index + 1}. ${question}`),
    ...(questions.length ? ['', 'Reply to this email with those details so the support team can identify the next step.'] : ['', 'You can reply to this email with any additional context for the support team.']),
    '', 'Please do not include passwords, verification codes, or payment card details.', '',
    'Rici', profile.displayName,
  ];
  return {text: body.join('\n'), subject: `We received your ${profile.displayName} report`, needsReview: safety};
}

export function createAutomatedSupportService({store, profiles = [], deliver, now = () => new Date(), environment = process.env} = {}) {
  if (!store || typeof deliver !== 'function') throw new TypeError('Support persistence and a delivery adapter are required.');
  const enrolled = () => typeof profiles === 'function' ? profiles() : profiles;
  const timestamp = () => { const date = asTime(now()); if (!Number.isFinite(date.getTime())) throw new TypeError('Invalid support clock.'); return date.toISOString(); };
  const profileById = id => enrolled().find(profile => profile.id === id);
  function ownedProfile(ownerUid, profileId) {
    const profile = profileById(profileId);
    if (!UUID.test(ownerUid || '') || !profile || profile.ownerUid !== ownerUid.toLowerCase()) fail('Support profile not found.', 404, 'support_not_found');
    return profile;
  }
  async function ownedCase(ownerUid, caseId) {
    if (!UUID.test(ownerUid || '') || !UUID.test(caseId || '')) fail('Support case not found.', 404, 'support_not_found');
    const record = await store.getCase(ownerUid.toLowerCase(), caseId);
    if (!record) fail('Support case not found.', 404, 'support_not_found');
    ownedProfile(ownerUid, record.profileId);
    return record;
  }
  async function profileView(profile) {
    const setting = await store.syncProfile(profile, timestamp());
    return {id: profile.id, displayName: profile.displayName, fromEmail: profile.fromEmail, replyTo: profile.replyTo, appKeys: profile.appKeys, dailyCap: profile.dailyCap, mode: setting.mode, senderVerified: profile.senderVerified, receivingVerified: profile.receivingVerified, ...supportReadiness(profile, environment)};
  }
  async function processProfileCase(profile, caseId) {
    const ready = supportReadiness(profile, environment);
    if (!ready.ready) return {processed: false, reason: 'setup_required'};
    await store.syncProfile(profile, timestamp());
    const token = randomUUID();
    const claimed = await store.claimMessage({profile, caseId, token, now: timestamp()});
    if (!claimed) return {processed: false, reason: 'no_eligible_message'};
    const {caseRecord, message} = claimed;
    // Claim atomically rechecks mode, pause, owner, fingerprint, recipient and quota.
    // A claimed handoff is never automatically retried after an uncertain result.
    try {
      if (!supportReadiness(profile, environment).ready) {
        await store.finishMessage({ownerUid: profile.ownerUid, messageId: message.id, token, status: 'failed', errorCode: 'support_paused_before_send', now: timestamp()});
        return {processed: false, reason: 'paused'};
      }
      const result = await deliver({profile, caseRecord, message, idempotencyKey: `korlix-support/${message.id}`});
      if (result?.accepted !== true || !result.providerMessageId) throw Object.assign(new Error('Unconfirmed email submission.'), {uncertain: true});
      const recorded = await store.finishMessage({ownerUid: profile.ownerUid, messageId: message.id, token, status: 'sent', providerMessageId: result.providerMessageId, internetMessageId: result.internetMessageId || null, now: timestamp()});
      if (recorded !== true) throw Object.assign(new Error('Email submission could not be recorded.'), {uncertain: true});
      return {processed: true, messageId: message.id, status: 'sent'};
    } catch (error) {
      const status = error?.uncertain === false ? 'failed' : 'uncertain';
      // Provider diagnostics may contain addresses or bodies. Persist only a bounded code.
      const errorCode = typeof error?.code === 'string' && /^[a-z0-9_]{1,80}$/.test(error.code) ? error.code : 'support_delivery_unconfirmed';
      try { await store.finishMessage({ownerUid: profile.ownerUid, messageId: message.id, token, status, errorCode, now: timestamp()}); } catch { /* The stale-claim settler will mark it uncertain. */ }
      return {processed: true, messageId: message.id, status};
    }
  }
  return Object.freeze({
    async listProfiles({ownerUid}) {
      if (!UUID.test(ownerUid || '')) fail('Sign in required.', 401, 'support_sign_in_required');
      return {profiles: await Promise.all(enrolled().filter(profile => profile.ownerUid === ownerUid.toLowerCase()).map(profileView))};
    },
    async setProfileMode({ownerUid, profileId, mode}) {
      const profile = ownedProfile(ownerUid, profileId);
      if (!SUPPORT_MODES.includes(mode)) fail('Choose a valid support mode.');
      const readiness = supportReadiness(profile, environment);
      if (mode === 'automatic' && !readiness.ready) fail('Complete support sending and reply setup before enabling automatic responses.', 409, 'support_setup_required');
      await store.syncProfile(profile, timestamp());
      await store.setMode(profile, mode, timestamp());
      return {profile: await profileView(profile)};
    },
    async listCases({ownerUid, profileId, state}) {
      if (!UUID.test(ownerUid || '')) fail('Sign in required.', 401, 'support_sign_in_required');
      const available = profileId ? [ownedProfile(ownerUid, profileId)] : enrolled().filter(profile => profile.ownerUid === ownerUid.toLowerCase());
      if (state && !SUPPORT_STATES.includes(state)) fail('Choose a valid case state.');
      return {cases: available.length ? await store.listCases(ownerUid.toLowerCase(), available.map(profile => profile.id), state || null) : []};
    },
    async getCase({ownerUid, caseId}) {
      const record = await ownedCase(ownerUid, caseId);
      return {case: record, messages: await store.listMessages(ownerUid.toLowerCase(), caseId)};
    },
    async updateCase({ownerUid, caseId, state, automationPaused, resolutionNote}) {
      await ownedCase(ownerUid, caseId);
      const patch = {};
      if (state !== undefined) { if (!SUPPORT_STATES.includes(state)) fail('Choose a valid case state.'); patch.state = state; }
      if (automationPaused !== undefined) { if (typeof automationPaused !== 'boolean') fail('Choose a valid automation setting.'); patch.automationPaused = automationPaused; }
      if (resolutionNote !== undefined) patch.resolutionNote = boundedText(resolutionNote, 2000, 'Resolution note');
      if (state === 'resolved' && !patch.resolutionNote) fail('Record how resolution was verified before resolving this case.');
      const record = await store.updateCase(ownerUid.toLowerCase(), caseId, patch, timestamp());
      return {case: record};
    },
    async queueOwnerReply({ownerUid, caseId, text, confirmed}) {
      const record = await ownedCase(ownerUid, caseId), profile = ownedProfile(ownerUid, record.profileId);
      if (confirmed !== true) fail('Review and confirm this reply before sending.', 409, 'support_confirmation_required');
      const body = boundedText(text, 12000, 'Reply');
      if (!body) fail('Write a reply.');
      if (!record.reporterVerified) fail('The reporter’s email could not be verified. This case requires manual review.', 409, 'support_recipient_unverified');
      if (record.state === 'resolved') fail('Reopen this case before replying.', 409, 'support_case_resolved');
      await store.syncProfile(profile, timestamp());
      const message = await store.queueReply({ownerUid: ownerUid.toLowerCase(), caseId, text: body, fingerprint: profile.fingerprint, now: timestamp()});
      await processProfileCase(profile, caseId);
      const messages = await store.listMessages(ownerUid.toLowerCase(), caseId);
      return {case: await ownedCase(ownerUid, caseId), message: messages.find(row => row.id === message.id) || message};
    },
    async processCase({ownerUid, caseId}) {
      const record = await ownedCase(ownerUid, caseId);
      return processProfileCase(ownedProfile(ownerUid, record.profileId), caseId);
    },
    async processPending({limit = 20} = {}) {
      await store.settleStale(timestamp());
      const results = [];
      for (const profile of enrolled()) {
        if (results.length >= limit || !supportReadiness(profile, environment).ready) continue;
        await store.syncProfile(profile, timestamp());
        const candidates = await store.pendingCases(profile, Math.max(1, Math.min(50, limit - results.length)));
        for (const caseId of candidates) results.push(await processProfileCase(profile, caseId));
      }
      return {results};
    },
    async drainIntake({resolveReporter, limit = 20} = {}) {
      if (typeof resolveReporter !== 'function') throw new TypeError('Verified reporter lookup is required.');
      // Only the existing KORLIX report route is enrolled in this increment.
      const profile = enrolled().find(row => row.appKeys.includes('korlix_ai'));
      if (!profile) return {processed: 0};
      await store.syncProfile(profile, timestamp());
      let processed = 0;
      for (let index = 0; index < Math.max(1, Math.min(50, limit)); index++) {
        const token = randomUUID(), intake = await store.claimIntake(token, timestamp());
        if (!intake) break;
        try {
          const report = intake.report;
          const reporter = await resolveReporter(report);
          const address = String(report.userEmail || '').toLowerCase();
          let verified = false;
          try { verified = reporter?.id === report.userId && reporter?.emailConfirmed === true && emailAddress(reporter.email) === emailAddress(address); } catch { /* An unverified account becomes a review-only case. */ }
          const acknowledgment = supportAcknowledgment(report, profile);
          const caseId = randomUUID();
          acknowledgment.subject = `${acknowledgment.subject.slice(0, 186)} [${caseId.slice(0, 8)}]`;
          const createdAt = timestamp();
          const caseData = {
            id: caseId, reportId: report.id, appKey: 'korlix_ai', reporterUid: report.userId,
            reporterEmail: address, reporterVerified: verified, subject: acknowledgment.subject,
            details: String(report.details || report.outputSummary || '').slice(0, 20000),
            appArea: String(report.appArea || '').slice(0, 100), appVersion: String(report.appVersion || '').slice(0, 100), platform: String(report.platform || '').slice(0, 100),
            state: !verified || acknowledgment.needsReview ? 'needs_review' : 'new',
            reportCreatedAt: validDate(report.createdAt) ? report.createdAt : createdAt, createdAt,
          };
          await store.completeIntake({intake, token, profile, caseData, messageData: {id: randomUUID(), subject: acknowledgment.subject, text: acknowledgment.text, profileFingerprint: profile.fingerprint}, now: createdAt});
          processed++;
        } catch {
          await store.releaseIntake(intake.reportId, token, timestamp());
        }
      }
      return {processed};
    },
    async lookupReply({profileId, inReplyTo, references = []}) {
      const profile = profileById(profileId);
      if (!profile) return null;
      const ids = [inReplyTo, ...references].filter(value => typeof value === 'string' && value.length <= 998 && !/[\r\n]/.test(value)).slice(0, 20);
      return ids.length ? store.lookupReply(profile, ids) : null;
    },
    async receiveReply({profileId, caseId, fromEmail, text, providerMessageId, internetMessageId = null, inReplyTo = null, attachments = [], authentication = 'unknown', senderAuthenticated = false}) {
      const profile = profileById(profileId);
      if (!profile || !UUID.test(caseId || '')) fail('Support conversation not found.', 404, 'support_not_found');
      const record = await store.getCase(profile.ownerUid, caseId);
      if (!record || record.profileId !== profile.id || emailAddress(fromEmail) !== record.reporterEmail || !record.reporterVerified) fail('Support conversation not found.', 404, 'support_not_found');
      if (['failed', 'fail'].includes(authentication)) fail('Incoming email could not be verified.', 403, 'support_inbound_unverified');
      const providerId = boundedText(providerMessageId, 200, 'Incoming message ID');
      if (!providerId) fail('Incoming message ID is required.');
      const safeInternetId = value => typeof value === 'string' && value.length <= 998 && /^<[^\s<>]+@[^\s<>]+>$/.test(value) ? value : null;
      const body = boundedText(text || '', 20000, 'Incoming reply');
      const safeAttachments = Array.isArray(attachments) ? attachments.slice(0, 10).map(item => ({id: String(item.id || '').slice(0, 200), filename: String(item.filename || item.name || 'Attachment').slice(0, 200), contentType: String(item.contentType || item.content_type || '').slice(0, 100), size: Number.isFinite(item.size) ? Math.max(0, item.size) : null})) : [];
      if (!body && !safeAttachments.length) return {accepted: false, reason: 'empty_message'};
      const result = await store.receiveReply({profile, caseId, fromEmail: record.reporterEmail, text: body, providerMessageId: providerId, internetMessageId: safeInternetId(internetMessageId), inReplyTo: safeInternetId(inReplyTo), attachments: safeAttachments, authentication: senderAuthenticated === true ? 'verified' : authentication, now: timestamp()});
      // Replies always require a human review in this first release. Never infer
      // resolution, account changes, refunds, or repairs from incoming prose.
      return {accepted: true, caseId, duplicate: result.duplicate === true};
    },
  });
}
