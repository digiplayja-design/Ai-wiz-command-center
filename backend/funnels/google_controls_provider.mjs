import {fail} from './core.mjs';
import {creationResources} from './google_paused_provider.mjs';

const unclear=()=>fail('Google did not confirm this campaign control. Reload the command record and check Google Ads.',409);
export function googleControlRequest(snapshot,resources,action){
  const r=creationResources(resources,snapshot?.identity?.account?.id);
  if(!['activate','pause'].includes(action))unclear();
  const operation=(key,resourceName,status)=>({[key]:{update:{resourceName,status},updateMask:'status'}});
  return {mutateOperations:action==='pause'?[operation('campaignOperation',r.campaign,'PAUSED')]:[
    operation('adGroupAdOperation',r.ad,'ENABLED'),operation('adGroupOperation',r.ad_group,'ENABLED'),operation('campaignOperation',r.campaign,'ENABLED')
  ],partialFailure:false,responseContentType:'RESOURCE_NAME_ONLY'};
}
export function googleControlsMethods(ads){
  async function mutate(access,s,resources,action,validateOnly){
    const request=googleControlRequest(s,resources,action),response=await ads(`customers/${s.identity.account.id}/googleAds:mutate`,access,s.identity.login_customer_id,{...request,validateOnly});
    if(response.partialFailureError)unclear();
    if(validateOnly){
      if(Object.keys(response).some(k=>k!=='mutateOperationResponses')||(response.mutateOperationResponses!==undefined&&(!Array.isArray(response.mutateOperationResponses)||response.mutateOperationResponses.length)))unclear();
      return {validated:true};
    }
    const rows=response.mutateOperationResponses;
    if(!Array.isArray(rows)||rows.length!==request.mutateOperations.length)unclear();
    request.mutateOperations.forEach((op,i)=>{const key=Object.keys(op)[0],result=key.replace('Operation','Result');if(!rows[i]||Object.keys(rows[i]).length!==1||rows[i][result]?.resourceName!==op[key].update.resourceName)unclear();});
    return {confirmed:true,action};
  }
  async function status(access,s,resources){
    const r=creationResources(resources,s.identity.account.id),id=r.campaign.split('/')[3];
    const out=await ads(`customers/${s.identity.account.id}/googleAds:search`,access,s.identity.login_customer_id,{query:`SELECT campaign.resource_name, campaign.name, campaign.status FROM campaign WHERE campaign.id = ${id} LIMIT 2`});
    if(out.nextPageToken||!Array.isArray(out.results)||out.results.length!==1)unclear();
    const c=out.results[0].campaign;
    if(c?.resourceName!==r.campaign||!['ENABLED','PAUSED','REMOVED'].includes(c.status)||typeof c.name!=='string'||c.name.length>1000)unclear();
    return {resource:r.campaign,name:c.name,status:c.status};
  }
  return {createdSearchStatus:status,validateSearchControl:(...args)=>mutate(...args,true),applySearchControl:(...args)=>mutate(...args,false)};
}
