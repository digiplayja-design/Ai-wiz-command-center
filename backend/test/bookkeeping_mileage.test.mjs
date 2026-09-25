import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerBookkeeping} from '../bookkeeping/routes.mjs';
import {tenths,mileagePayload,mileageQuery,mileageCsv} from '../bookkeeping/mileage.mjs';
let db,server,base,owner,other,b;
const payload=(extra={})=>({request_key:randomUUID(),confirmed:true,trip_date:'2027-01-31',vehicle:'Blue hatchback',origin:'Studio',destination:'Client office',purpose:'Deliver completed designs',method:'miles',miles:'12.3',...extra});
async function api(path='',body,method=body?'POST':'GET',actor=owner,status=200){const r=await fetch(base+'/api/bookkeeping/businesses'+path,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});const d=await r.json();assert.equal(r.status,status,JSON.stringify(d));assert.equal(r.headers.get('cache-control'),'no-store');return d;}
const path=(suffix='')=>'/'+b.id+'/mileage'+suffix;
const list=(period='2027-01',filter='')=>api(path('?period='+period+filter));
const post=async(extra={})=>(await api(path(),payload(extra),'POST',owner,201)).trip;
const rpc=async(action,p,actor=owner,business=b.id)=>(await db.query('select public.korlix_bookkeeping_mileage_v1($1,$2,$3,$4) r',[actor,action,business,p])).rows[0].r;
test.before(async()=>{
 db=new PGlite();await db.exec('create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);grant usage on schema public to anon,authenticated,service_role;');
 for(const f of ['20260925015926_bookkeeping_foundation.sql','20260925055030_bookkeeping_mileage.sql','20260925062141_bookkeeping_ledger.sql'])await db.exec(await readFile(new URL('../../supabase/migrations/'+f,import.meta.url),'utf8'));
 const database={rpc:async(name,p)=>{try{const r=await db.query(`select public.${name}($1,$2,$3,$4) r`,[p.p_actor,p.p_action,p.p_business,p.p_data]);return {data:r.rows[0].r};}catch(error){if(process.env.BK_DEBUG)console.error(error.message,error.where);return {error};}}};
 const app=express();app.use(express.json());registerBookkeeping(app,{database,requireUser:async q=>[owner,other].includes(q.headers.authorization)?{id:q.headers.authorization}:null});server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.beforeEach(async()=>{await db.exec('reset role');owner=randomUUID();other=randomUUID();for(const u of [owner,other])await db.query('insert into auth.users values($1)',[u]);await db.exec('set role service_role');b=(await api('',{name:'Mileage fixture',legal_structure:'llc',tax_treatment:'unsure',contractor_income:false,request_key:randomUUID()},'POST',owner,201)).business;});
test.after(async()=>{server.closeAllConnections();await new Promise(r=>server.close(r));await db.close();});
test('exact distance parsing rejects float, zero, negative and excess precision',()=>{
 for(const [v,n] of [['0.1','1'],['12.3','123'],['9999.9','99999']])assert.equal(tenths(v),n);
 assert.equal(tenths('9999999.9',{odometer:true}),'99999999');assert.equal(tenths('0',{odometer:true}),'0');
 for(const v of ['0','1.01','-1','1e2','01.2',12.3,' 1','10000'])assert.throws(()=>tenths(v));
 for(const x of [{confirmed:false},{trip_date:'2027-02-29'},{method:'gps'},{vehicle:' '},{origin:'=\n123'},{method:'odometer',odometer_start:'100',odometer_end:'99'}])assert.throws(()=>mileagePayload(payload(x)));
 assert.equal(mileagePayload(payload({trip_date:'2028-02-29'})).trip_date,'2028-02-29');
 for(const q of [{period:'2027-13'},{period:['2027']},{period:'2027',offset:'-1'},{period:'2027',vehicle:[]}])assert.throws(()=>mileageQuery(q));
});
test('miles and odometer difference are exact, monthly totals do not write cash entries',async()=>{
 const a=await post({miles:'0.1'});const z=await post({method:'odometer',odometer_start:'100.1',odometer_end:'100.3'});assert.equal(a.distance_tenths,'1');assert.equal(z.distance_tenths,'2');assert.equal(z.manual_tenths,null);
 const d=await list();assert.equal(d.summary.distance_tenths,'3');assert.equal(d.summary.trip_count,2);assert.equal(d.record_count,2);assert.deepEqual(d.vehicles,['Blue hatchback']);assert.equal(d.trips[0].request_data,undefined);assert.equal(d.trips[0].request_key,undefined);
 assert.equal((await db.query('select count(*)::int n from korlix_bookkeeping_entries where business_id=$1',[b.id])).rows[0].n,0);
});
test('authentication and owner boundaries protect every mileage route',async()=>{
 const t=await post();for(const [suffix,body] of [['?period=2027',null],['/export?period=2027',null],['',payload()],['/'+t.id+'/correct',payload({reason:'Changed'})],['/'+t.id+'/void',{request_key:randomUUID(),confirmed:true,reason:'Duplicate'}]]){await api(path(suffix),body,body?'POST':'GET',other,404);await api(path(suffix),body,body?'POST':'GET','invalid',401);}
});
test('concurrent same-key submissions create one trip; changed reuse conflicts',async()=>{
 const p=payload();const responses=await Promise.all(Array.from({length:5},()=>api(path(),p,'POST',owner,201)));assert.equal(new Set(responses.map(x=>x.trip.id)).size,1);assert.equal((await list()).record_count,1);await api(path(),{...p,miles:'12.4'},'POST',owner,409);
});
test('period boundaries, year totals, vehicle filters and pagination are consistent',async()=>{
 await post({trip_date:'2026-12-31'});await post({trip_date:'2027-01-01',vehicle:'Van',miles:'1.1'});await post({trip_date:'2027-02-01',vehicle:'Van',miles:'2.2'});await post({trip_date:'2027-12-31',miles:'3.3'});await post({trip_date:'2028-01-01'});
 assert.equal((await list()).summary.distance_tenths,'11');assert.equal((await list('2027')).summary.distance_tenths,'66');assert.equal((await list('2027','&vehicle=Van')).summary.distance_tenths,'33');assert.equal((await list('2027','&offset=1')).trips.length,2);assert.equal((await list('2027','&offset=1')).summary.distance_tenths,'66');
 for(let i=0;i<50;i++)await rpc('post',mileagePayload(payload({miles:'0.1'})));assert.equal((await list()).trips.length,50);assert.equal((await list('2027-01','&offset=50')).trips.length,1);
});
test('correction atomically excludes original, moves periods, preserves history and replays safely',async()=>{
 const t=await post();const p=payload({trip_date:'2027-02-01',method:'odometer',odometer_start:'50.1',odometer_end:'51.5',reason:'Correct the date and distance'});
 const result=await api(path('/'+t.id+'/correct'),p,'POST',owner,201);assert.equal(result.trip.correction_of,t.id);assert.equal(result.trip.distance_tenths,'14');
 const replay=await api(path('/'+t.id+'/correct'),p,'POST',owner,201);assert.equal(replay.trip.id,result.trip.id);
 const old=await list();assert.equal(old.summary.distance_tenths,'0');assert.equal(old.summary.excluded_count,1);assert.equal(old.trips[0].replacement_id,result.trip.id);assert.equal(old.trips[0].void_reason,p.reason);assert.equal((await list('2027-02')).summary.distance_tenths,'14');
 await api(path('/'+t.id+'/correct'),payload({reason:'Again'}),'POST',owner,409);
 const next=await api(path('/'+result.trip.id+'/correct'),payload({reason:'Second correction',miles:'1.7'}),'POST',owner,201);assert.equal(next.trip.correction_of,result.trip.id);assert.equal((await list('2027')).summary.distance_tenths,'17');
});
test('invalid correction rolls back everything and leaves original active',async()=>{
 const t=await post();const p=mileagePayload(payload({reason:'Bad replacement'}),{tripId:t.id});p.manual_tenths='0';await assert.rejects(rpc('correct',p));assert.equal((await list()).summary.distance_tenths,'123');assert.equal((await list()).record_count,1);assert.equal((await db.query('select count(*)::int n from korlix_bookkeeping_trip_voids where business_id=$1',[b.id])).rows[0].n,0);
});
test('void requires reason, preserves records and supports safe same-key retries',async()=>{
 const t=await post();const p={request_key:randomUUID(),confirmed:true,reason:'Duplicate trip'};await api(path('/'+t.id+'/void'),{...p,reason:''},'POST',owner,400);await api(path('/'+t.id+'/void'),{...p,confirmed:false},'POST',owner,400);
 const a=await api(path('/'+t.id+'/void'),p,'POST',owner,201);const z=await api(path('/'+t.id+'/void'),p,'POST',owner,201);assert.equal(a.void.id,z.void.id);assert.equal((await list()).summary.distance_tenths,'0');assert.equal((await list()).record_count,1);await api(path('/'+t.id+'/correct'),payload({reason:'Already voided'}),'POST',owner,409);
 await api(path('/'+t.id+'/void'),{...p,reason:'Changed'},'POST',owner,409);
});
test('cross-business correction and mismatched request actions are rejected',async()=>{
 const t=await post();const second=(await api('',{name:'Other fixture',legal_structure:'llc',tax_treatment:'unsure',contractor_income:false,request_key:randomUUID()},'POST',owner,201)).business;
 await assert.rejects(rpc('correct',mileagePayload(payload({reason:'Wrong business'}),{tripId:t.id}),owner,second.id),/Trip not found/);
 const p=payload();await api(path(),p,'POST',owner,201);await api(path('/'+t.id+'/correct'),{...p,reason:'Reused'},'POST',owner,409);
});
test('CSV identifies excluded history, exact included miles and neutralizes formula cells',async()=>{
 const t=await post({origin:'=HYPERLINK("bad")',vehicle:'@vehicle',miles:'0.1'});await api(path('/'+t.id+'/void'),{confirmed:true,request_key:randomUUID(),reason:'Duplicate'},'POST',owner,201);await post({miles:'0.2'});
 const d=await api(path('/export?period=2027'));assert.equal(d.count,2);assert.match(d.filename,/2027\.csv$/);assert(d.csv.includes('"\'=HYPERLINK(""bad"")"'));assert(d.csv.includes('"\'@vehicle"'));assert(d.csv.includes('"0.1","0.0","Voided — excluded"'));assert(d.csv.includes('"0.2","0.2","Included"'));assert(d.csv.startsWith('\uFEFF'));assert(d.csv.endsWith('\r\n'));
});
test('tables and view deny browser access and RPC execution',async()=>{
 await db.exec('reset role');try{for(const role of ['anon','authenticated']){await db.exec('set role '+role);for(const table of ['korlix_bookkeeping_trips','korlix_bookkeeping_trip_voids','korlix_bookkeeping_mileage_history'])await assert.rejects(db.query('select * from '+table),/permission denied/);await assert.rejects(rpc('list',{period:'2027'}),/permission denied/);await db.exec('reset role');}}finally{await db.exec('reset role;set role service_role');}
});
test('history is immutable and forged correction without paired exclusion is rejected',async()=>{
 const t=await post();await assert.rejects(db.query('update korlix_bookkeeping_trips set vehicle=$1 where id=$2',['changed',t.id]),/permission denied/);
 await db.exec('reset role');try{await assert.rejects(db.query('delete from korlix_bookkeeping_trips where id=$1',[t.id]),/immutable/);await assert.rejects(db.query(`insert into korlix_bookkeeping_trips(business_id,trip_date,vehicle,origin,destination,purpose,method,manual_tenths,correction_of,request_key,request_data,created_by) values($1,'2027-01-01','Car','A','B','Client meeting','miles',10,$2,$3,'{}',$4)`,[b.id,t.id,randomUUID(),owner]),/atomically/);}finally{await db.exec('set role service_role');}assert.equal((await list()).record_count,1);
});
test('oversized exports fail clearly instead of returning a partial year',async()=>{
 await db.query(`insert into korlix_bookkeeping_trips(business_id,trip_date,vehicle,origin,destination,purpose,method,manual_tenths,request_key,request_data,created_by) select $1,'2027-01-01','Fixture vehicle','A','B','Fixture trip','miles',1,gen_random_uuid(),'{}',$2 from generate_series(1,5001)`,[b.id,owner]);
 await api(path('/export?period=2027'),null,'GET',owner,422);assert.equal((await list('2027')).record_count,5001);
 const filtered=await api(path('/export?period=2027&vehicle=Unknown'));assert.equal(filtered.count,0);
});
