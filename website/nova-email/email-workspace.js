/* KORLIX Email Studio: read/review queues using the existing approved email API. */
(() => {
  'use strict';
  const M = window.KorlixEmailWorkspace, h = M.escape;
  const state = {kind: 'drafts', filter: 'all', sort: 'newest', query: '', page: 0, busy: false};
  const labels = {drafts: 'Drafts', recipients: 'Recipients', rules: 'Automation', events: 'Activity'};
  const filters = {drafts: [['all','All drafts'],['review','Needs review'],['approved','Approved'],['issues','Issues'],['sent','Sent']], recipients: [['all','All recipients'],['active','Eligible'],['restricted','Restricted']], rules: [['all','All rules'],['active','Enabled'],['paused','Paused'],['issues','Needs approval']], events: [['all','All activity'],['issues','Delivery issues']]};
  let previousFocus = null, detail = null, detailScope = '';
  const scope = () => {
    const p = decodeJwtPayload(APP.token) || {};
    return `${p.iss || ''}|${p.sub || ''}|${p.session_id || ''}|${APP.agentId || ''}|${APP.apiBase || ''}`;
  };
  const when = value => M.time(value) ? new Intl.DateTimeFormat(undefined, {dateStyle:'medium',timeStyle:'short'}).format(new Date(value)) : 'Not available';
  const go = id => document.getElementById(id)?.scrollIntoView({behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'start'});
  function create() {
    if (document.getElementById('emailWorkspace')) return;
    const section = document.createElement('section');
    section.id = 'emailWorkspace'; section.className = 'email-workspace';
    section.innerHTML = `
      <div class="email-hero"><div><span class="studio-eyebrow">KORLIX / EMAIL STUDIO</span><h2>Thoughtful emails.<br>Effortless oversight.</h2><p>From your first draft to the next follow-up.<br>Give every message a clear path forward.</p><div class="studio-hero-actions"><button class="button button-primary" data-studio-action="compose">＋ Compose email</button><button class="button button-secondary" data-studio-action="templates">Templates & rules ↗</button></div></div><div class="mail-sculpture" aria-hidden="true"><div class="mail-orbit"></div><div class="mail-plane"><span>✉</span><i></i></div><span class="mail-node one"></span><span class="mail-node two"></span><span class="mail-node three"></span></div></div>
      <div class="studio-metrics" id="emailStudioMetrics"></div>
      <div class="studio-queue panel"><div class="studio-queue-heading"><div><span class="studio-eyebrow">YOUR WORKSPACE</span><h2>Keep things moving.</h2></div><span id="emailStudioFreshness" class="studio-note"></span></div>
      <div class="studio-tabs" role="group" aria-label="Email work queues">${Object.entries(labels).map(([key,label]) => `<button data-studio-kind="${key}" aria-pressed="${key === state.kind}">${label}</button>`).join('')}</div>
      <div class="studio-toolbar"><label class="studio-search"><span>Search this queue</span><input id="emailQueueSearch" type="search" placeholder="Subject, name, address, or phrase…" autocomplete="off"></label><label><span>Show</span><select id="emailQueueFilter"></select></label><label><span>Sort</span><select id="emailQueueSort"><option value="newest">Newest first</option><option value="oldest">Oldest first</option><option value="name">Name A–Z</option><option value="next">Next scheduled</option></select></label></div>
      <div class="studio-queue-meta"><span id="emailQueueCount" role="status"></span><button class="button button-secondary" id="emailQueuePrimary" data-studio-action="primary">Compose email</button><button class="button button-secondary" id="emailQueueDelete" data-studio-action="delete-drafts">Delete drafts</button><button class="small-action" data-studio-action="reset">Clear filters</button></div><div id="emailQueueRows"></div>
      <div class="studio-pagination"><button class="button button-secondary" id="emailQueuePrevious">← Previous</button><span id="emailQueuePage"></span><button class="button button-secondary" id="emailQueueNext">Next →</button></div>
      <p class="studio-note">Search covers up to 100 loaded records per queue. Refresh to fetch the latest changes.</p></div>
      <div class="studio-readiness panel"><div><span class="studio-eyebrow">AUTONOMOUS EMAIL</span><h2>Know what happens next.</h2><p>Enabled rules follow your approved message, recipients, timing, and sending limits.</p></div><div id="emailStudioReadiness"></div><div class="studio-hero-actions"><button class="button button-secondary" data-studio-action="schedule">View schedules</button><button class="button button-secondary" data-studio-action="settings">Sending controls</button></div></div>`;
    document.querySelector('.top-header').after(section);
    const dialog = document.createElement('dialog'); dialog.id = 'emailStudioDetail'; dialog.className = 'studio-dialog';
    dialog.innerHTML = '<div class="studio-dialog-header"><span class="studio-eyebrow">EMAIL STUDIO</span><button class="button button-secondary" id="emailStudioClose" aria-label="Close details">✕</button></div><div id="emailStudioDetailBody"></div><div class="studio-detail-actions" id="emailStudioDetailActions"></div><p role="status" id="emailStudioDetailMessage"></p>';
    document.body.append(dialog);
    document.getElementById('emailStudioClose').onclick = () => dialog.close();
    dialog.addEventListener('close', () => { detail = null; previousFocus?.focus(); });
    dialog.addEventListener('click', e => { if (e.target === dialog && !dialog.querySelector('.studio-dialog-header').contains(e.target)) { const rect = dialog.getBoundingClientRect(); if (e.clientX < rect.left || e.clientX > rect.right || e.clientY < rect.top || e.clientY > rect.bottom) dialog.close(); } });
    document.getElementById('emailQueueSearch').oninput = e => { state.query = e.target.value; state.page = 0; renderRows(); };
    document.getElementById('emailQueueFilter').onchange = e => { state.filter = e.target.value; state.page = 0; renderRows(); };
    document.getElementById('emailQueueSort').onchange = e => { state.sort = e.target.value; state.page = 0; renderRows(); };
    document.getElementById('emailQueuePrevious').onclick = () => { state.page--; renderRows(); };
    document.getElementById('emailQueueNext').onclick = () => { state.page++; renderRows(); };
    section.addEventListener('click', e => {
      const kind = e.target.closest('[data-studio-kind]');
      if (kind) selectKind(kind.dataset.studioKind);
      const action = e.target.closest('[data-studio-action]')?.dataset.studioAction;
      if (action === 'compose') els.createDraftButton.click();
      if (action === 'delete-drafts') document.getElementById('k134bManageDraftsButton')?.click();
      if (action === 'primary') {
        if (state.kind === 'drafts') els.createDraftButton.click();
        if (state.kind === 'recipients') document.getElementById('manageRecipientsButton').click();
        if (state.kind === 'rules') document.querySelector('[data-section="templates"]').click();
        if (state.kind === 'events') els.refreshButton.click();
      }
      if (action === 'templates') document.querySelector('[data-section="templates"]').click();
      if (action === 'schedule') go('scheduledEmailsPanel');
      if (action === 'settings') go('commandPanel');
      if (action === 'reset') { state.query = ''; state.filter = 'all'; state.page = 0; document.getElementById('emailQueueSearch').value = ''; renderFilters(); renderRows(); }
      const index = e.target.closest('[data-studio-row]')?.dataset.studioRow;
      if (index !== undefined) openRecord(Number(index), e.target.closest('button'));
      const metric = e.target.closest('[data-studio-metric]')?.dataset.studioMetric;
      if (metric) { selectKind(metric === 'rules' ? 'rules' : metric === 'events' ? 'events' : 'drafts'); state.filter = metric === 'review' ? 'review' : metric === 'rules' ? 'active' : 'issues'; renderFilters(); renderRows(); go('emailQueueSearch'); }
    });
    document.getElementById('emailStudioDetailActions').addEventListener('click', async e => {
      const action = e.target.closest('[data-detail-action]')?.dataset.detailAction;
      if (!action || !detail || state.busy || scope() !== detailScope || !APP.connected) return;
      if (action === 'copy') {
        try { await navigator.clipboard.writeText(detail.email || detail.body); message('Copied.'); } catch { message('Copy unavailable. Select and copy the text above.'); }
      }
      if (action === 'rule') await toggleRule();
      if (action === 'suppress') await suppressRecipient();
      if (action === 'compose') {
        const row = detail; dialog.close();
        els.draftSubjectInput.value = row.raw.subjectTemplate || row.title; els.draftBodyInput.value = row.body; els.draftRecipientInput.value = ''; els.draftTransactionalInput.checked = false;
        els.createDraftButton.click();
      }
    });
    document.addEventListener('click', e => {
      const nav = e.target.closest('.nav-item');
      const kind = {drafts:'drafts', recipients:'recipients', logs:'events'}[nav?.dataset.section];
      if (!kind) return;
      e.preventDefault(); e.stopImmediatePropagation();
      document.querySelectorAll('.nav-item').forEach(n => n.classList.toggle('active', n === nav));
      selectKind(kind); closeMobileSidebar(); go('emailWorkspace');
    }, true);
    renderFilters(); render();
  }
  function selectKind(kind) {
    state.kind = kind; state.filter = 'all'; state.page = 0;
    document.querySelectorAll('[data-studio-kind]').forEach(b => b.setAttribute('aria-pressed', b.dataset.studioKind === kind));
    renderFilters(); renderRows();
  }
  function renderFilters() {
    document.getElementById('emailQueueFilter').innerHTML = filters[state.kind].map(([v,l]) => `<option value="${v}" ${v === state.filter ? 'selected' : ''}>${l}</option>`).join('');
  }
  let displayed = [];
  function renderRows() {
    const selection = M.select(M.records(APP, state.kind), state); displayed = selection.rows; state.page = selection.page;
    document.getElementById('emailQueuePrimary').textContent = {drafts:'Compose email',recipients:'Add recipient',rules:'Manage rules',events:'Refresh activity'}[state.kind];
    document.getElementById('emailQueueDelete').hidden = state.kind !== 'drafts';
    const unavailable = !APP.connected || APP.workspaceStale || APP.panelErrors?.[state.kind];
    document.getElementById('emailQueueCount').textContent = unavailable ? 'Data unavailable' : `${selection.total} matching ${labels[state.kind].toLowerCase()} records`;
    document.getElementById('emailQueueRows').innerHTML = unavailable ? '<div class="studio-empty"><strong>Connect or refresh to load this queue.</strong><p>Records could not be loaded. Existing saved data is unchanged.</p></div>' : displayed.length ? displayed.map((r,i) => `<button class="studio-mail-row" data-studio-row="${i}"><span class="studio-row-icon" aria-hidden="true">${{drafts:'✉',rules:'◷',recipients:'◎',events:'↗'}[state.kind]}</span><span class="studio-row-copy"><strong>${h(r.title)}</strong><span>${h(r.email || (r.next ? `Next: ${when(r.next)}` : r.body.slice(0,110) || 'View details'))}</span><small>${h(when(r.at))}</small></span><span class="studio-badge ${r.issue ? 'issue' : r.needsReview ? 'review' : ''}">${h(r.status.replaceAll('_',' '))}</span><span class="studio-row-arrow" aria-hidden="true">↗</span></button>`).join('') : '<div class="studio-empty"><strong>Nothing in this view yet.</strong><p>Try another search or clear your filters.</p></div>';
    document.getElementById('emailQueuePage').textContent = `${selection.page+1} / ${selection.pages}`;
    document.getElementById('emailQueuePrevious').disabled = state.page === 0;
    document.getElementById('emailQueueNext').disabled = state.page + 1 >= selection.pages;
  }
  function render() {
    if (!document.getElementById('emailWorkspace')) return;
    const summary = M.summary(APP);
    const connected = APP.connected && !APP.workspaceStale;
    const metric = (key, kind, number, label, detail) => `<button class="studio-metric" data-studio-metric="${key}"><span>${label}</span><strong>${!APP.connected || APP.workspaceStale || APP.panelErrors?.[kind] ? '—' : number}</strong><small>${detail} ↗</small></button>`;
    document.getElementById('emailStudioMetrics').innerHTML = metric('review','drafts',summary.review,'Needs your review','Open draft queue') + metric('issues','drafts',summary.issues,'Draft issues','Review before retrying') + metric('rules','rules',summary.rules,'Enabled rules','See approved scope') + metric('events','events',summary.recentIssues,'Delivery issues · 24h','View activity');
    document.getElementById('emailStudioFreshness').textContent = connected && APP.workspaceUpdatedAt ? `Updated ${when(APP.workspaceUpdatedAt)}` : 'Waiting for a connection';
    const s = APP.settings || {}, status = statusRoot(APP.statusPayload), enabled = M.bool(M.first(s.enabled, status.enabled));
    const paused = M.bool(M.first(s.paused, s.emergencyPaused, status.paused, true));
    const mode = M.text(M.first(s.mode, s.operatingMode, status.mode, 'draft_only'));
    const cap = M.first(s.dailySendCap, s.daily_send_cap, status.dailySendCap);
    const blocks = !connected ? 'Connect your KORLIX account to inspect sending controls.' : !enabled ? 'Email is disabled. Review sending controls when you are ready.' : paused ? 'Sending is paused. Enabled rules remain saved.' : mode === 'autopilot' ? 'Autopilot mode selected. Sends still depend on rule approval, recipient eligibility, limits, and provider availability.' : 'Approval required. Review each draft before sending.';
    document.getElementById('emailStudioReadiness').innerHTML = `<p class="studio-readiness-status">${h(blocks)}</p><dl><div><dt>Next scheduled rule</dt><dd>${h(summary.upcoming ? `${summary.upcoming.title} · ${when(summary.upcoming.next)}${summary.upcoming.zone ? ' · schedule zone: ' + summary.upcoming.zone : ''}` : APP.panelErrors?.rules || !connected ? 'Unavailable' : 'No scheduled run in loaded rules')}</dd></div><div><dt>Daily send limit</dt><dd>${h(connected && cap !== '' ? cap : 'Unavailable')}</dd></div><div><dt>Time display</dt><dd>Dates use your device’s time zone.</dd></div></dl>`;
    if (detail && (!APP.connected || scope() !== detailScope)) document.getElementById('emailStudioDetail').close();
    renderRows();
  }
  function message(value) { document.getElementById('emailStudioDetailMessage').textContent = value; }
  function openRecord(index, button) {
    const row = displayed[index]; if (!row || !APP.connected || APP.workspaceStale) return;
    if (row.kind === 'drafts') { openDraftDetails(row.id); return; }
    detail = row; detailScope = scope(); previousFocus = button;
    const raw = row.raw;
    const recipients = (raw.recipientIds || []).map(id => APP.recipients.find(r => String(r.id) === String(id))).filter(Boolean).map(r => r.email).join(', ');
    document.getElementById('emailStudioDetailBody').innerHTML = `<h2>${h(row.title)}</h2><span class="studio-badge">${h(row.status)}</span>${row.email ? `<p>${h(row.email)}</p>` : ''}${row.kind === 'rules' ? `<dl><dt>Approved recipients</dt><dd>${h(recipients || 'Recipient details unavailable')}</dd><dt>Subject</dt><dd>${h(raw.subjectTemplate || 'Not provided')}</dd><dt>Next scheduled run</dt><dd>${h(when(row.next))}</dd><dt>Schedule time zone</dt><dd>${h(row.zone || 'Event based')}</dd><dt>Daily limit</dt><dd>${h(raw.maxSendsPerDay ?? 'Unavailable')}</dd><dt>Trigger</dt><dd>${h(raw.triggerKey)}</dd></dl>` : ''}${row.body ? `<pre>${h(row.body)}</pre>` : ''}${row.kind === 'events' ? `<p>${h(when(row.at))}</p><p>${h(raw.detail || raw.description || raw.failureMessage || raw.failure_message || 'Activity recorded by the email service.')}</p>` : ''}`;
    document.getElementById('emailStudioDetailActions').innerHTML = `${row.email ? '<button class="button button-secondary" data-detail-action="copy">Copy address</button>' : ''}${row.kind === 'rules' && !raw.completedAt ? `<button class="button button-secondary" data-detail-action="rule" ${!row.enabled && row.mode === 'autopilot' && !row.preapproved ? 'disabled' : ''}>${row.enabled ? 'Pause rule' : 'Resume rule'}</button>` : ''}${row.kind === 'rules' && row.body ? '<button class="button button-secondary" data-detail-action="compose">Use message in a new draft</button>' : ''}${row.kind === 'recipients' && row.active && !['suppressed','unsubscribed'].includes(row.status) ? '<button class="button button-warning" data-detail-action="suppress">Suppress recipient</button>' : ''}`;
    message(''); document.getElementById('emailStudioDetail').showModal();
  }
  async function mutation(path, body, success) {
    if (!detail || state.busy || scope() !== detailScope) return;
    const activeScope = detailScope; state.busy = true;
    document.querySelectorAll('[data-detail-action]').forEach(b => b.disabled = true);
    try {
      await requestJson(`${emailBase()}${path}`, {method:'PATCH',body:JSON.stringify(body)});
      if (scope() !== activeScope) return;
      document.getElementById('emailStudioDetail').close(); toast(success, 'success'); await refreshDashboard({silent:true});
    } catch (e) { if (scope() === activeScope) message(e.message || 'The change could not be saved. Refresh and try again.'); }
    finally { state.busy = false; document.querySelectorAll('[data-detail-action]').forEach(b => b.disabled = false); }
  }
  async function toggleRule() {
    const row = detail;
    if (!row || (!row.enabled && row.mode === 'autopilot' && !row.preapproved)) return;
    if (!confirm(row.enabled ? `Pause “${row.title}”? Future matching sends will pause. A send already in progress may finish.` : `Resume “${row.title}”? It will become eligible at the next matching event or scheduled time, within its approved scope and sending controls.`)) return;
    await mutation(`/rules/${encodeURIComponent(row.id)}`, {confirmed:true,enabled:!row.enabled}, row.enabled ? 'Rule paused.' : 'Rule resumed.');
  }
  async function suppressRecipient() {
    const row = detail, reason = prompt(`Why should email to ${detail.email} be suppressed?`);
    if (!reason?.trim()) return;
    if (!confirm(`Suppress ${row.email}? Future sends to this recipient will be blocked.`)) return;
    await mutation(`/recipients/${encodeURIComponent(row.id)}`, {confirmed:true,status:'suppressed',suppressionReason:reason.trim().slice(0,500)}, 'Recipient suppressed.');
  }
  const originalRender = renderDashboard;
  renderDashboard = function(...args) { const result = originalRender(...args); render(); return result; };
  const originalConnection = setConnectedState;
  setConnectedState = function(...args) { const result = originalConnection(...args); render(); return result; };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', create, {once:true}); else create();
})();
