import {createHash} from 'node:crypto';
export class MusicError extends Error {
  constructor(message,status=400){super(message);this.name='MusicError';this.status=status;}
}
export const fail=(message,status=400)=>{throw new MusicError(message,status);};
export const PLANS=[
 {id:'music_starter_75_monthly',name:'Music Starter',priceMonthly:25,monthlyGenerations:75,description:'For occasional songs and ideas.'},
 {id:'music_creator_580_monthly',name:'Music Creator',priceMonthly:120,monthlyGenerations:580,description:'For creators making music regularly.'},
 {id:'music_studio_4000_monthly',name:'Music Studio',priceMonthly:450,monthlyGenerations:4000,description:'For teams with a busy release calendar.'},
 {id:'music_producer_10000_monthly',name:'Music Producer',priceMonthly:950,monthlyGenerations:10000,description:'For high-volume music production.'},
];
export const uuid=v=>{if(typeof v!=='string'||!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(v))fail('Refresh Music Studio before retrying.');return v.toLowerCase();};
const field=(v,n,label)=>{if(typeof v!=='string'||v.length>n||/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(v))fail(label+' is too long or invalid.');return v.trim();};
export function settings(v,{draft=false}={}){
 if(!v||typeof v!=='object'||Array.isArray(v))fail('Choose your music settings.');
 const mode=v.mode??(v.instrumentalOnly?'instrumental':v.customMode?'lyrics':'idea');
 if(!['idea','lyrics','instrumental'].includes(mode))fail('Choose Song idea, My lyrics or Instrumental.');
 const o={mode,idea:field(v.idea??v.prompt??'',400,'Song idea'),title:field(v.title??'',100,'Title'),style:field(v.style??v.tags??'',1000,'Style'),
 lyrics:field(v.lyrics??'',5000,'Lyrics'),voice:v.voice??v.vocalGender??'auto',duration:v.duration??null};
 if(!['auto','m','f'].includes(o.voice))fail('Choose a voice preference.');
 if(o.duration!==null&&(!Number.isInteger(o.duration)||o.duration<10||o.duration>360))fail('Choose a target length from 10 to 360 seconds.');
 if(!draft){
  if(mode==='lyrics'&&!o.lyrics)fail('Add your lyrics first.');
  if(mode!=='lyrics'&&!o.idea)fail('Describe the music you want to make.');
  if(mode!=='lyrics'&&description(o).length>400)fail('Shorten the idea or style: together they can use up to 400 characters.');
 }
 return o;
}
export const description=o=>[o.idea,o.style?'Style: '+o.style:''].filter(Boolean).join('\n');
export function providerPayload(o){
 const p={task_type:'create_music',custom_mode:o.mode==='lyrics',mv:'sonic-v5',make_instrumental:o.mode==='instrumental'};
 if(o.mode==='lyrics'){p.prompt=o.lyrics;p.title=o.title||'Untitled';p.tags=o.style||'original contemporary song';}
 else p.gpt_description_prompt=description(o);
 if(o.mode!=='instrumental'&&o.voice!=='auto')p.vocal_gender=o.voice;
 if(o.duration!==null)p.duration=o.duration;
 return p;
}
export const digest=v=>createHash('sha256').update(JSON.stringify(v)).digest('hex');
export function entitlement(user,env=process.env){
 const email=String(user.email??'').trim().toLowerCase();
 const allowed=String(env.KORLIX_MUSIC_ADDON_ALLOWLIST??'').split(',').map(s=>s.trim().toLowerCase()).filter(Boolean);
 const active=String(env.KORLIX_MUSIC_ADDON_DEV_ACTIVE??'').toLowerCase()==='true'||!!email&&allowed.includes(email);
 const plan=active?PLANS.find(p=>p.id===(env.KORLIX_MUSIC_ADDON_PLAN||env.KORLIX_MUSIC_ADDON_DEFAULT_PLAN||PLANS[0].id))??PLANS[0]:null;
 return {active,planId:plan?.id??null,plan,plans:PLANS,billingRequired:!active};
}
export function safeUrl(v){
 try {const u=new URL(v);return u.protocol==='https:'&&!u.username&&!u.password&&(!u.port||u.port==='443')&&!['localhost','localhost.localdomain'].includes(u.hostname)&&!/^(\d{1,3}\.){3}\d{1,3}$/.test(u.hostname)&&!u.hostname.includes(':')?u.href:null;}catch{return null;}
}
export function providerResult(raw){
 if(!raw||typeof raw!=='object'||!Array.isArray(raw.data)||raw.data.length>8)fail('The music service returned an unreadable status. Refresh shortly.',502);
 const tracks=raw.data.map((t,i)=>{
  if(!t||typeof t!=='object')fail('The music service returned an unreadable track.',502);
  const state=['pending','running','succeeded','failed'].includes(t.state)?t.state:'running';
  return {id:String(t.clip_id??t.id??i).slice(0,200),state,title:String(t.title??'Untitled track').slice(0,160),style:String(t.tags??'').slice(0,1000),
   lyrics:String(t.lyrics??'').slice(0,10000),audioUrl:state==='succeeded'?safeUrl(t.audio_url):null,imageUrl:safeUrl(t.image_url),
   duration:Number.isFinite(Number(t.duration))&&Number(t.duration)>0&&Number(t.duration)<3600?Number(t.duration):null};
 });
 const ready=tracks.filter(t=>t.state==='succeeded'&&t.audioUrl).length;
 const failed=tracks.filter(t=>t.state==='failed').length;
 const terminal=tracks.length>0&&ready+failed===tracks.length;
 return {state:terminal?(ready?(failed?'partial':'completed'):'failed'):'processing',tracks,error:terminal&&failed?(ready?'One version finished; another version failed.':'The music service could not finish this creation.') :null};
}
export function publicJob(j){
 return {id:j.id,jobId:j.id,status:j.state,settings:j.payload,tracks:j.tracks,favorite:j.favorite,createdAt:j.created_at,updatedAt:j.updated_at,error:j.error,accepted:j.accepted,quotaHeld:j.quota_held};
}
export function createProvider({env=process.env,fetcher=fetch}={}){
 const key=()=>String(env.MUSICAPI_KEY||env.MUSICAPI_API_KEY||env.MUSICAPI_AI_KEY||'').trim();
 const base=String(env.MUSICAPI_BASE_URL||'https://api.musicapi.ai/api/v1').replace(/\/+$/,'');
 async function request(path,payload){
  if(!key())fail('Music creation is temporarily unavailable. Your draft is safe.',503);
  let r;
  try{r=await fetcher(base+path,{method:payload?'POST':'GET',headers:{Authorization:'Bearer '+key(),'Content-Type':'application/json'},...(payload?{body:JSON.stringify(payload)}:{}),signal:AbortSignal.timeout(payload?45000:25000)});}
  catch{const e=new MusicError('The music service did not confirm the request. Check My tracks before creating again.',503);e.definite=false;throw e;}
  let data;try{data=JSON.parse(await r.text());}catch{data=null;}
  if(!r.ok||data?.code&&Number(data.code)!==200){
   const status=!r.ok?r.status:Number(data.code);
   const e=new MusicError(status===429?'The music service is busy. Try again later.':'The music service could not accept this request. Check your idea and try again.',502);
   e.definite=[400,401,403,404,422,429].includes(status);throw e;
  }
  return data;
 }
 return {ready:()=>!!key(),create:async o=>{
  const d=await request('/sonic/create',providerPayload(o));
  if(typeof d?.task_id!=='string'||!d.task_id||d.task_id.length>200){const e=new MusicError('The music service did not confirm a task. Check My tracks before creating again.',502);e.definite=false;throw e;}return d.task_id;
 },status:async id=>providerResult(await request('/sonic/task/'+encodeURIComponent(id)))};
}
const audioHosts=new Set(['cdn1.suno.ai','cdn2.suno.ai','cdn.suno.ai','cdn.musicapi.ai','musicapi-cdn.b-cdn.net']);
export async function downloadAudio(url,fetcher=fetch){
 let next=url;
 for(let i=0;i<4;i++){
  const safe=safeUrl(next);if(!safe||!audioHosts.has(new URL(safe).hostname))fail('Use Open audio to save this provider file.',422);
  const r=await fetcher(safe,{redirect:'manual',signal:AbortSignal.timeout(40000)});
  if([301,302,303,307,308].includes(r.status)){next=new URL(r.headers.get('location')||'',safe).href;continue;}
  if(!r.ok||!r.body)fail('This audio link is unavailable. Refresh the creation and try again.',502);
  if(Number(r.headers.get('content-length'))>64*1024*1024){await r.body.cancel();fail('Use Open audio to save this large file.',422);}
  const reader=r.body.getReader(),chunks=[];let total=0;
  try{while(true){const x=await reader.read();if(x.done)break;total+=x.value.length;if(total>64*1024*1024)fail('Use Open audio to save this large file.',422);chunks.push(Buffer.from(x.value));}}finally{await reader.cancel().catch(()=>{});}
  const bytes=Buffer.concat(chunks);let extension,mime;
  if(bytes.subarray(0,3).toString()==='ID3'||bytes[0]===255&&(bytes[1]&224)===224){extension='mp3';mime='audio/mpeg';}
  else if(bytes.subarray(0,4).toString()==='RIFF'&&bytes.subarray(8,12).toString()==='WAVE'){extension='wav';mime='audio/wav';}
  else if(bytes.subarray(4,8).toString()==='ftyp'){extension='m4a';mime='audio/mp4';}
  else fail('The provider file is not recognized audio. Try Open audio.',502);
  return {bytes,extension,mime};
 }
 fail('The audio link redirected too many times. Try Open audio.',502);
}
