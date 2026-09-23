import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {fail} from './core.mjs';
import countries from './google_targeting_catalog.json' with {type:'json'};

export const googleLocationVersion='google-locations-2026-08-12';
const data=JSON.parse(gunzipSync(readFileSync(new URL('./google_locations_catalog.json.gz',import.meta.url)),{maxOutputLength:16*1024*1024}));
if(data.version!==googleLocationVersion)throw Error('Google location reference version mismatch');
const knownCountries=new Set(countries.countries.map(x=>x.code));
const byId=new Map(),byCountry=new Map();
const fold=s=>s.normalize('NFKD').replace(/\p{M}/gu,'').toLowerCase();
for(const [id,name,country,type] of data.rows){
  const row=Object.freeze({id,name,country,type});byId.set(id,row);
  const rows=byCountry.get(country)||[];rows.push({row,search:fold(name),short:fold(name.split(',')[0])});byCountry.set(country,rows);
}
export function googleLocationsValid(v){
  return Array.isArray(v)&&v.length<=20&&new Set(v.map(x=>x?.id)).size===v.length&&v.every(x=>{
    if(!x||typeof x!=='object'||Array.isArray(x)||Object.keys(x).length!==4)return false;
    const r=byId.get(x.id);return !!r&&['id','name','country','type'].every(k=>x[k]===r[k]);
  });
}
export function googleLocationSearchInput(q){
  if(!q||Object.keys(q).length!==3||Object.keys(q).some(k=>!['q','country','kind'].includes(k))||typeof q.q!=='string'||[...q.q].length<2||[...q.q].length>80||q.q.trim()!==q.q||/[\x00-\x1f\x7f-\x9f<>\u2028\u2029\uD800-\uDFFF]/u.test(q.q)||!knownCountries.has(q.country)||!['all','city','region'].includes(q.kind))fail('Choose a country and enter 2–80 characters to search cities or regions.');
  return {q:q.q,country:q.country,kind:q.kind};
}
export function searchGoogleLocations(input){
  const {q,country,kind}=googleLocationSearchInput(input),query=fold(q),tokens=query.split(/[\s,]+/).filter(Boolean);
  if(!tokens.length)fail('Enter a city or region name.');
  const matches=(byCountry.get(country)||[]).filter(x=>(kind==='all'||(kind==='city')===(x.row.type==='City'))&&tokens.every(t=>x.search.includes(t)));
  const rank=x=>x.short===query||query.startsWith(x.short+' ')||query.startsWith(x.short+',')?0:x.short.startsWith(query)?1:2;
  matches.sort((a,b)=>rank(a)-rank(b)||a.row.name.localeCompare(b.row.name,'en')||Number(a.row.id)-Number(b.row.id));
  return {source:'google_location_catalog',catalog_version:googleLocationVersion,country,query:q,kind,more:matches.length>30,locations:matches.slice(0,30).map(x=>x.row)};
}
