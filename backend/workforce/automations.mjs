import { randomUUID } from 'node:crypto';
import { fail, id, text, integer, shiftSeconds, enrichSnapshot, dailyBrief } from './core.mjs';
import { createKorlixAgentEmailDeliveryService } from '../korlix_agent_email_delivery.mjs';
import { createKorlixAgentEmailSupabaseStore } from '../korlix_agent_email_routes.mjs';
import { korlixAgentEmailNovaBinding } from '../korlix_agent_email.mjs';

export const automationTemplates = Object.freeze({
  subject: 'Workforce · {{topic}}',
  text: '{{report}}\n\nSent by NOVA for your approved Workforce automation. Open KORLIX Workforce to review the records.',
});
export function automationInput(body = {}) {
  if (!['missed_update', 'missed_shift', 'daily_summary'].includes(body.kind)) fail('Choose an automation type.');
  if (!['email', 'call_review'].includes(body.channel)) fail('Choose email or call review.');
  if (body.kind === 'daily_summary' && body.channel !== 'email') fail('Daily summaries use email.');
  if (!/^([01]\d|2[0-3]):[0-5]\d$/.test(body.local_time || '')) fail('Choose a local delivery time.');
  if (!Array.isArray(body.days) || !body.days.length || body.days.length > 7) fail('Select at least one weekday.');
  const days = [...new Set(body.days.map(d => integer(d, 0, 6)))].sort();
  return {
    id: id(body.id), name: text(body.name, 100, true), kind: body.kind, channel: body.channel,
    member_id: body.kind === 'daily_summary' ? null : body.member_id ? id(body.member_id) : null,
    recipient_id: body.channel === 'email' ? id(body.recipient_id) : null,
    delay_minutes: integer(body.delay_minutes, 0, 240), local_time: body.local_time,
    days, daily_limit: integer(body.daily_limit, 1, 50),
  };
}

export function localDay(now, timezone) {
  const parts = Object.fromEntries(new Intl.DateTimeFormat('en-CA', {
    timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(new Date(now)).map(p => [p.type, p.value]));
  const date = `${parts.year}-${parts.month}-${parts.day}`;
  return { date, minutes: Number(parts.hour) * 60 + Number(parts.minute), weekday: new Date(date + 'T12:00:00Z').getUTCDay() };
}
export const previousDay = date => new Date(Date.parse(date + 'T12:00:00Z') - 86400000).toISOString().slice(0, 10);
const cut = v => v.length > 3600 ? v.slice(0, 3480) + '\n\nAdditional entries omitted. Open Workforce for the complete report.' : v;
const validMember = (r, m) => m.active && (!r.member_id || r.member_id === m.user_id);

// Evaluate only current conditions. A delayed email is cancelled if its condition
// has resolved; no backlog of obsolete hourly reminders is replayed after a restart.
export function automationEvents(rule, raw, now = Date.now()) {
  if (!rule.enabled || !raw.active_plan) return [];
  const day = localDay(now, raw.organization.timezone);
  if (!rule.days.includes(day.weekday)) return [];
  const members = new Map(raw.members.filter(m => validMember(rule, m)).map(m => [m.user_id, m]));
  const scope = raw.organization.name;
  const ttl = new Date(now + 2 * 3600000).toISOString();
  if (rule.kind === 'daily_summary') {
    const [h, m] = rule.local_time.split(':').map(Number);
    const scheduled = h * 60 + m;
    if (day.minutes < scheduled || day.minutes >= scheduled + 360) return [];
    // Only the previous completed calendar day is summarised, including DST days.
    const reportDate = previousDay(day.date);
    return [{ event_key: `daily:${day.date}`, subject: `Daily summary · ${reportDate}`, member_id: null,
      expires_at: new Date(now + Math.min(360, scheduled + 360 - day.minutes) * 60000).toISOString(), report_date: reportDate }];
  }
  if (rule.kind === 'missed_update') return raw.shifts.flatMap(s => {
    const member = members.get(s.user_id), p = s.policy_snapshot || {};
    if (!member || s.state !== 'working' || !p.hourly_updates) return [];
    const updates = raw.updates.filter(u => u.shift_id === s.id).sort((a, b) => b.worked_seconds_at_submit - a.worked_seconds_at_submit);
    const last = updates[0];
    const since = shiftSeconds(s, now).raw_worked_seconds - (last?.worked_seconds_at_submit || 0);
    const due = (Number(p.interval_minutes || 60) + Number(p.grace_minutes || 0) + rule.delay_minutes) * 60;
    if (since < due) return [];
    return [{ event_key: `update:${s.id}:${last?.id || 'start'}`, subject: 'Work update reminder', member_id: member.user_id, expires_at: ttl,
      body: `${scope}\n${member.display_name} has a work update due.\n\nPlease open Workforce → My day and record completed work, quantities, and any blockers.\nThis reminder reflects recorded updates, not a judgement of productivity.` }];
  });
  return raw.schedule.flatMap(s => {
    const member = members.get(s.user_id), start = Date.parse(s.starts_at), end = Date.parse(s.ends_at);
    if (!member || s.cancelled_at || now < start + rule.delay_minutes * 60000 || now >= end) return [];
    if (raw.shifts.some(x => x.user_id === s.user_id && Date.parse(x.clock_in) < end && Date.parse(x.clock_out || new Date(now).toISOString()) >= start)) return [];
    return [{ event_key: `shift:${s.id}:${s.version}`, subject: 'Scheduled shift check-in', member_id: member.user_id,
      expires_at: new Date(Math.min(end, now + 2 * 3600000)).toISOString(),
      body: `${scope}\nNo clock-in is recorded for ${member.display_name}'s scheduled shift starting ${new Date(start).toLocaleString('en-US', { timeZone: raw.organization.timezone })} (${raw.organization.timezone}).\n\nPlease check in through Workforce or contact your employer if plans have changed. This alert is based on attendance records; it does not establish an absence.` }];
  });
}

export function createAutomationStore(database) {
  return { async command(actor, action, org, payload = {}) {
    const { data, error } = await database.rpc('korlix_workforce_automation_v1', { p_actor: actor, p_action: action, p_org: org, p: payload });
    if (error) {
      const match = /WF(403|404|409)?: (.+)/.exec(error.message || '');
      if (match) fail(match[2], Number(match[1] || 400), 'WORKFORCE_AUTOMATION_INVALID');
      fail('Workforce automations are temporarily unavailable.', 503, 'WORKFORCE_AUTOMATION_UNAVAILABLE');
    }
    return data;
  } };
}

const trigger = r => `workforce.${r.org_id}.${r.id}`;
export function approvedRuleMatches(raw, rule) {
  return raw && raw.id === rule.email_rule_id && raw.enabled === true && !raw.deleted_at && raw.send_mode === 'autopilot'
    && raw.trigger_key === trigger(rule) && raw.preapproved_by === rule.owner_id && !!raw.preapproved_at
    && raw.approval_version === rule.email_approval_version && raw.marketing === false
    && JSON.stringify(raw.recipient_scope?.recipientIds) === JSON.stringify([rule.recipient_id])
    && raw.subject_template === automationTemplates.subject && raw.text_template === automationTemplates.text
    && !raw.html_template && raw.max_sends_per_day === rule.daily_limit;
}

export function createWorkforceAutomations({ database, persistence, loadAgentProfile, environment = process.env, store,
  emailStore, delivery, now = Date.now, autoStart = true, logger = console } = {}) {
  const state = store || createAutomationStore(database);
  const mailStore = emailStore || createKorlixAgentEmailSupabaseStore(database);
  const mail = delivery || createKorlixAgentEmailDeliveryService({ environment, store: mailStore, loadAgentProfile, now: () => new Date(now()) });
  const binding = korlixAgentEmailNovaBinding(environment);
  const bound = user => binding.configured && binding.ownerUid === user;
  const cmd = (user, action, org, p) => state.command(user, action, org, p);
  const identity = user => ({ userId: user, agentId: binding.agentId });
  const ruleAt = async (user, org, ruleId) => {
    const data = await cmd(user, 'state', org);
    const r = data.rules.find(r => r.id === ruleId);
    if (!r) fail('Automation not found.', 404, 'WORKFORCE_AUTOMATION_NOT_FOUND');
    return { ...r, owner_id: user, active_plan: data.active_plan };
  };
  let running = false, stopped = false, lastTick = null;
  async function capabilities(user) {
    if (!bound(user)) return { email_ready: false, reason: 'Connect this owner’s NOVA Email Center to use automatic emails.', outbound_calling_enabled: false };
    try {
      const s = await mail.getDeliveryStatus(identity(user));
      return { email_ready: s.canAutopilot === true, reason: s.canAutopilot ? null : 'Enable approved Autopilot in NOVA Email Center. Existing sending limits and quiet hours apply.', daily_usage: s.dailyUsage, outbound_calling_enabled: false };
    } catch { return { email_ready: false, reason: 'NOVA Email Center is not ready. Check its settings and approved recipients.', outbound_calling_enabled: false }; }
  }
  async function setEnabled(user, org, body) {
    const r = await ruleAt(user, org, id(body.rule_id));
    if (integer(body.version, 1, 2147483646) !== r.version) fail('Automation changed; refresh before saving.', 409, 'WORKFORCE_AUTOMATION_CHANGED');
    if (body.enabled !== true) {
      const result = await cmd(user, 'pause', org, { rule_id: r.id, version: r.version });
      if (r.email_rule_id && bound(user)) await mail.updateRule({ ...identity(user), ruleId: r.email_rule_id, body: { enabled: false } }).catch(() => {});
      return result;
    }
    if (body.confirmed !== true) fail('Review the recipient, timing, and message before enabling.');
    if (!r.active_plan) fail('An active Enterprise plan is required.', 403, 'WORKFORCE_PLAN_REQUIRED');
    let approval = {};
    if (r.channel === 'email') {
      const cap = await capabilities(user);
      if (!cap.email_ready) fail(cap.reason, 409, 'WORKFORCE_EMAIL_UNAVAILABLE');
      const candidates = (await mail.listRules({ ...identity(user), limit: 200 })).rules.filter(x => x.triggerKey === trigger(r));
      if (candidates.length > 1) fail('Duplicate email rules found. Review this trigger in NOVA Email Center before enabling.', 409, 'WORKFORCE_EMAIL_DUPLICATE');
      const body = { name: `Workforce · ${r.name}`, triggerKey: trigger(r), recipientIds: [r.recipient_id],
        subjectTemplate: automationTemplates.subject, textTemplate: automationTemplates.text, htmlTemplate: '', marketing: false,
        sendMode: 'autopilot', enabled: true, maxSendsPerDay: r.daily_limit, allowedDays: [0,1,2,3,4,5,6], scheduleType: 'event',
        preapproved: true, confirmed: true, confirmationNonce: randomUUID() };
      const result = candidates.length
        ? await mail.updateRule({ ...identity(user), ruleId: candidates[0].id, body })
        : await mail.createRule({ ...identity(user), body });
      approval = { email_rule_id: result.rule.id, email_approval_version: result.rule.approvalVersion };
    }
    return cmd(user, 'enable', org, { rule_id: r.id, version: r.version, confirmed: true, ...approval });
  }
  async function rawSnapshot(rule, dates = {}) {
    return persistence.command(rule.owner_id, rule.owner_email || '', 'snapshot', rule.org_id, dates);
  }
  async function events(rule) {
    const raw = await rawSnapshot(rule);
    const list = automationEvents(rule, raw, now());
    for (const e of list) if (e.report_date) {
      const report = await rawSnapshot(rule, { from: e.report_date, to: e.report_date });
      e.body = cut(dailyBrief(enrichSnapshot(report, now())));
    }
    return list;
  }
  async function processJob(rule, job) {
    const done = (status, code, extra = {}) => cmd(rule.owner_id, 'finish', rule.org_id, {
      rule_id: rule.id, job_id: job.id, lease_token: job.lease_token, status, code, ...extra,
    });
    try {
      // Fresh owner/plan/rule/condition checks after claiming; never rely on a UI snapshot.
      const current = { ...await ruleAt(rule.owner_id, rule.org_id, rule.id), owner_email: rule.owner_email };
      if (!current.enabled || !current.active_plan || !(await events(current)).some(e => e.event_key === job.event_key)) return done('cancelled', 'condition_resolved_or_paused');
      if (current.channel === 'call_review') return done('review', 'review_required_no_call_placed');
      if (!bound(rule.owner_id)) return done('blocked', 'nova_owner_binding_changed');
      const rawRule = await mailStore.getRule(rule.owner_id, binding.agentId, current.email_rule_id);
      if (!approvedRuleMatches(rawRule, current)) return done('blocked', 'email_rule_changed_reapproval_required');
      const result = await mail.runAutopilot({ body: { ruleId: current.email_rule_id, triggerKey: trigger(current),
        eventId: `workforce:${current.id}:${job.event_key}`, variables: { topic: job.subject, report: job.body } } });
      const receipt = result.results?.find(x => x.ruleId === current.email_rule_id && x.recipientId === current.recipient_id);
      if (receipt?.sent || receipt?.replayed) return done('sent', 'accepted_by_email_provider', { message_id: receipt.messageId });
      const code = receipt?.code || result.results?.[0]?.skipped || 'email_rule_unavailable';
      // Sending/unknown provider outcomes are reconciled through the existing Email
      // Center, never turned into a second email with a new idempotency key.
      if (/uncertain|unknown|in_progress|message_id_missing|sending/.test(code)) return done('blocked', 'email_outcome_needs_review', { message_id: receipt?.messageId });
      const retry = /window|daily|limit|rate|temporar|timeout|resend_/.test(code) && job.attempts < 12;
      return done(retry ? 'pending' : 'blocked', code, { message_id: receipt?.messageId, retry_seconds: Math.min(1800, 60 * 2 ** Math.min(job.attempts, 5)) });
    } catch (error) {
      const code = String(error?.code || 'automation_delivery_unavailable').slice(0, 180);
      return done(job.attempts < 12 ? 'pending' : 'blocked', code, { retry_seconds: 300 });
    }
  }
  async function tick() {
    if (running || stopped) return;
    running = true;
    try {
      const rules = await cmd(null, 'due_rules', null);
      for (const rule of rules) {
        if (stopped) break;
        try {
          await cmd(rule.owner_id, 'checked', rule.org_id, { rule_id: rule.id });
          for (const event of (await events(rule)).slice(0, 500)) await cmd(rule.owner_id, 'enqueue', rule.org_id, { rule_id: rule.id, ...event });
          for (let i = 0; i < 5; i++) {
            const job = await cmd(rule.owner_id, 'claim', rule.org_id, { rule_id: rule.id });
            if (!job) break;
            await processJob(rule, job);
          }
        } catch (e) { await cmd(rule.owner_id, 'checked', rule.org_id, { rule_id: rule.id, error: String(e.code || 'automation_check_unavailable').slice(0,180) }).catch(() => {}); }
      }
      lastTick = new Date(now()).toISOString();
    } catch { logger.warn?.('Workforce automation worker: storage unavailable; retrying next minute.'); }
    finally { running = false; }
  }
  const timer = autoStart ? setInterval(() => void tick(), 60000) : null;
  const initial = autoStart ? setTimeout(() => void tick(), 10000) : null;
  timer?.unref?.(); initial?.unref?.();
  return {
    async get(user, org) { return { ...await cmd(user, 'state', org), ...await capabilities(user), templates: automationTemplates, worker_last_tick: lastTick }; },
    create: (user, org, body) => cmd(user, 'create', org, automationInput(body)), setEnabled,
    async pauseAll(user, org) {
      const before = await cmd(user, 'state', org);
      const result = await cmd(user, 'pause_all', org);
      if (bound(user)) for (const r of before.rules.filter(x => x.email_rule_id)) await mail.updateRule({ ...identity(user), ruleId: r.email_rule_id, body: { enabled: false } }).catch(() => {});
      return result;
    },
    resolve: (user, org, job) => cmd(user, 'resolve', org, { id: id(job) }), tick,
    close() { stopped = true; clearInterval(timer); clearTimeout(initial); },
  };
}
