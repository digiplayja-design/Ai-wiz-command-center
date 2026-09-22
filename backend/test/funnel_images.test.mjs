import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID,createHash} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import sharp from 'sharp';
import {registerFunnels,createFunnelStore} from '../funnels/routes.mjs';
import {createImageStore,normalizeImage} from '../funnels/images.mjs';
import {document,publishReady} from '../funnels/core.mjs';
const [owner,other,basic]=Array.from({length:3},()=>randomUUID());
const doc={brand:'Studio',headline:'Our offer',subheadline:'Talk to us.',cta:'Inquire',thank_you:'Thank you.',benefits:[],faq:[],layout:'product',accent:'cyan',privacy_url:'https://example.com/privacy',booking_url:'',contact_email:'hi@example.com'};
let db,server,base,clock=Date.now(),png,webp,store,normalized;
const rpc=async(actor,action,id=null,data={})=>(await db.query('select korlix_funnel_images_v1($1,$2,$3,$4::jsonb) v',[actor,action,id,JSON.stringify(data)])).rows[0].v;
const page=async(actor,action,id=null,data={})=>(await db.query('select korlix_funnel_v1($1,$2,$3,$4::jsonb) v',[actor,action,id,JSON.stringify(data)])).rows[0].v;
const create=(d=doc)=>page(owner,'create',null,{name:'Image page',slug:'image-'+randomUUID(),document:d});
const publish=f=>page(owner,'publish',f.id,{version:f.version,confirmed:true});
const put=(actor=owner,extra={})=>rpc(actor,'put',null,{label:'Our team.png',width:normalized.width,height:normalized.height,sha256:normalized.sha256,content:normalized.bytes.toString('base64'),...extra});
const request=(url,options={})=>fetch(base+url,options);
const auth=(actor=owner,body)=>({headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
async function upload(bytes=png,actor=owner,name='Photo.png'){
 const form=new FormData();form.append('image',new Blob([bytes],{type:'image/png'}),name);
 return request('/api/funnels/images',{method:'POST',headers:{Authorization:actor},body:form});
}
test.before(async()=>{
 png=await sharp({create:{width:300,height:180,channels:4,background:'#1baab5'}}).png().withMetadata({exif:{IFD0:{Artist:'Private camera metadata'}}}).toBuffer();
 normalized=await normalizeImage(png);webp=normalized.bytes;
 db=new PGlite();
 await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table user_profiles(id uuid primary key,tier text);create table korlix_agent_email_recipients(id uuid primary key default gen_random_uuid(),user_id uuid,email text,active boolean default true,consent_status text default 'transactional_only',source_reference text,suppressed_at timestamptz,suppression_reason text,updated_at timestamptz);grant usage on schema public to anon,authenticated,service_role;grant select,update on user_profiles to service_role;grant all on korlix_agent_email_recipients to service_role;`);
 for(const u of [owner,other,basic]){await db.query('insert into auth.users values($1)',[u]);await db.query('insert into user_profiles values($1,$2)',[u,u===basic?'basic':'enterprise']);}
 for(const file of ['20260921162128_enterprise_contacts_crm.sql','20260922023935_enterprise_funnel_studio.sql','20260922194529_funnel_images.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+file,import.meta.url),'utf8'));
 await db.exec('set role service_role');
 const database={rpc:async(name,p)=>{try{return{data:await(name==='korlix_funnel_images_v1'?rpc:page)(p.p_actor,p.p_action,p.p_id,p.p_data)}}catch(error){return{error}}}};
 store=createImageStore(database);
 const app=express();app.use(express.json());registerFunnels(app,{database,store:createFunnelStore(database),imageStore:store,environment:{},now:()=>clock,requireUser:async q=>{if(![owner,other,basic].includes(q.headers.authorization))throw Error('auth');return{id:q.headers.authorization};}});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.after(async()=>{await new Promise(r=>server?.close(r));await db?.close();});

test('Image conversion strips metadata, constrains dimensions, and rejects active, animated, corrupt and oversized formats',async()=>{
 const meta=await sharp(webp).metadata();assert.equal(meta.format,'webp');assert.equal(meta.exif,undefined);assert.equal(meta.xmp,undefined);
 const big=await sharp({create:{width:2000,height:1000,channels:3,background:'#112233'}}).jpeg().toBuffer();
 assert.equal((await normalizeImage(big)).width,1600);
 for(const bad of [Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"/>'),Buffer.from('<script>alert(1)</script>'),Buffer.from([255,216,255,0]),Buffer.alloc(5*1024*1024+1),Buffer.from('GIF89a')])await assert.rejects(normalizeImage(bad));
 const frame=await sharp({create:{width:300,height:180,channels:3,background:'#ff0033'}}).png().toBuffer();
 const animated=await sharp([png,frame],{join:{animated:true}}).webp({delay:[100,100],loop:0}).toBuffer();
 assert.equal((await sharp(animated).metadata()).pages,2);await assert.rejects(normalizeImage(animated),/still/);
 const over=await sharp({create:{width:4100,height:4100,channels:3,background:'#112233'}}).png().toBuffer();await assert.rejects(normalizeImage(over),/16 megapixels/);
});
test('Browser roles, missing sessions, other owners and tier downgrade cannot read private images',async()=>{
 const a=await put();
 for(const role of ['anon','authenticated']){await db.exec('reset role;set role '+role);await assert.rejects(db.query('select * from korlix_funnel_images'),/permission denied/);await assert.rejects(rpc(owner,'list'),/permission denied/);}
 await db.exec('reset role;set role service_role');
 assert.equal((await request('/api/funnels/images')).status,401);
 assert.equal((await request('/api/funnels/images/'+a.id,auth(other))).status,404);
 assert.equal((await upload(png,basic)).status,403);
 await db.query("update user_profiles set tier='basic' where id=$1",[owner]);assert.equal((await request('/api/funnels/images/'+a.id,auth())).status,403);await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
});
test('Uploads are private, normalized, deduplicated, bounded, and list responses omit content',async()=>{
 const a=await put();
 const r=await upload();assert.equal(r.status,201,await r.clone().text());const saved=(await r.json()).image;assert.equal(saved.id,a.id);
 assert.equal((await upload(png,other)).status,201);
 const listed=await rpc(owner,'list');assert.equal(listed.images.length,1);assert.equal(listed.images[0].content,undefined);
 const get=await request('/api/funnels/images/'+a.id,auth());assert.equal(get.status,200);assert.equal(get.headers.get('cache-control'),'no-store');assert.deepEqual(Buffer.from((await get.json()).content,'base64'),webp);
 assert.equal((await upload(Buffer.from('<svg/>'))).status,400);
 assert.equal((await upload(Buffer.alloc(5*1024*1024+1))).status,400);
});
test('Draft images stay private and publication, pause, replacement and downgrade control public reads without counting views',async()=>{
 const a=await put(),secondBytes=await normalizeImage(await sharp({create:{width:40,height:40,channels:3,background:'#f08000'}}).png().toBuffer());
 const b=await put(owner,{sha256:secondBytes.sha256,content:secondBytes.bytes.toString('base64'),width:40,height:40});
 let f=await create({...doc,logo:{id:a.id,alt:'Our logo'},hero_image:{id:a.id,alt:'Our team'}});
 const url=id=>'/f/'+f.slug+'/media/'+id;
 assert.equal((await request(url(a.id))).status,404);
 f=await publish(f);const before=(await page(owner,'list')).funnels.find(x=>x.id===f.id).page_requests;
 const r=await request(url(a.id));assert.equal(r.status,200);assert.equal(r.headers.get('content-type'),'image/webp');assert.equal(r.headers.get('cache-control'),'no-store');assert.equal(r.headers.get('x-content-type-options'),'nosniff');
 assert.equal((await page(owner,'list')).funnels.find(x=>x.id===f.id).page_requests,before);
 const html=await(await request('/f/'+f.slug)).text();assert.match(html,new RegExp('/media/'+a.id));assert.match(html,/alt="Our team"/);
 f=await page(owner,'save',f.id,{version:f.version,name:f.name,document:{...doc,hero_image:{id:b.id,alt:'New image'}}});
 assert.equal((await request(url(b.id))).status,404);assert.equal((await request(url(a.id))).status,200);
 f=await publish(f);assert.equal((await request(url(a.id))).status,404);assert.equal((await request(url(b.id))).status,200);
 f=await page(owner,'pause',f.id,{version:f.version});assert.equal((await request(url(b.id))).status,404);
 f=await publish(f);await db.query("update user_profiles set tier='basic' where id=$1",[owner]);assert.equal((await request(url(b.id))).status,404);await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);
});
test('Page references reject cross-owner and deleted images; in-use deletion checks draft and paused published snapshots',async()=>{
 const foreign=await put(other),a=await put();
 await assert.rejects(create({...doc,logo:{id:foreign.id,alt:'Foreign'}}),/unavailable/);
 let f=await create({...doc,logo:{id:a.id,alt:'Logo'}});f=await publish(f);
 await assert.rejects(rpc(owner,'delete',a.id,{confirmed:true}),/used/);
 f=await page(owner,'save',f.id,{version:f.version,name:f.name,document:doc});f=await page(owner,'pause',f.id,{version:f.version});
 await assert.rejects(rpc(owner,'delete',a.id,{confirmed:true}),/used/);
 f=await publish(f);
 // This image is now unreferenced by all saved snapshots.
 assert.equal((await rpc(owner,'delete',a.id,{confirmed:true})).deleted,true);
 await assert.rejects(page(owner,'save',f.id,{version:f.version,name:f.name,document:{...doc,logo:{id:a.id,alt:'Old'}}}),/unavailable/);
 assert.equal((await request('/api/funnels/images/'+foreign.id,{method:'DELETE',...auth(owner,{confirmed:true})})).status,404);
 assert.equal((await request('/api/funnels/images/'+foreign.id,{method:'DELETE',...auth(other,{confirmed:false})})).status,400);
});
test('Preview resolves only owner images; descriptions are escaped and required for publication',async()=>{
 const a=await put(),alt='\"><script>alert(1)</script>';
 const body={document:{...doc,logo:{id:a.id,alt}}};const r=await request('/api/funnels/preview',{method:'POST',...auth(owner,body)});assert.equal(r.status,200);
 const {html}=await r.json();assert.match(html,/data:image\/webp;base64,/);assert(!html.includes('<script>'));assert.match(html,/&lt;script&gt;/);
 const otherResult=await request('/api/funnels/preview',{method:'POST',...auth(other,body)});assert.equal(otherResult.status,404);
 assert.throws(()=>document({...doc,logo:{id:'https://example.com/photo.png',alt:'Bad'}}));
 assert.throws(()=>publishReady({...doc,hero_image:{id:a.id,alt:''}}),/description/);
 assert.equal(document(doc).logo,null);
});
test('Atomic library caps and deletion of unused images leave CRM and inquiry records unchanged',async()=>{
 const before=(await db.query('select (select count(*) from korlix_contacts)::int contacts,(select count(*) from korlix_funnel_leads)::int leads')).rows[0];
 await db.exec('reset role');
 await db.query("insert into korlix_funnel_images(user_id,label,sha256,width,height,content) select $1,'Fixture',md5(x::text)||md5((x+1000)::text),1,1,$2 from generate_series(1,49) x",[other,webp]);
 await db.exec('set role service_role');
 await assert.rejects(put(other,{sha256:'a'.repeat(64)}),/library is full/);
 const a=(await rpc(other,'list')).images[0];await rpc(other,'delete',a.id,{confirmed:true});assert.equal((await rpc(other,'list')).images.length,49);
 const after=(await db.query('select (select count(*) from korlix_contacts)::int contacts,(select count(*) from korlix_funnel_leads)::int leads')).rows[0];assert.deepEqual(after,before);
});
