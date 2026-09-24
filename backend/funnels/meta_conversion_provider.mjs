import {fail,FunnelError} from './core.mjs';

export class MetaConversionAccessError extends FunnelError {
  constructor(){super('Meta data source access is unavailable. Review the assets and permissions shared with KORLIX before loading the list again.',409);}
}
export const metaDestinationFields=['pixel_id','name'];
const object=v=>v&&typeof v==='object'&&!Array.isArray(v);
const unreadable=()=>fail('Meta returned an unreadable data source list. Refresh account access before trying again.',503);
export function metaDestination(d){
  if(!object(d)||Object.keys(d).length!==2||!metaDestinationFields.every(k=>Object.hasOwn(d,k))||typeof d.pixel_id!=='string'||!/^\d{1,40}$/.test(d.pixel_id)||typeof d.name!=='string'||!d.name||d.name.length>1000||d.name.trim()!==d.name||/[\x00-\x1f\x7f]/.test(d.name))unreadable();
  return {pixel_id:d.pixel_id,name:d.name};
}
export function metaDestinationList(rows){
  if(!Array.isArray(rows)||rows.length>500)unreadable();
  const seen=new Set();return rows.map(row=>{const d=metaDestination(row);if(seen.has(d.pixel_id))unreadable();seen.add(d.pixel_id);return d;});
}
// Account edge membership is the only claim. It does not prove event write
// permission, website ownership, dataset eligibility or conversion attribution.
export async function readMetaDestinations(graph,token,accountId){
  if(typeof accountId!=='string'||!/^act_\d{1,40}$/.test(accountId))fail('Choose an active Meta ad account.');
  const rows=[],seen=new Set(),cursors=new Set();let after;
  for(let page=0;page<5;page++){
    const r=await graph(`${accountId}/adspixels`,{fields:'id,name',limit:100,...(after?{after}:{})},token,'conversion');
    if(!object(r)||!Array.isArray(r.data)||r.data.length>100)unreadable();
    for(const raw of r.data){
      if(!object(raw))unreadable();
      const d=metaDestination({pixel_id:raw.id,name:raw.name});
      if(seen.has(d.pixel_id))unreadable();seen.add(d.pixel_id);rows.push(d);
    }
    if(r.paging!=null&&!object(r.paging))unreadable();
    if(r.paging?.next==null)return rows;
    if(typeof r.paging.next!=='string'||!r.paging.next||!r.data.length)unreadable();
    after=r.paging.cursors?.after;
    if(typeof after!=='string'||!after||after.length>4000||/[\x00-\x20\x7f]/.test(after)||cursors.has(after))unreadable();
    cursors.add(after);
  }
  fail('More than 500 Meta data sources were returned. Limit the assets shared with KORLIX before loading again.',409);
}
