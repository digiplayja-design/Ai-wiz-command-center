import {randomBytes,randomUUID} from 'node:crypto';
import {fail,FunnelError,text,uuid,version,esc} from './core.mjs';
import {googleAdsCallback,googleAdsConfiguration,googleDigest,googleChallenge,googleCustomerId,googleTokenCipher,GoogleAdsAccessError,createGoogleAdsProvider} from './google_ads_provider.mjs';

const opaque=value=>{if(typeof value!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(value))fail('Start a new Google connection.');return value;};
export function createGoogleAdsStore(database) {
  return {async command(actor,action,data={}){
    if(!database)fail('Google Ads connection storage is not configured.',503);
    const r=await database.rpc('korlix_google_ads_v1',{p_actor:actor,p_action:action,p_data:data});
    if(r.error){const status={'42501':403,'P0002':404,'40001':409,'54000':429,'P0001':400}[r.error.code];fail(status?r.error.message:'Google Ads connection storage is temporarily unavailable.',status||503);}
    return r.data;
  }};
}
export function registerGoogleAds(app,{base,owner,limit=()=>{},database,googleAdsStore,googleAdsProvider,environment,now=Date.now}) {
  const config=googleAdsConfiguration(environment),store=googleAdsStore||createGoogleAdsStore(database),provider=googleAdsProvider||createGoogleAdsProvider(config,{now});
  const configured=()=>{if(!config.ready)fail('Google Ads connections are awaiting KORLIX platform setup.',503);};
  const binding=(user,id,purpose)=>`korlix-google-ads:${purpose}:${user}:${id}`;
  const status=async u=>({...await store.command(u,'status',{config_hash:config.hash}),configured:config.ready,ad_publishing_ready:false});
  async function credentials(u){configured();const c=await store.command(u,'secret');if(c.config_hash!==config.hash||c.needs_reconnect||(c.refresh_expires_at&&Date.parse(c.refresh_expires_at)<=now()+60000))fail('Reconnect Google Ads to renew access.',409);return c;}
  // Check the browser's version BEFORE contacting Google, and again in the
  // service-only transaction after remote work. A disconnect/downgrade wins.
  async function withAccess(u,requestedVersion,fn){
    const c=await credentials(u);if(version(requestedVersion)!==c.version)fail('The Google connection changed. Refresh before trying again.',409);
    try{const refresh=googleTokenCipher(config.key).open(c.sealed,binding(u,c.binding_id,'refresh'));const token=await provider.refresh(refresh);return await fn(c,token);}catch(e){if(e instanceof GoogleAdsAccessError)await store.command(u,'invalid',{version:c.version});throw e;}
  }
  const mutation=(u,c,action,data)=>store.command(u,action,{...data,version:c.version,config_hash:config.hash});
  const limited={ratePrefix:'google-ads:',max:15};
  app.get(base+'/google-ads/readiness',(_q,r)=>r.set('Cache-Control','no-store').json({configured:config.ready,ad_publishing_ready:false}));
  app.get(base+'/google-ads/connection',owner(async(_q,r,u)=>r.json(await status(u))));
  app.post(base+'/google-ads/begin',owner(async(_q,r,u)=>{
    configured();const id=randomUUID(),state=randomBytes(32).toString('base64url'),proof=randomBytes(32).toString('base64url'),verifier=randomBytes(32).toString('base64url');
    await store.command(u,'begin',{id,state_hash:googleDigest(state),proof_hash:googleDigest(proof),config_hash:config.hash,verifier_sealed:googleTokenCipher(config.key).seal(verifier,binding(u,id,'pkce'))});
    r.json({id,proof,authorization_url:provider.authorizationUrl(`${id}.${state}`,googleChallenge(verifier)),expires_in:600});
  },limited));
  app.get(googleAdsCallback,async(q,r)=>{
    r.set({'Cache-Control':'no-store','Referrer-Policy':'no-referrer','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'",'X-Content-Type-Options':'nosniff'});
    let consumed,message='Google authorization received. Return to the original KORLIX window and tap Finish Google connection.';
    try{
      limit('google-callback:'+q.ip,30);configured();
      if(typeof q.query.state!=='string'||q.query.state.length>100)fail('Start a new Google connection.');
      const state=q.query.state.split('.');if(state.length!==2)fail('Start a new Google connection.');
      consumed=await store.command(null,'consume',{id:uuid(state[0]),state_hash:googleDigest(opaque(state[1])),config_hash:config.hash});
      if(q.query.error)fail('Google authorization was cancelled. Return to KORLIX and start again.');
      const verifier=googleTokenCipher(config.key).open(consumed.verifier_sealed,binding(consumed.user_id,consumed.id,'pkce'));
      const result=await provider.exchange(text(q.query.code,4000,true),verifier);
      await store.command(consumed.user_id,'candidate',{id:consumed.id,refresh_expires_at:result.refresh_expires_at,sealed:googleTokenCipher(config.key).seal(result.refresh_token,binding(consumed.user_id,consumed.id,'refresh'))});
    }catch(e){if(consumed)try{await store.command(consumed.user_id,'failed',{id:consumed.id});}catch{}r.status(e instanceof FunnelError?e.status:503);message=e instanceof FunnelError?e.message:'Google authorization could not finish. Return to KORLIX and start again.';}
    r.type('html').send(`<!doctype html><html lang="en"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KORLIX · Google connection</title><body style="background:#061827;color:#e5f3f8;font:18px system-ui;padding:10vh 8vw"><h1>KORLIX · Google connection</h1><p>${esc(message)}</p><p>You may close this window. No ad was launched.</p></body></html>`);
  });
  app.post(base+'/google-ads/finish',owner(async(q,r,u)=>{configured();await store.command(u,'finish',{id:uuid(q.body?.id),proof_hash:googleDigest(opaque(q.body?.proof)),config_hash:config.hash});r.json(await status(u));},limited));
  app.post(base+'/google-ads/roots',owner(async(q,r,u)=>{await withAccess(u,q.body?.version,async(c,t)=>{await mutation(u,c,'roots',{roots:await provider.roots(t)});});r.json(await status(u));},limited));
  app.post(base+'/google-ads/accounts',owner(async(q,r,u)=>{
    const root=googleCustomerId(q.body?.root_id);
    await withAccess(u,q.body?.version,async(c,t)=>{
      if(!c.roots.includes(root))fail('Refresh your Google access accounts before choosing one.');
      if(!(await provider.roots(t)).includes(root))fail('Google access to this account was removed. Refresh access accounts.',409);
      const result=await provider.accounts(t,root);if(result.root.id!==root)fail('Google returned a different access account.',503);
      await mutation(u,c,'accounts',{root_id:root,root_name:result.root.name,login_customer_id:result.root.manager?root:null,accounts:result.accounts});
    });r.json(await status(u));
  },limited));
  app.post(base+'/google-ads/select',owner(async(q,r,u)=>{
    const root=googleCustomerId(q.body?.root_id),id=googleCustomerId(q.body?.account_id);
    await withAccess(u,q.body?.version,async(c,t)=>{
      if(c.root_id!==root||!c.accounts.some(a=>a.id===id&&!a.manager&&a.status==='ENABLED'))fail('Load your Google accounts and choose an active advertising account.');
      if(!(await provider.roots(t)).includes(root))fail('Google access to this account was removed. Refresh access accounts.',409);
      const a=await provider.account(t,id,c.login_customer_id);if(a.id!==id||a.manager||a.status!=='ENABLED')fail('This Google advertising account is no longer active or accessible.',409);
      await mutation(u,c,'select',{root_id:root,account_id:id});
    });r.json(await status(u));
  },limited));
  app.post(base+'/google-ads/disconnect',owner(async(q,r,u)=>{if(q.body?.confirmed!==true)fail('Confirm disconnecting Google Ads first.');await store.command(u,'disconnect',{version:q.body.version==null?null:version(q.body.version)});r.json(await status(u));}));
}
