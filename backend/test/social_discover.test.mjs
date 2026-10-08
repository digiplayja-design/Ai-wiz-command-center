import {test,before,beforeEach,after} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir,mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {execFileSync} from 'node:child_process';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerSocialDiscover,processDiscoverVideo} from '../social/discover.mjs';
import {parseDiscoverNews} from '../social/discover_news.mjs';
let db,server,base,profiles,service;const users=Array.from({length:4},()=>randomUUID()),stored=new Map(),signed=[];
const rpc=async(who,action,data={},name='korlix_social_discover_v1')=>(await db.query(`select ${name}($1,$2,$3::jsonb) result`,[users[who],action,JSON.stringify(data)])).rows[0].result;
const social=(who,action,data)=>rpc(who,action,data,'korlix_social_v1');
const worker=async(action,data={})=>(await db.query('select korlix_social_discover_worker($1,$2::jsonb) result',[action,JSON.stringify(data)])).rows[0].result;
const draft=async(who=0)=>rpc(who,'video_reserve',{id:randomUUID(),checksum:'a'.repeat(64)});
const ready=async(who=0)=>{const v=await draft(who);await rpc(who,'video_ready',{id:v.id,size_bytes:10000,duration_ms:1200});return v;};
const publish=async(who=0)=>{const v=await ready(who);await rpc(who,'discover_publish',{id:v.id,caption:'A day in Kingston',accepted_rules:true});return v;};
const newsItem=()=>({id:randomUUID(),title:'A new community project',summary:'A local community announced a new project.',url:'https://news.gov.jm/article/'+randomUUID(),source:'news.gov.jm',category:'jamaica',published_at:new Date().toISOString()});
const edition=async()=>{const {claim}=await worker('claim'),n=newsItem();await worker('news_ready',{claim,items:[n]});return n;};
before(async()=>{
 db=new PGlite();await db.exec('create schema auth;create role anon;create role authenticated;create role service_role bypassrls;create table auth.users(id uuid primary key,last_sign_in_at timestamptz);grant usage on schema auth to service_role;grant select(id) on auth.users to service_role;create schema storage;create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);create table storage.objects(id uuid primary key,bucket_id text,name text);alter table storage.objects enable row level security;');
 for(const u of users)await db.query('insert into auth.users(id) values($1)',[u]);
 const folder=new URL('../../supabase/migrations/',import.meta.url);
 for(const f of(await readdir(folder)).filter(f=>/_korlix_social(?:_|\.)/.test(f)).sort())await db.exec(await readFile(new URL(f,folder),'utf8'));
 const database={rpc:async(name,p)=>{try{return{data:name.endsWith('_worker')?await worker(p.p_action,p.p_data):await rpc(users.indexOf(p.p_actor),p.p_action,p.p_data,name)};}catch(e){return{error:{code:e.code,message:e.message}};}},storage:{from:()=>({upload:async(path,bytes)=>{if(stored.has(path))return{error:{statusCode:409}};stored.set(path,bytes);return{data:{path}};},remove:async paths=>{for(const p of paths)stored.delete(p);return{data:[]};},createSignedUrl:async(path,ttl)=>{signed.push({path,ttl});return{data:{signedUrl:`https://media.example.org/${path}?ttl=${ttl}`}};}})}};
 const app=express();app.use(express.json());service=registerSocialDiscover(app,{database,autoStart:false,authenticate:async(req,res)=>{const id=req.headers.authorization;if(!users.includes(id)){res.status(401).json({error:'Sign in'});return null;}return{id};},research:async()=>[newsItem()],processVideo:async()=>({video:Buffer.from('mp4'),thumbnail:Buffer.from('jpg'),duration_ms:1000}),logger:{warn(){}}});
 server=app.listen(0);await new Promise(r=>server.once('listening',r));base=`http://127.0.0.1:${server.address().port}/api/social/`;
});
beforeEach(async()=>{await db.exec("truncate korlix_social_profiles,korlix_social_moderators,korlix_social_limits,korlix_social_discover_news,korlix_social_discover_gc restart identity cascade;update korlix_social_discover_edition set lease=null,lease_until=null,next_attempt=now(),refreshed_at=null");stored.clear();signed.length=0;profiles=[];for(let i=0;i<4;i++)profiles.push((await social(i,'save_profile',{handle:['alice','bruno','chris','diana'][i],name:'Member '+i,color:'cyan',discoverable:true,show_online:false,accepted_rules:true})).profile);});
after(async()=>{await new Promise(r=>server.close(r));await db.close();});

test('draft ownership, explicit consent, idempotent reserve and visibility',async()=>{
 const v=await ready();assert.equal((await rpc(1,'discover_videos')).items.length,0);assert.equal((await rpc(0,'discover_videos',{feed:'mine'})).items[0].state,'ready');
 await assert.rejects(rpc(1,'video_link',{id:v.id}),/unavailable/);await assert.rejects(rpc(1,'discover_publish',{id:v.id,accepted_rules:true}),/not found/);
 await assert.rejects(rpc(0,'discover_publish',{id:v.id}),/permission/);
 await assert.rejects(rpc(1,'video_reserve',{id:v.id,checksum:'a'.repeat(64)}),/cannot be reused/);
 assert.equal((await rpc(0,'video_reserve',{id:v.id,checksum:'a'.repeat(64)})).state,'ready');
 await rpc(0,'discover_publish',{id:v.id,accepted_rules:true,caption:'Hello'});assert.equal((await rpc(1,'discover_videos')).items[0].caption,'Hello');
});
test('blocks, suspension and accepted follows control feeds and fresh playback',async()=>{
 const v=await publish();assert.equal((await rpc(1,'discover_videos',{feed:'following'})).items.length,0);
 await social(0,'request',{peer:profiles[1].id});await social(1,'accept',{peer:profiles[0].id});assert.equal((await rpc(1,'discover_videos',{feed:'following'})).items.length,1);
 await social(1,'block',{peer:profiles[0].id});assert.equal((await rpc(1,'discover_videos')).items.length,0);await assert.rejects(rpc(1,'video_link',{id:v.id}),/unavailable/);
 await db.query('update korlix_social_profiles set suspended=true where id=$1',[profiles[0].id]);assert.equal((await rpc(2,'discover_videos')).items.length,0);await assert.rejects(rpc(0,'discover_videos'),/active Social/);
});
test('likes, saved stories and stable keyset video pages are scoped to the viewer',async()=>{
 const a=await publish(),b=await publish();await rpc(1,'discover_mark',{id:a.id,kind:'video',field:'liked',value:true});await rpc(1,'discover_mark',{id:a.id,kind:'video',field:'saved',value:true});
 const feed=await rpc(1,'discover_videos');assert.equal(feed.items[0].id,b.id);assert.equal(feed.items[1].like_count,1);assert.equal((await rpc(2,'discover_videos',{feed:'saved'})).items.length,0);
 assert.equal((await rpc(1,'discover_videos',{before:feed.items[0].seq})).items[0].id,a.id);
 const n=await edition();await rpc(1,'discover_mark',{id:n.id,kind:'news',field:'saved',value:true});assert.equal((await rpc(1,'discover_news',{feed:'saved'})).items[0].id,n.id);
 await assert.rejects(rpc(1,'discover_mark',{id:n.id,kind:'news',field:'saved',value:'yes'}),/save or like/);
});
test('reports hide content for reporter, authorize moderator review and remove content',async()=>{
 const v=await publish(),id=randomUUID();await rpc(1,'report',{id,kind:'video',target:v.id,reason:'Review this video'});
 assert.equal((await rpc(1,'discover_videos')).items.length,0);await assert.rejects(rpc(1,'moderate',{id,decision:'remove'}),/Moderator/);
 await db.query('insert into korlix_social_moderators values($1)',[users[2]]);
 assert.match((await rpc(2,'video_link',{id:v.id,report:id})).path,/\.mp4$/);await assert.rejects(rpc(2,'video_link',{id:v.id,report:randomUUID()}),/unavailable/);
 await rpc(2,'moderate',{id,decision:'remove'});await assert.rejects(rpc(3,'video_link',{id:v.id}),/unavailable/);assert.equal((await db.query('select * from korlix_social_discover_gc')).rows.length,2);
 const n=await edition(),report=randomUUID();await rpc(1,'report',{id:report,kind:'news',target:n.id,reason:'Date looks wrong'});await rpc(2,'moderate',{id:report,decision:'remove'});assert.equal((await rpc(3,'discover_news')).items.length,0);
});
test('delete, profile cascade and abandoned drafts queue durable media cleanup',async()=>{
 const v=await publish();await assert.rejects(rpc(1,'discover_delete',{id:v.id}),/not found/);await rpc(0,'discover_delete',{id:v.id});assert.equal((await db.query('select * from korlix_social_discover_gc')).rows.length,2);
 await ready(1);await db.query('delete from korlix_social_profiles where id=$1',[profiles[1].id]);assert.equal((await db.query('select * from korlix_social_discover_gc')).rows.length,4);
 await ready(2);await db.exec("update korlix_social_videos set created_at=now()-interval '2 days' where state='ready'");await worker('cleanup');assert.equal((await db.query('select * from korlix_social_discover_gc')).rows.length,6);
 await db.exec("update korlix_social_discover_gc set created_at=now()-interval '11 minutes'");await service.cleanup();assert.equal((await worker('cleanup')).paths.length,0);
});
test('news worker lease coalesces refresh and backs off after failure',async()=>{
 const {claim}=await worker('claim');assert.ok(claim);assert.equal((await worker('claim')).claim,undefined);await assert.rejects(worker('news_ready',{claim:randomUUID(),items:[newsItem()]}),/lease expired/);
 await worker('news_failed',{claim});assert.equal((await worker('claim')).claim,undefined);
});
test('browser roles have neither table/RPC privileges nor a public video bucket',async()=>{
 const r=await db.query("select has_function_privilege('anon','korlix_social_discover_v1(uuid,text,jsonb)','execute') allowed,has_table_privilege('authenticated','korlix_social_videos','select') readable");assert.equal(r.rows[0].allowed,false);assert.equal(r.rows[0].readable,false);
 assert.equal((await db.query("select public from storage.buckets where id='korlix-social-videos'")).rows[0].public,false);
});
test('HTTP upload is a private draft, retries safely, and signed playback is short-lived',async()=>{
 const id=randomUUID();for(let i=0;i<2;i++){const form=new FormData();form.append('video',new Blob(['input']),'clip.mp4');const r=await fetch(base+'discover_upload?id='+id,{method:'POST',headers:{authorization:users[0]},body:form});assert.equal(r.status,200,await r.text());}
 assert.equal(stored.size,2);const r=await fetch(base+'discover_link?id='+id,{headers:{authorization:users[0]}});assert.equal(r.status,200);assert.equal(r.headers.get('cache-control'),'no-store');assert.equal(signed.at(-1).ttl,90);
 assert.equal((await fetch(base+'discover_videos')).status,401);
});
test('news parser rejects invented links, stale dates, unsafe URLs and copied-length summaries',()=>{
 const now=Date.now(),n=newsItem();const response={status:'completed',output:[{type:'web_search_call',status:'completed',action:{sources:[{url:n.url}]}}],output_text:JSON.stringify({items:[n]})};assert.equal(parseDiscoverNews(response,now)[0].source,'news.gov.jm');
 for(const change of[{url:'https://invented.gov.jm/a'},{url:'javascript:alert(1)'},{published_at:'2020-01-01'},{published_at:'2099-01-01'},{summary:'word '.repeat(80)}])assert.throws(()=>parseDiscoverNews({...response,output_text:JSON.stringify({items:[{...n,...change}]})},now));
});
test('real video is transcoded to browser-compatible MP4 and JPEG; non-video inputs rejected',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'discover-test-'));try{const path=join(dir,'clip.mp4');execFileSync('ffmpeg',['-v','error','-f','lavfi','-i','color=c=teal:s=180x320:d=1','-c:v','libx264','-pix_fmt','yuv420p',path]);const r=await processDiscoverVideo(await readFile(path));assert.equal(r.video.toString('ascii',4,8),'ftyp');assert.equal(r.thumbnail.subarray(0,2).toString('hex'),'ffd8');assert.equal(r.duration_ms,1000);await assert.rejects(processDiscoverVideo(Buffer.from('#EXTM3U\nfile:///etc/passwd')),/MP4/);}finally{await rm(dir,{recursive:true,force:true});}
});
