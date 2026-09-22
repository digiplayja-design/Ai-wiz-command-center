import {fail,text,uuid,version} from './core.mjs';

export const LEAD_STATUSES=['new','in_review','qualified','won','lost'];
export const LEAD_STATUS_LABELS={new:'New',in_review:'In review',qualified:'Qualified',won:'Won',lost:'Lost'};

export function leadChange(body) {
  if(!body||typeof body!=='object'||Array.isArray(body)||
    Object.keys(body).some(k=>!['version','status','private_note'].includes(k))) fail('Check the lead status and private note.');
  if(!LEAD_STATUSES.includes(body.status)) fail('Choose an available lead status.');
  const v=version(body.version);
  if(v>2147483647) fail('Reload this inquiry before editing.');
  return {version:v,status:body.status,private_note:text(body.private_note,4000)};
}

export function registerLeadManagement(app,{base,owner,command}) {
  app.get(base+'/:id/inbox/:leadId',owner(async(q,r,u)=>{
    r.json(await command(u,'lead_manage',uuid(q.params.id),{action:'get',lead_id:uuid(q.params.leadId)}));
  }));
  app.patch(base+'/:id/inbox/:leadId',owner(async(q,r,u)=>{
    r.json(await command(u,'lead_manage',uuid(q.params.id),{
      ...leadChange(q.body),action:'update',lead_id:uuid(q.params.leadId),
    }));
  }));
}
