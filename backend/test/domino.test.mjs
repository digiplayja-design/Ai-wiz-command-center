import {test,before,after,beforeEach} from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {dominoAction,dominoDeck,dominoLegal,dominoView,registerDomino} from '../social/domino.mjs';
let db,server,url;const users=Array.from({length:5},()=>randomUUID());let profiles;
const rpc=async(actor,action,data={})=>(await db.query('select korlix_domino_v1($1,$2,$3) r',[actor,action,data])).rows[0].r;
const social=async(actor,action,data={})=>(await db.query('select korlix_social_v1($1,$2,$3) r',[actor,action,data])).rows[0].r;
const move=async(actor,id,action,extra={})=>{const r=await rpc(actor,'snapshot',{id}),v=dominoAction(r,r.me,{action,revision:r.revision,requestId:randomUUID(),...extra});return rpc(actor,'commit',{id,revision:r.revision,state:v.state});};
const api=async(actor,body,status=200)=>{const r=await fetch(url,{method:'POST',headers:{Authorization:actor,'Content-Type':'application/json'},body:JSON.stringify(body)});const j=await r.json();assert.equal(r.status,status,JSON.stringify(j));assert.equal(r.headers.get('cache-control'),'no-store');return j;};
async function table(capacity=2){const id=randomUUID();await rpc(users[0],'create',{id,name:'Friends table',capacity});for(let i=1;i<capacity;i++){await rpc(users[0],'invite',{id,peer:profiles[i].id});await rpc(users[i],'join',{id});}return id;}
async function start(id,count=2){for(let i=0;i<count;i++)await move(users[i],id,'ready',{ready:true});return move(users[0],id,'start');}
before(async()=>{
 db=new PGlite();await db.exec('create schema auth;create role anon;create role authenticated;create role service_role bypassrls;create table auth.users(id uuid primary key);');
 await db.exec(await readFile(new URL('../../supabase/migrations/20260928184131_korlix_social.sql',import.meta.url),'utf8'));
 await db.exec(await readFile(new URL('../../supabase/migrations/20260929043337_korlix_social_domino_video.sql',import.meta.url),'utf8'));
 const database={rpc:async(_n,p)=>{try{return {data:await rpc(p.p_actor,p.p_action,p.p_data)};}catch(e){return {error:{code:e.code,message:e.message}};}}};
 const app=express();app.use(express.json({limit:'200kb'}));registerDomino(app,{database,authenticate:async(q,r)=>{if(!users.includes(q.headers.authorization)){r.status(401).json({error:'Sign in'});return null;}return {id:q.headers.authorization};},logger:{warn(){}}});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));url=`http://127.0.0.1:${server.address().port}/api/social/domino`;
});
after(async()=>{server?.close();await db?.close();});
beforeEach(async()=>{
 await db.exec('reset role;truncate auth.users cascade');profiles=[];
 for(let i=0;i<users.length;i++){await db.query('insert into auth.users values($1)',[users[i]]);profiles.push((await social(users[i],'save_profile',{accepted_rules:true,handle:'player'+i,name:'Player '+i,bio:'',color:'cyan',discoverable:true,show_online:true})).profile);}
 for(let i=1;i<4;i++){await social(users[0],'request',{peer:profiles[i].id});await social(users[i],'accept',{peer:profiles[0].id});}
});
test('private invitations, accepted connections and fixed seats',async()=>{
 const id=await table();await assert.rejects(rpc(users[4],'snapshot',{id}),/private table/);await assert.rejects(rpc(users[4],'join',{id}),/private table/);
 await assert.rejects(rpc(users[0],'invite',{id,peer:profiles[4].id}),/accepted Social/);await assert.rejects(rpc(users[1],'invite',{id,peer:profiles[2].id}),/Only the host/);
 await rpc(users[0],'invite',{id,peer:profiles[2].id});await assert.rejects(rpc(users[2],'join',{id}),/full/);await rpc(users[2],'decline',{id});assert.equal((await rpc(users[2],'list')).items.length,0);
 assert.equal((await rpc(users[0],'list')).items[0].seated,2);
});
test('server deals distinct tiles, enforces turns and never exposes opponent hands',async()=>{
 const id=await table(),r=await start(id);const s=r.state;assert.equal(Object.values(s.hands).flat().length,14);assert.equal(new Set(Object.values(s.hands).flat()).size,14);
 const card=(await api(users[0],{action:'sync',id})).table;assert.equal(card.hand.length,7);assert.equal(card.hands,undefined);assert.equal(card.state,undefined);assert.equal(card.receipts,undefined);assert(card.players.every(p=>p.hands===undefined));
 assert.equal(dominoLegal(s,s.turn)[0].tile,s.opener);const wrong=profiles.find(p=>p.id!==s.turn).id;
 assert.throws(()=>dominoAction(r,wrong,{action:'play',revision:r.revision,requestId:randomUUID(),tile:s.opener,side:'right'}),/turn/);
 assert.throws(()=>dominoAction(r,s.turn,{action:'pass',revision:r.revision,requestId:randomUUID()}),/playable/);
});
test('table invitations notify once and revoked friendships cannot join',async()=>{
 const id=await table();await rpc(users[0],'invite',{id,peer:profiles[2].id});await rpc(users[0],'invite',{id,peer:profiles[2].id});
 const messages=await db.query('select body from korlix_social_messages where sender=$1 and recipient=$2',[profiles[0].id,profiles[2].id]);
 assert.equal(messages.rows.length,1);assert.match(messages.rows[0].body,/free-play domino table/);
 await db.query('delete from korlix_social_connections where requester=$1 and recipient=$2',[profiles[0].id,profiles[2].id]);
 await assert.rejects(rpc(users[2],'join',{id}),/Reconnect with the host/);
});
test('all players must be ready and online, only host deals, stale moves conflict',async()=>{
 const id=await table();await assert.rejects(move(users[0],id,'start'),/ready/);await move(users[0],id,'ready',{ready:true});await move(users[1],id,'ready',{ready:true});await assert.rejects(move(users[1],id,'start'),/host/);
 await db.query("update korlix_domino_members set last_seen=now()-interval '3 minutes' where table_id=$1 and profile_id=$2",[id,profiles[1].id]);await assert.rejects(move(users[0],id,'start'),/online/);await rpc(users[1],'sync',{id});const r=await move(users[0],id,'start');
 await assert.rejects(rpc(users[0],'commit',{id,revision:r.revision-1,state:r.state}),/changed/);
});
test('full rounds conserve tiles, orient legal ends, finish and score teams correctly',async()=>{
 assert.equal(dominoDeck().length,28);
 for(const capacity of [2,4]){
  const id=await table(capacity);let r=await start(id,capacity),steps=0;
  while(r.state.phase==='playing'&&steps++<130){const actor=r.state.turn,legal=dominoLegal(r.state,actor);const before=r.state.board.map(t=>t.id);const action={action:legal.length?'play':'pass',revision:r.revision,requestId:randomUUID(),...(legal[0]||{})};const next=dominoAction(r,actor,action);assert.deepEqual(dominoAction({...r,state:next.state},actor,action).state,next.state);
   r=await rpc(users[profiles.findIndex(p=>p.id===actor)],'commit',{id,revision:r.revision,state:next.state});const b=r.state.board;
   for(let i=1;i<b.length;i++)assert.equal(b[i-1].b,b[i].a);assert(before.every(id=>b.some(t=>t.id===id)));assert.equal(new Set([...b.map(t=>t.id),...Object.values(r.state.hands).flat()]).size,capacity*7);
  }
  assert.equal(r.state.phase,'finished');assert(steps<130);if(capacity===4&&r.state.result.winner)assert.match(r.state.result.winner,/^team[01]$/);
  assert.equal(dominoView(r).legal.length,0);
 }
});
test('blocked tie, team victory and pass cannot invent points',()=>{
 const ids=profiles.slice(0,4).map(p=>p.id),players=ids.map((id,seat)=>({id,seat,state:'joined',online:true,name:'Player'}));
 const r={capacity:4,revision:1,host:ids[0],players,state:{phase:'playing',hands:{[ids[0]]:['1-1'],[ids[1]]:['2-2'],[ids[2]]:['3-3'],[ids[3]]:['4-4']},board:[{id:'6-6',a:6,b:6}],turn:ids[0],passes:3,wins:{},points:{}}};
 const s=dominoAction(r,ids[0],{action:'pass',revision:1,requestId:randomUUID()}).state;assert.equal(s.result.winner,'team0');assert.equal(s.result.points,12);
 r.state.hands[ids[3]]=['2-2'];const tie=dominoAction(r,ids[0],{action:'pass',revision:1,requestId:randomUUID()}).state;assert.equal(tie.result.winner,null);assert.equal(tie.result.points,0);
});
test('video signals require joined, current media sessions and only reach their recipient',async()=>{
 const id=await table(),sessions=[randomUUID(),randomUUID()],devices=[randomUUID(),randomUUID()];
 const signal={id,peer:profiles[1].id,session:sessions[0],targetSession:sessions[1],signalId:randomUUID(),kind:'offer',payload:{sdp:'test SDP'}};
 await assert.rejects(rpc(users[0],'signal',signal),/session changed/);
 for(let i=0;i<2;i++)await rpc(users[i],'media',{id,session:sessions[i],device:devices[i],enabled:true,start:true,camera:true,microphone:true});
 await rpc(users[0],'signal',signal);await rpc(users[0],'signal',signal);
 assert.equal((await rpc(users[0],'sync',{id,session:sessions[0],device:devices[0]})).signals.length,0);
 assert.equal((await rpc(users[1],'sync',{id,session:sessions[1],device:devices[1]})).signals.length,1);
 const fresh=randomUUID();await rpc(users[1],'media',{id,session:fresh,device:devices[1],enabled:true,start:true,camera:true,microphone:true});await assert.rejects(rpc(users[0],'signal',signal),/session changed/);
 await assert.rejects(rpc(users[1],'media',{id,session:sessions[1],device:devices[1],enabled:true,start:false,camera:false,microphone:false}),/session changed/);
 await rpc(users[1],'media',{id,session:sessions[1],enabled:false});assert.equal((await rpc(users[1],'sync',{id,session:fresh,device:devices[1]})).players.find(p=>p.id===profiles[1].id).mediaSession,fresh);
});
test('leaving, blocks and expiry close active rooms and discard private state',async()=>{
 const id=await table();await start(id);await rpc(users[1],'leave',{id});const r=await rpc(users[0],'sync',{id});assert.equal(r.state.phase,'closed');assert.equal(r.state.hands,undefined);
 const next=await table();await social(users[1],'block',{peer:profiles[0].id});assert.equal((await rpc(users[0],'sync',{id:next})).state.phase,'closed');
});
test('RLS and grants deny browser roles all tables and private engine RPCs',async()=>{
 for(const role of ['anon','authenticated']){await db.exec(`set role ${role}`);try{for(const table of ['tables','members','signals'])await assert.rejects(db.query(`select * from korlix_domino_${table}`),/permission denied/);await assert.rejects(rpc(users[0],'list'),/permission denied/);}finally{await db.exec('reset role');}}
 const r=await db.query("select relrowsecurity from pg_class where relname in ('korlix_domino_tables','korlix_domino_members','korlix_domino_signals')");assert(r.rows.every(r=>r.relrowsecurity));
 await api('unknown',{action:'list'},401);await api(users[0],{action:'commit'},404);
});
