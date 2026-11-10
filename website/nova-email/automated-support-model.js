/* Owner-scoped support requests. The server selects addresses and recipients. */
(function (root, factory) {
  const model = factory();
  if (typeof module === 'object' && module.exports) module.exports = model;
  else root.KorlixAutomatedSupport = model;
})(typeof globalThis !== 'undefined' ? globalThis : this, () => {
  'use strict';
  const states = Object.freeze({new:'New',waiting_for_customer:'Waiting for customer',needs_review:'Needs review',resolved:'Resolved'});
  const modes = Object.freeze({paused:'Paused',draft:'Draft for review',automatic:'Automatic'});
  const text = value => String(value ?? '').trim();
  const escape = value => text(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const rows = value => Array.isArray(value) ? value.filter(row => row && typeof row === 'object') : [];
  const canReply = (profile,record) => profile?.ready === true && record?.reporterVerified === true && record?.state !== 'resolved';
  const id = value => { const result = text(value); if (!result || result.length > 160) throw new Error('Choose a saved support record.'); return encodeURIComponent(result); };
  function profiles(value) {
    return rows(value).filter(p => p.id).map(p => ({...p,id:text(p.id),displayName:text(p.displayName)||'Support',fromEmail:text(p.fromEmail),replyTo:text(p.replyTo),mode:Object.hasOwn(modes,p.mode)?p.mode:'paused',ready:p.ready===true,senderVerified:p.senderVerified===true,receivingVerified:p.receivingVerified===true}));
  }
  function cases(value, profileId, query = '') {
    const words = text(query).toLowerCase().split(/\s+/).filter(Boolean);
    return rows(value).filter(c => text(c.profileId) === text(profileId) && c.id).filter(c => {
      const haystack = `${text(c.subject)} ${text(c.summary || c.details)} ${text(c.reporterEmail)}`.toLowerCase();
      return words.every(word => haystack.includes(word));
    });
  }
  function client(request, scope) {
    async function call(path, options = {}) {
      const original = scope();
      if (!original) throw new Error('Sign in to open automated support.');
      const result = await request(`/api/automated-support${path}`, options);
      if (scope() !== original) throw new Error('Your support workspace changed. Refresh to continue.');
      if (!result || result.ok !== true) throw new Error('Support information could not be confirmed. Refresh to try again.');
      return result;
    }
    const mutation = (path,method,body) => call(path,{method,body:JSON.stringify(body)});
    return Object.freeze({
      profiles:()=>call('/profiles'),
      cases:(profileId,state='')=>call(`/cases?profileId=${id(profileId)}${Object.hasOwn(states,state)?`&state=${state}`:''}`),
      detail:caseId=>call(`/cases/${id(caseId)}`),
      mode:(profile,mode)=>{
        if (!Object.hasOwn(modes,mode)) throw new Error('Choose a support mode.');
        if (mode==='automatic' && profile.ready!==true) throw new Error('Complete this support address setup before enabling automatic replies.');
        return mutation(`/profiles/${id(profile.id)}`,'PATCH',{mode});
      },
      pause:(caseId,automationPaused)=>mutation(`/cases/${id(caseId)}`,'PATCH',{automationPaused:automationPaused===true}),
      status:(caseId,state,resolutionNote='')=>{
        if (!Object.hasOwn(states,state)) throw new Error('Choose a support status.');
        if (state==='resolved' && !text(resolutionNote)) throw new Error('Describe how the issue was resolved.');
        return mutation(`/cases/${id(caseId)}`,'PATCH',{state,...(state==='resolved'?{resolutionNote:text(resolutionNote).slice(0,2000)}:{})});
      },
      reply:(caseId,body)=>{
        const value=text(body); if (!value || value.length>12000) throw new Error('Write a reply of up to 12,000 characters.');
        return mutation(`/cases/${id(caseId)}/replies`,'POST',{text:value,confirmed:true});
      },
    });
  }
  return Object.freeze({states,modes,text,escape,rows,profiles,cases,canReply,client});
});
