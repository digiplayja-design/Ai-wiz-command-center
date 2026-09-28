/* Shared, side-effect-free queue model. Dates and counts come from loaded data. */
(function (root, factory) {
  const model = factory();
  if (typeof module === 'object' && module.exports) module.exports = model;
  else root.KorlixEmailWorkspace = model;
})(typeof globalThis !== 'undefined' ? globalThis : this, () => {
  'use strict';
  const text = value => String(value ?? '').trim();
  const first = (...values) => values.find(v => v !== undefined && v !== null && v !== '') ?? '';
  const bool = value => value === true || value === 1 || ['true', '1', 'enabled'].includes(text(value).toLowerCase());
  const time = value => Number.isFinite(Date.parse(value)) ? Date.parse(value) : 0;
  const failed = value => /fail|bounc|complain|reject|suppress/.test(text(value).toLowerCase());
  const review = value => ['draft', 'pending_approval'].includes(text(value).toLowerCase());
  const delivered = value => ['sent', 'delivered', 'opened', 'clicked'].includes(text(value).toLowerCase());
  const escape = value => text(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  function records(app, kind) {
    if (!app.connected || app.workspaceStale || app.panelErrors?.[kind]) return [];
    return (app[kind] || []).map(raw => {
      const status = text(first(raw.status, raw.consentStatus, raw.consent_status, raw.eventType, raw.event_type, raw.type)).toLowerCase();
      const mode = text(first(raw.sendMode, raw.send_mode, 'draft_only'));
      const enabled = bool(raw.enabled), preapproved = bool(raw.preapproved);
      const active = raw.active !== undefined ? bool(raw.active) : !['suppressed', 'unsubscribed'].includes(status);
      return {
        raw, kind, id: text(first(raw.id, raw.messageId, raw.ruleId, raw.recipientId)),
        title: text(kind === 'drafts' ? first(raw.subject, raw.subjectLine, 'Untitled draft') : kind === 'rules' ? first(raw.name, 'Unnamed rule') : kind === 'recipients' ? first(raw.name, raw.displayName, raw.display_name, raw.email, 'Recipient') : first(raw.eventType, raw.event_type, raw.type, 'Email activity')).replaceAll('_', ' '),
        email: text(first(raw.recipientEmail, raw.recipient_email, raw.to_email, raw.email, raw.to)),
        body: text(first(raw.textBody, raw.text_body, raw.body, raw.textTemplate, raw.text_template)),
        status: kind === 'rules' ? (raw.completedAt ? 'completed' : !enabled ? 'paused' : mode === 'autopilot' && !preapproved ? 'needs approval' : mode === 'autopilot' ? 'autopilot' : 'draft only') : status || 'unknown',
        at: first(raw.createdAt, raw.created_at, raw.occurredAt, raw.occurred_at),
        next: first(raw.nextRunAt, raw.next_run_at),
        zone: text(first(raw.scheduleTimezone, raw.schedule_timezone)),
        enabled, preapproved, active, mode,
        issue: failed(status) || (kind === 'rules' && enabled && mode === 'autopilot' && !preapproved),
        needsReview: review(status),
      };
    });
  }
  function select(rows, {query = '', filter = 'all', sort = 'newest', page = 0, pageSize = 12} = {}) {
    const words = text(query).toLowerCase().split(/\s+/).filter(Boolean);
    const selected = rows.filter(row => {
      const haystack = `${row.title} ${row.email} ${row.body} ${row.status} ${row.zone}`.toLowerCase();
      if (!words.every(word => haystack.includes(word))) return false;
      return filter === 'all' || (filter === 'review' && row.needsReview) ||
        (filter === 'issues' && row.issue) || (filter === 'approved' && row.status === 'approved') ||
        (filter === 'sent' && delivered(row.status)) || (filter === 'active' && (row.kind === 'rules' ? row.enabled && !row.raw.completedAt : row.active && !['unsubscribed', 'suppressed'].includes(row.status))) ||
        (filter === 'paused' && row.status === 'paused') || (filter === 'restricted' && (!row.active || ['unsubscribed', 'suppressed'].includes(row.status)));
    }).sort((a, b) => sort === 'name' ? a.title.localeCompare(b.title) : sort === 'oldest' ? time(a.at) - time(b.at) : sort === 'next' ? (time(a.next) || Infinity) - (time(b.next) || Infinity) : time(b.at) - time(a.at));
    const pages = Math.max(1, Math.ceil(selected.length / pageSize));
    const current = Math.max(0, Math.min(page, pages - 1));
    return {rows: selected.slice(current * pageSize, (current + 1) * pageSize), total: selected.length, page: current, pages};
  }
  function summary(app, now = Date.now()) {
    const drafts = records(app, 'drafts'), rules = records(app, 'rules'), events = records(app, 'events');
    const upcoming = rules.filter(r => r.enabled && !r.raw.completedAt && time(r.next) > 0).sort((a,b) => time(a.next) - time(b.next))[0];
    return {
      review: drafts.filter(d => d.needsReview).length,
      issues: drafts.filter(d => d.issue).length,
      rules: rules.filter(r => r.enabled && !r.raw.completedAt).length,
      recentIssues: events.filter(e => e.issue && time(e.at) >= now - 86400000).length,
      upcoming,
    };
  }
  return Object.freeze({text, first, bool, time, failed, review, escape, records, select, summary});
});
