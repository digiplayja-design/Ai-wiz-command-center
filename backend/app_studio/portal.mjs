import {randomUUID,randomBytes,createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import multer from 'multer';
import sharp from 'sharp';
import {AppStudioError,fail,text,uuid} from './model.mjs';
const BUCKET='korlix-app-portals',MAX_FILE=5*1024*1024,hash=v=>createHash('sha256').update(v).digest('hex');
const script=readFileSync(new URL('./portal_runtime.js',import.meta.url),'utf8');
const css=readFileSync(new URL('./portal_runtime.css',import.meta.url),'utf8');
const statuses=['open','in_progress','waiting','completed','cancelled'];
export const portalCapabilities={customerPortal:true,sharedDatabase:true,privateFiles:true,payments:'external_link',maxFileBytes:MAX_FILE,maxPortalFileBytes:100*1024*1024,maxMembers:500,maxRequests:1000};
export function paymentUrl(v){if(v==null||v==='')return '';if(typeof v!=='string'||v.length>2048)fail('Use a valid HTTPS checkout link.');let u;try{u=new URL(v);}catch{fail('Use a valid HTTPS checkout link.');}if(u.protocol!=='https:'||u.username||u.password||u.port&&u.port!=='443'||u.hostname==='localhost'||u.hostname.endsWith('.local')||!u.hostname.includes('.')||u.hostname.includes(':')||/^\d+\.\d+\.\d+\.\d+$/.test(u.hostname))fail('Use a public HTTPS checkout link without account credentials.');u.hash='';return u.href;}
function code(v){if(typeof v!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(v))fail('This portal link is incomplete. Open it from KORLIX again.',400);return v;}
function version(v){if(!Number.isInteger(v)||v<0)fail('Reload the portal before saving.');return v;}
function email(v){const s=text(v,254,'Invitation email').toLowerCase();if(!/^[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+$/.test(s))fail('Enter the member’s KORLIX sign-in email.');return s;}
function authSession(q){try{const token=q.headers.authorization?.match(/^Bearer (\S+)$/i)?.[1];return uuid(JSON.parse(Buffer.from(token.split('.')[1],'base64url').toString()).session_id);}catch{fail('Sign in to KORLIX again before opening the portal.',401);}}
export async function portalFile(file){
 if(!file?.buffer?.length||file.buffer.length>MAX_FILE)fail('Choose one JPG, PNG, WEBP or PDF file under 5 MB.');
 let bytes,mime,name=text(file.originalname,120,'File name').replace(/[\r\n\x00-\x1f\x7f/\\]/g,'_');
 if(file.buffer.subarray(0,5).toString()==='%PDF-'){
  if(!file.buffer.subarray(-2048).toString().includes('%%EOF'))fail('This PDF appears incomplete. Export it again and retry.');
  bytes=file.buffer;mime='application/pdf';name=name.replace(/\.[^.]*$/,'')+'.pdf';
 }else{
  try{const img=sharp(file.buffer,{limitInputPixels:30_000_000,animated:false});const meta=await img.metadata();if(!['jpeg','png','webp'].includes(meta.format)||meta.pages>1)throw Error();bytes=await img.rotate().resize({width:2400,height:2400,fit:'inside',withoutEnlargement:true}).jpeg({quality:85}).toBuffer();mime='image/jpeg';name=name.replace(/\.[^.]*$/,'')+'.jpg';}catch{fail('Choose a readable JPG, PNG, WEBP or PDF file under 5 MB.');}
 }
 if(bytes.length>MAX_FILE)fail('This file is too large after processing. Choose a smaller file.');
 return {bytes,mime,name:name.slice(0,120),sha256:hash(bytes)};
}
export function portalShell({id,appRoot}){
 const cfg=JSON.stringify({id,signInUrl:appRoot+'?app_portal='+id}).replace(/</g,'\\u003c');
 return '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>KORLIX Customer Portal</title><link rel="stylesheet" href="/portals/assets/runtime.css"></head><body><main id="app" aria-live="polite"><p>Opening your customer portal…</p></main><script id="portal-config" type="application/json">'+cfg+'</script><script src="/portals/assets/runtime.js" defer></script></body></html>';
}
export function registerAppPortals(app,{database,storageDatabase=database,requireUser,publicRoot='https://chee-chai-chee-backend.onrender.com',appRoot='https://www.korlixdeveloper.com/app/',logger=console,autoStart=true}={}){
 publicRoot=new URL(publicRoot).origin;appRoot=new URL(appRoot).origin+new URL(appRoot).pathname;
 const base='/api/app-studio',runtime='/api/app-studio/portals/:id/runtime';let uploads=0,cleaning=false,stopped=false;
 const call=async(actor,action,id=null,data={})=>{if(!database)fail('Customer portal storage is temporarily unavailable.',503);const r=await database.rpc('korlix_app_portal_v1',{p_actor:actor,p_action:action,p_id:id,p_data:data});if(r.error){const status={P0002:404,'40001':409,'23505':409,'54000':429,'42501':403,P0001:400,'23514':400}[r.error.code];if(status)fail(status===400&&r.error.code==='23514'?'Check your portal entries and retry.':r.error.message,status);logger.warn('Customer portal storage unavailable',{action,code:r.error.code});fail('The portal could not save this change. Refresh before retrying.',503);}return r.data;};
 const objects=()=>{if(!storageDatabase?.storage)fail('Portal files are temporarily unavailable.',503);return storageDatabase.storage.from(BUCKET);};
 const secure=r=>{r.set('Cache-Control','no-store');r.set('X-Content-Type-Options','nosniff');r.set('Referrer-Policy','no-referrer');};
 const route=(fn,{session=false,publicAction=false}={})=>async(q,r)=>{secure(r);try{let u=null,sessionHash=null;if(session){sessionHash=hash(code(q.headers.authorization?.match(/^Portal (\S+)$/)?.[1]));}else if(!publicAction){try{u=await requireUser(q);}catch{fail('Sign in to KORLIX to continue.',401);}if(!u?.id)fail('Sign in to KORLIX to continue.',401);}await fn(q,r,u,sessionHash);}catch(e){if(!(e instanceof AppStudioError))logger.warn('Customer portal request failed',{errorType:e.name});r.status(e instanceof AppStudioError?e.status:503).json({error:e instanceof AppStudioError?e.message:'This portal is temporarily unavailable. Please retry.'});}};
 const withUrl=d=>({...d,url:d.portal?publicRoot+'/portals/'+d.portal.id:null,capabilities:portalCapabilities});
 const confirmed=q=>{if(q.body?.confirmed!==true)fail('Confirm this action before continuing.');};
 const sessionCall=(q,sh,action,data={})=>call(null,action,uuid(q.params.id),{...data,session_hash:sh});
 app.get(base+'/portals',route(async(_q,r,u)=>r.json({...await call(u.id,'list'),capabilities:portalCapabilities})));
 app.post(base+'/portals/join',route(async(q,r,u)=>r.json(withUrl(await call(u.id,'join',null,{code_hash:hash(code(q.body?.code)),...(q.body?.portal_id?{portal_id:uuid(q.body.portal_id)}:{})})))));
 app.get(base+'/projects/:id/portal',route(async(q,r,u)=>r.json(withUrl(await call(u.id,'manage',uuid(q.params.id))))));
 app.put(base+'/projects/:id/portal',route(async(q,r,u)=>{confirmed(q);const b=q.body||{};if(typeof b.published!=='boolean')fail('Choose whether to publish this portal.');r.json(withUrl(await call(u.id,'save',uuid(q.params.id),{version:version(b.version),project_version:version(b.project_version),name:text(b.name,80,'Portal name'),description:text(b.description,1800,'Description',true),payment_url:paymentUrl(b.payment_url),published:b.published,confirmed:true})));}));
 app.get(base+'/portals/:id',route(async(q,r,u)=>r.json(withUrl(await call(u.id,'get',uuid(q.params.id))))));
 app.post(base+'/portals/:id/invites',route(async(q,r,u)=>{const b=q.body||{},id=uuid(q.params.id),token=randomBytes(32).toString('base64url');if(!['customer','staff'].includes(b.role))fail('Choose customer or staff access.');const days=b.expires_days??7;if(!Number.isInteger(days)||days<1||days>30)fail('Choose an invitation expiry between 1 and 30 days.');const d=await call(u.id,'invite',id,{id:randomUUID(),email:email(b.email),role:b.role,expires_days:days,code_hash:hash(token)});r.status(201).json({...d,code:token,join_url:appRoot+'?app_portal='+id+'#invite='+token});}));
 app.delete(base+'/portals/:id/invites/:inviteId',route(async(q,r,u)=>{confirmed(q);await call(u.id,'invite_revoke',uuid(q.params.id),{invite_id:uuid(q.params.inviteId)});r.json({revoked:true});}));
 app.delete(base+'/portals/:id/members/:userId',route(async(q,r,u)=>{confirmed(q);await call(u.id,'member_remove',uuid(q.params.id),{user_id:uuid(q.params.userId)});r.json({removed:true});}));
 app.post(base+'/portals/:id/session',route(async(q,r,u)=>{const id=uuid(q.params.id),token=randomBytes(32).toString('base64url');await call(u.id,'launch',id,{auth_session_id:authSession(q),token_hash:hash(token)});r.json({launch_url:publicRoot+'/portals/'+id+'/#launch='+token,expires_in:60});}));
 app.post(runtime+'/exchange',route(async(q,r)=>{const token=randomBytes(32).toString('base64url'),d=await call(null,'exchange',uuid(q.params.id),{session_hash:hash(code(q.body?.code)),token_hash:hash(token)});r.json({...d,token});},{publicAction:true}));
 app.post(runtime+'/logout',route(async(q,r,_u,sh)=>r.json(await sessionCall(q,sh,'logout')),{session:true}));
 app.get(runtime,route(async(q,r,_u,sh)=>r.json(await sessionCall(q,sh,'requests')),{session:true}));
 app.post(runtime+'/requests',route(async(q,r,_u,sh)=>r.status(201).json({request:await sessionCall(q,sh,'request_create',{id:uuid(q.body?.request_key),title:text(q.body?.title,160,'Request title'),description:text(q.body?.description,6000,'Request details')})}),{session:true}));
 app.get(runtime+'/requests/:requestId',route(async(q,r,_u,sh)=>r.json(await sessionCall(q,sh,'request_get',{request_id:uuid(q.params.requestId)})),{session:true}));
 app.put(runtime+'/requests/:requestId/status',route(async(q,r,_u,sh)=>{if(!statuses.includes(q.body?.status))fail('Choose a supported request status.');r.json({request:await sessionCall(q,sh,'request_status',{request_id:uuid(q.params.requestId),version:version(q.body?.version),status:q.body.status})});},{session:true}));
 app.delete(runtime+'/requests/:requestId',route(async(q,r,_u,sh)=>{confirmed(q);r.json(await sessionCall(q,sh,'request_delete',{request_id:uuid(q.params.requestId),version:version(q.body?.version)}));void cleanup();},{session:true}));
 app.post(runtime+'/requests/:requestId/messages',route(async(q,r,_u,sh)=>r.status(201).json(await sessionCall(q,sh,'message',{request_id:uuid(q.params.requestId),id:uuid(q.body?.request_key),body:text(q.body?.body,6000,'Reply')})),{session:true}));
 const upload=multer({storage:multer.memoryStorage(),limits:{fileSize:MAX_FILE,files:1,fields:0}}).single('file');
 app.post(runtime+'/requests/:requestId/files',route(async(q,r,_u,sh)=>{
  if(uploads>=2)fail('Portal uploads are busy. Try again shortly.',429);uploads++;
  try{
   const requestId=uuid(q.params.requestId);await sessionCall(q,sh,'request_get',{request_id:requestId});
   await new Promise((resolve,reject)=>upload(q,r,e=>e?reject(new AppStudioError('Choose one JPG, PNG, WEBP or PDF file under 5 MB.')):resolve()));
   const prepared=await portalFile(q.file),fileId=randomUUID();
   const f=await sessionCall(q,sh,'file_begin',{request_id:requestId,file_id:fileId,name:prepared.name,mime:prepared.mime,bytes:prepared.bytes.length,sha256:prepared.sha256});
   const saved=await objects().upload(f.path,prepared.bytes,{contentType:prepared.mime,upsert:false,cacheControl:'0'});if(saved.error)fail('This upload was interrupted. Refresh before retrying.',503);
   try{await sessionCall(q,sh,'file_finish',{file_id:fileId});}catch(e){/* Pending rows are reclaimed durably, including if access was revoked mid-upload. */throw e;}
   r.status(201).json(await sessionCall(q,sh,'request_get',{request_id:requestId}));
  }finally{uploads--;}
 },{session:true}));
 app.get(runtime+'/files/:fileId',route(async(q,r,_u,sh)=>{
  const f=await sessionCall(q,sh,'file_get',{file_id:uuid(q.params.fileId)}),download=await objects().download(f.path);if(download.error||!download.data)fail('This attachment is temporarily unavailable.',503);
  const bytes=Buffer.from(await download.data.arrayBuffer());if(bytes.length!==f.bytes||hash(bytes)!==f.sha256)fail('This attachment failed its integrity check.',503);
  // Recheck after the storage await so a revoked member cannot obtain a late response.
  await sessionCall(q,sh,'file_get',{file_id:f.id});
  r.set('Content-Type','application/octet-stream');r.set('Content-Disposition',`attachment; filename="attachment-${f.id}.${f.mime==='application/pdf'?'pdf':'jpg'}"; filename*=UTF-8''${encodeURIComponent(f.name).replace(/'/g,'%27')}`);r.set('Content-Security-Policy',"default-src 'none'; sandbox");r.send(bytes);
 },{session:true}));
 app.delete(runtime+'/files/:fileId',route(async(q,r,_u,sh)=>{confirmed(q);r.json(await sessionCall(q,sh,'file_delete',{file_id:uuid(q.params.fileId)}));void cleanup();},{session:true}));
 app.get('/portals/assets/runtime.js',(_q,r)=>{r.set('Content-Type','application/javascript');r.set('Cache-Control','public,max-age=60');r.set('X-Content-Type-Options','nosniff');r.send(script);});
 app.get('/portals/assets/runtime.css',(_q,r)=>{r.set('Content-Type','text/css');r.set('Cache-Control','public,max-age=60');r.set('X-Content-Type-Options','nosniff');r.send(css);});
 app.get('/portals/:id',(q,r)=>{secure(r);try{const id=uuid(q.params.id);r.set('Content-Security-Policy',"default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self' blob:; base-uri 'none'; frame-ancestors 'none'; form-action 'none'; object-src 'none'");r.set('X-Frame-Options','DENY');r.type('html').send(portalShell({id,appRoot}));}catch{r.status(404).send('Portal not found.');}});
 async function cleanup(){if(cleaning||stopped||!database||!storageDatabase)return;cleaning=true;try{const paths=await call(null,'cleanup');if(paths.length){const result=await objects().remove(paths);if(result.error)throw Error('Storage cleanup deferred');await call(null,'cleanup_done',null,{paths});}}catch(e){logger.warn('Customer portal cleanup deferred',{errorType:e.name});}finally{cleaning=false;}}
 const timer=autoStart?setInterval(()=>void cleanup(),60000):null;timer?.unref();
 return {call,cleanup,stop(){stopped=true;if(timer)clearInterval(timer);}};
}
