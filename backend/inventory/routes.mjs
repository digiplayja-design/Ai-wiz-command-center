import multer from 'multer';
import {randomUUID} from 'node:crypto';
import {InventoryError,fail,uuid,normalizeMutation,searchInput,csv,parseCsv,cleanImage,digest} from './model.mjs';

export function registerInventory(app,{database,storageDatabase=database,requireUser,aiAccess,recognize,logger=console}={}){
 const base='/api/inventory',active=new Set(),starting=new Set();
 const call=async(actor,action,id=null,data={})=>{
  const r=await database.rpc('korlix_inventory_v1',{p_actor:actor,p_action:action,p_id:id,p_data:data});
  if(r.error){const status={P0002:404,'40001':409,'23505':409,'54000':429,'42501':403,P0001:400,'22007':400,'22008':400,'23514':400,'23503':400}[r.error.code];
   if(status)fail(r.error.code==='23505'?'This SKU, serial or request already exists. Refresh before trying again.':(['22007','22008'].includes(r.error.code)?'Enter a valid calendar date.':(['23514','23503'].includes(r.error.code)?'That change would create invalid inventory. Review the quantities and selected records.':r.error.message)),status);
   logger.warn('Inventory storage unavailable',{action,code:r.error.code});fail('Your change could not be confirmed. Refresh Inventory before retrying.',503);}
  if(r.data==null)fail('Inventory is temporarily unavailable.',503);return r.data;
 };
 const route=fn=>async(q,r)=>{r.set('Cache-Control','no-store');try{let u;try{u=await requireUser(q);}catch{fail('Sign in to use Inventory.',401);}if(!u?.id)fail('Sign in to use Inventory.',401);if(!database)fail('Inventory is temporarily unavailable.',503);await fn(q,r,u);}catch(e){r.status(e instanceof InventoryError?e.status:503).json({error:e instanceof InventoryError?e.message:'Inventory could not finish this request. Refresh before retrying.'});}};
 const uploader=multer({storage:multer.memoryStorage(),limits:{fileSize:8*1024*1024,files:1,fields:6,fieldSize:300}}).single('image');
 const upload=(q,r)=>new Promise((resolve,reject)=>uploader(q,r,e=>e?reject(new InventoryError('Choose one JPG, PNG or WebP photo up to 8 MB.')):resolve()));
 const photos=async(actor,items)=>{await Promise.all(items.map(async x=>{if(!x.photo_path)return;const path=x.photo_path;delete x.photo_path;if(!path.startsWith(actor+'/'))return;try{const signed=await storageDatabase.storage.from('korlix-inventory').createSignedUrl(path,300);if(signed.data?.signedUrl)x.photo_url=signed.data.signedUrl;}catch{ /* Product still works without its picture. */ }}));return items;};
 app.get(base,route(async(_q,r,u)=>{await call(u.id,'vision_recover');r.json(await call(u.id,'workspace'));}));
 app.get(base+'/search',route(async(q,r,u)=>{const result=await call(u.id,'search',null,searchInput(q.query));await photos(u.id,result.items);r.json(result);}));
 app.get(base+'/items/:id',route(async(q,r,u)=>{const result=await call(u.id,'item',uuid(q.params.id));await photos(u.id,[result.item]);r.json(result);}));
 app.get(base+'/events',route(async(q,r,u)=>r.json(await call(u.id,'events',q.query.item?uuid(q.query.item):null,{offset:Math.max(0,Math.min(100000,parseInt(q.query.offset||0,10)||0))}))));
 app.post(base+'/changes',route(async(q,r,u)=>r.json(await call(u.id,'mutate',null,normalizeMutation(q.body||{})))));
 app.post(base+'/import/preview',route(async(q,r,_u)=>r.json({products:parseCsv(q.body?.csv),note:'New products only. Existing SKUs are rejected; no stock quantities change.'})));
 app.get(base+'/export',route(async(_q,r,u)=>{
  const d=await call(u.id,'export'),products=new Map(d.products.map(p=>[p.id,p.data])),locations=new Map(d.locations.map(l=>[l.id,l.data]));
  const rows=[['name','sku','barcode','brand','category','unit','currency','price','reorder','tracking','location','city','state_province','country','bin','serial','batch','expiry','on_hand','reserved','available','unit_cost','stock_value']];
  const row=(p,s={},l={})=>[p.name,p.sku,p.barcode,p.brand,p.category,p.unit,p.currency,p.price,p.reorder,p.tracking,l.name,l.city,l.region,l.country,s.bin,s.serial,s.batch,s.expiry,s.quantity??0,s.reserved??0,s.expiry&&s.expiry<new Date().toISOString().slice(0,10)?0:Number(s.quantity??0)-Number(s.reserved??0),s.unit_cost??0,Number(s.quantity??0)*Number(s.unit_cost??0)];
  const stocked=new Set();for(const s of d.stock){const p=products.get(s.product_id);if(p){rows.push(row(p,s,locations.get(s.location_id)));stocked.add(s.product_id);}}for(const [id,p]of products)if(!stocked.has(id))rows.push(row(p));
  r.set({'Content-Type':'text/csv; charset=utf-8','Content-Disposition':'attachment; filename="KORLIX-Inventory.csv"','X-Content-Type-Options':'nosniff'}).send(csv(rows));
 }));
 app.post(base+'/items/:id/photo',route(async(q,r,u)=>{
  const id=uuid(q.params.id),existing=await call(u.id,'item',id);await upload(q,r);
  if(existing.item.kind!=='product')fail('Choose an inventory item.');
  const bytes=await cleanImage(q.file?.buffer),revision=Number(q.body.revision);
  if(!Number.isInteger(revision)||revision<1)fail('Refresh the item before adding a photo.');
  const path=`${u.id}/${id}/${randomUUID()}.jpg`,bucket=storageDatabase.storage.from('korlix-inventory');
  const saved=await bucket.upload(path,bytes,{contentType:'image/jpeg',upsert:false,cacheControl:'0'});if(saved.error)fail('The photo could not be uploaded. Try again.',503);
  let item;try{item=await call(u.id,'photo',id,{path,revision});}catch(e){if(e instanceof InventoryError&&e.status>=400&&e.status<500)await bucket.remove([path]).catch(()=>{});throw e;}
  if(existing.item.photo_path)await bucket.remove([existing.item.photo_path]).catch(()=>{});
  await photos(u.id,[item]);r.json({item});
 }));
 const run=async(u,id,bytes,mode)=>{active.add(id);try{const result=await recognize({bytes,mode});await call(u.id,'vision_finish',id,{result});}catch{logger.warn('Inventory image recognition failed',{requestId:id});try{await call(u.id,'vision_fail',id);}catch{logger.warn('Inventory image recognition needs recovery',{requestId:id});}}finally{active.delete(id);}};
 app.post(base+'/vision',route(async(q,r,u)=>{
  await upload(q,r);const id=uuid(q.body.request_key),mode=q.body.mode;
  if(!['picture','serial'].includes(mode)||q.body.consent!=='true')fail('Allow OpenAI to read this picture before scanning.');
  const bytes=await cleanImage(q.file?.buffer),request_hash=digest(Buffer.concat([Buffer.from(mode),bytes]));
  try{return r.json({scan:await call(u.id,'vision_lookup',id,{request_hash})});}catch(e){if(e.status!==404)throw e;}
  if(starting.has(id)||active.size+starting.size>=3)fail('KORLIX is reading other pictures. Try again shortly.',429);
  starting.add(id);try{
   const access=await aiAccess(u);if(!access?.allowed)fail(access?.reason||'Your generation allowance is unavailable.',access?.status||403);
   const scan=await call(u.id,'vision_start',id,{request_hash,mode,usage_id:access.usageId,credit_limit:access.creditLimit,request_limit:access.requestLimit});
   r.status(scan.replayed?200:202).json({scan});if(!scan.replayed)void run(u,id,bytes,mode);
  }finally{starting.delete(id);}
 }));
 app.get(base+'/vision/:id',route(async(q,r,u)=>r.json({scan:await call(u.id,'vision_get',uuid(q.params.id))})));
 return {call,active};
}
