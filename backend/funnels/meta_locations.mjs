import {createHmac,timingSafeEqual} from 'node:crypto';
import {fail} from './core.mjs';
import catalog from './meta_targeting_catalog.json' with {type:'json'};

const countries=new Set(catalog.countries.map(x=>x.code));
const clean=(v,min,max)=>typeof v==='string'&&[...v].length>=min&&[...v].length<=max&&v.trim()===v&&!/[\x00-\x1f\x7f-\x9f<>\u2028\u2029\uD800-\uDFFF]/u.test(v);
export const metaLocationIdentity=v=>`${v.type}:${v.key}`;
export function metaLocationValid(v){return !!v&&typeof v==='object'&&!Array.isArray(v)&&Object.keys(v).length===5&&typeof v.key==='string'&&/^[0-9]{1,40}$/.test(v.key)&&clean(v.name,1,200)&&countries.has(v.country)&&['city','region'].includes(v.type)&&clean(v.region,0,200);}
export function metaLocationsValid(v){return Array.isArray(v)&&v.length<=20&&v.every(metaLocationValid)&&new Set(v.map(metaLocationIdentity)).size===v.length;}
export function metaLocationSearchInput(v){
  if(!v||Object.keys(v).length!==4||Object.keys(v).some(k=>!['q','country','kind','fingerprint'].includes(k))||!clean(v.q,2,80)||!countries.has(v.country)||!['all','city','region'].includes(v.kind)||typeof v.fingerprint!=='string'||!/^[a-f0-9]{64}$/.test(v.fingerprint))fail('Choose a country and enter 2–80 characters to search Meta cities or regions.');
  return {q:v.q,country:v.country,kind:v.kind,fingerprint:v.fingerprint};
}
// One bounded page; never follow a provider URL. Results do not assert eligibility.
export async function readMetaLocations(graph,token,input){
  const r=await graph('search',{type:'adgeolocation',q:input.q,country_code:input.country,location_types:JSON.stringify(input.kind==='all'?['city','region']:[input.kind]),limit:31},token,'location');
  if(!Array.isArray(r.data)||r.data.length>31||(r.paging?.next!=null&&typeof r.paging.next!=='string'))fail('Meta returned unreadable location results.',503);
  const rows=r.data.map(x=>({key:x?.key,name:x?.name,country:x?.country_code,type:x?.type,region:x?.region??''}));
  if(rows.some(x=>!metaLocationValid(x)||x.country!==input.country||(input.kind!=='all'&&x.type!==input.kind))||new Set(rows.map(metaLocationIdentity)).size!==rows.length)fail('Meta returned inconsistent location results. Search again.',503);
  return {locations:rows.slice(0,30),more:rows.length>30||!!r.paging?.next};
}
const lifetime=30*60*1000;
const payload=(scope,row,expiry)=>JSON.stringify(['korlix-meta-location-v1',scope.actor,scope.funnel,scope.campaign,scope.fingerprint,expiry,row.key,row.name,row.country,row.type,row.region]);
export function metaLocationProof(secret,scope,row,now){
  const expiry=now+lifetime;
  return `${expiry}.${createHmac('sha256',secret).update(payload(scope,row,expiry)).digest('hex')}`;
}
export function metaLocationProofValid(secret,scope,row,proof,now){
  if(typeof proof!=='string'||!/^\d{13}\.[a-f0-9]{64}$/.test(proof))return false;
  const [expires,signature]=proof.split('.'),expiry=Number(expires);
  if(expiry<=now||expiry>now+lifetime)return false;
  return timingSafeEqual(Buffer.from(signature,'hex'),createHmac('sha256',secret).update(payload(scope,row,expiry)).digest());
}
export const sameMetaLocation=(a,b)=>['key','name','country','type','region'].every(k=>a[k]===b[k]);
