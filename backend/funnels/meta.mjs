import express from 'express';
import {metaReportQuery,metaReportRange,readMetaInsights} from './meta_performance.mjs';
import {randomBytes,randomUUID,createHash,createHmac,createCipheriv,createDecipheriv,timingSafeEqual} from 'node:crypto';
import {fail,FunnelError,text,uuid,version,esc} from './core.mjs';

export const digest=value=>createHash('sha256').update(value).digest('hex');
const callbackPath='/api/funnels/meta/callback';
const opaque=value=>{if(typeof value!=='string'||! /^[A-Za-z0-9_-]{43}$/.test(value))fail('Start a new Meta connection.');return value;};
export function metaConfiguration(env={}) {
  const id=env.KORLIX_META_APP_ID||'',secret=env.KORLIX_META_APP_SECRET||'',configId=env.KORLIX_META_LOGIN_CONFIG_ID||'',key=env.KORLIX_META_TOKEN_KEY||'';
  const apiVersion=env.KORLIX_META_API_VERSION||'v26.0',callback=env.KORLIX_META_REDIRECT_URI||'';
  let validCallback=false;
  try{const u=new URL(callback);validCallback=u.protocol==='https:'&&!u.username&&!u.password&&!u.search&&!u.hash&&u.pathname===callbackPath;}catch{}
  const ready=env.KORLIX_META_ENABLED==='true'&&/^\d{5,40}$/.test(id)&&secret.length>=16&&/^\d{5,40}$/.test(configId)&&/^[A-Za-z0-9+/]{43}=$/.test(key)&&Buffer.from(key,'base64').length===32&&/^v\d{2,3}\.0$/.test(apiVersion)&&validCallback;
  return {ready,id,secret,configId,key,apiVersion,callback,hash:digest(JSON.stringify([id,secret,configId,key,apiVersion,callback]))};
}
export function tokenCipher(key) {
  const bytes=Buffer.from(key,'base64');if(bytes.length!==32)fail('Meta connection storage is not configured.',503);
  return {
    seal(value,binding){const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',bytes,iv);cipher.setAAD(Buffer.from(binding));const ciphertext=Buffer.concat([cipher.update(value,'utf8'),cipher.final()]);return {v:1,iv:iv.toString('base64url'),tag:cipher.getAuthTag().toString('base64url'),ciphertext:ciphertext.toString('base64url')};},
    open(value,binding){try{if(value.v!==1)throw Error();const decipher=createDecipheriv('aes-256-gcm',bytes,Buffer.from(value.iv,'base64url'));decipher.setAAD(Buffer.from(binding));decipher.setAuthTag(Buffer.from(value.tag,'base64url'));return Buffer.concat([decipher.update(Buffer.from(value.ciphertext,'base64url')),decipher.final()]).toString('utf8');}catch{fail('Reconnect Meta to renew secure access.',409);}}
  };
}
export function createMetaStore(database) {
  return {async command(actor,action,data={}) {
    if(!database)fail('Meta connection storage is not configured.',503);
    const r=await database.rpc('korlix_meta_v1',{p_actor:actor,p_action:action,p_data:data});
    if(r.error){const status={'42501':403,'P0002':404,'40001':409,'40900':409,'54000':429,'P0001':400}[r.error.code];fail(status?r.error.message:'Meta connection storage is temporarily unavailable.',status||503);}
    return r.data;
  }};
}
class MetaAccessError extends FunnelError {constructor(){super('Meta access expired or was removed. Reconnect your account.',409);}}
export function createMetaProvider(config,{fetchImpl=fetch,now=Date.now}={}) {
  async function graph(path,params={},token) {
    const url=new URL(`https://graph.facebook.com/${config.apiVersion}/${path}`);
    for(const [k,v] of Object.entries(params))url.searchParams.set(k,String(v));
    if(token)url.searchParams.set('appsecret_proof',createHmac('sha256',config.secret).update(token).digest('hex'));
    let response,body;
    try{response=await fetchImpl(url,{headers:token?{Authorization:`Bearer ${token}`}:{},redirect:'error',signal:AbortSignal.timeout(10000)});body=await response.json();}catch{fail('Meta could not be reached. Please try again.',503);}
    if(!response.ok||body.error){if(body.error?.code===190||body.error?.code===10||body.error?.code===200)throw new MetaAccessError();fail('Meta could not complete this request. Check your account access and try again.',503);}
    return body;
  }
  const account=a=>{
    if(!a||!/^act_\d{1,40}$/.test(a.id)||!Number.isSafeInteger(a.account_status))fail('Meta returned an unreadable ad account.',503);
    return {id:a.id,name:text(a.name||a.id,200),currency:text(a.currency||'',8),timezone:text(a.timezone_name||'',100),status:a.account_status};
  };
  const fields='id,name,currency,timezone_name,account_status';
  return {
    authorizationUrl(state){const u=new URL(`https://www.facebook.com/${config.apiVersion}/dialog/oauth`);u.search=new URLSearchParams({client_id:config.id,redirect_uri:config.callback,state,config_id:config.configId,response_type:'code',override_default_response_type:'true',auth_type:'rerequest'}).toString();return u.href;},
    async exchange(code){
      const short=await graph('oauth/access_token',{client_id:config.id,client_secret:config.secret,redirect_uri:config.callback,code});
      if(typeof short.access_token!=='string'||short.access_token.length>12000)fail('Meta did not return valid access.',503);
      const long=await graph('oauth/access_token',{grant_type:'fb_exchange_token',client_id:config.id,client_secret:config.secret,fb_exchange_token:short.access_token});
      const token=long.access_token;if(typeof token!=='string'||!token||token.length>12000)fail('Meta did not return valid access.',503);
      const debug=await graph('debug_token',{input_token:token},`${config.id}|${config.secret}`);
      const d=debug.data;
      if(!d?.is_valid||String(d.app_id)!==config.id||d.type!=='USER'||!/^\d{1,40}$/.test(d.user_id)||!d.scopes?.includes('ads_read'))fail('Approve read access to your Meta ad accounts using the configured user login.',409);
      if(!Number.isSafeInteger(d.expires_at)||d.expires_at*1000<=now()+60000)fail('Meta access is expired. Reconnect.',409);
      const times=[Number(d.expires_at),Number(d.data_access_expires_at)].filter(n=>Number.isSafeInteger(n)&&n>0);
      const expiry=Math.min(...times);
      if(!times.length||expiry*1000<=now()+60000)fail('Meta access is expired. Reconnect.',409);
      return {token,meta_user_id:d.user_id,expires_at:new Date(expiry*1000).toISOString()};
    },
    async accounts(token){
      const found=new Map();let after;
      for(let page=0;page<5;page++){
        const r=await graph('me/adaccounts',{fields,limit:100,...(after?{after}:{})},token);
        if(!Array.isArray(r.data))fail('Meta returned an unreadable account list.',503);
        for(const a of r.data){const clean=account(a);found.set(clean.id,clean);}
        if(!r.paging?.next)return [...found.values()];
        after=r.paging?.cursors?.after;
        if(typeof after!=='string'||after.length>4000)fail('Meta account pagination could not be completed.',503);
      }
      fail('More than 500 ad accounts were returned. Limit the assets shared with KORLIX and reconnect.',409);
    },
    async account(token,id){return account(await graph(id,{fields},token));},
    async insights(token,account,range){return readMetaInsights(graph,token,account,range);},
    async campaignInsights(token,account,range){return readMetaInsights(graph,token,account,range,'campaign');}
  };
}
export function verifiedMetaEvent(value,secret,now=Date.now()) {
  if(typeof value!=='string'||value.length>8192)fail('Invalid Meta callback.',400);
  try{
    const parts=value.split('.');if(parts.length!==2||!parts.every(x=>/^[A-Za-z0-9_-]+$/.test(x)))throw Error();
    const supplied=Buffer.from(parts[0],'base64url'),expected=createHmac('sha256',secret).update(parts[1]).digest();
    if(supplied.length!==expected.length||!timingSafeEqual(supplied,expected))throw Error();
    const data=JSON.parse(Buffer.from(parts[1],'base64url').toString('utf8'));
    if(data.algorithm!=='HMAC-SHA256'||!/^\d{1,40}$/.test(data.user_id)||!Number.isSafeInteger(data.issued_at)||data.issued_at>now/1000+300||data.issued_at<now/1000-86400)throw Error();
    return {meta_user_id:data.user_id,issued_at:data.issued_at};
  }catch{fail('Invalid Meta callback.',400);}
}
export function registerMeta(app,{base,owner,database,metaStore,metaProvider,environment,now=Date.now}) {
  const config=metaConfiguration(environment),store=metaStore||createMetaStore(database),provider=metaProvider||createMetaProvider(config,{now});
  const configured=()=>{if(!config.ready)fail('Meta connections are awaiting KORLIX platform setup.',503);};
  const binding=(user,id)=>`korlix-meta:${user}:${id}`;
  const status=async user=>({...await store.command(user,'status',{config_hash:config.hash}),configured:config.ready,ad_publishing_ready:false});
  async function access(user){configured();const c=await store.command(user,'secret');if(c.config_hash!==config.hash||c.needs_reconnect||Date.parse(c.expires_at)<=now()+60000)fail('Reconnect Meta to renew access.',409);return {c,token:tokenCipher(config.key).open(c.sealed,binding(user,c.binding_id))};}
  async function withAccess(user,fn){const {c,token}=await access(user);try{return await fn(c,token);}catch(e){if(e instanceof MetaAccessError)await store.command(user,'invalid',{version:c.version});throw e;}}
  app.get(base+'/meta/data-deletion',(_q,r)=>r.set({'Cache-Control':'no-store','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'",'X-Content-Type-Options':'nosniff'}).type('html').send(`<!doctype html><html lang="en"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KORLIX · Remove Meta data</title><body style="background:#061827;color:#e5f3f8;font:18px system-ui;line-height:1.6;max-width:760px;margin:8vh auto;padding:24px"><h1>Remove your Meta connection data</h1><p>In KORLIX, open Enterprise Funnel Studio, open a funnel, and choose Ads workspace. In Meta ad accounts, select Disconnect and confirm.</p><p>This deletes your stored Meta access token, cached ad account details, selected account, and pending sign-in attempt from KORLIX. Campaign plans and results you entered yourself remain available.</p><p>You can also remove KORLIX in Meta Business Integrations to revoke its permission. Disconnecting does not stop ads running on Meta.</p><p>If you cannot access your KORLIX account, contact support@korlixdeveloper.com from your registered email address and request removal of your Meta connection data. Never send your password or access token.</p></body></html>`));
  app.get(base+'/meta/readiness',(_q,r)=>r.set('Cache-Control','no-store').json({configured:config.ready,ad_publishing_ready:false}));
  app.get(base+'/meta/connection',owner(async(_q,r,u)=>r.json(await status(u))));
  app.post(base+'/meta/begin',owner(async(_q,r,u)=>{
    configured();const id=randomUUID(),state=randomBytes(32).toString('base64url'),proof=randomBytes(32).toString('base64url');
    await store.command(u,'begin',{id,state_hash:digest(state),proof_hash:digest(proof),config_hash:config.hash});
    r.json({id,proof,authorization_url:provider.authorizationUrl(`${id}.${state}`),expires_in:600});
  }));
  app.get(callbackPath,async(q,r)=>{
    r.set({'Cache-Control':'no-store','Referrer-Policy':'no-referrer','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; frame-ancestors 'none'; base-uri 'none'",'X-Content-Type-Options':'nosniff'});
    let consumed;let message='Meta authorization received. Return to the original KORLIX window and tap Finish connection.';
    try{
      configured();const state=String(q.query.state||'').split('.');if(state.length!==2)fail('Start a new Meta connection.');
      consumed=await store.command(null,'consume',{id:uuid(state[0]),state_hash:digest(opaque(state[1])),config_hash:config.hash});
      if(q.query.error)fail('Meta authorization was cancelled. Return to KORLIX and start again.');
      const result=await provider.exchange(text(q.query.code,4000,true));
      await store.command(consumed.user_id,'candidate',{id:consumed.id,meta_user_id:result.meta_user_id,expires_at:result.expires_at,sealed:tokenCipher(config.key).seal(result.token,binding(consumed.user_id,consumed.id))});
    }catch(e){if(consumed)try{await store.command(consumed.user_id,'failed',{id:consumed.id});}catch{}r.status(e instanceof FunnelError?e.status:503);message=e instanceof FunnelError?e.message:'Meta authorization could not finish. Return to KORLIX and start again.';}
    r.type('html').send(`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><title>KORLIX · Meta connection</title><body style="background:#061827;color:#e5f3f8;font:18px system-ui;padding:10vh 8vw"><h1>KORLIX · Meta connection</h1><p>${esc(message)}</p><p>You may close this window. No ad was launched.</p></body>`);
  });
  app.post(base+'/meta/finish',owner(async(q,r,u)=>{configured();await store.command(u,'finish',{id:uuid(q.body?.id),proof_hash:digest(opaque(q.body?.proof)),config_hash:config.hash});r.json(await status(u));}));
  app.post(base+'/meta/accounts',owner(async(_q,r,u)=>{await withAccess(u,async(c,token)=>{const accounts=await provider.accounts(token);await store.command(u,'accounts',{version:c.version,accounts});});r.json(await status(u));}));
  app.post(base+'/meta/select',owner(async(q,r,u)=>{
    const id=text(q.body?.account_id,44,true);if(!/^act_\d{1,40}$/.test(id))fail('Choose an available Meta ad account.');
    await withAccess(u,async(c,token)=>{if(version(q.body?.version)!==c.version)fail('The connection changed. Refresh before selecting an account.',409);if(!c.accounts.some(a=>a.id===id))fail('Refresh your accounts before selecting.');const a=await provider.account(token,id);if(a.id!==id)fail('Meta returned a different account.',503);await store.command(u,'select',{version:c.version,account_id:id});});r.json(await status(u));
  }));
  const performance=scope=>owner(async(q,r,u)=>{
    const requested=metaReportQuery(q.query);
    await withAccess(u,async(c,token)=>{
      if(c.version!==requested.version||!c.selected_account||c.selected_account!==requested.account_id||!c.accounts.some(a=>a.id===c.selected_account))fail('The selected account changed. Check your Meta connection before reporting.',409);
      const account=await provider.account(token,c.selected_account);
      if(account.id!==c.selected_account)fail('Meta returned a different account.',503);
      const range=metaReportRange(requested.days,account.timezone,now());
      const report=await (scope==='campaign'?provider.campaignInsights(token,account,range):provider.insights(token,account,range));
      // Recheck current entitlement and credentials after remote work. A late
      // response must not expose data after disconnect, reselect or downgrade.
      const latest=await access(u);
      if(latest.c.version!==c.version||latest.c.binding_id!==c.binding_id||latest.c.selected_account!==c.selected_account)fail('The Meta connection changed while loading. Check your connection and try again.',409);
      r.json({source:'meta',scope,account:{id:account.id,name:account.name,currency:account.currency,timezone:account.timezone},connection_version:c.version,range,...report,fetched_at:new Date(now()).toISOString()});
    });
  },{ratePrefix:'meta-performance:',max:10});
  app.get(base+'/meta/performance',performance('account'));
  app.get(base+'/meta/campaign-performance',performance('campaign'));
  app.post(base+'/meta/disconnect',owner(async(q,r,u)=>{if(q.body?.confirmed!==true)fail('Confirm disconnecting Meta first.');await store.command(u,'disconnect',{version:q.body.version==null?null:version(q.body.version)});r.json(await status(u));}));
  app.post(base+'/meta/deauthorize',express.urlencoded({extended:false,limit:'12kb'}),async(q,r)=>{
    r.set('Cache-Control','no-store');try{if(config.secret.length<16)fail('Meta callback unavailable.',503);const event=verifiedMetaEvent(q.body?.signed_request,config.secret,now());await store.command(null,'deauthorize',event);r.json({success:true});}catch(e){r.status(e instanceof FunnelError?e.status:503).json({error:'Meta callback could not be verified.'});}
  });
}
