import {fail,FunnelError,version} from './core.mjs';
export class MetaPageAccessError extends FunnelError {
  constructor(){super('Page access is unavailable. Check the Pages shared with KORLIX and reconnect Meta after Page permissions are approved.',409);}
}
export function metaPageInput(body={},select=false) {
  const keys=['version','account_id',...(select?['page_id']:[])];
  if(!body||typeof body!=='object'||Array.isArray(body)||Object.keys(body).some(k=>!keys.includes(k))||typeof body.account_id!=='string'||!/^act_\d{1,40}$/.test(body.account_id)|| (select&&(typeof body.page_id!=='string'||!/^\d{1,40}$/.test(body.page_id))))fail('Choose the current Meta ad account and a shared Page.');
  return {version:version(body.version),account_id:body.account_id,...(select?{page_id:body.page_id}:{})};
}
// Explicit fields exclude Page tokens. Membership comes from /me/accounts,
// never from a publicly readable Page node. Selection does not prove ad eligibility.
export async function readMetaPages(graph,token) {
  const permissions=await graph('me/permissions',{fields:'permission,status',limit:100},token,true);
  if(!Array.isArray(permissions.data)||permissions.data.length>100||permissions.paging?.next||permissions.data.some(p=>!p||typeof p.permission!=='string'||p.permission.length>100||!['granted','declined','expired'].includes(p.status)))fail('Meta returned unreadable Page permissions.',503);
  if(!permissions.data.some(p=>p.permission==='pages_show_list'&&p.status==='granted'))throw new MetaPageAccessError();
  const found=new Map(),cursors=new Set();let after;
  for(let page=0;page<5;page++){
    const r=await graph('me/accounts',{fields:'id,name,category',limit:100,...(after?{after}:{})},token,true);
    if(!Array.isArray(r.data)||r.data.length>100)fail('Meta returned an unreadable Page list.',503);
    for(const p of r.data){
      if(!p||typeof p.id!=='string'||!/^\d{1,40}$/.test(p.id)||typeof p.name!=='string'||!p.name.trim()||p.name.length>200|| (p.category!=null&&(typeof p.category!=='string'||p.category.length>200))||found.has(p.id))fail('Meta returned an unreadable or repeated Page.',503);
      found.set(p.id,{id:p.id,name:p.name.trim(),category:p.category||''});
    }
    if(!r.paging?.next)return [...found.values()];
    after=r.paging?.cursors?.after;
    if(typeof after!=='string'||!after||after.length>4000||cursors.has(after))fail('Meta Page pagination could not be completed.',503);
    cursors.add(after);
  }
  fail('More than 500 Pages were returned. Limit the Pages shared with KORLIX and reconnect.',409);
}
export async function boundedMetaPageJson(response) {
  const reader=response.body?.getReader();if(!reader)throw Error();
  let size=0;const chunks=[];
  try{for(;;){const {done,value}=await reader.read();if(done)break;size+=value.byteLength;if(size>1024*1024)throw Error();chunks.push(Buffer.from(value));}}finally{await reader.cancel().catch(()=>{});}
  const data=JSON.parse(Buffer.concat(chunks).toString('utf8'));
  if(!data||typeof data!=='object'||Array.isArray(data))throw Error();return data;
}
