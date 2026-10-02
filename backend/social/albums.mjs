import { randomUUID, createHash } from 'node:crypto';
import { socialPhotos } from './media.mjs';
export const albumBucket = 'korlix-social-albums';
const uuid = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const statusFor = e => ({'42501':403,P0002:404,'54000':429,'22P02':400,'23514':400,P0001:400}[e.code] || 503);

async function signed(database, result) {
  const photos = [];
  function walk(value) {
    if (!value || typeof value !== 'object') return;
    if (typeof value.photo_path === 'string') photos.push(value);
    for (const item of Object.values(value)) if (typeof item === 'object') walk(item);
  }
  walk(result);
  if (photos.length) {
    const paths = [...new Set(photos.map(p=>p.photo_path))];
    const r = await database.storage.from(albumBucket).createSignedUrls(paths, 300);
    if (r.error) throw Error('Photo links unavailable');
    const links = new Map((r.data || []).map(p=>[p.path,p.signedUrl]));
    for (const p of photos) { p.photo_url = links.get(p.photo_path) || null; delete p.photo_path; }
  }
  return socialPhotos(database,result);
}

export function registerSocialAlbums(app, {database, authenticate, logger=console}) {
  const rpc = async (actor,action,data) => {
    const r = await database.rpc('korlix_social_albums_v1',{p_actor:actor,p_action:action,p_data:data});
    if (r.error) throw Object.assign(new Error(r.error.message),{status:statusFor(r.error)});
    if (!r.data) throw Error('Empty album response');
    return r.data;
  };
  const actions = ['albums','album','album_create','album_save','album_delete','album_photo_delete','album_cover'];
  for (const action of actions) app[['albums','album'].includes(action)?'get':'post'](`/api/social/${action}`,async(req,res)=>{
    res.set('Cache-Control','no-store');
    try {
      const user=await authenticate(req,res); if(!user)return;
      const data=req.method==='GET'?req.query:req.body;
      if (!data || typeof data!=='object' || Buffer.byteLength(JSON.stringify(data))>2000) return res.status(400).json({error:'Check the album details.'});
      const result=await rpc(user.id,action,data);
      if (result.remove_paths) {
        for(let i=0;i<result.remove_paths.length;i+=100) {
          const removed=await database.storage.from(albumBucket).remove(result.remove_paths.slice(i,i+100));
          if (removed.error) throw Error('Photo deletion pending');
        }
        delete result.remove_paths;
      }
      res.json(await signed(database,result));
    } catch(e) { res.status(e.status||503).json({error:e.status?e.message:'Album update could not be confirmed. Refresh before retrying.'}); }
  });
  app.post('/api/social/album_upload',async(req,res)=>{
    res.set('Cache-Control','no-store');
    let uploaded, committed=false;
    try {
      const user=await authenticate(req,res); if(!user)return;
      const {album,photo}=req.query;
      if (!uuid.test(album||'') || !uuid.test(photo||'')) return res.status(400).json({error:'Choose an album before uploading.'});
      const begin=await rpc(user.id,'album_upload_begin',{album,photo});
      if(begin.existing) return res.json(await signed(database,begin));
      const {default:multer}=await import('multer');
      const upload=multer({storage:multer.memoryStorage(),limits:{fileSize:8388608,files:1,fields:0,parts:2}}).single('photo');
      try { await new Promise((resolve,reject)=>upload(req,res,e=>e?reject(e):resolve())); }
      catch { return res.status(400).json({error:'Choose a photo smaller than 8 MB.'}); }
      let jpeg;
      try {
        const {default:sharp}=await import('sharp');
        const image=sharp(req.file?.buffer||Buffer.alloc(0),{limitInputPixels:32000000,animated:false,failOn:'error'});
        const meta=await image.metadata();
        if(!['jpeg','png','webp','heif'].includes(meta.format)||(meta.pages||1)>1)throw Error();
        jpeg=await image.rotate().resize(2048,2048,{fit:'inside',withoutEnlargement:true}).jpeg({quality:87}).toBuffer();
      } catch { return res.status(400).json({error:'That photo could not be opened. Choose a still JPG, PNG or WebP photo.'}); }
      uploaded=`${begin.owner}/${album}/${randomUUID()}.jpg`;
      const bucket=database.storage.from(albumBucket);
      const put=await bucket.upload(uploaded,jpeg,{contentType:'image/jpeg',upsert:false,cacheControl:'60'});
      if(put.error)throw Error('Upload unavailable');
      let saved;
      try { saved=await rpc(user.id,'album_photo_add',{album,photo,path:uploaded,sha256:createHash('sha256').update(jpeg).digest('hex'),bytes:jpeg.length}); }
      catch(e) {
        // Only remove on a definite database rejection. A transport failure can
        // occur after commit; a retry with the same photo ID recovers that case.
        if(e.status && e.status!==503)await bucket.remove([uploaded]);
        throw e;
      }
      committed=true;
      if(saved.existing) await bucket.remove([uploaded]);
      res.json(await signed(database,saved));
    } catch(e) {
      logger.warn('Social album upload could not be confirmed',{committed});
      res.status(e.status||503).json({error:e.status?e.message:'Photo upload could not be confirmed. Retry the same photo or refresh the album.'});
    }
  });
}
