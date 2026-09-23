import {createHmac,timingSafeEqual} from 'node:crypto';
import {fail,uuid} from './core.mjs';
import {googleAdsConfiguration,createGoogleAdsProvider,googleTokenCipher,GoogleAdsAccessError} from './google_ads_provider.mjs';
import {createGoogleAdsStore} from './google_ads.mjs';
import {googleReportRange} from './google_ads_performance.mjs';

const ownKeys=(v,keys)=>v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length===keys.length&&keys.every(k=>Object.hasOwn(v,k));
const fingerprint=v=>typeof v==='string'&&/^[a-f0-9]{64}$/.test(v);
const count=n=>Number.isSafeInteger(n)&&n>=0;
const id=v=>typeof v==='string'&&/^[1-9][0-9]{0,18}$/.test(v)&&BigInt(v)<=9223372036854775807n;
const name=v=>typeof v==='string'&&v.length>0&&v.length<=1000&&v.trim()===v&&!v.includes('\0');
const statuses=['ENABLED','PAUSED','REMOVED','UNKNOWN','UNSPECIFIED'];
const channels=['DEMAND_GEN','DISPLAY','HOTEL','LOCAL','LOCAL_SERVICES','MULTI_CHANNEL','PERFORMANCE_MAX','SEARCH','SHOPPING','SMART','TRAVEL','UNKNOWN','UNSPECIFIED','VIDEO'];
const unreadable=()=>fail('Google returned inconsistent campaign data. Reload a shorter reporting period.',503);
const micro=v=>{
  if(typeof v!=='string'||!/^\d{1,13}(\.\d{1,6})?$/.test(v))unreadable();
  const [w,f='']=v.split('.'),n=BigInt(w)*1000000n+BigInt(f.padEnd(6,'0'));
  if(n>1000000000000000000n)unreadable();return n;
};
// Validate injected provider adapters as well as the existing Google Ads reader.
export function linkedGoogleRows(report){
  if(!report||!Array.isArray(report.rows)||report.rows.length>500||report.reported_campaigns!==report.rows.length||!report.totals)unreadable();
  let spend=0n,clicks=0n,impressions=0n;const identities=new Set();
  const rows=report.rows.map(r=>{
    if(!r||!id(r.campaign_id)||!name(r.campaign_name)||identities.has(r.campaign_id)||!count(r.clicks)||!count(r.impressions)||!statuses.includes(r.status)||!channels.includes(r.channel))unreadable();
    identities.add(r.campaign_id);spend+=micro(r.spend);clicks+=BigInt(r.clicks);impressions+=BigInt(r.impressions);
    return {campaign_id:r.campaign_id,campaign_name:r.campaign_name,spend:r.spend,clicks:r.clicks,impressions:r.impressions,status:r.status,channel:r.channel};
  });
  if(!count(report.totals.clicks)||!count(report.totals.impressions)||micro(report.totals.spend)!==spend||BigInt(report.totals.clicks)!==clicks||BigInt(report.totals.impressions)!==impressions)unreadable();
  return rows;
}
const lifetime=30*60*1000;
const proofBody=(scope,row,expiry)=>JSON.stringify(['korlix-google-campaign-link-v1',scope.actor,scope.funnel,scope.campaign,scope.fingerprint,expiry,row.provider_campaign_id,row.provider_campaign_name]);
export const googleCampaignChoiceProof=(secret,scope,row,now)=>{
  const expiry=now+lifetime;return `${expiry}.${createHmac('sha256',secret).update(proofBody(scope,row,expiry)).digest('hex')}`;
};
export function googleCampaignChoiceProofValid(secret,scope,row,proof,now){
  if(typeof proof!=='string'||!/^\d{13}\.[a-f0-9]{64}$/.test(proof))return false;
  const [expires,signature]=proof.split('.'),expiry=Number(expires);
  if(expiry<=now||expiry>now+lifetime)return false;
  return timingSafeEqual(Buffer.from(signature,'hex'),createHmac('sha256',secret).update(proofBody(scope,row,expiry)).digest());
}
export function registerGoogleCampaignLink(app,{base,owner,database,environment,googleAdsStore,googleAdsProvider,now=Date.now}){
  const config=googleAdsConfiguration(environment),store=googleAdsStore||createGoogleAdsStore(database),provider=googleAdsProvider||createGoogleAdsProvider(config,{now});
  const path=base+'/:id/campaigns/:campaign_id/google-link';
  const context=q=>({campaign_id:uuid(q.params.campaign_id),configured:config.ready,config_hash:config.hash});
  const command=async(actor,funnel,action,data)=>{
    if(!database)fail('Google campaign link storage is not configured.',503);
    const {data:out,error}=await database.rpc('korlix_funnel_google_campaign_link_v1',{p_actor:actor,p_action:action,p_funnel:funnel,p_data:data});
    if(error){const status={'42501':403,'P0002':404,'40001':409,'23505':409,'P0001':400,'23514':400}[error.code];fail(status?error.message:'Campaign link storage is temporarily unavailable.',status||503);}
    return out;
  };
  const scope=(actor,funnel,campaign,fp)=>({actor,funnel,campaign,fingerprint:fp});
  for(const action of ['read','save','clear']){
    const run=owner(async(q,r,u)=>{
      if(Object.keys(q.query).length)fail('Open the saved campaign link without extra parameters.');
      const funnel=uuid(q.params.id),data=context(q);
      if(action!=='read'){
        const b=q.body,keys=['version','fingerprint','confirmed',...(action==='save'?['provider_campaign_id','provider_campaign_name','proof']:[])];
        if(!ownKeys(b,keys)||!Number.isSafeInteger(b.version)||b.version<0||b.version>2147483646||!fingerprint(b.fingerprint)||b.confirmed!==true)fail('Reload and confirm the Google campaign association.');
        Object.assign(data,{version:b.version,fingerprint:b.fingerprint,confirmed:true});
        if(action==='save'){
          if(!id(b.provider_campaign_id)||!name(b.provider_campaign_name))fail('Choose a listed Google campaign.');
          const before=await command(u,funnel,'read',context(q));
          if(before.version!==b.version||before.fingerprint!==b.fingerprint)fail('The campaign or Google connection changed. Reload before linking.',409);
          if(!config.ready||!before.lookup_ready||!googleCampaignChoiceProofValid(config.secret,scope(u,funnel,data.campaign_id,b.fingerprint),b,b.proof,now()))fail('This Google campaign choice expired or could not be verified. Load the campaign list again.',400);
          Object.assign(data,{provider_campaign_id:b.provider_campaign_id,provider_campaign_name:b.provider_campaign_name});
        }
      }
      r.json(await command(u,funnel,action,data));
    },{ratePrefix:'google-campaign-link:',max:30});
    if(action==='read')app.get(path,run);else app.post(path+'/'+action,run);
  }
  for(const mode of ['campaigns','performance'])app.get(path+'/'+mode,owner(async(q,r,u)=>{
    if(!ownKeys(q.query,['days','fingerprint'])||!['7','30','90'].includes(q.query.days)||!fingerprint(q.query.fingerprint))fail('Choose 7, 30 or 90 completed reporting days from the current campaign link.');
    const funnel=uuid(q.params.id),data=context(q),before=await command(u,funnel,'read',data),days=Number(q.query.days);
    if(before.fingerprint!==q.query.fingerprint)fail('The campaign link or account changed. Reload before reporting.',409);
    if(!config.ready||!(mode==='campaigns'?before.lookup_ready:before.report_ready))fail('Connect the selected active Google account and refresh this campaign link first.',409);
    const access=async()=>{
      const c=await store.command(u,'secret');
      if(c.config_hash!==config.hash||c.needs_reconnect||(c.refresh_expires_at!=null&&(!Number.isFinite(Date.parse(c.refresh_expires_at))||Date.parse(c.refresh_expires_at)<=now()+60000))||c.version!==before.connection_version||c.root_id!==before.root_id||c.login_customer_id!==before.login_customer_id||c.selected_account!==before.account?.id||!Array.isArray(c.roots)||!c.roots.includes(c.root_id)||!Array.isArray(c.accounts)||!c.accounts.some(a=>a.id===c.selected_account&&a.manager===false&&a.status==='ENABLED'))fail('The Google connection changed. Reload before reporting.',409);
      return c;
    };
    const c=await access();
    let account,range,rows;
    try{
      const refresh=googleTokenCipher(config.key).open(c.sealed,`korlix-google-ads:refresh:${u}:${c.binding_id}`);
      const token=await provider.refresh(refresh);
      const roots=await provider.roots(token);
      if(!Array.isArray(roots)||!roots.includes(c.root_id))fail('Google access to this account was removed. Refresh access accounts.',409);
      account=await provider.account(token,c.selected_account,c.login_customer_id);
      if(!account||account.id!==before.account.id||account.currency!==before.account.currency||account.timezone!==before.account.timezone||account.status!=='ENABLED'||account.manager!==false||account.test_account!==before.account.test_account)fail('Google account details changed. Refresh ad accounts before continuing.',409);
      range=googleReportRange(days,account.timezone,now());
      rows=linkedGoogleRows(await provider.campaignPerformance(token,account,c.login_customer_id,range));
    }catch(e){if(e instanceof GoogleAdsAccessError)await store.command(u,'invalid',{version:c.version});throw e;}
    // Reject late data after disconnect/reselect, entitlement loss, archive,
    // relink, plan/page edits or a new reporting calendar day.
    const after=await command(u,funnel,mode==='performance'?'measure':'read',{...data,...(mode==='performance'?{fingerprint:before.fingerprint,...range}:{})});
    if(after.fingerprint!==before.fingerprint||!(mode==='campaigns'?after.lookup_ready:after.report_ready)||JSON.stringify(googleReportRange(days,account.timezone,now()))!==JSON.stringify(range))fail('The campaign, connection or reporting day changed while loading. Reload and try again.',409);
    const latest=await access();if(latest.binding_id!==c.binding_id)fail('The Google connection changed while loading. Reload.',409);
    const common={source:mode==='campaigns'?'google_campaign_choices':'google_linked_performance',funnel_id:funnel,campaign_id:data.campaign_id,fingerprint:after.fingerprint,connection_version:after.connection_version,root_id:after.root_id,login_customer_id:after.login_customer_id,account:after.account,range,fetched_at:new Date(now()).toISOString(),ad_publishing_ready:false,attribution_verified:false};
    if(mode==='campaigns'){
      const choices=rows.map(row=>{const choice={provider_campaign_id:row.campaign_id,provider_campaign_name:row.campaign_name};return {...choice,proof:googleCampaignChoiceProof(config.secret,scope(u,funnel,data.campaign_id,before.fingerprint),choice,now())};});
      r.json({...common,choices});
    }else{
      const row=rows.find(x=>x.campaign_id===after.link.provider_campaign_id)??null;
      r.json({...common,link:after.link,row,measurement:after.measurement});
    }
  },{ratePrefix:'google-ads-performance:',max:10}));
}
