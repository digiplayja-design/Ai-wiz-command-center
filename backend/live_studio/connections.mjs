import {createCipheriv,createDecipheriv,createHash,randomBytes,randomUUID} from 'node:crypto';
import {LiveStudioError,uuid,fail} from './core.mjs';

export const YOUTUBE_SCOPE='https://www.googleapis.com/auth/youtube.force-ssl';
export const connectionHash=value=>createHash('sha256').update(value).digest('hex');
const secret=()=>randomBytes(32).toString('base64url');
const challenge=value=>createHash('sha256').update(value).digest('base64url');
const grantBinding=c=>`grant:${c.owner_id}:${c.id}:${c.channel_id}`;
const attemptBinding=a=>`attempt:${a.owner_id}:${a.id}`;
const scalar=(value,max=4000)=>{
  if(typeof value!=='string'||!value||value.length>max||/[\u0000-\u001f\u007f]/.test(value))fail('This connection request is invalid. Start again.',400);
  return value;
};
const token=value=>{const v=scalar(value,100);if(!/^[A-Za-z0-9_-]{43}$/.test(v))fail('This connection request expired. Start again.',409);return v;};

// A distinct key and AAD namespace prevent grants being reused across products, owners or channels.
export function liveConnectionCipher(env={}){
  const encoded=env.LIVE_STUDIO_TOKEN_KEY||'',key=Buffer.from(encoded,'base64');
  const ready=key.length===32&&key.toString('base64')===encoded;
  return {ready,seal(value,binding){
    if(!ready)fail('Secure YouTube connection storage needs administrator setup.',503);
    const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,iv);
    cipher.setAAD(Buffer.from('korlix-live-studio:v1:'+binding));
    return ['v1',iv.toString('base64url'),Buffer.concat([cipher.update(JSON.stringify(value),'utf8'),cipher.final()]).toString('base64url'),cipher.getAuthTag().toString('base64url')].join('.');
  },open(value,binding){
    try{
      if(!ready||typeof value!=='string')throw Error();
      const [version,iv,data,tag,...extra]=value.split('.');
      if(version!=='v1'||extra.length||!iv||!data||!tag)throw Error();
      const nonce=Buffer.from(iv,'base64url'),authTag=Buffer.from(tag,'base64url');
      if(nonce.length!==12||authTag.length!==16)throw Error();
      const decipher=createDecipheriv('aes-256-gcm',key,nonce);
      decipher.setAAD(Buffer.from('korlix-live-studio:v1:'+binding));decipher.setAuthTag(authTag);
      return JSON.parse(Buffer.concat([decipher.update(Buffer.from(data,'base64url')),decipher.final()]).toString('utf8'));
    }catch{fail('Reconnect YouTube to restore secure channel access.',409);}
  }};
}

export function liveConnectionSettings(env={},publicRoot){
  const cipher=liveConnectionCipher(env),id=env.LIVE_STUDIO_YOUTUBE_CLIENT_ID||'',clientSecret=env.LIVE_STUDIO_YOUTUBE_CLIENT_SECRET||'';
  let origin='';
  try{const url=new URL(env.LIVE_STUDIO_PUBLIC_ORIGIN||publicRoot);if(url.protocol==='https:'&&!url.username&&!url.password&&url.pathname==='/'&&!url.search&&!url.hash)origin=url.origin;}catch{}
  const callback=origin+'/api/live-studio/connect/youtube/callback';
  return {cipher,id,clientSecret,origin,callback,configured:Boolean(cipher.ready&&id&&clientSecret&&origin&&env.LIVE_STUDIO_YOUTUBE_ENABLED==='true'),
    fingerprint:connectionHash(JSON.stringify(['youtube',id,clientSecret,callback,YOUTUBE_SCOPE,env.LIVE_STUDIO_TOKEN_KEY||'']))};
}

class ConnectionProviderError extends LiveStudioError{
  constructor(message,status=503,reconnect=false){super(message,status);this.reconnect=reconnect;}
}
async function providerRequest(fetcher,url,options={},signal){
  let response,data;
  try{
    response=await fetcher(url,{...options,redirect:'error',signal:signal?AbortSignal.any([signal,AbortSignal.timeout(15000)]):AbortSignal.timeout(15000)});
    const reader=response.body?.getReader();if(!reader)throw Error();
    const chunks=[];let size=0;
    try{for(;;){const part=await reader.read();if(part.done)break;size+=part.value.byteLength;if(size>1024*1024)throw Error();chunks.push(Buffer.from(part.value));}}finally{await reader.cancel().catch(()=>{});}
    const raw=Buffer.concat(chunks).toString('utf8');data=raw?JSON.parse(raw):{};
  }catch{throw new ConnectionProviderError('YouTube did not confirm the connection request. Try again later.');}
  if(!response.ok){
    const denied=new Set(['insufficientPermissions','authenticatedUserAccountClosed','authenticatedUserAccountSuspended','authenticatedUserNotChannel','channelClosed','channelNotFound','channelSuspended','youtubeSignupRequired','authorizationRequired','forbidden']);
    const reasons=Array.isArray(data.error?.errors)?data.error.errors.map(e=>e?.reason):[];
    const reconnect=response.status===401||data.error==='invalid_grant'||reasons.some(reason=>denied.has(reason));
    throw new ConnectionProviderError(reconnect?'Reconnect YouTube to restore channel access.':'YouTube could not complete this connection request.',reconnect?409:503,reconnect);
  }
  return data;
}
function checkedGrant(data,previous,now){
  const scopes=typeof data.scope==='string'?data.scope.split(/\s+/):previous?.scopes;
  if(!scopes?.includes(YOUTUBE_SCOPE))throw new ConnectionProviderError('YouTube broadcasting permission was not granted. Start again and allow the requested permission.',409,true);
  if(typeof data.access_token!=='string'||data.access_token.length>8192||!data.access_token||data.token_type?.toLowerCase()!=='bearer')throw new ConnectionProviderError('YouTube returned an incomplete connection. Start again.',409,true);
  const refreshToken=data.refresh_token||previous?.refresh_token;
  if(typeof refreshToken!=='string'||!refreshToken||refreshToken.length>8192)throw new ConnectionProviderError('YouTube did not grant continuing access. Reconnect and allow access for scheduled shows.',409,true);
  if(!Number.isFinite(Number(data.expires_in))||Number(data.expires_in)<60||Number(data.expires_in)>86400)throw new ConnectionProviderError('YouTube returned an invalid connection lifetime.',409,true);
  return {access_token:data.access_token,refresh_token:refreshToken,expires_at:new Date(now()+Number(data.expires_in)*1000).toISOString(),scopes};
}
const publicConnection=c=>c?{id:c.id,channelId:c.channel_id,channelTitle:c.channel_title||(c.state==='reconnect_required'?'Reconnect YouTube':'YouTube channel'),state:c.state,revision:c.revision,connectedAt:c.connected_at}:null;
const html='<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KORLIX Live Studio connection</title><body><main><h1>YouTube channel verified</h1><p>Return to KORLIX Live Studio, review the channel shown in Connections, then confirm it.</p><p>You can close this tab.</p></main></body></html>';

export function createLiveConnections({database,env=process.env,publicRoot,fetcher=fetch,now=Date.now}={}){
  const settings=liveConnectionSettings(env,publicRoot),{cipher}=settings;
  const call=async(actor,action,id=null,data={})=>{
    if(!database)fail('YouTube connection storage is unavailable.',503);
    let result;try{result=await database.rpc('korlix_live_studio_connections_v1',{p_actor:actor,p_action:action,p_id:id,p_data:data});}catch{fail('YouTube connection status could not be confirmed. Refresh before retrying.',503);}
    if(result.error){const status={P0002:404,'40001':409,'23505':409,'54000':429,'22023':400,'42501':403}[result.error.code];throw new LiveStudioError(status?result.error.message:'YouTube connection storage is temporarily unavailable.',status||503);}
    return result.data;
  };
  const configured=()=>{if(!settings.configured)fail('YouTube connections need administrator setup before customers can connect.',503);};
  const checkConfig=c=>{configured();if(c.config_hash!==settings.fingerprint)fail('YouTube connection settings changed. Reconnect your channel.',409);};
  const exchange=async(code,verifier)=>checkedGrant(await providerRequest(fetcher,'https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:settings.id,client_secret:settings.clientSecret,redirect_uri:settings.callback,grant_type:'authorization_code',code,code_verifier:verifier})}),null,now);
  const refreshGrant=async(grant,signal)=>checkedGrant(await providerRequest(fetcher,'https://oauth2.googleapis.com/token',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:settings.id,client_secret:settings.clientSecret,grant_type:'refresh_token',refresh_token:grant.refresh_token})},signal),grant,now);
  const openGrant=c=>{try{return cipher.open(c.sealed_grant,grantBinding(c));}catch{throw new ConnectionProviderError('Reconnect YouTube to restore secure channel access.',409,true);}};
  const identity=async(grant,signal)=>{
    const result=await providerRequest(fetcher,'https://www.googleapis.com/youtube/v3/channels?part=id%2Csnippet&mine=true&maxResults=2',{headers:{Authorization:'Bearer '+grant.access_token}},signal);
    if(!Array.isArray(result.items)||result.items.length!==1||result.nextPageToken)throw new ConnectionProviderError('Choose one YouTube channel with your Google account, then connect again.',409,true);
    const item=result.items[0];
    if(typeof item.id!=='string'||!/^UC[A-Za-z0-9_-]{22}$/.test(item.id))throw new ConnectionProviderError('YouTube did not return a usable channel. Create or choose a channel first.',409,true);
    return {channel_id:item.id,channel_title:typeof item.snippet?.title==='string'?item.snippet.title.replace(/[\u0000-\u001f\u007f]/g,' ').slice(0,150):'YouTube channel'};
  };
  const summary=async(owner)=>{
    const result=await call(uuid(owner),'list',null,{config_hash:settings.fingerprint});
    const c=result.connection;
    if(c&&(!settings.configured||c.config_hash!==settings.fingerprint))c.state='reconnect_required';
    return {connection:publicConnection(c),pendingConnections:(result.pending||[]).filter(a=>settings.configured&&a.config_hash===settings.fingerprint).map(a=>({id:a.id,channelId:a.channel_id,channelTitle:a.channel_title,expiresAt:a.expires_at})),connectionConfigured:settings.configured};
  };
  const start=async(owner,{confirmed}={})=>{
    configured();uuid(owner);if(confirmed!==true)fail('Confirm connecting a YouTube channel.');
    const id=randomUUID(),ticket=secret(),state=secret(),verifier=secret();
    await call(owner,'start',id,{ticket_hash:connectionHash(ticket),state_hash:connectionHash(state),sealed_secrets:cipher.seal({state,verifier},attemptBinding({owner_id:owner,id})),config_hash:settings.fingerprint});
    return {id,url:settings.origin+'/api/live-studio/connect/youtube/launch?ticket='+ticket};
  };
  const confirm=async(owner,{id,confirmed}={})=>{
    configured();uuid(owner);uuid(id);if(confirmed!==true)fail('Review and confirm this YouTube channel.');
    const a=await call(owner,'ready',id);checkConfig(a);
    if(a.state==='confirmed')return summary(owner);
    try{
      const grant=openGrant(a),channel=await identity(grant);
      if(channel.channel_id!==a.channel_id)throw new ConnectionProviderError('The YouTube channel changed. Start again.',409,true);
      await call(owner,'confirm',id,{config_hash:settings.fingerprint});
    }catch(error){if(error.reconnect)await call(owner,'fail',id).catch(()=>{});throw error;}
    return summary(owner);
  };
  const disconnect=async(owner,{confirmed}={})=>{
    uuid(owner);if(confirmed!==true)fail('Confirm disconnecting YouTube and stopping its scheduled or active shows.');
    const c=await call(owner,'disconnect');let providerRevoked=false;
    if(c?.sealed_grant){try{const grant=cipher.open(c.sealed_grant,grantBinding(c));await providerRequest(fetcher,'https://oauth2.googleapis.com/revoke',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({token:grant.refresh_token})});providerRevoked=true;}catch{}}
    return {...await summary(owner),disconnected:true,providerRevoked,message:providerRevoked?'YouTube disconnected. Scheduled shows were cancelled and active broadcasts were asked to stop.':'YouTube disconnected from KORLIX. Scheduled shows were cancelled and active broadcasts were asked to stop. Google access revocation could not be confirmed; you can remove KORLIX access in your Google Account permissions.'};
  };
  function registerPublic(app,{base='/api/live-studio'}={}){
    // The callback is fixed by app configuration; neither route accepts a return URL.
    if(base!=='/api/live-studio')throw new Error('The Live Studio OAuth base must match the configured callback.');
    const cookieName='__Secure-korlix_live_youtube',cookieOptions={httpOnly:true,secure:true,sameSite:'lax',path:base+'/connect/youtube'};
    const route=fn=>async(q,r)=>{
      r.set('Cache-Control','no-store').set('Pragma','no-cache').set('Referrer-Policy','no-referrer').set('X-Content-Type-Options','nosniff').set('Content-Security-Policy',"default-src 'none'; base-uri 'none'; frame-ancestors 'none'");
      try{configured();await fn(q,r);}catch(error){if(!r.headersSent)r.status(error instanceof LiveStudioError?error.status:503).type('text').send(error instanceof LiveStudioError?error.message:'YouTube connection could not be completed. Return to KORLIX and start again.');}
    };
    app.get(base+'/connect/youtube/launch',route(async(q,r)=>{
      const browser=secret(),attempt=await call(null,'launch',null,{ticket_hash:connectionHash(token(q.query.ticket)),browser_hash:connectionHash(browser)});
      checkConfig(attempt);const secrets=cipher.open(attempt.sealed_secrets,attemptBinding(attempt));
      const url=new URL('https://accounts.google.com/o/oauth2/v2/auth');
      url.search=new URLSearchParams({client_id:settings.id,redirect_uri:settings.callback,response_type:'code',scope:YOUTUBE_SCOPE,access_type:'offline',prompt:'consent select_account',include_granted_scopes:'false',state:secrets.state,code_challenge:challenge(secrets.verifier),code_challenge_method:'S256'}).toString();
      r.cookie(cookieName,browser,{...cookieOptions,maxAge:600000});r.redirect(303,url.toString());
    }));
    app.get(base+'/connect/youtube/callback',route(async(q,r)=>{
      const browser=(q.get('cookie')||'').split(';').map(s=>s.trim()).find(s=>s.startsWith(cookieName+'='))?.slice(cookieName.length+1);
      const attempt=await call(null,'claim',null,{state_hash:connectionHash(token(q.query.state)),browser_hash:connectionHash(token(browser))});
      r.clearCookie(cookieName,cookieOptions);
      try{
        checkConfig(attempt);if(q.query.error)fail('YouTube authorization was not completed. Return to KORLIX and start again.',409);
        const secrets=cipher.open(attempt.sealed_secrets,attemptBinding(attempt)),grant=await exchange(scalar(q.query.code),secrets.verifier),channel=await identity(grant);
        await call(null,'complete',attempt.id,{config_hash:settings.fingerprint,...channel,sealed_grant:cipher.seal(grant,grantBinding({...attempt,...channel}))});
        r.type('html').send(html);
      }catch(error){await call(null,'fail',attempt.id).catch(()=>{});throw error;}
    }));
  }
  async function forShow(show){
    configured();const owner=uuid(show.owner_id),id=uuid(show.connection_id),showId=uuid(show.id),workerToken=uuid(show.worker_token);
    const pinned={show_id:showId,worker_token:workerToken,revision:show.connection_revision,channel_id:show.channel_id,config_hash:settings.fingerprint};
    let inFlight;
    return async function accessToken(signal){
      if(signal?.aborted)throw new ConnectionProviderError('The show has stopped.',409);
      if(inFlight)return inFlight;
      inFlight=(async()=>{
        const lease=randomUUID(),c=await call(owner,'token_claim',id,{...pinned,lease});
        try{
          checkConfig(c);let grant=openGrant(c);
          if(!Number.isFinite(Date.parse(grant.expires_at)))throw new ConnectionProviderError('Reconnect YouTube to restore channel access.',409,true);
          if(Date.parse(grant.expires_at)<now()+60000){
            grant=await refreshGrant(grant,signal);
            await call(owner,'token_store',id,{...pinned,lease,sealed_grant:cipher.seal(grant,grantBinding(c))});
          }
          // A disconnect or lost show lease during a provider call must fence the result too.
          await call(owner,'token_check',id,{...pinned,lease});
          return grant.access_token;
        }catch(error){if(error.reconnect)await call(owner,'token_fail',id,{...pinned,lease}).catch(()=>{});throw error;}
        finally{await call(owner,'token_release',id,{...pinned,lease}).catch(()=>{});}
      })().finally(()=>{inFlight=null;});return inFlight;
    };
  }
  let maintenanceTimer=null,maintenanceFlight=null,maintenanceAbort=null,maintenanceStopped=false;
  // Every API instance may run this loop. SQL leases serialize work, while the
  // credential-independent sweep bounds retention even during setup or outages.
  function maintenanceTick(){
    if(maintenanceStopped)return Promise.resolve({stopped:true});
    if(maintenanceFlight)return maintenanceFlight;
    const controller=new AbortController();maintenanceAbort=controller;
    maintenanceFlight=(async()=>{
      const swept=await call(null,'retention_sweep'),counts={ownersProcessed:Number(swept?.ownersProcessed)||0,verified:0,deferred:0,revoked:0};
      if(!settings.configured)return counts;
      for(let i=0;i<5&&!controller.signal.aborted;i++){
        const lease=randomUUID(),c=await call(null,'maintenance_claim',null,{lease,config_hash:settings.fingerprint});
        if(!c?.id)break;
        const fence={lease,revision:c.revision,config_hash:settings.fingerprint};let rotatedGrant;
        try{
          checkConfig(c);let grant=openGrant(c);
          if(!Number.isFinite(Date.parse(grant.expires_at)))throw new ConnectionProviderError('Reconnect YouTube to restore channel access.',409,true);
          if(Date.parse(grant.expires_at)<now()+60000){grant=await refreshGrant(grant,controller.signal);rotatedGrant=cipher.seal(grant,grantBinding(c));}
          const channel=await identity(grant,controller.signal);
          if(channel.channel_id!==c.channel_id)throw new ConnectionProviderError('The connected YouTube channel changed. Reconnect it.',409,true);
          await call(c.owner_id,'maintenance_store',c.id,{...fence,...channel,sealed_grant:rotatedGrant||cipher.seal(grant,grantBinding(c))});
          counts.verified++;
        }catch(error){
          const revoked=error.reconnect===true;
          // A stale lease or disconnect must never repersist a returned token.
          // Transient metadata failure can preserve token rotation, but SQL does
          // not advance the verification/retention deadline on this path.
          let recorded=false;
          try{await call(c.owner_id,'maintenance_fail',c.id,{...fence,revoked,...(!revoked&&rotatedGrant?{sealed_grant:rotatedGrant}:{})});recorded=true;}catch{}
          counts[revoked&&recorded?'revoked':'deferred']++;
        }
      }
      return counts;
    })().finally(()=>{maintenanceFlight=null;maintenanceAbort=null;});
    return maintenanceFlight;
  }
  function startMaintenance(){
    if(maintenanceTimer)return;
    maintenanceStopped=false;
    const run=()=>{void maintenanceTick().catch(()=>console.error('Live Studio connection maintenance could not complete. It will retry.'));};
    maintenanceTimer=setInterval(run,60000);maintenanceTimer.unref?.();run();
  }
  async function stopMaintenance(){
    maintenanceStopped=true;if(maintenanceTimer)clearInterval(maintenanceTimer);maintenanceTimer=null;
    maintenanceAbort?.abort();await maintenanceFlight?.catch(()=>{});
  }
  return {configured:settings.configured,fingerprint:settings.fingerprint,summary,start,confirm,disconnect,registerPublic,forShow,maintenanceTick,startMaintenance,stopMaintenance};
}
