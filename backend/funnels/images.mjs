import multer from 'multer';
import {createHash} from 'node:crypto';
import {FunnelError,fail,text,uuid,slug} from './core.mjs';

const maxInput=5*1024*1024,maxOutput=512*1024;
const parseUpload=multer({storage:multer.memoryStorage(),limits:{fileSize:maxInput,files:1,fields:0,parts:2}}).single('image');
export function createImageStore(database) {
  return {async command(actor,action,id=null,data={}) {
    if(!database)fail('Image storage is not configured.',503);
    const result=await database.rpc('korlix_funnel_images_v1',{p_actor:actor,p_action:action,p_id:id,p_data:data});
    if(result.error){
      const status={42501:403,P0002:404,40001:409,54000:429,P0001:400}[result.error.code];
      fail(status?result.error.message:'Image storage is temporarily unavailable. Refresh your image library before retrying.',status??503);
    }
    return result.data;
  }};
}
export async function normalizeImage(buffer) {
  if(!Buffer.isBuffer(buffer)||!buffer.length||buffer.length>maxInput)fail('Choose an image up to 5 MB.');
  const png=buffer.subarray(0,8).equals(Buffer.from('89504e470d0a1a0a','hex'));
  const jpeg=buffer[0]===255&&buffer[1]===216&&buffer[2]===255;
  const webp=buffer.toString('ascii',0,4)==='RIFF'&&buffer.toString('ascii',8,12)==='WEBP';
  if(!png&&!jpeg&&!webp)fail('Choose a still JPG, PNG, or WebP image.');
  try {
    const {default:sharp}=await import('sharp');
    const source=sharp(buffer,{limitInputPixels:16000000,failOn:'warning',animated:false});
    const metadata=await source.metadata();
    if(!['jpeg','png','webp'].includes(metadata.format)||(metadata.pages??1)>1)fail('Choose a still JPG, PNG, or WebP image.');
    let result=await source.clone().rotate().resize({width:1600,height:1600,fit:'inside',withoutEnlargement:true}).webp({quality:82}).timeout({seconds:10}).toBuffer({resolveWithObject:true});
    if(result.data.length>maxOutput)result=await source.clone().rotate().resize({width:1200,height:1200,fit:'inside',withoutEnlargement:true}).webp({quality:65}).timeout({seconds:10}).toBuffer({resolveWithObject:true});
    if(result.data.length>maxOutput)fail('This image is too detailed. Resize it and try again.');
    return {bytes:result.data,width:result.info.width,height:result.info.height,sha256:createHash('sha256').update(result.data).digest('hex')};
  }catch(e){if(e instanceof FunnelError)throw e;fail('This image could not be read. Choose a still JPG, PNG, or WebP up to 5 MB and 16 megapixels.');}
}
export function registerImages(app,{base,owner,publicRoute,database,imageStore,limit}) {
  const store=imageStore??createImageStore(database);
  let pending=0;
  app.get(base+'/images',owner(async(_q,r,u)=>r.json(await store.command(u,'list'))));
  app.post(base+'/images',owner(async(q,r,u)=>{
    await store.command(u,'list'); // Current entitlement before parsing or decoding.
    limit('image-upload:'+u,10);
    if(pending>=2)fail('Image uploads are busy. Please try again shortly.',429);
    pending++;
    try {
      await new Promise((resolve,reject)=>parseUpload(q,r,e=>e?reject(e):resolve()));
      if(!q.file)fail('Choose one image to upload.');
      const image=await normalizeImage(q.file.buffer);
      const label=text(String(q.file.originalname).split(/[\\/]/).pop().replace(/[\x00-\x1f\x7f]/g,'').slice(0,100)||'Page image',100,true);
      const saved=await store.command(u,'put',null,{label,sha256:image.sha256,width:image.width,height:image.height,content:image.bytes.toString('base64')});
      r.status(201).json({image:saved});
    }catch(e){
      if(e instanceof multer.MulterError)fail(e.code==='LIMIT_FILE_SIZE'?'Choose an image up to 5 MB.':'Upload one JPG, PNG, or WebP image at a time.');
      throw e;
    }finally{pending--;q.file=undefined;}
  }));
  app.get(base+'/images/:imageId',owner(async(q,r,u)=>r.json(await store.command(u,'get',uuid(q.params.imageId)))));
  app.delete(base+'/images/:imageId',owner(async(q,r,u)=>{
    if(q.body?.confirmed!==true)fail('Confirm image deletion first.');
    r.json(await store.command(u,'delete',uuid(q.params.imageId),{confirmed:true}));
  }));
  app.get('/f/:slug/media/:imageId',publicRoute(async(q,r)=>{
    const result=await store.command(null,'public',uuid(q.params.imageId),{slug:slug(q.params.slug)});
    r.set({'Content-Type':'image/webp','Content-Disposition':'inline','Cross-Origin-Resource-Policy':'same-origin','X-Robots-Tag':'noindex, nofollow'});
    r.send(Buffer.from(result.content,'base64'));
  }));
}
