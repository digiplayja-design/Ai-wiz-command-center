/* Report conversations alongside the existing Email Center. */
(() => {
  'use strict';
  const M = window.KorlixAutomatedSupport, h = M.escape;
  const state = {scope:'',profiles:[],profileId:'',filter:'',query:'',cases:[],detail:null,messages:[],loading:false,busy:false,error:'',revision:0};
  const scope = () => {
    const claims = decodeJwtPayload(APP.token) || {};
    return APP.token && claims.sub && Number(claims.exp)*1000>Date.now()
      ? `${claims.iss || ''}|${claims.sub}|${claims.session_id || ''}|${APP.apiBase}` : '';
  };
  const api = M.client((path,options)=>requestJson(path,options),scope);
  const selected = () => state.profiles.find(p=>p.id===state.profileId);
  const date = value => Number.isFinite(Date.parse(value)) ? new Intl.DateTimeFormat(undefined,{dateStyle:'medium',timeStyle:'short'}).format(new Date(value)) : 'Time unavailable';
  const explain = error => error?.status===404 ? 'Automated support is awaiting setup for this workspace.' : error?.status===503 ? 'Support is temporarily unavailable or its setup is incomplete. Refresh to check again.' : [401,403].includes(error?.status) ? 'Sign in with an account that manages this support address.' : 'Support could not complete this request. Refresh to check the latest status before trying again.';
  let returnFocus = null;
  function reset() {
    state.revision++;state.profiles=[];state.profileId='';state.cases=[];state.detail=null;state.messages=[];state.error='';state.loading=false;state.busy=false;
    document.getElementById('supportCaseDialog')?.close();
    const body=document.getElementById('supportCaseBody');if(body)body.replaceChildren();
    const notice=document.getElementById('supportCaseNotice');if(notice)notice.textContent='';
  }
  function create() {
    if (document.getElementById('automatedSupport')) return;
    const panel=document.createElement('section');panel.id='automatedSupport';panel.className='panel support-workspace';
    panel.innerHTML=`<div class="support-heading"><div><span class="studio-eyebrow">KORLIX / AUTOMATED SUPPORT</span><h2>Every report. A clear next step.</h2><p>Give customers a helpful first response and keep every conversation with its support address.</p></div><button class="button button-secondary" id="supportRefresh">Refresh support</button></div><p class="support-status-note" id="supportStatus" role="status"></p><div id="supportProfileControls"></div><div class="support-filters" role="group" aria-label="Filter support cases">${[['','All cases'],...Object.entries(M.states)].map(([value,label])=>`<button data-support-filter="${h(value)}" aria-pressed="${value===''}">${h(label)}</button>`).join('')}</div><label><span class="studio-note">Search loaded cases</span><input type="search" class="support-search" id="supportSearch" placeholder="Subject, customer address, or details…" autocomplete="off"></label><div id="supportCaseList"></div><p class="studio-note">The list shows the most recent cases returned by the support service. Dates use your device’s time zone.</p>`;
    const anchor=document.getElementById('emailWorkspace')||document.querySelector('.top-header');anchor.after(panel);
    const nav=document.createElement('button');nav.className='nav-item';nav.dataset.supportNav='';nav.innerHTML='<span class="nav-icon" aria-hidden="true">◌</span><span>Automated Support</span>';
    document.querySelector('.navigation')?.append(nav);
    document.addEventListener('click',e=>{const item=e.target.closest('.nav-item');if(item&&item!==nav)nav.classList.remove('active');},true);
    nav.addEventListener('click',()=>{document.querySelectorAll('.nav-item').forEach(b=>b.classList.toggle('active',b===nav));closeMobileSidebar();panel.scrollIntoView({behavior:matchMedia('(prefers-reduced-motion: reduce)').matches?'auto':'smooth'});if(!state.profiles.length&&!state.loading)void load();});
    const dialog=document.createElement('dialog');dialog.id='supportCaseDialog';dialog.className='studio-dialog support-dialog';
    dialog.innerHTML='<div class="studio-dialog-header"><span class="studio-eyebrow">SUPPORT CONVERSATION</span><button class="button button-secondary" id="supportClose" aria-label="Close support case">✕</button></div><div id="supportCaseBody"></div><p id="supportCaseNotice" class="support-status-note" role="status"></p>';
    document.body.append(dialog);
    document.getElementById('supportClose').onclick=()=>dialog.close();
    dialog.addEventListener('close',()=>{state.detail=null;state.messages=[];returnFocus?.focus();});
    document.getElementById('supportRefresh').onclick=()=>void load();
    document.getElementById('supportSearch').oninput=e=>{state.query=e.target.value;renderCases();};
    panel.addEventListener('change',e=>{if(e.target.id==='supportProfile'){state.profileId=e.target.value;state.cases=[];state.detail=null;dialog.close();renderProfiles();void loadCases();}});
    panel.addEventListener('click',e=>{
      const filter=e.target.closest('[data-support-filter]');if(filter){state.filter=filter.dataset.supportFilter;void loadCases();}
      const row=e.target.closest('[data-support-case]');if(row){returnFocus=row;void openCase(row.dataset.supportCase);}
      if(e.target.id==='supportSaveMode')void changeMode();
    });
    dialog.addEventListener('click',e=>{
      const action=e.target.closest('[data-support-action]')?.dataset.supportAction;if(!action||state.busy||!state.detail)return;
      if(action==='pause')void updateCase(()=>api.pause(state.detail.id,!state.detail.automationPaused),'Case automation updated.');
      if(action==='status')void changeStatus();
      if(action==='reply')void sendReply();
      if(action==='draft'){const message=state.messages.find(m=>m.id===e.target.closest('[data-support-action]').dataset.messageId);if(message){document.getElementById('supportReply').value=message.text||'';document.getElementById('supportReply').focus();}}
    });
    render();synchronize();
  }
  function renderProfiles() {
    const p=selected();
    document.getElementById('supportProfileControls').innerHTML=state.profiles.length?`<div class="support-controls"><label>Support address<select id="supportProfile" ${state.busy?'disabled':''}>${state.profiles.map(row=>`<option value="${h(row.id)}" ${row.id===state.profileId?'selected':''}>${h(row.displayName)} · ${h(row.fromEmail)}</option>`).join('')}</select></label><label>Response mode<select id="supportMode" ${state.busy?'disabled':''}>${Object.entries(M.modes).map(([value,label])=>`<option value="${value}" ${p?.mode===value?'selected':''} ${value==='automatic'&&!p?.ready?'disabled':''}>${label}</option>`).join('')}</select></label><button class="button button-secondary" id="supportSaveMode" ${state.busy?'disabled':''}>Save mode</button></div>${p?`<div class="support-address"><dl><div><dt>Customers receive emails from</dt><dd>${h(p.fromEmail||'Address setup pending')}</dd></div><div><dt>Customer replies go to</dt><dd>${h(p.replyTo||'Reply address setup pending')}</dd></div></dl><p>${p.ready?'Sending and replies are ready for this profile.':'This address needs setup before automatic replies can be enabled.'} · ${h(M.modes[p.mode])}${p.dailyCap?` · Up to ${h(p.dailyCap)} support emails per day`:''}</p></div>`:''}`:'';
  }
  function renderCases() {
    const available=Boolean(scope()&&scope()===state.scope);
    document.querySelectorAll('[data-support-filter]').forEach(b=>{b.setAttribute('aria-pressed',b.dataset.supportFilter===state.filter);b.disabled=state.loading||!selected();});
    const cases=available?M.cases(state.cases,state.profileId,state.query):[];
    document.getElementById('supportCaseList').innerHTML=!available?'<div class="studio-empty"><strong>Sign in to view your support workspace.</strong><p>Each account sees only its own enrolled support addresses.</p></div>':state.loading?'<div class="studio-empty" role="status">Loading support cases…</div>':state.error?'<div class="studio-empty"><strong>Support information is unavailable.</strong><p>Use Refresh support to try again.</p></div>':!state.profiles.length?'<div class="studio-empty"><strong>No support addresses are enrolled yet.</strong><p>Connect an approved support address to begin. Each address keeps its own settings and conversations.</p></div>':!cases.length?'<div class="studio-empty"><strong>No cases in this view.</strong><p>Choose another status or search.</p></div>':cases.map(c=>`<button class="studio-mail-row" data-support-case="${h(c.id)}"><span class="studio-row-icon" aria-hidden="true">◌</span><span class="studio-row-copy"><strong>${h(c.subject||'Customer report')}</strong><span>${h(c.reporterEmail||'Contact unavailable')}</span><span>${h(M.text(c.summary||c.details).slice(0,140))}</span><small>${h(date(c.updatedAt||c.createdAt))}${c.automationPaused?' · Automation paused':''}</small></span><span class="studio-badge ${c.state==='needs_review'?'issue':''}">${h(M.states[c.state]||'Needs review')}</span></button>`).join('');
  }
  function render() {
    if(!document.getElementById('automatedSupport'))return;
    document.getElementById('supportStatus').textContent=state.error||(state.loading?'Loading your support workspace…':'');
    document.getElementById('supportRefresh').disabled=state.loading||state.busy;
    renderProfiles();renderCases();
  }
  async function load() {
    if(state.busy||state.loading)return;
    const active=scope();if(!active){reset();state.scope='';render();return;}
    state.scope=active;const revision=++state.revision;state.loading=true;state.error='';state.cases=[];render();
    try {
      const response=await api.profiles();if(revision!==state.revision||scope()!==active)return;
      state.profiles=M.profiles(response.profiles);if(!selected())state.profileId=state.profiles[0]?.id||'';
      if(state.profileId){const result=await api.cases(state.profileId,state.filter);if(revision!==state.revision||scope()!==active)return;state.cases=M.rows(result.cases);}
    }catch(error){if(revision===state.revision&&scope()===active){state.error=explain(error);state.profiles=[];state.cases=[];}}
    finally{if(revision===state.revision){state.loading=false;render();}}
  }
  async function loadCases() {
    if(!selected()||state.busy)return;
    const active=scope(),profileId=state.profileId,revision=++state.revision;state.loading=true;state.error='';state.cases=[];renderCases();
    try {const result=await api.cases(profileId,state.filter);if(revision===state.revision&&scope()===active&&profileId===state.profileId)state.cases=M.rows(result.cases);}
    catch(error){if(revision===state.revision&&scope()===active)state.error=explain(error);}
    finally{if(revision===state.revision){state.loading=false;render();}}
  }
  function renderDetail() {
    const c=state.detail,p=selected();if(!c)return;const mayReply=M.canReply(p,c);
    document.getElementById('supportCaseBody').innerHTML=`<h2>${h(c.subject||'Customer report')}</h2><p>${h(c.reporterEmail||'Contact unavailable')}</p><p class="support-case-ref">Case ${h(c.id)}</p><span class="studio-badge">${h(M.states[c.state]||'Needs review')}</span><p class="support-detail-summary">${h(c.details||c.summary||'')}</p><p class="studio-note">${h([c.appArea,c.appVersion,c.platform].filter(Boolean).join(' · '))}</p><div class="support-case-controls"><label>Status<select id="supportCaseState">${Object.entries(M.states).map(([value,label])=>`<option value="${value}" ${c.state===value?'selected':''}>${label}</option>`).join('')}</select></label><button class="button button-secondary" data-support-action="status">Update status</button><button class="button button-secondary" data-support-action="pause">${c.automationPaused?'Resume case automation':'Take over · pause automation'}</button></div><div aria-label="Conversation history">${state.messages.length?state.messages.map(m=>`<article class="support-message ${m.direction==='outbound'?'outbound':''}"><header><span>${m.direction==='outbound'?'KORLIX support':'Customer'} · ${h(m.status||'Recorded')}</span><time>${h(date(m.createdAt))}</time></header><p>${h(m.text||'')}</p>${M.rows(m.attachments).length?`<p class="studio-note">Attachments: ${M.rows(m.attachments).map(a=>h(a.filename||a.name||'Attachment')).join(', ')}</p>`:''}${m.kind==='acknowledgment'&&m.status==='pending'?`<button class="button button-secondary" data-support-action="draft" data-message-id="${h(m.id)}">Use this draft</button>`:''}</article>`).join(''):'<p class="studio-note">No email messages recorded yet.</p>'}</div><label class="support-reply">Reply to ${h(c.reporterEmail||'the reporting customer')}<textarea id="supportReply" maxlength="12000" placeholder="Write a helpful response…"></textarea></label><p class="studio-note">From ${h(p?.fromEmail||'the selected support address')}. Your reply is addressed to this case’s customer.</p><button class="button button-primary" data-support-action="reply" ${mayReply?'':'disabled'}>Review reply</button>${!mayReply?`<p class="studio-note">${c.state==='resolved'?'Reopen this case before replying.':c.reporterVerified!==true?'The customer’s email needs verification before replying.':'Complete this support address setup before sending replies.'}</p>`:''}`;
    document.getElementById('supportCaseNotice').textContent='';
  }
  async function openCase(caseId) {
    if(state.busy||scope()!==state.scope)return;
    const active=scope(),profileId=state.profileId;state.busy=true;render();
    try {const result=await api.detail(caseId);if(scope()!==active||profileId!==state.profileId)return;if(result.case?.profileId!==profileId)throw new Error('Support profile changed.');state.detail=result.case;state.cases=state.cases.map(row=>row.id===caseId?result.case:row);state.messages=M.rows(result.messages);renderDetail();const dialog=document.getElementById('supportCaseDialog');if(!dialog.open)dialog.showModal();}
    catch(error){if(scope()===active){state.error=explain(error);}}
    finally{if(scope()===active){state.busy=false;render();}}
  }
  async function changeMode() {
    const p=selected(),mode=document.getElementById('supportMode')?.value;if(!p||state.busy)return;
    if(mode==='automatic'&&!confirm(`Enable automatic support for ${p.fromEmail}? New eligible reports can receive responses within this profile’s limits.`))return;
    const active=scope();state.busy=true;render();
    try {await api.mode(p,mode);if(scope()!==active)return;state.busy=false;await load();}
    catch(error){if(scope()===active){state.error=explain(error);}}
    finally{if(scope()===active){state.busy=false;render();}}
  }
  async function updateCase(action,notice) {
    if(!state.detail||state.busy||scope()!==state.scope)return;
    const active=scope(),caseId=state.detail.id;state.busy=true;
    document.querySelectorAll('[data-support-action]').forEach(b=>b.disabled=true);
    try {await action();if(scope()!==active)return;state.busy=false;await openCase(caseId);if(scope()===active)document.getElementById('supportCaseNotice').textContent=notice;}
    catch(error){if(scope()===active)document.getElementById('supportCaseNotice').textContent=explain(error);}
    finally{if(scope()===active){state.busy=false;document.querySelectorAll('[data-support-action]').forEach(b=>b.disabled=b.dataset.supportAction==='reply'&&!M.canReply(selected(),state.detail));render();}}
  }
  async function changeStatus() {
    const c=state.detail,stateValue=document.getElementById('supportCaseState')?.value;if(!c)return;
    let note='';if(stateValue==='resolved'){note=prompt('What confirmed that this issue is resolved?')||'';if(!note.trim())return;}
    await updateCase(()=>api.status(c.id,stateValue,note),'Case status updated.');
  }
  async function sendReply() {
    const c=state.detail,value=document.getElementById('supportReply')?.value||'';if(!c||!value.trim()||!M.canReply(selected(),c))return;
    if(!confirm(`Queue this reply to ${c.reporterEmail} from ${selected().fromEmail}?\n\n${value}`))return;
    await updateCase(()=>api.reply(c.id,value),'Reply recorded. Check its message status for sending progress.');
  }
  function synchronize() {
    const current=scope();if(current!==state.scope){reset();state.scope=current;render();if(current)void load();}
  }
  const originalConnection=setConnectedState;setConnectedState=function(...args){const result=originalConnection(...args);synchronize();return result;};
  const originalRender=renderDashboard;renderDashboard=function(...args){const result=originalRender(...args);synchronize();return result;};
  // Account changes discard private case data even while another panel is open.
  setInterval(synchronize,1000);
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',create,{once:true});else create();
})();
