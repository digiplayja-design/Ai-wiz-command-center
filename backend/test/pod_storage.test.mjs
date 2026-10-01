import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile,readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {createPodStore} from '../pod/store.mjs';

let db,store,owner,other;
const limits={tier:'ultra',monthlySessions:20,monthlySeconds:10800,monthlyTokens:4000000,maxSessionSeconds:1200,maxResponses:80};
const input={category:'technology',topic:'What makes technology useful?',durationSeconds:900,hostCount:3,style:'balanced'};
const welcomeTurn=hostCount=>({speaker:'host',sourceIds:[],text:`Hey, I’m K-Nova. Welcome to The Pod and You, with ${hostCount===3?'our AI Analyst and Challenger':'our AI Analyst'}. Next, we’ll check sources before discussing the facts. That check can take a little time. You can pause us, or use Chime in to add your take.`});
const raw=async(actor,action,id=null,data={})=>(await db.query('select public.korlix_pod_v1($1,$2,$3,$4) r',[actor,action,id,data])).rows[0].r;
const create=async(extra={})=>store.create(owner,{requestId:randomUUID(),input,limits,...extra});
const row=async(id)=>(await db.query('select * from public.korlix_pod_sessions where id=$1',[id])).rows[0];
const monthly=async()=>(await db.query('select * from public.korlix_live_convo_monthly_usage where user_id=$1',[owner])).rows[0];
const claim=async(episode,kind='next',requestId=randomUUID())=>({requestId,...await store.claim(owner,episode.id,{requestId,version:episode.version,kind})});
async function paid(id,requestId,key,usage={}) {
 assert.equal((await store.authorizeDispatch(owner,id,requestId,key)).allowed,true);
 return store.recordUsage(owner,id,requestId,{callKey:key,usage,evidence:{model:'fixture',usageKnown:key!=='speak'}});
}
async function firstTurn(extra={}) {
 const {episode}=await create(extra),c=await claim(episode);
 await paid(episode.id,c.requestId,'turn',{inputTokens:8,outputTokens:12,totalTokens:20});
 await paid(episode.id,c.requestId,'speak');
 const done=await store.finish(owner,episode.id,c.requestId,{turn:{speaker:'host',text:'Welcome to this conversation.',sourceIds:[]}});
 assert(done.committed);return {...done,requestId:c.requestId};
}
test.before(async()=>{
 db=new PGlite();
 await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);');
 const dir=new URL('../../supabase/migrations/',import.meta.url);
 await db.exec(await readFile(new URL('202607120001_live_convo_limits_build129.sql',dir),'utf8'));
 const name=(await readdir(dir)).find(n=>n.endsWith('_pod_personal_beta.sql'));
 await db.exec(await readFile(new URL(name,dir),'utf8'));
 const welcomeMigration=(await readdir(dir)).find(n=>n.endsWith('_pod_prompt_welcome_audio.sql'));
 await db.exec(await readFile(new URL(welcomeMigration,dir),'utf8'));
 const preparedMigration=(await readdir(dir)).find(n=>n.endsWith('_pod_prepared_turn_buffer.sql'));
 await db.exec(await readFile(new URL(preparedMigration,dir),'utf8'));
 store=createPodStore({database:{rpc:async(_name,p)=>{try{return {data:await raw(p.p_actor,p.p_action,p.p_id,p.p_data)};}catch(error){if(process.env.POD_DEBUG)console.error(error.message,error.where);return {error};}}},logger:{warn(){}}});
});
test.beforeEach(async()=>{await db.exec('reset role');owner=randomUUID();other=randomUUID();await db.query('insert into auth.users values($1),($2)',[owner,other]);await db.exec('set role service_role');});
test.after(async()=>{await db.close();});

test('Listen creates one private reservation and retries neither reserve nor generate again',async()=>{
 const requestId=randomUUID(),a=await create({requestId}),b=await create({requestId});
 assert.equal(a.episode.state,'ready');assert.equal(a.episode.startedAt,null);assert.equal(a.episode.deadlineAt,null);
 assert.equal(b.episode.id,a.episode.id);assert(b.replayed);assert.equal((await monthly()).session_count,1);
 assert(!('quotaSessionId' in a.episode));assert(!JSON.stringify(a.episode).includes('owner_id'));
 await assert.rejects(create({requestId,input:{...input,topic:'Changed'}}),e=>e.status===409);
 assert.equal((await db.query('select count(*)::int n from korlix_pod_operations where episode_id=$1',[requestId])).rows[0].n,0);
});
test('reservation and episode creation are atomic, including insufficient remaining time',async()=>{
 await assert.rejects(create({limits:{...limits,monthlySeconds:899}}),e=>e.status===429);
 assert.equal((await db.query('select count(*)::int n from korlix_live_convo_sessions where user_id=$1',[owner])).rows[0].n,0);
 assert.equal((await db.query('select count(*)::int n from korlix_pod_sessions where owner_id=$1',[owner])).rows[0].n,0);
 await assert.rejects(create({limits:{...limits,maxSessionSeconds:600}}),e=>e.status===429);
});
test('one live episode per account, owner isolation and scoped quota lookup',async()=>{
 const {episode}=await create();await assert.rejects(create(),e=>e.status===409);
 await assert.rejects(store.get(other,episode.id),e=>e.status===404);
 assert.equal((await store.list(other)).episodes.length,0);
 const s=await row(episode.id);assert(await store.isQuotaSession(owner,s.quota_session_id));assert.equal(await store.isQuotaSession(other,s.quota_session_id),false);
});
test('one durable claim, no automatic dispatch replay, and changed operation key conflicts',async()=>{
 const {episode}=await create(),c=await claim(episode);
 const replay=await store.claim(owner,episode.id,{requestId:c.requestId,version:episode.version,kind:'next'});
 assert.equal(replay.dispatch,false);assert(replay.replayed);
 await assert.rejects(claim(episode),e=>e.status===409);
 assert((await store.authorizeDispatch(owner,episode.id,c.requestId,'turn')).allowed);
 await assert.rejects(store.authorizeDispatch(owner,episode.id,c.requestId,'turn'),e=>e.status===409);
 await assert.rejects(store.claim(owner,episode.id,{requestId:c.requestId,version:4,kind:'next'}),e=>e.status===409);
});
test('real usage is cumulative exactly once; unknown binary TTS stays explicit evidence',async()=>{
 const {episode}=await create(),c=await claim(episode);
 await paid(episode.id,c.requestId,'turn',{inputTokens:5,outputTokens:7,totalTokens:12});
 const receipt={callKey:'turn',usage:{inputTokens:5,outputTokens:7,totalTokens:12},evidence:{model:'fixture',usageKnown:true}};
 assert((await store.recordUsage(owner,episode.id,c.requestId,receipt)).replayed);
 await assert.rejects(store.recordUsage(owner,episode.id,c.requestId,{...receipt,usage:{totalTokens:99}}),e=>e.status===409);
 await paid(episode.id,c.requestId,'speak');
 const s=await row(episode.id),m=await monthly();assert.equal(s.total_tokens,12);assert.equal(m.total_tokens,12);assert.equal(s.output_audio_tokens,0);
 const evidence=(await db.query("select evidence from korlix_pod_usage_receipts where episode_id=$1 and call_key='speak'",[episode.id])).rows[0].evidence;assert.equal(evidence.usageKnown,false);
 await assert.rejects(store.recordUsage(owner,episode.id,c.requestId,{callKey:'research',usage:{totalTokens:1}}),e=>e.status===400);
});
test('fixed first welcome commits with speech receipt alone and no fabricated text usage, sources or brief',async()=>{
 const {episode}=await create(),c=await claim(episode);await paid(episode.id,c.requestId,'speak');
 const done=await store.finish(owner,episode.id,c.requestId,{welcome:true,turn:welcomeTurn(3)});assert(done.committed);assert.equal(done.episode.state,'active');
 assert.equal(done.episode.turns.length,1);assert.deepEqual(done.episode.sources,[]);assert.equal(done.episode.checkedAt,null);assert.deepEqual((await store.get(owner,episode.id)).brief,{});
 const m=await monthly();assert.equal(m.response_count,0);assert.equal(m.total_tokens,0);assert.equal(m.output_audio_tokens,0);assert.equal(m.session_count,1);
 assert.equal(Date.parse(done.episode.deadlineAt)-Date.parse(done.episode.startedAt),900000);
 const nextClaim=await claim(done.episode);await paid(episode.id,nextClaim.requestId,'speak');
 await assert.rejects(store.finish(owner,episode.id,nextClaim.requestId,{welcome:true,turn:welcomeTurn(3)}),e=>e.status===400);
});
test('welcome guard rejects improvised text and fake source metadata but supports two-host copy',async()=>{
 const {episode}=await create({input:{...input,hostCount:2}}),c=await claim(episode);await paid(episode.id,c.requestId,'speak');
 await assert.rejects(store.finish(owner,episode.id,c.requestId,{welcome:true,turn:{...welcomeTurn(2),text:'A fabricated factual opening.'}}),e=>e.status===400);
 await assert.rejects(store.finish(owner,episode.id,c.requestId,{welcome:true,turn:welcomeTurn(2),brief:{text:'Pretend research'}}),e=>e.status===400);
 const done=await store.finish(owner,episode.id,c.requestId,{welcome:true,turn:welcomeTurn(2)});assert(done.committed);
});
test('research can commit its sourced initial Analyst turn with one real text receipt and no second text dispatch',async()=>{
 const {episode}=await create(),welcome=await claim(episode);await paid(episode.id,welcome.requestId,'speak');
 const opening=await store.finish(owner,episode.id,welcome.requestId,{welcome:true,turn:welcomeTurn(3)}),c=await claim(opening.episode);
 await paid(episode.id,c.requestId,'research',{inputTokens:15,outputTokens:30,totalTokens:45});await paid(episode.id,c.requestId,'speak');
 const sources=[{id:'s1',title:'Fixture source',url:'https://www.nasa.gov/'}],brief={text:'A sourced factual fixture.',sources,checkedAt:new Date().toISOString()};
 await assert.rejects(store.finish(owner,episode.id,c.requestId,{turn:{speaker:'analyst',text:'The first grounded thought.',sourceIds:['fake']},brief,sources,checkedAt:brief.checkedAt}),e=>e.status===400);
 const done=await store.finish(owner,episode.id,c.requestId,{turn:{speaker:'analyst',text:'The first grounded thought.',sourceIds:['s1']},brief,sources,checkedAt:brief.checkedAt});
 assert(done.committed);assert.equal(done.episode.turns.length,2);assert.equal(done.episode.deadlineAt,opening.episode.deadlineAt);assert.equal((await monthly()).response_count,1);assert.equal((await monthly()).total_tokens,45);
 const dispatch=(await db.query('select dispatched from korlix_pod_operations where episode_id=$1 and request_id=$2',[episode.id,c.requestId])).rows[0].dispatched;
 assert.deepEqual(Object.keys(dispatch).sort(),['research','speak']);
});
test('215-second claim lease remains bounded by ready expiry and by the immutable playback deadline',async()=>{
 const {episode}=await create(),welcome=await claim(episode);
 assert(Date.parse(welcome.operation.leaseUntil)<=Date.parse(episode.createdAt)+180000);
 await paid(episode.id,welcome.requestId,'speak');const opening=await store.finish(owner,episode.id,welcome.requestId,{welcome:true,turn:welcomeTurn(3)});
 const c=await claim(opening.episode),delta=Date.parse(c.operation.leaseUntil)-Date.parse(c.episode.serverNow);assert(delta>213000&&delta<=215000);
 await store.control(owner,episode.id,'interrupt');await store.fail(owner,episode.id,c.requestId);await store.control(owner,episode.id,'resume');
 await db.query("update korlix_pod_sessions set started_at=now()-interval '870 seconds',deadline_at=now()+interval '30 seconds' where id=$1",[episode.id]);
 const updated=(await store.get(owner,episode.id)).episode,near=await claim(updated);assert.equal(Date.parse(near.operation.leaseUntil),Date.parse(updated.deadlineAt));
});
test('first successful turn starts the immutable 900-second deadline; completed replay does not generate',async()=>{
 const {episode,requestId}=await firstTurn();assert.equal(episode.state,'active');
 assert.equal(Date.parse(episode.deadlineAt)-Date.parse(episode.startedAt),900000);
 const done=await store.finish(owner,episode.id,requestId,{turn:{speaker:'host',text:'Must not replace.'}});assert(done.replayed);assert.equal(done.episode.turns.length,1);
 const c=await store.claim(owner,episode.id,{requestId,version:0,kind:'next'});assert.equal(c.dispatch,false);assert.equal(c.result.turn.text,'Welcome to this conversation.');
 const stopped=await store.control(owner,episode.id,'pause');const resumed=await store.control(owner,episode.id,'resume');assert.equal(resumed.episode.deadlineAt,episode.deadlineAt);assert.equal(stopped.episode.state,'paused');
});
test('pause accumulates only active server time, and resume never extends deadline',async()=>{
 const {episode}=await firstTurn();
 await db.query("update korlix_pod_sessions set accounted_at=clock_timestamp()-interval '20 seconds',last_heartbeat_at=clock_timestamp() where id=$1",[episode.id]);
 const pause=await store.control(owner,episode.id,'pause');assert(pause.episode.activeSeconds>=20&&pause.episode.activeSeconds<=21);
 await db.query("update korlix_pod_sessions set accounted_at=clock_timestamp()-interval '200 seconds' where id=$1",[episode.id]);
 const resumed=await store.control(owner,episode.id,'resume');assert.equal(resumed.episode.activeSeconds,pause.episode.activeSeconds);assert.equal(resumed.episode.deadlineAt,episode.deadlineAt);
 assert.equal((await monthly()).duration_seconds,pause.episode.activeSeconds);
});
test('missing heartbeat bounds billable time to 35 seconds and pauses before refresh',async()=>{
 const {episode}=await firstTurn();
 await db.query("update korlix_pod_sessions set accounted_at=clock_timestamp()-interval '100 seconds',last_heartbeat_at=clock_timestamp()-interval '100 seconds' where id=$1",[episode.id]);
 const h=await store.control(owner,episode.id,'heartbeat');assert.equal(h.episode.state,'paused');assert(h.episode.activeSeconds>=35&&h.episode.activeSeconds<=36);assert.equal(h.episode.endReason,'heartbeat_lost');
});
test('interrupt invalidates output but keeps the dispatch lease until cancellation acknowledgement',async()=>{
 const {episode}=await firstTurn(),c=await claim(episode);await paid(episode.id,c.requestId,'turn',{totalTokens:10});
 const paused=await store.control(owner,episode.id,'interrupt');assert.equal(paused.episode.state,'paused');
 assert.equal((await store.authorizeDispatch(owner,episode.id,c.requestId,'speak')).allowed,false);
 await assert.rejects(store.control(owner,episode.id,'resume'),e=>e.status===409);
 const done=await store.finish(owner,episode.id,c.requestId,{turn:{speaker:'analyst',text:'Stale'}});assert.equal(done.committed,false);assert.equal(done.episode.turns.length,1);
 assert.equal((await row(episode.id)).total_tokens,30);
 assert.equal((await store.control(owner,episode.id,'resume')).episode.state,'active');
});
test('late provider usage after interruption is retained without restoring output',async()=>{
 const {episode}=await firstTurn(),c=await claim(episode);
 await store.authorizeDispatch(owner,episode.id,c.requestId,'turn');await store.control(owner,episode.id,'interrupt');
 const r=await store.recordUsage(owner,episode.id,c.requestId,{callKey:'turn',usage:{totalTokens:19},evidence:{usageKnown:true}});assert.equal(r.allowed,false);
 await store.fail(owner,episode.id,c.requestId,{uncertain:true});assert.equal((await row(episode.id)).total_tokens,39);assert.equal((await monthly()).total_tokens,39);
});
test('expired operation cannot dispatch or retry automatically and survives process recovery',async()=>{
 const {episode}=await create(),c=await claim(episode);await store.authorizeDispatch(owner,episode.id,c.requestId,'turn');
 await db.query("update korlix_pod_operations set lease_until=clock_timestamp()-interval '1 second' where episode_id=$1",[episode.id]);
 await store.sweep();const got=await store.get(owner,episode.id);assert.equal(got.episode.state,'failed');
 const r=await store.claim(owner,episode.id,{requestId:c.requestId,version:0,kind:'next'});assert.equal(r.dispatch,false);assert.equal(r.operation.state,'expired');
 assert.equal((await monthly()).session_count,1);
});
test('End then Listen cannot overlap an older paid call; sweep releases its expired lease',async()=>{
 const {episode}=await create(),c=await claim(episode);await store.authorizeDispatch(owner,episode.id,c.requestId,'turn');
 await store.control(owner,episode.id,'end');await assert.rejects(create(),e=>e.status===409);
 await db.query("update korlix_pod_operations set lease_until=clock_timestamp()-interval '1 second' where episode_id=$1",[episode.id]);
 await store.sweep();const next=await create();assert.equal(next.episode.state,'ready');assert.equal((await monthly()).session_count,2);
});
test('uncertain provider error retains its dispatch and session even when exact usage is unavailable',async()=>{
 const {episode}=await create(),c=await claim(episode);await store.authorizeDispatch(owner,episode.id,c.requestId,'research');
 await store.recordUsage(owner,episode.id,c.requestId,{callKey:'research',usage:{},evidence:{status:'uncertain',usageKnown:false}});
 await store.fail(owner,episode.id,c.requestId);assert.equal((await monthly()).session_count,1);
 const op=(await db.query('select * from korlix_pod_operations where episode_id=$1',[episode.id])).rows[0];assert.equal(op.uncertain,true);
 await store.remove(owner,episode.id,{confirmed:true});assert.equal((await monthly()).session_count,1);
});
test('stale initial preparation heartbeat invalidates work before a heartbeat can refresh it',async()=>{
 const {episode}=await create(),c=await claim(episode);await store.authorizeDispatch(owner,episode.id,c.requestId,'research');
 await db.query("update korlix_pod_sessions set last_heartbeat_at=clock_timestamp()-interval '36 seconds' where id=$1",[episode.id]);
 const h=await store.control(owner,episode.id,'heartbeat');assert.equal(h.episode.state,'paused');assert.equal(h.episode.version,1);
 assert.equal((await store.authorizeDispatch(owner,episode.id,c.requestId,'turn')).allowed,false);
});
test('ready expiration refunds a never-dispatched reservation once and retains rate receipts',async()=>{
 const {episode}=await create();await db.query("update korlix_pod_sessions set created_at=clock_timestamp()-interval '181 seconds' where id=$1",[episode.id]);
 assert.equal((await store.get(owner,episode.id)).episode.endReason,'ready_expired');assert.equal((await monthly()).session_count,0);
 await store.get(owner,episode.id);assert.equal((await monthly()).session_count,0);
});
test('absolute deadline expires even while paused and cannot be revived',async()=>{
 const {episode}=await firstTurn();await store.control(owner,episode.id,'pause');
 await db.query("update korlix_pod_sessions set started_at=clock_timestamp()-interval '901 seconds',deadline_at=clock_timestamp()-interval '1 second' where id=$1",[episode.id]);
 const r=await store.control(owner,episode.id,'resume');assert.equal(r.episode.state,'ended');assert.equal(r.episode.endReason,'time_limit');
});
test('contributions require a pause, are idempotent, attributed and bounded',async()=>{
 const {episode}=await firstTurn(),requestId=randomUUID();await assert.rejects(store.contribute(owner,episode.id,{requestId,text:'My thought'}),e=>e.status===409);
 await store.control(owner,episode.id,'interrupt');const c=await store.contribute(owner,episode.id,{requestId,text:'My thought'});assert.equal(c.episode.turns.at(-1).speaker,'user');
 const r=await store.contribute(owner,episode.id,{requestId,text:'My thought'});assert(r.replayed);assert.equal(r.episode.turns.length,2);
 await assert.rejects(store.contribute(owner,episode.id,{requestId,text:'Changed'}),e=>e.status===409);
 for(let i=1;i<12;i++)await store.contribute(owner,episode.id,{requestId:randomUUID(),text:'Another thought '+i});
 await assert.rejects(store.contribute(owner,episode.id,{requestId:randomUUID(),text:'Too many'}),e=>e.status===429);
});
test('transcription is reviewed text, never submitted automatically, and is not double-counted',async()=>{
 const {episode}=await firstTurn(),paused=await store.control(owner,episode.id,'pause'),c=await claim(paused.episode,'transcribe');
 await store.authorizeDispatch(owner,episode.id,c.requestId,'transcribe');
 await assert.rejects(store.recordUsage(owner,episode.id,c.requestId,{callKey:'transcribe',usage:{totalTokens:7,transcriptionTokens:7}}),e=>e.status===400);
 await store.recordUsage(owner,episode.id,c.requestId,{callKey:'transcribe',usage:{transcriptionTokens:7},evidence:{usageKnown:true}});
 const r=await store.finish(owner,episode.id,c.requestId,{text:'Review this thought'});assert.equal(r.text,'Review this thought');assert.equal(r.episode.turns.length,1);assert.equal(r.episode.state,'paused');
 const m=await monthly();assert.equal(m.total_tokens,20);assert.equal(m.transcription_tokens,7);
});
test('usage exhaustion ends the episode before any later dispatch',async()=>{
 const {episode}=await create({limits:{...limits,monthlyTokens:10}}),c=await claim(episode);
 const r=await paid(episode.id,c.requestId,'turn',{totalTokens:12});assert.equal(r.allowed,false);assert.equal(r.episode.state,'ended');
 assert.equal((await store.authorizeDispatch(owner,episode.id,c.requestId,'speak')).allowed,false);
});
test('a valid silence transcription preserves the paused episode for review without submitting text',async()=>{
 const {episode}=await firstTurn(),paused=await store.control(owner,episode.id,'pause'),c=await claim(paused.episode,'transcribe');
 await paid(episode.id,c.requestId,'transcribe',{transcriptionTokens:2});
 const r=await store.finish(owner,episode.id,c.requestId,{text:''});assert(r.committed);assert.equal(r.text,'');assert.equal(r.episode.state,'paused');assert.equal(r.episode.turns.length,1);
 assert.equal((await monthly()).transcription_tokens,2);
});
test('developer access bypasses monthly debit but keeps the 900-second and operation boundaries',async()=>{
 const {episode}=await firstTurn({unlimited:true,limits:{...limits,monthlySessions:0,monthlySeconds:0,monthlyTokens:0}});
 assert.equal(await monthly(),undefined);const s=await row(episode.id);const quota=(await db.query('select * from korlix_live_convo_sessions where id=$1',[s.quota_session_id])).rows[0];assert.equal(quota.tier,'developer_unlimited');assert.equal(quota.total_tokens,20);assert.equal(quota.max_duration_seconds,900);
});
test('history deletion scrubs content but retains billing and replay receipts without refunds',async()=>{
 const {episode}=await firstTurn();await assert.rejects(store.remove(owner,episode.id,{confirmed:true}),e=>e.status===409);
 await store.control(owner,episode.id,'end');await store.remove(owner,episode.id,{confirmed:true});await store.remove(owner,episode.id,{confirmed:true});
 await assert.rejects(store.get(owner,episode.id),e=>e.status===404);assert.equal((await store.list(owner)).episodes.length,0);
 const s=await row(episode.id);assert.deepEqual(s.input,{});assert.deepEqual(s.turns,[]);assert.deepEqual(s.brief,{});assert.equal((await monthly()).total_tokens,20);assert.equal((await monthly()).session_count,1);
 assert.equal((await db.query('select count(*)::int n from korlix_pod_usage_receipts where episode_id=$1',[episode.id])).rows[0].n,2);
 assert(await store.isQuotaSession(owner,s.quota_session_id));
});
test('service-only tables/functions enforce RLS and deny direct client accounting mutations',async()=>{
 await db.exec('reset role');for(const table of ['korlix_pod_sessions','korlix_pod_operations','korlix_pod_usage_receipts'])assert((await db.query('select relrowsecurity from pg_class where relname=$1',[table])).rows[0].relrowsecurity);
 for(const role of ['anon','authenticated']){
  await db.exec('set role '+role);
  await assert.rejects(db.query('select * from korlix_pod_sessions'),/permission denied/);
  await assert.rejects(db.query("select public.korlix_pod_v1($1,'list')",[owner]),/permission denied/);
  await assert.rejects(db.query("select public.korlix_pod_v1(null,'sweep')"),/permission denied/);
  await db.exec('reset role');
 }
});

async function prepareTurn(episode, extra={}) {
 const c=await claim(episode,'prepare');
 await paid(episode.id,c.requestId,'turn',{inputTokens:5,outputTokens:5,totalTokens:10});
 await paid(episode.id,c.requestId,'speak');
 const result={turn:{speaker:'analyst',text:'A prepared second perspective.',sourceIds:[]},...extra};
 return {...await store.finish(owner,episode.id,c.requestId,result),requestId:c.requestId};
}
test('one prepared turn stays private until atomic handoff and retries never append twice',async()=>{
 const {episode}=await firstTurn(),ready=await prepareTurn(episode);
 assert(ready.prepared);assert(ready.committed);assert.equal(ready.preparedId,ready.requestId);assert(!('turn' in ready));
 assert.equal(ready.episode.preparedId,ready.requestId);assert.equal(ready.episode.turns.length,1);assert.equal(ready.episode.phase,'listening');
 const privateOp=(await db.query('select * from korlix_pod_operations where episode_id=$1 and request_id=$2',[episode.id,ready.requestId])).rows[0];
 assert.equal(privateOp.state,'prepared');assert.equal(privateOp.result.turn.text,'A prepared second perspective.');
 await assert.rejects(claim(ready.episode,'prepare'),e=>e.status===409);
 await assert.rejects(claim(ready.episode,'next'),e=>e.status===409);
 const same=await store.claim(owner,episode.id,{requestId:ready.requestId,version:episode.version,kind:'prepare'});
 assert.equal(same.dispatch,false);assert.deepEqual(same.result,{});
 const finishedAgain=await store.finish(owner,episode.id,ready.requestId,{});assert(finishedAgain.prepared);assert(!('turn' in finishedAgain));
 const played=await store.playPrepared(owner,episode.id,{requestId:ready.requestId,version:ready.episode.version});
 assert(played.committed);assert.equal(played.episode.turns.length,2);assert.equal(played.turn.id,ready.requestId);assert.equal(played.episode.preparedId,null);
 const repeated=await store.playPrepared(owner,episode.id,{requestId:ready.requestId,version:played.episode.version});assert(repeated.replayed);assert.equal(repeated.episode.turns.length,2);
 assert.equal((await monthly()).total_tokens,30);assert.equal(played.episode.deadlineAt,episode.deadlineAt);
});
test('prepared research does not expose brief, sources, summary or heard transcript before consume',async()=>{
 const {episode}=await create(),welcome=await claim(episode);await paid(episode.id,welcome.requestId,'speak');
 const opening=await store.finish(owner,episode.id,welcome.requestId,{welcome:true,turn:welcomeTurn(3)}),c=await claim(opening.episode,'prepare');
 await paid(episode.id,c.requestId,'research',{inputTokens:4,outputTokens:6,totalTokens:10});await paid(episode.id,c.requestId,'speak');
 const sources=[{id:'s1',title:'Fixture',url:'https://www.nasa.gov/'}],brief={text:'Checked facts.',sources,checkedAt:new Date().toISOString()};
 const ready=await store.finish(owner,episode.id,c.requestId,{turn:{speaker:'analyst',text:'A grounded opening.',sourceIds:['s1']},brief,sources,checkedAt:brief.checkedAt});
 assert.equal(ready.episode.turns.length,1);assert.deepEqual(ready.episode.sources,[]);assert.deepEqual((await store.get(owner,episode.id)).brief,{});
 const played=await store.playPrepared(owner,episode.id,{requestId:c.requestId,version:ready.episode.version});
 assert.equal(played.episode.turns.length,2);assert.deepEqual(played.episode.sources,sources);assert.equal((await store.get(owner,episode.id)).brief.text,'Checked facts.');
});
test('ordinary pause and lost heartbeat preserve a completed preparation without extending its deadline',async()=>{
 const {episode}=await firstTurn(),ready=await prepareTurn(episode),paused=await store.control(owner,episode.id,'pause');
 assert.equal(paused.episode.preparedId,ready.requestId);assert(paused.episode.version>ready.episode.version);
 await assert.rejects(store.playPrepared(owner,episode.id,{requestId:ready.requestId,version:paused.episode.version}),e=>e.status===409);
 const resumed=await store.control(owner,episode.id,'resume');
 await assert.rejects(store.playPrepared(owner,episode.id,{requestId:ready.requestId,version:ready.episode.version}),e=>e.status===409);
 await db.query("update korlix_pod_sessions set last_heartbeat_at=clock_timestamp()-interval '36 seconds' where id=$1",[episode.id]);
 const lost=await store.get(owner,episode.id);assert.equal(lost.episode.state,'paused');assert.equal(lost.episode.preparedId,ready.requestId);
 const again=await store.control(owner,episode.id,'resume'),played=await store.playPrepared(owner,episode.id,{requestId:ready.requestId,version:again.episode.version});
 assert(played.committed);assert.equal(played.episode.deadlineAt,resumed.episode.deadlineAt);assert.equal((await monthly()).total_tokens,30);
 const secondPause=await store.control(owner,episode.id,'pause'),secondResume=await store.control(owner,episode.id,'resume');
 const lostResponseReplay=await store.playPrepared(owner,episode.id,{requestId:ready.requestId,version:secondResume.episode.version});
 assert(lostResponseReplay.replayed);assert.equal(lostResponseReplay.episode.turns.length,2);assert.equal(secondPause.episode.preparedId,null);
});
test('Chime in discards staged words while keeping actual receipts; old preparation cannot be consumed',async()=>{
 const {episode}=await firstTurn(),ready=await prepareTurn(episode),interrupted=await store.control(owner,episode.id,'interrupt');
 assert.equal(interrupted.episode.preparedId,null);
 await store.contribute(owner,episode.id,{requestId:randomUUID(),text:'Please address my different perspective.'});
 const resumed=await store.control(owner,episode.id,'resume');
 await assert.rejects(store.playPrepared(owner,episode.id,{requestId:ready.requestId,version:resumed.episode.version}),e=>e.status===409);
 assert.equal(resumed.episode.turns.length,2);assert.equal(resumed.episode.turns.at(-1).speaker,'user');assert.equal((await monthly()).total_tokens,30);
 const op=(await db.query('select state,result from korlix_pod_operations where episode_id=$1 and request_id=$2',[episode.id,ready.requestId])).rows[0];assert.equal(op.state,'interrupted');assert.deepEqual(op.result,{});
});
test('prepared handoff rejects owner mismatch and changed transcript context',async()=>{
 const {episode}=await firstTurn(),ready=await prepareTurn(episode);
 await assert.rejects(store.playPrepared(other,episode.id,{requestId:ready.requestId,version:episode.version}),e=>e.status===404);
 await db.query("update korlix_pod_sessions set turns=turns||$2::jsonb where id=$1",[episode.id,JSON.stringify([{id:randomUUID(),speaker:'user',text:'Changed',seq:2}])]);
 await assert.rejects(store.playPrepared(owner,episode.id,{requestId:ready.requestId,version:episode.version}),e=>e.status===409);
 assert.equal((await row(episode.id)).turns.length,2);
});
test('end and absolute deadline discard staged output without altering billing evidence',async()=>{
 const {episode}=await firstTurn(),ready=await prepareTurn(episode),ended=await store.control(owner,episode.id,'end');assert.equal(ended.episode.preparedId,null);
 await assert.rejects(store.playPrepared(owner,episode.id,{requestId:ready.requestId,version:ended.episode.version}),e=>e.status===409);
 assert.equal((await monthly()).total_tokens,30);
 const next=await firstTurn(),nextReady=await prepareTurn(next.episode);
 await db.query("update korlix_pod_sessions set started_at=clock_timestamp()-interval '901 seconds',deadline_at=clock_timestamp()-interval '1 second' where id=$1",[next.episode.id]);
 const expired=await store.get(owner,next.episode.id);assert.equal(expired.episode.state,'ended');assert.equal(expired.episode.preparedId,null);
 assert.equal((await db.query('select state from korlix_pod_operations where episode_id=$1 and request_id=$2',[next.episode.id,nextReady.requestId])).rows[0].state,'interrupted');
});
test('prepare cannot start an episode or create a second closing after the closing was consumed',async()=>{
 const {episode}=await create();await assert.rejects(claim(episode,'prepare'),e=>e.status===409);assert.equal((await monthly()).total_tokens,0);
 const c=await claim(episode);await paid(episode.id,c.requestId,'speak');
 const welcome=await store.finish(owner,episode.id,c.requestId,{welcome:true,turn:welcomeTurn(3)});
 const closing=await prepareTurn(welcome.episode,{summary:'Thanks for listening.'});assert.equal(closing.episode.summary,null);
 const played=await store.playPrepared(owner,episode.id,{requestId:closing.requestId,version:closing.episode.version});assert.equal(played.episode.summary,'Thanks for listening.');
 await assert.rejects(claim(played.episode,'prepare'),e=>e.status===409);
});
test('known prefetch failure leaves current audio active and requires an explicit pause/resume before retry',async()=>{
 const {episode}=await firstTurn(),c=await claim(episode,'prepare');await paid(episode.id,c.requestId,'turn',{inputTokens:5,outputTokens:5,totalTokens:10});
 const failed=await store.fail(owner,episode.id,c.requestId,{error:'The next voice could not prepare.'});
 assert.equal(failed.episode.state,'active');assert.equal(failed.episode.version,episode.version);assert.equal(failed.episode.turns.length,1);assert.equal(failed.episode.preparationError,'The next voice could not prepare.');
 await assert.rejects(claim(failed.episode,'prepare'),e=>e.status===409);await assert.rejects(claim(failed.episode,'next'),e=>e.status===409);await assert.rejects(store.control(owner,episode.id,'resume'),e=>e.status===409);
 await store.control(owner,episode.id,'pause');const resumed=await store.control(owner,episode.id,'resume');assert.equal(resumed.episode.preparationError,null);
 const retry=await claim(resumed.episode,'prepare');assert(retry.dispatch);assert.equal((await monthly()).total_tokens,30);
});
test('uncertain prefetch usage remains receipted and cannot restart paid work by pause/resume',async()=>{
 const {episode}=await firstTurn(),c=await claim(episode,'prepare');await store.authorizeDispatch(owner,episode.id,c.requestId,'turn');
 await store.recordUsage(owner,episode.id,c.requestId,{callKey:'turn',usage:{},evidence:{status:'uncertain',usageKnown:false}});
 const failed=await store.fail(owner,episode.id,c.requestId,{error:'AI usage is unknown.'});assert.equal(failed.episode.state,'active');
 await store.control(owner,episode.id,'pause');await assert.rejects(store.control(owner,episode.id,'resume'),e=>e.status===409);
 const receipts=(await db.query('select count(*)::int n from korlix_pod_usage_receipts where episode_id=$1',[episode.id])).rows[0].n;assert.equal(receipts,3);
});
test('cache loss discards only prepared output and requires explicit retry without appending unheard words',async()=>{
 const {episode}=await firstTurn(),ready=await prepareTurn(episode);
 const discarded=await store.discardPrepared(owner,episode.id,{requestId:ready.requestId,version:episode.version});assert(discarded.discarded);assert.equal(discarded.episode.preparedId,null);assert.equal(discarded.episode.turns.length,1);assert(discarded.episode.preparationError.includes('expired'));
 await assert.rejects(claim(discarded.episode,'prepare'),e=>e.status===409);
 await store.control(owner,episode.id,'pause');const resumed=await store.control(owner,episode.id,'resume');const retry=await claim(resumed.episode,'prepare');assert(retry.dispatch);assert.equal((await monthly()).total_tokens,30);
});
test('pause during paid preparation rejects late output but retains its measured usage',async()=>{
 const {episode}=await firstTurn(),c=await claim(episode,'prepare');await store.authorizeDispatch(owner,episode.id,c.requestId,'turn');await store.control(owner,episode.id,'pause');
 const receipt=await store.recordUsage(owner,episode.id,c.requestId,{callKey:'turn',usage:{inputTokens:5,outputTokens:6,totalTokens:11},evidence:{usageKnown:true}});assert.equal(receipt.allowed,false);
 const late=await store.finish(owner,episode.id,c.requestId,{turn:{speaker:'analyst',text:'This must never become heard.'}});assert.equal(late.committed,false);assert.equal(late.episode.turns.length,1);assert.equal(late.episode.preparedId,null);assert.equal((await monthly()).total_tokens,31);
 const resumed=await store.control(owner,episode.id,'resume');assert.equal(resumed.episode.state,'active');
});
test('expired preparation lease preserves current playback and does not automatically repeat a dispatched call',async()=>{
 const {episode}=await firstTurn(),c=await claim(episode,'prepare');await store.authorizeDispatch(owner,episode.id,c.requestId,'turn');
 await db.query("update korlix_pod_operations set lease_until=clock_timestamp()-interval '1 second' where episode_id=$1 and request_id=$2",[episode.id,c.requestId]);
 const current=await store.get(owner,episode.id);assert.equal(current.episode.state,'active');assert.equal(current.episode.version,episode.version);assert.equal(current.episode.turns.length,1);assert(current.episode.preparationError);
 await assert.rejects(claim(current.episode,'prepare'),e=>e.status===409);assert.equal((await store.authorizeDispatch(owner,episode.id,c.requestId,'speak')).allowed,false);
 await store.control(owner,episode.id,'pause');await assert.rejects(store.control(owner,episode.id,'resume'),e=>e.status===409);
 const op=(await db.query('select state,uncertain from korlix_pod_operations where episode_id=$1 and request_id=$2',[episode.id,c.requestId])).rows[0];assert.equal(op.state,'expired');assert(op.uncertain);
});
test('expired cache after a lost consume response reports already-played without deleting or regenerating transcript',async()=>{
 const {episode}=await firstTurn(),ready=await prepareTurn(episode),played=await store.playPrepared(owner,episode.id,{requestId:ready.requestId,version:episode.version});
 await store.control(owner,episode.id,'pause');const resumed=await store.control(owner,episode.id,'resume');
 const missing=await store.discardPrepared(owner,episode.id,{requestId:ready.requestId,version:resumed.episode.version});
 assert(missing.alreadyPlayed);assert.equal(missing.episode.turns.length,2);assert.equal(missing.turn.id,played.turn.id);assert.equal(missing.episode.preparationError,null);assert.equal((await monthly()).total_tokens,30);
 await store.control(owner,episode.id,'interrupt');await store.contribute(owner,episode.id,{requestId:randomUUID(),text:'Another thought'});const changed=await store.control(owner,episode.id,'resume');
 await assert.rejects(store.discardPrepared(owner,episode.id,{requestId:ready.requestId,version:changed.episode.version}),e=>e.status===409);
});
