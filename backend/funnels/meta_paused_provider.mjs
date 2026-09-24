import {createHash,createHmac} from 'node:crypto';
import {fail,FunnelError} from './core.mjs';
import {boundedMetaPageJson} from './meta_pages.mjs';
import {metaCreativeAssets} from './meta_creative.mjs';
import {metaTargetingAssets} from './meta_targeting.mjs';
export class MetaPausedAccessError extends FunnelError {constructor(){super('Meta advertising access expired or was removed. Reconnect the saved account and Page.',409);}}
const id=v=>typeof v==='string'&&/^[1-9][0-9]{0,39}$/.test(v);
const imageHash=v=>typeof v==='string'&&/^[a-f0-9]{32}$/.test(v);
const uncertain=()=>fail('Meta did not return a verifiable creation result. Check the saved record and Meta Ads Manager.',409);
const stable=v=>Array.isArray(v)?'['+v.map(stable).join(',')+']':v&&typeof v==='object'?'{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+stable(v[k])).join(',')+'}':JSON.stringify(v);
export const metaCreationDigest=v=>createHash('sha256').update(stable(v)).digest('hex');
export function metaCreationResources(r,complete=false){
  const names=['image_hash','campaign','ad_set','creative','ad'];
  if(!r||typeof r!=='object'||Array.isArray(r)||Object.keys(r).some(k=>!names.includes(k))||complete&&Object.keys(r).length!==5)uncertain();
  for(let i=0;i<Object.keys(r).length;i++){const k=names[i];if(!Object.hasOwn(r,k)||!(k==='image_hash'?imageHash(r[k]):id(r[k])))uncertain();}
  if(new Set(Object.entries(r).filter(([k])=>k!=='image_hash').map(([,v])=>v)).size!==Object.keys(r).length-(r.image_hash?1:0))uncertain();
  return Object.fromEntries(names.filter(k=>r[k]).map(k=>[k,r[k]]));
}
export function metaPausedPlan(s){
  if(!s||!/^KORLIX [a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(s.provider_name)||!/^act_[1-9][0-9]{0,39}$/.test(s.identity?.account?.id)||!id(s.identity?.page?.id)||s.identity.account.currency!=='USD'||s.identity.account.status!==1||s.budget_acknowledged!==true)fail('The saved Meta campaign identity is invalid.',409);
  const a=metaCreativeAssets(s.creative),t=metaTargetingAssets(s.targeting),p=s.plan;
  if(!a.primary_text||!a.headline||!a.image_id||!a.image_alt||s.image?.id!==a.image_id||! /^[a-f0-9]{64}$/.test(s.image.sha256)||t.placements!=='facebook_feed'||stable(t.categories)!=='["NONE"]'||!Number.isInteger(p?.daily_cents)||p.daily_cents<100||p.daily_cents>1000000||!Number.isInteger(p.days)||p.days<1||p.days>90)fail('Complete the image, creative, Facebook Feed and ordinary-category campaign details.',409);
  let destination;try{destination=new URL(s.page.destination);}catch{fail('The saved destination is invalid.',409);}
  if(destination.protocol!=='https:'||destination.username||destination.password||destination.hash||destination.searchParams.get('utm_source')!=='facebook'||destination.searchParams.get('utm_campaign')!=='k143_'+p.id.replaceAll('-',''))fail('The saved destination is invalid.',409);
  const start=Date.parse(s.start_time),end=Date.parse(s.end_time);
  if(!Number.isFinite(start)||!Number.isFinite(end)||end<=start||end-start>91*86400000||!/^\d{4}-\d{2}-\d{2}$/.test(s.start_date)||!/^\d{4}-\d{2}-\d{2}$/.test(s.end_date))fail('The saved Meta schedule is invalid.',409);
  let geo;
  if(t.countries.length)geo={countries:[...t.countries].sort()};
  else if(t.custom_locations?.length)geo={custom_locations:t.custom_locations.map(x=>({latitude:x.latitude_micro/1000000,longitude:x.longitude_micro/1000000,radius:x.radius_meters/1000,distance_unit:'kilometer'}))};
  else if(t.geo_locations?.length){geo={};for(const [type,key]of [['city','cities'],['region','regions']]){const rows=t.geo_locations.filter(x=>x.type===type).map(x=>({key:x.key}));if(rows.length)geo[key]=rows;}}
  else fail('Choose a saved target area.',409);
  return {
    campaign:{name:s.provider_name+' Campaign',objective:'OUTCOME_TRAFFIC',buying_type:'AUCTION',special_ad_categories:[],is_adset_budget_sharing_enabled:false,status:'PAUSED'},
    ad_set:{name:s.provider_name+' Ad set',daily_budget:p.daily_cents,billing_event:'IMPRESSIONS',optimization_goal:'LINK_CLICKS',bid_strategy:'LOWEST_COST_WITHOUT_CAP',destination_type:'WEBSITE',start_time:Math.floor(start/1000),end_time:Math.floor(end/1000),is_dynamic_creative:false,targeting:{age_min:t.age_min,age_max:t.age_max,geo_locations:geo,publisher_platforms:['facebook'],facebook_positions:['feed'],device_platforms:['mobile','desktop'],targeting_automation:{advantage_audience:0}},status:'PAUSED'},
    creative:{name:s.provider_name+' Creative',object_story_spec:{page_id:s.identity.page.id,link_data:{link:destination.href,message:a.primary_text,name:a.headline,description:a.description,call_to_action:{type:a.cta,value:{link:destination.href}}}}},
    ad:{name:s.provider_name+' Ad',status:'PAUSED'}
  };
}
export async function prepareMetaImage(result,snapshot){
  if(typeof result?.content!=='string'||result.content.length>710000)fail('The saved image could not be verified.',409);
  const bytes=Buffer.from(result.content,'base64');
  if(!bytes.length||bytes.length>524288||createHash('sha256').update(bytes).digest('hex')!==snapshot.image.sha256||result.width!==snapshot.image.width||result.height!==snapshot.image.height)fail('The saved image changed. Reload the creative review.',409);
  try{
    const {default:sharp}=await import('sharp');
    const image=sharp(bytes,{limitInputPixels:2560000,failOn:'warning',animated:false}),meta=await image.metadata();
    if(meta.format!=='webp'||(meta.pages??1)!==1||meta.width!==result.width||meta.height!==result.height)throw Error();
    const png=await image.png().timeout({seconds:10}).toBuffer();if(png.length>10485760)throw Error();
    return {bytes:png,sha256:createHash('sha256').update(png).digest('hex')};
  }catch{fail('The saved image could not be prepared for Meta. Choose another image.',409);}
}
export function createMetaPausedProvider(config,{fetchImpl=fetch,now=Date.now}={}){
  async function call(path,params,token,write=false){
    if(config.apiVersion!=='v26.0')fail('Paused Meta creation requires the supported API version.',409);
    const url=new URL(`https://graph.facebook.com/v26.0/${path}`),body=new URLSearchParams();
    for(const [k,v]of Object.entries(params))body.set(k,typeof v==='object'?JSON.stringify(v):String(v));
    body.set('appsecret_proof',createHmac('sha256',config.secret).update(token).digest('hex'));
    if(!write)url.search=body.toString();
    let response,data;
    try{response=await fetchImpl(url,{method:write?'POST':'GET',headers:{Authorization:`Bearer ${token}`,...(write?{'Content-Type':'application/x-www-form-urlencoded'}:{})},...(write?{body:body.toString()}:{}),redirect:'error',signal:AbortSignal.timeout(10000)});data=await boundedMetaPageJson(response);}catch{fail('Meta could not confirm the request. Check the creation record before continuing.',503);}
    if(!response.ok||data.error){if([10,190,200,283].includes(data.error?.code))throw new MetaPausedAccessError();fail('Meta could not complete this paused creation request. Check account eligibility and the saved creation record.',409);}
    return data;
  }
  async function access(token,user,page){
    const debug=await call('debug_token',{input_token:token},`${config.id}|${config.secret}`),d=debug.data;
    if(!d?.is_valid||d.type!=='USER'||String(d.app_id)!==config.id||d.user_id!==user||!Number.isSafeInteger(d.expires_at)||d.expires_at*1000<=now()+60000||(d.data_access_expires_at!==0&&(!Number.isSafeInteger(d.data_access_expires_at)||d.data_access_expires_at*1000<=now()+60000)))throw new MetaPausedAccessError();
    if(!Array.isArray(d.scopes)||!(page?['ads_management','pages_show_list','pages_read_engagement','pages_manage_ads']:['ads_management']).every(x=>d.scopes.includes(x)))fail('Reconnect Meta with advertising management and Page advertising permissions after platform approval.',409);
    if(!page)return {verified:true};
    let after,found=null;const cursors=new Set();
    for(let n=0;n<5;n++){
      const r=await call('me/accounts',{fields:'id,name,category,tasks',limit:100,...(after?{after}:{})},token);
      if(!Array.isArray(r.data)||r.data.length>100)uncertain();
      for(const p of r.data){if(p.id===page.id){if(found||p.name!==page.name||(p.category||'')!==page.category||!Array.isArray(p.tasks)||!p.tasks.some(x=>['ADVERTISE','MANAGE'].includes(x)))fail('The saved Page or its advertising permissions changed. Refresh Meta Pages and review again.',409);found=true;}}
      if(!r.paging?.next){if(!found)fail('The saved Page is no longer shared for advertising.',409);return {verified:true};}
      after=r.paging?.cursors?.after;if(typeof after!=='string'||!after||after.length>4000||cursors.has(after))uncertain();cursors.add(after);
    }
    fail('Limit the shared Pages to 500 before creating ads.',409);
  }
  function params(s,resources,stage){
    const p=metaPausedPlan(s),r=metaCreationResources(resources);
    if(stage==='campaign')return p.campaign;
    if(stage==='ad_set'&&r.campaign)return {...p.ad_set,campaign_id:r.campaign};
    if(stage==='creative'&&r.image_hash)return {...p.creative,object_story_spec:{...p.creative.object_story_spec,link_data:{...p.creative.object_story_spec.link_data,image_hash:r.image_hash}}};
    if(stage==='ad'&&r.ad_set&&r.creative)return {...p.ad,adset_id:r.ad_set,creative:{creative_id:r.creative}};
    fail('The preceding Meta creation receipt is missing.',409);
  }
  const edges={campaign:'campaigns',ad_set:'adsets',creative:'adcreatives',ad:'ads'};
  async function validate(token,s,resources,stage){
    const body=params(s,resources,stage),r=await call(s.identity.account.id+'/'+edges[stage],{...body,execution_options:['validate_only']},token,true);
    if(r.success!==true||Object.keys(r).some(k=>k!=='success'))uncertain();return {validated:true};
  }
  async function create(token,s,resources,stage,png){
    if(stage==='image_hash'){
      if(!Buffer.isBuffer(png)||png.length>10485760||!png.subarray(0,8).equals(Buffer.from('89504e470d0a1a0a','hex')))uncertain();
      const r=await call(s.identity.account.id+'/adimages',{bytes:png.toString('base64')},token,true),images=r.images;
      if(!images||typeof images!=='object'||Array.isArray(images)||Object.keys(images).length!==1)uncertain();const value=Object.values(images)[0]?.hash;if(!imageHash(value))uncertain();return value;
    }
    const body=params(s,resources,stage),r=await call(s.identity.account.id+'/'+edges[stage],body,token,true);
    if(!id(r.id)||Object.keys(r).some(k=>k!=='id'))uncertain();return r.id;
  }
  async function find(token,s,known,controls=false){
    metaCreationResources(known,controls);if(!known.image_hash)return null;
    const p=metaPausedPlan(s),account=s.identity.account.id.slice(4);let campaign=null,after;const cursors=new Set();
    const allowed=controls?['PAUSED','ACTIVE']:['PAUSED'];
    const cf='id,account_id,name,objective,buying_type,special_ad_categories,status,is_adset_budget_sharing_enabled'+(controls?',effective_status,daily_budget,lifetime_budget,is_budget_schedule_enabled':'');
    if(known.campaign)campaign=await call(known.campaign,{fields:cf},token);
    else {
      for(let n=0;n<5;n++){
        const out=await call(s.identity.account.id+'/campaigns',{fields:cf,limit:100,...(after?{after}:{})},token);
        if(!Array.isArray(out.data)||out.data.length>100)uncertain();for(const c of out.data){if(c.name===p.campaign.name){if(campaign)uncertain();campaign=c;}}
        if(!out.paging?.next)break;
        after=out.paging?.cursors?.after;if(n===4||typeof after!=='string'||!after||after.length>4000||cursors.has(after))uncertain();cursors.add(after);
      }
    }
    if(!campaign)return null;
    if(!id(campaign.id)||campaign.account_id!==account||campaign.name!==p.campaign.name||!allowed.includes(campaign.status)||campaign.objective!=='OUTCOME_TRAFFIC'||campaign.buying_type!=='AUCTION'||stable(campaign.special_ad_categories)!=='[]'||campaign.is_adset_budget_sharing_enabled!==false)uncertain();
    const sets=await call(campaign.id+'/adsets',{fields:'id,account_id,campaign_id,name,status,daily_budget,billing_event,optimization_goal,bid_strategy,destination_type,start_time,end_time,is_dynamic_creative,targeting'+(controls?',effective_status,lifetime_budget,is_budget_schedule_enabled':''),limit:2},token);
    const ads=await call(campaign.id+'/ads',{fields:'id,account_id,campaign_id,adset_id,name,status,creative{id}'+(controls?',effective_status,issues_info,ad_review_feedback,failed_delivery_checks':''),limit:2},token);
    if(!Array.isArray(sets.data)||!Array.isArray(ads.data)||sets.paging?.next||ads.paging?.next||sets.data.length>1||ads.data.length>1)uncertain();
    if(!sets.data.length||!ads.data.length)return null;
    const a=sets.data[0],ad=ads.data[0];
    for(const [k,v]of Object.entries(p.ad_set)){
      if(k==='targeting')continue;
      if(k==='status'){if(!allowed.includes(a.status))uncertain();continue;}
      if(k==='start_time'||k==='end_time'){if(Date.parse(a[k])/1000!==v)uncertain();}
      else if(k==='daily_budget'){if(String(a[k])!==String(v))uncertain();}
      else if(a[k]!==v)uncertain();
    }
    // Ignore provider display labels, but reject additions to the modeled target sets.
    const t=a.targeting,e=p.ad_set.targeting;
    if(!t||Object.keys(t).some(k=>!Object.hasOwn(e,k))||t.age_min!==e.age_min||t.age_max!==e.age_max||stable([...(t.publisher_platforms||[])].sort())!==stable(['facebook'])||stable([...(t.facebook_positions||[])].sort())!==stable(['feed'])||stable([...(t.device_platforms||[])].sort())!==stable(['desktop','mobile'])||stable(t.targeting_automation)!==stable(e.targeting_automation))uncertain();
    const geo=t.geo_locations;if(!geo||Object.keys(geo).some(k=>!['countries','custom_locations','cities','regions','location_types'].includes(k)))uncertain();
    for(const key of ['countries','custom_locations','cities','regions']){
      const values=geo[key]||[],expected=e.geo_locations[key]||[];
      if(key==='custom_locations'&&values.some(x=>!x||Object.keys(x).some(k=>!['latitude','longitude','radius','distance_unit','name','address_string'].includes(k))))uncertain();
      if(['cities','regions'].includes(key)&&values.some(x=>!x||Object.keys(x).some(k=>!['key','name','country','region','region_id'].includes(k))))uncertain();
      const normalize=x=>key==='countries'?x:key==='custom_locations'?{latitude:Number(x.latitude),longitude:Number(x.longitude),radius:Number(x.radius),distance_unit:x.distance_unit}:{key:x.key};
      if(!Array.isArray(values)||stable(values.map(normalize).sort((a,b)=>stable(a).localeCompare(stable(b))))!==stable(expected.map(normalize).sort((a,b)=>stable(a).localeCompare(stable(b)))))uncertain();
    }
    if(!id(a.id)||a.account_id!==account||a.campaign_id!==campaign.id||!id(ad.id)||ad.account_id!==account||ad.campaign_id!==campaign.id||ad.adset_id!==a.id||ad.name!==p.ad.name||!allowed.includes(ad.status)||!id(ad.creative?.id))uncertain();
    const cr=await call(ad.creative.id,{fields:'id,account_id,name,object_story_spec'},token),link=cr.object_story_spec?.link_data,expect=params(s,{image_hash:known.image_hash,campaign:campaign.id,ad_set:a.id},'creative').object_story_spec;
    if(Object.keys(cr.object_story_spec||{}).some(k=>!['page_id','link_data'].includes(k))||(link&&Object.keys(link).some(k=>!['link','message','name','description','image_hash','call_to_action'].includes(k)))||cr.id!==ad.creative.id||cr.account_id!==account||cr.name!==p.creative.name||cr.object_story_spec?.page_id!==s.identity.page.id||!link)uncertain();
    for(const key of ['link','message','name','description','image_hash'])if(link[key]!==expect.link_data[key])uncertain();
    if(Object.keys(link.call_to_action||{}).some(k=>!['type','value'].includes(k))||Object.keys(link.call_to_action?.value||{}).some(k=>k!=='link')||link.call_to_action?.type!==expect.link_data.call_to_action.type||link.call_to_action?.value?.link!==expect.link_data.call_to_action.value.link)uncertain();
    const found=metaCreationResources({image_hash:known.image_hash,campaign:campaign.id,ad_set:a.id,creative:cr.id,ad:ad.id},true);
    for(const [k,v]of Object.entries(known))if(found[k]!==v)uncertain();
    if(controls){
      budgetModes(campaign,a);
      const effective={campaign:campaign.effective_status,ad_set:a.effective_status,ad:ad.effective_status};
      if(!['ACTIVE','PAUSED'].includes(effective.campaign)||!['ACTIVE','PAUSED','CAMPAIGN_PAUSED','IN_PROCESS'].includes(effective.ad_set)||!['ACTIVE','PAUSED','CAMPAIGN_PAUSED','ADSET_PAUSED','PENDING_REVIEW','IN_PROCESS','PREAPPROVED'].includes(effective.ad))fail('Meta reports a delivery or review restriction. Check Ads Manager before activation.',409);
      for(const key of ['issues_info','failed_delivery_checks'])if(ad[key]!=null&&(!Array.isArray(ad[key])||ad[key].length))fail('Meta reports an ad issue. Review it in Ads Manager.',409);
      if(ad.ad_review_feedback!=null&&(typeof ad.ad_review_feedback!=='object'||Array.isArray(ad.ad_review_feedback)||Object.keys(ad.ad_review_feedback).length))fail('Meta returned review feedback. Resolve it in Ads Manager before activation.',409);
      return {resources:found,statuses:{campaign:campaign.status,ad_set:a.status,ad:ad.status},effective_statuses:effective};
    }
    return found;
  }
  async function status(token,s,r){
    metaCreationResources(r,true);
    const out=await call(r.campaign,{fields:'id,account_id,name,status,effective_status'},token);
    if(out.id!==r.campaign||out.account_id!==s.identity.account.id.slice(4)||typeof out.name!=='string'||out.name.length>1000||!['ACTIVE','PAUSED','ARCHIVED','DELETED'].includes(out.status)||typeof out.effective_status!=='string'||!/^[A-Z_]{1,40}$/.test(out.effective_status))uncertain();
    return {resource:out.id,name:out.name,status:out.status,effective_status:out.effective_status};
  }
  async function control(token,s,r,action,stage,validateOnly=false){
    metaCreationResources(r,true);
    if(!['activate','pause'].includes(action)||!['ad','ad_set','campaign'].includes(stage)||action==='pause'&&stage!=='campaign'||!/^act_[1-9][0-9]{0,39}$/.test(s.identity?.account?.id))fail('Choose a supported Meta status command.',409);
    const target=action==='activate'?'ACTIVE':'PAUSED';
    const out=await call(r[stage],{status:target,...(validateOnly?{execution_options:['validate_only']}:{})},token,true);
    if(out.success!==true||Object.keys(out).some(k=>k!=='success'))uncertain();
    return validateOnly?{validated:true}:{confirmed:true,resource:r[stage],stage,status:target};
  }
  const zero=v=>v==null||v===0||v==='0';
  function budgetModes(c,a){
    if(c.is_adset_budget_sharing_enabled!==false||c.is_budget_schedule_enabled!==false||a.is_budget_schedule_enabled!==false||!zero(c.daily_budget)||!zero(c.lifetime_budget)||!zero(a.lifetime_budget))fail('Meta budget sharing, scheduling or lifetime budgets are not supported here. Check Ads Manager.',409);
  }
  async function budget(token,s,r){
    metaCreationResources(r,true);const p=metaPausedPlan(s),account=s.identity.account.id.slice(4);
    const c=await call(r.campaign,{fields:'id,account_id,name,status,effective_status,daily_budget,lifetime_budget,is_adset_budget_sharing_enabled,is_budget_schedule_enabled'},token);
    const sets=await call(r.campaign+'/adsets',{fields:'id,account_id,campaign_id,name,status,effective_status,daily_budget,lifetime_budget,is_budget_schedule_enabled',limit:2},token);
    if(c.id!==r.campaign||c.account_id!==account||c.name!==p.campaign.name||!['ACTIVE','PAUSED'].includes(c.status)||!Array.isArray(sets.data)||sets.data.length!==1||sets.paging?.next)uncertain();
    const a=sets.data[0];if(a.id!==r.ad_set||a.account_id!==account||a.campaign_id!==r.campaign||a.name!==p.ad_set.name||!['ACTIVE','PAUSED'].includes(a.status)||String(a.daily_budget)!==String(s.plan.daily_cents))uncertain();
    for(const v of [c.effective_status,a.effective_status])if(typeof v!=='string'||!/^[A-Z_]{1,40}$/.test(v))uncertain();
    budgetModes(c,a);
    return {status:{resource:c.id,name:c.name,status:c.status,effective_status:c.effective_status},budget:{resource:a.id,daily_cents:s.plan.daily_cents,status:a.status,effective_status:a.effective_status}};
  }
  async function budgetWrite(token,s,r,cents,validateOnly=false){
    metaCreationResources(r,true);metaPausedPlan(s);
    if(!Number.isSafeInteger(cents)||cents<100||cents>1000000||cents===s.plan.daily_cents)fail('Choose a changed Meta average daily budget from $1.00 to $10,000.00 USD.',409);
    const out=await call(r.ad_set,{daily_budget:cents,...(validateOnly?{execution_options:['validate_only']}:{})},token,true);
    if(out.success!==true||Object.keys(out).some(k=>k!=='success'))uncertain();
    return validateOnly?{validated:true}:{confirmed:true,resource:r.ad_set,daily_cents:cents};
  }
  return {inspectMetaBudget:budget,validateMetaBudget:(token,s,r,cents)=>budgetWrite(token,s,r,cents,true),applyMetaBudget:budgetWrite,verifyMetaControlAccess:(token,user)=>access(token,user,null),createdMetaStatus:status,inspectCreatedMeta:(token,s,r)=>find(token,s,r,true),validateMetaControl:(token,s,r,action,stage)=>control(token,s,r,action,stage,true),applyMetaControlStage:control,verifyCreationAccess:access,validatePausedMeta:validate,createPausedMetaResource:create,findPausedMeta:find};
}
