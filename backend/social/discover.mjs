import {createHash} from 'node:crypto';
import {mkdtemp,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {socialPhotos} from './media.mjs';
export const discoverBucket = 'korlix-social-videos';
export const discoverVideoLimit = 50 * 1024 * 1024;
const run = promisify(execFile);
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const bad = message => Object.assign(Error(message),{status:400});
const errorFor = error => Object.assign(Error(error?.message || 'Discover could not finish this request. Refresh before retrying.'),{status:({'42501':403,P0002:404,'54000':429,'22P02':400,'23514':400,'23505':409,P0001:400}[error?.code] || 503)});

export async function processDiscoverVideo(bytes) {
  if (!bytes?.length || bytes.length > discoverVideoLimit) throw bad('Choose a video smaller than 50 MB.');
  // Accept media containers only. Playlists and network/file indirection are not inputs.
  if (bytes.toString('ascii',4,8) !== 'ftyp' && bytes.subarray(0,4).toString('hex') !== '1a45dfa3') throw bad('Choose an MP4, MOV or WebM video.');
  const directory = await mkdtemp(join(tmpdir(),'korlix-discover-'));
  try {
    const input=join(directory,'input'), output=join(directory,'video.mp4'), cover=join(directory,'cover.jpg');
    await writeFile(input,bytes,{mode:0o600});
    const common=['-v','error','-protocol_whitelist','file,pipe','-format_whitelist','mov,matroska,webm'];
    const {stdout}=await run('ffprobe',[...common,'-show_format','-show_streams','-of','json',input],{timeout:15000,maxBuffer:1024*1024});
    const meta=JSON.parse(stdout), stream=meta.streams?.find(s=>s.codec_type==='video'), duration=Number(meta.format?.duration);
    if (!stream || !Number.isFinite(duration) || duration < .5 || duration > 60 || stream.width*stream.height > 9000000 || !stream.width || !stream.height) throw bad('Choose a video between 1 and 60 seconds, up to 4K resolution.');
    await run('ffmpeg',[...common,'-threads','2','-i',input,'-map','0:v:0','-map','0:a:0?','-t','60','-sn','-dn','-map_metadata','-1','-map_chapters','-1',
      '-vf','scale=w=min(720\\,iw):h=min(1280\\,ih):force_original_aspect_ratio=decrease:force_divisible_by=2','-r','30','-c:v','libx264','-preset','veryfast','-crf','25','-threads','2','-pix_fmt','yuv420p','-c:a','aac','-b:a','96k','-ac','2','-movflags','+faststart','-fs',String(discoverVideoLimit),output],{timeout:120000,maxBuffer:1024*1024});
    await run('ffmpeg',['-v','error','-i',output,'-frames:v','1','-vf','scale=480:-2','-q:v','4','-map_metadata','-1',cover],{timeout:15000,maxBuffer:1024*1024});
    const video=await readFile(output),thumbnail=await readFile(cover);
    if (!video.length || video.length >= discoverVideoLimit || !thumbnail.length || thumbnail.length>1048576) throw bad('This video could not be prepared. Try a smaller clip.');
    return {video,thumbnail,duration_ms:Math.round(duration*1000)};
  } catch(e) { if(e.status) throw e; throw bad('That video could not be opened. Try a shorter MP4, MOV or WebM clip.'); }
  finally { await rm(directory,{recursive:true,force:true}); }
}

export function registerSocialDiscover(app,{database,authenticate,research,processVideo=processDiscoverVideo,logger=console,autoStart=true}) {
  const uploading=new Set(); let refreshing=null,cleaning=false;
  const rpc=async(actor,action,data={})=>{
    const r=await database.rpc('korlix_social_discover_v1',{p_actor:actor,p_action:action,p_data:data});
    if(r.error || r.data==null)throw errorFor(r.error); return r.data;
  };
  const worker=async(action,data={})=>{
    const r=await database.rpc('korlix_social_discover_worker',{p_action:action,p_data:data});
    if(r.error || r.data==null)throw errorFor(r.error); return r.data;
  };
  const cleanup=async()=>{
    if(cleaning||!database)return; cleaning=true;
    try {
      const {paths}=await worker('cleanup');
      if(paths?.length) { const r=await database.storage.from(discoverBucket).remove(paths); if(!r.error)await worker('cleaned',{paths}); }
    }catch{logger.warn('Discover media cleanup will retry.');}finally{cleaning=false;}
  };
  const refreshNews=()=>{
    if(!research||refreshing)return refreshing;
    refreshing=(async()=>{
      let claim;
      try { claim=(await worker('claim')).claim; if(claim){ const items=await research(); await worker('news_ready',{claim,items}); } }
      catch { if(claim)await worker('news_failed',{claim}).catch(()=>{}); logger.warn('Discover news refresh unavailable; keeping the previous checked edition.'); }
      finally{refreshing=null;}
    })(); return refreshing;
  };
  const cards=async result=>{
    for(const item of result.items||[]) {
      if(item.thumbnail_path){const r=await database.storage.from(discoverBucket).createSignedUrl(item.thumbnail_path,60);item.thumbnail_url=r.data?.signedUrl||null;delete item.thumbnail_path;}
    }
    return socialPhotos(database,result);
  };
  for(const action of ['discover_news','discover_videos','discover_mark','discover_publish','discover_delete']) {
    const method=['discover_news','discover_videos'].includes(action)?'get':'post';
    app[method](`/api/social/${action}`,async(req,res)=>{
      res.set('Cache-Control','no-store');
      try{
        const user=await authenticate(req,res);if(!user)return;
        const data=method==='get'?req.query:req.body;
        if(!data||Array.isArray(data)||Buffer.byteLength(JSON.stringify(data))>2500)throw bad('Check the Discover details.');
        const result=await rpc(user.id,action,data);
        if(action==='discover_news'){result.available=!!research;void refreshNews();}
        res.json(await cards(result));
        if(action==='discover_delete')void cleanup();
      }catch(e){res.status(e.status||503).json({error:e.status&&e.status!==503?e.message:'Discover could not finish this request. Refresh before retrying.'});}
    });
  }
  app.post('/api/social/discover_upload',async(req,res)=>{
    res.set('Cache-Control','no-store');let actor,draft;
    try{
      const user=await authenticate(req,res);if(!user)return;
      if(!uuid.test(req.query.id||''))throw bad('Choose a video before uploading.');
      if(uploading.has(user.id)||uploading.size>=2)throw Object.assign(Error('Video processing is busy. Try again in a moment.'),{status:429});
      actor=user.id;uploading.add(actor);await rpc(actor,'upload_access');
      const {default:multer}=await import('multer');
      const upload=multer({storage:multer.memoryStorage(),limits:{fileSize:discoverVideoLimit,files:1,fields:0,parts:2}}).single('video');
      try{await new Promise((resolve,reject)=>upload(req,res,e=>e?reject(e):resolve()));}catch{throw bad('Choose one video smaller than 50 MB.');}
      const bytes=req.file?.buffer;if(!bytes?.length)throw bad('Choose a video to upload.');
      draft=await rpc(actor,'video_reserve',{id:req.query.id,checksum:createHash('sha256').update(bytes).digest('hex')});
      if(draft.state!=='uploading')return res.json({id:draft.id,state:draft.state});
      const media=await processVideo(bytes),bucket=database.storage.from(discoverBucket);
      for(const [path,body,contentType]of[[draft.video_path,media.video,'video/mp4'],[draft.thumbnail_path,media.thumbnail,'image/jpeg']]){
        const r=await bucket.upload(path,body,{contentType,cacheControl:'60',upsert:false});
        const duplicate=r.error&&(String(r.error.statusCode)==='409'||(String(r.error.statusCode)==='400'&&/already exists|duplicate/i.test(r.error.message||'')));
        if(r.error&&!duplicate)throw errorFor();
      }
      res.json(await rpc(actor,'video_ready',{id:draft.id,duration_ms:media.duration_ms,size_bytes:media.video.length+media.thumbnail.length}));
    }catch(e){
      // A deletion/account suspension can race with media processing. Preserve
      // cleanup evidence even if an earlier cleanup already removed the paths.
      if(draft && [403,404].includes(e.status))await worker('enqueue',{paths:[draft.video_path,draft.thumbnail_path]}).catch(()=>{});
      res.status(e.status||503).json({error:e.status&&e.status!==503?e.message:'Upload could not be confirmed. Retry with the same video.'});
    }
    finally{if(actor)uploading.delete(actor);}
  });
  app.get('/api/social/discover_link',async(req,res)=>{
    res.set('Cache-Control','no-store');
    try{
      const user=await authenticate(req,res);if(!user)return;
      const result=await rpc(user.id,'video_link',{id:req.query.id,report:req.query.report});
      const r=await database.storage.from(discoverBucket).createSignedUrl(result.path,90);
      if(r.error||!r.data?.signedUrl)throw errorFor();
      res.json({url:r.data.signedUrl});
    }catch(e){res.status(e.status||503).json({error:e.status&&e.status!==503?e.message:'This video could not be opened.'});}
  });
  if(autoStart){const timer=setInterval(()=>void cleanup(),30*60*1000);timer.unref?.();const first=setTimeout(()=>{void cleanup();void refreshNews();},20000);first.unref?.();}
  return {cleanup,refreshNews};
}
