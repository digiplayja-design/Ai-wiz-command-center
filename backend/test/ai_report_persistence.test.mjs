import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import {persistAiReport, listAiReports, markAiReportNotification} from '../security/ai_report_persistence.mjs';

const userId='10000000-0000-4000-8000-000000000001';
const reportId='korlix_report_20000000-0000-4000-8000-000000000001';
const report={id:reportId,reportId,userId,userEmail:'synthetic@example.invalid',details:'Synthetic report only.',createdAt:'2026-10-07T20:00:00Z'};
const migration=new URL('../../supabase/migrations/20261007214516_durable_ai_report_queue.sql',import.meta.url);

// A fresh client has no local report collection; results come from the database.
function adapter(db) {
  return {from(name) {
    assert.equal(name,'korlix_ai_output_reports');
    const q={kind:null,args:null,limitValue:25,filter:null,
      insert(row){this.kind='insert';this.args=row;return this;},
      update(row){this.kind='update';this.args=row;return this;},
      select(){this.kind='select';return this;},order(){return this;},
      eq(key,value){assert.equal(key,'id');this.filter=value;return this;},
      limit(value){this.limitValue=value;return this;},
      async abortSignal(signal){
        assert(signal instanceof AbortSignal);
        try {
          if(this.kind==='insert') {
            const r=this.args;
            await db.query('insert into public.korlix_ai_output_reports(id,user_id,report,created_at) values($1,$2,$3,$4)',[r.id,r.user_id,r.report,r.created_at]);
            return {error:null};
          }
          if(this.kind==='update') {
            await db.query('update public.korlix_ai_output_reports set notification_state=$1 where id=$2',[this.args.notification_state,this.filter]);
            return {error:null};
          }
          const data=(await db.query('select report,state,notification_state,created_at,resolved_at from public.korlix_ai_output_reports order by created_at desc,id desc limit $1',[this.limitValue])).rows;
          const count=(await db.query('select count(*)::int n from public.korlix_ai_output_reports')).rows[0].n;
          return {data,count,error:null};
        } catch(error) { return {error}; }
      }};
    return q;
  }};
}

test('durable AI report migration protects browser roles and survives fresh clients',async t=>{
  const db=new PGlite();
  try {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
      create schema auth; create table auth.users(id uuid primary key);
      grant usage on schema public,auth to anon,authenticated,service_role;
      insert into auth.users values('${userId}');`);
    await db.exec(await readFile(migration,'utf8'));
    await t.test('acknowledged data survives client/process state loss, including failed notification',async()=>{
      await db.exec('set role service_role');
      await persistAiReport(adapter(db),report);
      await markAiReportNotification(adapter(db),report.id,false);
      const result=await listAiReports(adapter(db));
      assert.equal(result.reportCount,1);assert.equal(result.reports[0].details,report.details);
      assert.equal(result.reports[0].notificationState,'failed');assert.equal(result.reports[0].reviewState,'open');
      assert.equal(await markAiReportNotification(adapter(db),report.id,true),true);
      assert.equal((await listAiReports(adapter(db))).reports[0].notificationState,'delivered');
      await db.exec('reset role');
    });
    await t.test('anon and authenticated cannot read, forge, relabel or delete reports',async()=>{
      for(const role of ['anon','authenticated']) {
        await db.exec('set role '+role);
        for(const sql of ['select * from public.korlix_ai_output_reports',
          `insert into public.korlix_ai_output_reports(id,user_id,report) values('forged','${userId}','{}')`,
          "update public.korlix_ai_output_reports set state='resolved',resolved_at=now()",
          'delete from public.korlix_ai_output_reports']) await assert.rejects(db.query(sql),e=>e.code==='42501');
        await db.exec('reset role');
      }
      assert.equal((await db.query("select relrowsecurity enabled from pg_class where oid='public.korlix_ai_output_reports'::regclass")).rows[0].enabled,true);
    });
    await t.test('database rejects malformed, oversized, mismatched and contradictory records',async()=>{
      const id='korlix_report_20000000-0000-4000-8000-000000000002';
      for(const payload of [{},{...report,id,userId:null},{...report,id,userId:'20000000-0000-4000-8000-000000000001'},
        {...report,id,details:'x'.repeat(50000)}]) {
        await assert.rejects(db.query('insert into public.korlix_ai_output_reports(id,user_id,report) values($1,$2,$3)',[id,userId,payload]),e=>e.code==='23514');
      }
      await assert.rejects(db.query("update public.korlix_ai_output_reports set state='resolved'"),e=>e.code==='23514');
    });
    await t.test('account deletion cascade includes this private report payload',async()=>{
      await db.query('delete from auth.users where id=$1',[userId]);
      assert.equal((await listAiReports(adapter(db))).reportCount,0);
    });
  } finally {await db.close();}
});

test('missing database and database failures fail closed without exposing diagnostics',async()=>{
  const failDb={from(){throw new Error('secret credential and customer payload');}};
  for(const database of [null,failDb]) {
    for(const action of [()=>persistAiReport(database,report),()=>listAiReports(database)]) {
      await assert.rejects(action,e=>e.statusCode===503 && !e.message.includes('secret'));
    }
    assert.equal(await markAiReportNotification(database,report.id,false),false);
  }
});

test('review limit remains bounded and returned database errors fail closed',async()=>{
  const limits=[];
  const database={from(){return {select(){return this;},order(){return this;},limit(v){limits.push(v);return this;},
    async abortSignal(){return {data:[],error:null,count:0};}};}};
  for(const limit of [500,0,Number.NaN]) await listAiReports(database,limit);
  assert.deepEqual(limits,[100,1,25]);
  const fail={from(){return {insert(){return this;},async abortSignal(){return {error:{message:'private SQL details'}};}};}};
  await assert.rejects(()=>persistAiReport(fail,report),e=>e.statusCode===503 && !e.message.includes('SQL'));
});
