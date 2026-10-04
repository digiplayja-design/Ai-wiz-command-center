import {fail} from './core.mjs';
import {CATEGORIES} from '../directory/core.mjs';
export function directorySyncFilters(input={}){
 if(!input||typeof input!=='object'||Array.isArray(input)||Object.keys(input).some(k=>!['q','category','city','country','verified_only'].includes(k)))fail('Choose supported business listing filters.');
 const result={};for(const [key,max]of Object.entries({q:120,category:80,city:100,country:100})){const v=input[key]??'';if(typeof v!=='string'||v.trim().length>max||/[\u0000-\u001f\u007f]/.test(v))fail('Check the business listing filters.');result[key]=v.trim();}
 if(result.category&&!CATEGORIES.includes(result.category))fail('Choose a listed business category.');
 if(input.verified_only!=null&&typeof input.verified_only!=='boolean')fail('Choose whether to include only verified businesses.');
 result.verified_only=input.verified_only===true;return result;
}
export function createCrmDirectorySync({database}={}){
 let timer=null,running=false,stopped=false,lastStartedAt=null,lastCompletedAt=null,lastError=null;
 const command=async(actor,action,p={})=>{if(!database)fail('Business listing imports are temporarily unavailable.',503);const {data,error}=await database.rpc('korlix_crm_directory_v1',{p_actor:actor,p_action:action,p});if(error){const m=/CRM(403|404|409)?: (.+)/.exec(error.message||'');fail(m?m[2]:'Business listing imports are temporarily unavailable. Refresh before trying again.',m?Number(m[1]||400):503);}return data;};
 const version=p=>{if(!Number.isInteger(p.version)||p.version<0)fail('Refresh the listing settings first.');return p.version;};
 const action=async(user,action,p={})=>{
  if(action==='state')return {...await command(user,'state'),categories:CATEGORIES};
  if(action==='preview')return command(user,'preview',{filters:directorySyncFilters(p.filters)});
  if(action==='save')return command(user,'save',{version:version(p),filters:directorySyncFilters(p.filters)});
  if(action==='toggle'){
   if(typeof p.enabled!=='boolean')fail('Choose enable or pause.');if(p.enabled&&p.confirmed!==true)fail('Review and confirm automatic imports first.');
   return command(user,'toggle',{version:version(p),enabled:p.enabled,confirmed:p.confirmed===true});
  }
  if(action==='run'){
   if(p.confirmed!==true)fail('Confirm importing these business listings.');
   // No client-controlled worker mode, user ID, listing content or destination.
   return command(user,'run',{version:version(p),confirmed:true,automatic:false});
  }
  fail('Choose a supported listing import action.');
 };
 const tick=async()=>{if(stopped||running||!database)return;running=true;lastStartedAt=new Date().toISOString();try{await command(null,'tick');lastCompletedAt=new Date().toISOString();lastError=null;}catch{lastError='Automatic imports temporarily unavailable.';console.warn('[CRM directory] Automatic imports temporarily unavailable.');}finally{running=false;}};
 const health=()=>({configured:Boolean(database),started:timer!==null,running,intervalSeconds:60,lastStartedAt,lastCompletedAt,lastError});
 return {action,tick,health,start(){if(timer||!database)return;stopped=false;timer=setInterval(()=>void tick(),60000);timer.unref?.();void tick();},stop(){stopped=true;if(timer)clearInterval(timer);timer=null;}};
}
