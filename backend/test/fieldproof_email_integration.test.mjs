import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID, createHash} from 'node:crypto';
import {readFile, readdir} from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import sharp from 'sharp';
import {registerFieldProof} from '../fieldproof/routes.mjs';
import {jobData} from '../fieldproof/model.mjs';
import {createFieldProofEmails, FIELDPROOF_EMAIL_DEFAULTS} from '../fieldproof/emails.mjs';

const pdf = Buffer.from('%PDF-1.7\nFieldProof integration fixture\n%%EOF');
const hash = x => createHash('sha256').update(x).digest('hex');
async function fixture(t) {
  const db = new PGlite();
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create table auth.users(id uuid primary key);
    create schema storage; create table storage.buckets(id text primary key,name text,public boolean,file_size_limit bigint,allowed_mime_types text[]);
    create table storage.objects(id text primary key,bucket_id text); alter table storage.objects enable row level security;
    create policy broad_legacy on storage.objects for all to anon,authenticated using(true) with check(true);
    grant usage on schema public,storage to anon,authenticated,service_role; grant all on storage.objects to anon,authenticated;
    create table public.usage_counters(id uuid primary key,user_id uuid references auth.users,credits_used int default 0,standard_generations int default 0,updated_at timestamptz);
    grant all on usage_counters to service_role;`);
  const dir = new URL('../../supabase/migrations/', import.meta.url), names = await readdir(dir);
  for (const suffix of ['_fieldproof.sql', '_fieldproof_workspace_upgrade.sql', '_fieldproof_autonomous_email.sql']) {
    const name = names.find(n => n.endsWith(suffix)); assert.ok(name, suffix);
    await db.exec(await readFile(new URL(name, dir), 'utf8'));
  }
  const owner = randomUUID(), other = randomUUID(), objects = new Map(), sends = [], users = new Map();
  for (const [id, email] of [[owner, 'owner@example.com'], [other, 'second-business@example.com']]) {
    await db.query('insert into auth.users values($1)', [id]);
    users.set(id, {id, email, email_confirmed_at: new Date().toISOString()});
  }
  await db.exec('set role service_role');
  const database = {
    from: () => ({select: () => ({eq: (_column, id) => ({maybeSingle: async () => ({data: users.has(id) ? {id, tier: 'enterprise', is_disabled: false} : null})})})}),
    auth: {admin: {getUserById: async id => ({data: {user: users.get(id)}})}},
    async rpc(name, p) {
      assert.ok(['korlix_fieldproof_v1', 'korlix_fieldproof_email_v1'].includes(name));
      try { return {data: (await db.query(`select public.${name}($1,$2,$3,$4) r`, [p.p_actor,p.p_action,p.p_id,p.p_data])).rows[0].r}; }
      catch (error) { if (process.env.FIELDPROOF_DEBUG) console.error(p.p_action,error.message,error.where); return {error}; }
    },
  };
  const storage = {storage: {from: bucket => ({
    async upload(path, bytes, options) {
      const key = bucket + '/' + path;
      if (!options.upsert && objects.has(key)) return {error: Error('existing immutable file')};
      objects.set(key, Buffer.from(bytes)); return {data: {path}};
    },
    async download(path) {const bytes = objects.get(bucket + '/' + path); return bytes ? {data: new Blob([bytes])} : {error: Error('missing file')};},
    async remove(paths) {for (const path of paths) objects.delete(bucket + '/' + path); return {data: []};},
    async createSignedUrls(paths) {return {data: paths.map(path => ({path,signedUrl: 'https://private.example/' + path + '?private-token'}))};},
  })}};
  const f = {db, owner, other, objects, sends, users, database, storage};
  const provider = {
    status: () => ({ready: true,senderFingerprint: hash('verified-server-sender')}),
    async send(payload) {sends.push(structuredClone(payload)); if (f.sendHook) return f.sendHook(payload); return {accepted: true,providerId: randomUUID()};},
  };
  const requireUser = async q => users.has(q.headers.authorization) ? users.get(q.headers.authorization) : null;
  const app = express(); app.use(express.json());
  registerFieldProof(app,{database,storageDatabase: storage,requireUser,aiAccess: async () => ({allowed:false}),logger:{warn(){}}});
  const mail = createFieldProofEmails({database,storageDatabase: storage,requireUser,provider,autoStart:false,publicRoot:'https://backend.example.com',logger:{warn(){}},
    renderer: async ({snapshot}) => ({subject:'Report: '+snapshot.job.data.title,text:'Saved completed work: '+snapshot.job.data.summary,html:'<html><body><p>Saved completed work</p></body></html>',attachments:[{filename:'FieldProof-job.pdf',content:pdf}]})});
  mail.register(app); f.mail = mail;
  const server = app.listen(0, '127.0.0.1'); await new Promise(r => server.once('listening',r));
  f.base = 'http://127.0.0.1:' + server.address().port + '/api/fieldproof';
  t.after(async () => {mail.stop(); await new Promise(r => server.close(r)); await db.close();});
  f.api = async (path='', {body, method=body?'POST':'GET', actor=owner, status=200}={}) => {
    const response=await fetch(f.base+path,{method,headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
    const result=await response.json(); assert.equal(response.status,status,JSON.stringify(result)); assert.equal(response.headers.get('cache-control'),'no-store'); return result;
  };
  f.settings = async (patch, actor=owner) => {
    const current=await f.api('/email',{actor}); const {version,...settings}=current.settings;
    return f.api('/email/settings',{method:'PUT',actor,body:{version,settings:{...settings,...patch},confirmed:true}});
  };
  f.create = async (actor=owner, recipient='customer@example.com', enabled=true) => {
    const d=jobData({title:'Meter service',customer:'Customer',site:'Recorded site',template:'general',technician:'Technician',performedOn:new Date().toISOString().slice(0,10),summary:'Meter replaced and reading recorded.'});
    d.checks=d.checks.map(c=>({...c,done:true}));
    let result=await f.api('/jobs',{actor,body:{request_key:randomUUID(),data:d},status:201});
    await f.api('/email/jobs/'+result.job.id,{actor,method:'PUT',body:{version:0,job_settings:{customer_email:recipient,enabled},confirmed:true}});
    const bytes=await sharp({create:{width:16,height:16,channels:3,background:'#446677'}}).jpeg().toBuffer();
    const form=new FormData();form.append('image',new Blob([bytes],{type:'image/jpeg'}),'after.jpg');
    for(const [k,v] of Object.entries({request_key:randomUUID(),version:result.job.version,tag:'after',name:'Completed work',note:''}))form.append(k,String(v));
    const upload=await fetch(f.base+'/jobs/'+result.job.id+'/photos',{method:'POST',headers:{Authorization:actor},body:form});result=await upload.json();assert.equal(upload.status,201,JSON.stringify(result));
    return result.job;
  };
  f.closeJob=async(job,actor=owner)=>f.api('/jobs/'+job.id+'/complete',{actor,body:{version:job.version,confirmed:true}});
  f.deliveryRows=async(actor=owner)=>(await db.query('select * from korlix_fieldproof_email_deliveries where owner_id=$1 order by created_at,id',[actor])).rows;
  return f;
}

test('real routes and queue default off; draft approval sends once with a private report', async t => {
  const f=await fixture(t);
  const initial=await f.api('/email');assert.equal(initial.settings.customer_mode,'off');assert.equal(initial.capabilities.reply_to,'owner@example.com');
  const offJob=await f.create();await f.closeJob(offJob);await f.mail.tick();assert.equal((await f.deliveryRows()).length,0);assert.equal(f.sends.length,0);
  await f.settings({business_name:'Example business',customer_mode:'draft',followup_mode:'draft',followup_days:3});
  const job=await f.create();await f.closeJob(job);await f.mail.tick();
  let rows=await f.deliveryRows();const report=rows.find(r=>r.kind==='customer_report');const followup=rows.find(r=>r.kind==='customer_followup');
  assert.equal(report.state,'draft');assert.equal(followup.state,'pending');assert.ok(Date.parse(followup.scheduled_at)>Date.now()+2*86400000);assert.equal(f.sends.length,0);
  const view=(await f.api('/email/deliveries/'+report.id)).delivery;
  assert.equal(view.can_approve,true);assert.equal(view.has_report,true);assert.ok(!JSON.stringify(view).includes('token='));assert.ok(!JSON.stringify(view).includes('attachment_path'));
  await f.api('/email/deliveries/'+report.id,{actor:f.other,status:404});
  const unauthorized=await fetch(f.base+'/email/deliveries/'+report.id+'/report',{headers:{Authorization:f.other}});assert.equal(unauthorized.status,404);
  const download=await fetch(f.base+'/email/deliveries/'+report.id+'/report',{headers:{Authorization:f.owner}});assert.equal(download.status,200);assert.deepEqual(Buffer.from(await download.arrayBuffer()),pdf);
  await f.api('/email/deliveries/'+report.id+'/approve',{body:{version:view.version,confirmed:true}});
  await f.mail.tick();await f.mail.tick();assert.equal(f.sends.length,1);assert.equal(f.sends[0].id,report.id);assert.equal(f.sends[0].to,'customer@example.com');assert.equal(f.sends[0].replyTo,'owner@example.com');
  rows=await f.deliveryRows();assert.equal(rows.find(r=>r.id===report.id).state,'accepted');
  assert.equal((await f.api('/email')).deliveries.find(r=>r.id===report.id).has_report,true);
});

test('two businesses stay separate; changing a recipient cancels a prepared report', async t => {
  const f=await fixture(t);
  await f.settings({customer_mode:'automatic'});
  await f.settings({customer_mode:'draft'},f.other);
  const first=await f.create(f.owner,'first-customer@example.com'),second=await f.create(f.other,'second-customer@example.com');
  await f.closeJob(first);await f.closeJob(second,f.other);await f.mail.tick();await f.mail.tick();
  assert.equal(f.sends.length,1);assert.equal(f.sends[0].to,'first-customer@example.com');assert.equal(f.sends[0].replyTo,'owner@example.com');
  const otherRow=(await f.deliveryRows(f.other))[0];assert.equal(otherRow.state,'draft');
  const state=await f.api('/email/jobs/'+second.id,{actor:f.other});
  await f.api('/email/jobs/'+second.id,{actor:f.other,method:'PUT',body:{version:state.job_settings.version,job_settings:{enabled:true,customer_email:'changed@example.com'},confirmed:true}});
  await f.api('/email/deliveries/'+otherRow.id+'/approve',{actor:f.other,body:{version:otherRow.version,confirmed:true},status:409});
  await f.mail.tick();assert.equal(f.sends.length,1);assert.equal((await f.deliveryRows(f.other))[0].state,'cancelled');
  assert.ok((await f.api('/email')).deliveries.every(d=>d.recipient!=='second-customer@example.com'));
});

test('real summary scheduling creates separate saved drafts for each supervisor, once per day', async t => {
  const f=await fixture(t), now=new Date();
  const localTime=now.toISOString().slice(11,16);
  await f.settings({supervisor_mode:'draft',supervisor_emails:['boss-a@example.com','boss-b@example.com'],summary_days:[0,1,2,3,4,5,6],timezone:'UTC',summary_time:localTime});
  // Model a rule saved before today's scheduled minute. Enabling a rule after
  // its due time deliberately does not backfill a message for that day.
  await f.db.query("update korlix_fieldproof_email_settings set updated_at=now()-interval '2 minutes' where owner_id=$1",[f.owner]);
  await f.mail.tick();await f.mail.tick();
  let rows=await f.deliveryRows();assert.equal(rows.length,2);assert.ok(rows.every(r=>r.kind==='supervisor_summary'&&r.state==='draft'));
  assert.deepEqual(new Set(rows.map(r=>r.recipient)),new Set(['boss-a@example.com','boss-b@example.com']));assert.equal(f.sends.length,0);
  for(const row of rows){const view=(await f.api('/email/deliveries/'+row.id)).delivery;assert.match(view.text,/previous local calendar day/i);assert.equal(view.has_report,false);}
  await f.mail.tick();rows=await f.deliveryRows();assert.equal(rows.length,2);
  // The actual settings DTO can be saved again without undocumented DB columns or time formats.
  await f.settings({business_name:'Renamed business'});
});

test('an older delivered email opt-out stops later queued reports for that same business only', async t => {
  const f=await fixture(t);await f.settings({customer_mode:'automatic'});
  for(let i=0;i<2;i++){const job=await f.create();await f.closeJob(job);await f.mail.tick();}
  assert.equal(f.sends.length,2);
  const token=new URL(f.sends[0].text.match(/https:\/\/backend\.example\.com\/api\/fieldproof\/email\/unsubscribe\?token=[A-Za-z0-9_-]+/)[0]).searchParams.get('token');
  const response=await fetch(f.base+'/email/unsubscribe',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({token})});assert.equal(response.status,200);
  const job=await f.create();await f.closeJob(job);await f.mail.tick();assert.equal(f.sends.length,2);
  const suppressed=(await f.db.query('select suppressed_at from korlix_fieldproof_email_recipients where owner_id=$1 and recipient=$2',[f.owner,'customer@example.com'])).rows[0];assert.ok(suppressed.suppressed_at);
  await f.settings({customer_mode:'automatic'},f.other);const otherJob=await f.create(f.other);await f.closeJob(otherJob,f.other);await f.mail.tick();assert.equal(f.sends.length,3);assert.equal(f.sends[2].replyTo,'second-business@example.com');
});

test('an uncertain provider outcome requires review and retries identical bytes with one daily reservation', async t => {
  const f=await fixture(t);await f.settings({customer_mode:'automatic'});
  f.sendHook=async()=>{if(f.sends.length===1)throw Object.assign(Error('response connection lost'),{outcome:'uncertain',code:'provider_response_unknown'});return {accepted:true,providerId:randomUUID()};};
  const job=await f.create();await f.closeJob(job);await f.mail.tick();
  let row=(await f.deliveryRows())[0];assert.equal(row.state,'unknown');assert.equal(f.sends.length,1);
  await f.mail.tick();assert.equal(f.sends.length,1,'An unknown outcome does not silently retry.');
  const view=(await f.api('/email/deliveries/'+row.id)).delivery;assert.equal(view.can_retry,true);
  await f.api('/email/deliveries/'+row.id+'/retry',{body:{version:view.version,confirmed:true}});await f.mail.tick();
  assert.equal(f.sends.length,2);assert.deepEqual(f.sends[1],f.sends[0]);row=(await f.deliveryRows())[0];assert.equal(row.state,'accepted');
  const usage=(await f.db.query('select sum(reserved)::int n from korlix_fieldproof_email_daily_usage where owner_id=$1',[f.owner])).rows[0];assert.equal(usage.n,1);
});

test('a signed-provider event before the send receipt preserves suppression after acceptance', async t => {
  const f=await fixture(t);await f.settings({customer_mode:'automatic'});
  f.sendHook=async payload=>{const providerId=randomUUID();await f.mail.suppressProviderEvent({providerId,deliveryId:payload.id,reason:'email.bounced'});return {accepted:true,providerId};};
  const job=await f.create();await f.closeJob(job);await f.mail.tick();
  const row=(await f.deliveryRows())[0];assert.equal(row.code,'bounced');assert.equal(f.sends.length,1);
  const recipient=(await f.db.query('select suppressed_at from korlix_fieldproof_email_recipients where owner_id=$1 and recipient=$2',[f.owner,'customer@example.com'])).rows[0];assert.ok(recipient.suppressed_at);
  const another=await f.create();await f.closeJob(another);await f.mail.tick();assert.equal(f.sends.length,1);
});
