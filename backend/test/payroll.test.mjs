import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID,randomBytes} from 'node:crypto';
import {PGlite} from '@electric-sql/pglite';
import express from 'express';
import {registerPayroll} from '../payroll/routes.mjs';
import {configuration,publicConfiguration,seal,unseal,safeFlowUrl,PayrollError} from '../payroll/core.mjs';
import {createGustoProvider} from '../payroll/provider.mjs';
const owner=randomUUID(),other=randomUUID(),basic=randomUUID(),disabled=randomUUID();
const key=randomBytes(32).toString('base64');
const env={PAYROLL_GUSTO_ENVIRONMENT:'demo',GUSTO_CLIENT_ID:'fixture',GUSTO_CLIENT_SECRET:'fixture-secret',PAYROLL_TOKEN_ENCRYPTION_KEY:key};
let db,server,base,companyCount=0,refreshCount=0,flowCount=0,complete=false,createFails=false,refreshFails=false,unauthorized=false;
const provider={
 systemToken:async()=>({access_token:'system-fixture'}),
 createCompany:async(_token,body)=>{companyCount++;assert.equal(body.user.email,owner+'@example.test');assert.deepEqual(Object.keys(body.company),['name']);if(createFails)throw new Error('secret provider body');return{company_uuid:randomUUID(),access_token:'access-fixture',refresh_token:'refresh-fixture',expires_in:7200};},
 refresh:async()=>{refreshCount++;if(refreshFails)throw new Error('secret refresh failure');return {access_token:'new-access-fixture',refresh_token:'new-refresh-fixture',expires_in:7200};},
 terms:async(_company,_token,body)=>{assert.equal(body.email,owner+'@example.test');assert.equal(body.external_user_id,owner);return{};},
 onboarding:async()=>{if(unauthorized){unauthorized=false;const e=new PayrollError('unauthorized',502);e.providerStatus=401;throw e;}return{onboarding_completed:complete,onboarding_steps:[{id:'add_bank_info',title:'Verify bank',completed:complete,required:true,ssn:'hidden'}],bank_account:'hidden'};},
 flow:async(_company,_token,body)=>{flowCount++;if(body.flow_type==='employee_management'){assert.equal(body.entity_type,'Company');assert.match(body.entity_uuid,/^[\da-f-]{36}$/);}return{url:'https://flows.gusto-demo.com/flows/fixture-session',access_token:'hidden'};},
};
const rpc=async(actor,action,account=null,data={})=>(await db.query('select korlix_payroll_v1($1,$2,$3,$4) r',[actor,action,account,data])).rows[0].r;
async function api(path='',body,actor=owner,status=200){const r=await fetch(base+'/api/payroll/workspaces'+path,{method:body?'POST':'GET',headers:{Authorization:actor,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});const result=await r.json();assert.equal(r.status,status,JSON.stringify(result));assert.equal(r.headers.get('cache-control'),'no-store');return result;}
async function workspace(actor=owner,paid=true){const business=randomUUID();await db.query('insert into korlix_bookkeeping_businesses values($1,$2,$3)',[business,actor,'Fixture US LLC']);const a=(await api('',{business_id:business,legal_name:'Fixture US LLC',country:'US',confirmed:true},actor,201)).account;if(paid)await activate(a);return a;}
async function activate(a){await db.query("insert into korlix_payroll_addons(account_id,state,access_starts_at,paid_through,billing_reference,billing_verified_at) values($1,'active',now()-interval '1 minute',now()+interval '30 days',$2,now()) on conflict(account_id) do update set state='active',access_starts_at=excluded.access_starts_at,paid_through=excluded.paid_through,billing_reference=excluded.billing_reference,billing_verified_at=excluded.billing_verified_at",[a.id,'test-invoice-'+randomUUID()]);}
async function connect(a){return api('/'+a.id+'/connect',{first_name:'Test',last_name:'Owner',confirmed:true,new_company:true},owner,201);}
async function ready(a){await connect(a);await api('/'+a.id+'/terms',{accepted:true});}
test.before(async()=>{
 db=new PGlite();await db.exec(`create role anon;create role authenticated;create role service_role bypassrls;create schema auth;create table auth.users(id uuid primary key);create table public.user_profiles(id uuid primary key,tier text,is_disabled boolean);create table public.korlix_bookkeeping_businesses(id uuid primary key,owner_id uuid references auth.users(id),name text);grant usage on schema public to anon,authenticated,service_role;grant select,insert,update on public.user_profiles,public.korlix_bookkeeping_businesses to service_role;`);
 for(const [u,t,d] of [[owner,'enterprise',false],[other,'enterprise',false],[basic,'basic',false],[disabled,'enterprise',true]]){await db.query('insert into auth.users values($1)',[u]);await db.query('insert into user_profiles values($1,$2,$3)',[u,t,d]);}
 await db.exec(await readFile(new URL('../../supabase/migrations/20260930132942_enterprise_us_payroll.sql',import.meta.url),'utf8'));await db.exec(await readFile(new URL('../../supabase/migrations/20260930141241_payroll_paid_addon.sql',import.meta.url),'utf8'));await db.exec('set role service_role');
 const app=express();app.use(express.json());registerPayroll(app,{database:{rpc:async(_,p)=>{try{return{data:await rpc(p.p_actor,p.p_action,p.p_account,p.p_data)}}catch(error){return{error}}}},requireUser:async q=>[owner,other,basic,disabled].includes(q.headers.authorization)?{id:q.headers.authorization,email:q.headers.authorization+'@example.test',email_confirmed_at:'2026-01-01'}:null,environment:env,provider});
 server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));base='http://127.0.0.1:'+server.address().port;
});
test.after(async()=>{server?.closeAllConnections();if(server)await new Promise(r=>server.close(r));await db?.close();});
test.beforeEach(()=>{complete=false;createFails=false;refreshFails=false;unauthorized=false;});
test('configuration fails closed; production needs explicit approval and secrets stay private',()=>{
 for(const input of [{},{...env,PAYROLL_GUSTO_ENVIRONMENT:'production'},{...env,PAYROLL_TOKEN_ENCRYPTION_KEY:'bad'},{...env,PAYROLL_GUSTO_ENVIRONMENT:'typo'}])assert.equal(configuration(input).ready,false);
 assert.equal(configuration({...env,PAYROLL_GUSTO_ENVIRONMENT:'production',PAYROLL_GUSTO_PRODUCTION_APPROVED:'true'}).ready,true);
 assert(!JSON.stringify(publicConfiguration(configuration(env))).includes('fixture-secret'));
});
test('token encryption authenticates account and environment; session URL allowlist blocks lookalikes',()=>{
 const value=seal({access_token:'secret'},key,'account1:demo');assert(!value.includes('secret'));assert.equal(unseal(value,key,'account1:demo').access_token,'secret');assert.throws(()=>unseal(value,key,'account2:demo'));assert.throws(()=>unseal(value,key,'account1:production'));
 for(const url of ['javascript:alert(1)','http://flows.gusto-demo.com/flows/x','https://flows.gusto-demo.com.evil.test/flows/x','https://evil@flows.gusto-demo.com/flows/x','https://flows.gusto.com/flows/x','https://flows.gusto-demo.com/other'])assert.throws(()=>safeFlowUrl(url,configuration(env)));
});
test('only active Enterprise owners can list, create, or reach any operation',async()=>{
 const a=await workspace();
 for(const actor of ['',basic,disabled]){await api('',null,actor,actor?403:401);for(const [path,body]of [['/'+a.id,null],['/'+a.id+'/connect',{confirmed:true}],['/'+a.id+'/terms',{accepted:true}],['/'+a.id+'/refresh',{}],['/'+a.id+'/flows',{flow_type:'run_payroll'}]])await api(path,body,actor,actor?403:401);}
 assert(!(await api('',null,other)).accounts.some(x=>x.id===a.id));
 for(const [path,body]of [['/'+a.id,null],['/'+a.id+'/connect',{first_name:'Other',last_name:'Owner',confirmed:true,new_company:true}],['/'+a.id+'/terms',{accepted:true}],['/'+a.id+'/refresh',{}],['/'+a.id+'/flows',{flow_type:'run_payroll'}]])await api(path,body,other,404);
 await assert.rejects(rpc(basic,'create',null,{business_id:a.business_id,legal_name:'Other',country:'US',confirmed:true}),/Enterprise/);
});
test('business ownership, US-only confirmation and idempotent workspace creation are enforced',async()=>{
 const a=await workspace();const body={business_id:a.business_id,legal_name:'Fixture US LLC',country:'US',confirmed:true};
 assert.equal((await api('',body,owner,201)).account.id,a.id);await api('',body,other,404);
 await api('',{...body,country:'CA'},owner,400);await api('',{...body,confirmed:false},owner,400);
 await assert.rejects(rpc(owner,'create',null,{...body,country:'CA'}),/US business/);
});
test('Enterprise membership alone never grants the business payroll add-on',async()=>{
 const a=await workspace(owner,false),before=[companyCount,refreshCount,flowCount];
 const details=await api('/'+a.id);assert.equal(details.account.addon.active,false);assert.equal(details.account.addon.status,'inactive');
 assert.equal(details.offer.pricing_status,'pending');assert.equal(details.offer.checkout_available,false);assert.equal(details.offer.base_price_cents,null);assert.equal(details.offer.per_employee_price_cents,null);
 for(const [path,body]of [['connect',{first_name:'Test',last_name:'Owner',confirmed:true,new_company:true,paid:true}],['terms',{accepted:true}],['refresh',{}],['flows',{flow_type:'company_onboarding'}]]){
  const result=await api('/'+a.id+'/'+path,body,owner,402);assert.equal(result.code,'PAYROLL_ADDON_REQUIRED');
 }
 for(const action of ['check_addon','begin_connection','lease','refresh_started','flow_opened'])await assert.rejects(rpc(owner,action,a.id,{paid:true,state:'active'}),e=>e.code==='P0402');
 assert.deepEqual([companyCount,refreshCount,flowCount],before);
 await activate(a);assert.equal((await api('/'+a.id)).account.addon.active,true);
 assert(!JSON.stringify(await api('/'+a.id)).includes('test-invoice'));
 const sameOwner=await workspace(owner,false),differentOwner=await workspace(other,false);
 assert.equal((await api('/'+sameOwner.id)).account.addon.active,false);
 assert.equal((await api('/'+differentOwner.id,null,other)).account.addon.active,false);
});
test('activation requests are explicit, isolated, idempotent and never create a paid entitlement',async()=>{
 const a=await workspace(owner,false),path='/'+a.id+'/activation-request';
 for(const body of [{confirmed:false,estimated_employees:5},{confirmed:true,estimated_employees:-1},{confirmed:true,estimated_employees:2.5},{confirmed:true,estimated_employees:'5'},{confirmed:true,estimated_employees:100001}])await api(path,body,owner,400);
 const body={confirmed:true,estimated_employees:7,state:'active',paid:true,billing_reference:'forged',paid_through:'2099-01-01'};
 await api(path,body,other,404);await api(path,body,basic,403);
 await Promise.all([api(path,body),api(path,body)]);
 let result=await api('/'+a.id);assert.equal(result.account.addon.active,false);assert.equal(result.account.addon.activation_request.estimated_employees,7);
 assert.equal((await db.query('select count(*)::int n from korlix_payroll_addons where account_id=$1',[a.id])).rows[0].n,0);
 assert.equal(result.audit.filter(x=>x.action==='payroll_addon_requested').length,1);
 await api(path,{confirmed:true,estimated_employees:99});assert.equal((await api('/'+a.id)).account.addon.activation_request.estimated_employees,7);
 await api(path+'/withdraw',{confirmed:false},owner,400);
 await api(path+'/withdraw',{confirmed:true});await api(path+'/withdraw',{confirmed:true});
 result=await api('/'+a.id);assert.equal(result.account.addon.activation_request.status,'withdrawn');assert.equal(result.audit.filter(x=>x.action==='payroll_addon_request_withdrawn').length,1);
 await api(path,{confirmed:true,estimated_employees:12});assert.equal((await api('/'+a.id)).account.addon.activation_request.estimated_employees,12);
 await activate(a);await api(path,body,owner,400);
});
test('billing states and time bounds stop new provider access while preserving workspace metadata',async()=>{
 const a=await workspace();await ready(a);const before=flowCount;
 for(const state of ['past_due','canceled','suspended','inactive']){
  await db.query('update korlix_payroll_addons set state=$2 where account_id=$1',[a.id,state]);
  assert.equal((await api('/'+a.id)).account.addon.active,false);await api('/'+a.id+'/flows',{flow_type:'company_onboarding'},owner,402);
 }
 await activate(a);await db.query("update korlix_payroll_addons set access_starts_at=now()-interval '31 days',billing_verified_at=now()-interval '31 days',paid_through=now()-interval '1 second' where account_id=$1",[a.id]);
 assert.equal((await api('/'+a.id)).account.addon.status,'expired');await api('/'+a.id+'/refresh',{},owner,402);
 await activate(a);await db.query("update korlix_payroll_addons set access_starts_at=now()+interval '1 day' where account_id=$1",[a.id]);
 assert.equal((await api('/'+a.id)).account.addon.status,'scheduled');await api('/'+a.id+'/flows',{flow_type:'company_onboarding'},owner,402);
 assert.equal(flowCount,before);
 for(const update of ["billing_reference=null","billing_verified_at=null","paid_through='infinity'","paid_through=now()+interval '365 days'"])
  await assert.rejects(db.query('update korlix_payroll_addons set '+update+' where account_id=$1',[a.id]),/check constraint/);
});
test('a cancellation during provider work prevents disclosure of its session URL',async()=>{
 const a=await workspace();await ready(a);const original=provider.flow;
 provider.flow=async(...args)=>{const response=await original(...args);await db.query("update korlix_payroll_addons set state='canceled' where account_id=$1",[a.id]);return response;};
 try{const result=await api('/'+a.id+'/flows',{flow_type:'company_onboarding'},owner,402);assert.equal(result.url,undefined);assert.equal((await db.query('select lease_id from korlix_payroll_accounts where id=$1',[a.id])).rows[0].lease_id,null);}finally{provider.flow=original;}
});
test('connection is single-creation and credentials never appear in public responses',async()=>{
 const a=await workspace(),before=companyCount;const results=await Promise.all([fetch(base+'/api/payroll/workspaces/'+a.id+'/connect',{method:'POST',headers:{Authorization:owner,'Content-Type':'application/json'},body:JSON.stringify({first_name:'Test',last_name:'Owner',confirmed:true,new_company:true})}),fetch(base+'/api/payroll/workspaces/'+a.id+'/connect',{method:'POST',headers:{Authorization:owner,'Content-Type':'application/json'},body:JSON.stringify({first_name:'Test',last_name:'Owner',confirmed:true,new_company:true})})]);
 assert.deepEqual(results.map(r=>r.status).sort(),[201,409]);assert.equal(companyCount,before+1);
 for(const result of [await api(),await api('/'+a.id)]){const text=JSON.stringify(result);for(const secret of ['access_token','refresh_token','sealed_tokens','admin_email','provider_company_id','lease_id'])assert(!text.includes(secret));}
 const stored=(await db.query('select sealed_tokens from korlix_payroll_accounts where id=$1',[a.id])).rows[0].sealed_tokens;assert(stored.startsWith('v1.'));assert(!stored.includes('access-fixture'));
});
test('ambiguous company creation stops automatic retries and exposes a review state',async()=>{
 const a=await workspace(),before=companyCount;createFails=true;await api('/'+a.id+'/connect',{first_name:'Test',last_name:'Owner',confirmed:true,new_company:true},owner,503);
 createFails=false;await connectError(a);assert.equal(companyCount,before+1);assert.equal((await api('/'+a.id)).account.status,'connection_review');
});
async function connectError(a){return api('/'+a.id+'/connect',{first_name:'Test',last_name:'Owner',confirmed:true,new_company:true},owner,409);}
test('explicit terms, completed onboarding and supported flow types gate secure payroll sessions',async()=>{
 const a=await workspace();await connect(a);
 await api('/'+a.id+'/flows',{flow_type:'run_payroll'},owner,409);await api('/'+a.id+'/terms',{accepted:false},owner,400);await api('/'+a.id+'/terms',{accepted:true});
 const before=flowCount;await api('/'+a.id+'/flows',{flow_type:'run_payroll'},owner,409);assert.equal(flowCount,before);
 await api('/'+a.id+'/flows',{flow_type:'run_payroll,company_recovery_cases'},owner,400);await api('/'+a.id+'/flows',{flow_type:'constructor'},owner,400);
 const employee=await api('/'+a.id+'/flows',{flow_type:'employee_management'});assert.equal(employee.environment,'demo');assert.equal(employee.access_token,undefined);
 complete=true;const flow=await api('/'+a.id+'/flows',{flow_type:'run_payroll'});assert.match(flow.url,/^https:\/\/flows.gusto-demo.com\/flows\//);
 const status=await api('/'+a.id+'/refresh',{});assert.equal(status.onboarding.onboarding_completed,true);assert.equal(status.onboarding.bank_account,undefined);assert.equal(status.onboarding.steps[0].ssn,undefined);
});
test('database lease serializes refreshes, stale leases cannot save and uncertain refresh requires review',async()=>{
 const a=await workspace();await ready(a);const lease=randomUUID();await rpc(owner,'lease',a.id,{lease_id:lease,environment:'demo'});
 await assert.rejects(rpc(owner,'lease',a.id,{lease_id:randomUUID(),environment:'demo'}),/in progress/);
 await assert.rejects(rpc(owner,'refresh_started',a.id,{lease_id:randomUUID()}),/session changed/);await rpc(owner,'release',a.id,{lease_id:lease});
 await db.query("update korlix_payroll_accounts set token_expires_at=now()-interval '1 minute' where id=$1",[a.id]);
 const before=refreshCount;await api('/'+a.id+'/refresh',{});assert.equal(refreshCount,before+1);
 unauthorized=true;await api('/'+a.id+'/refresh',{});assert.equal(refreshCount,before+2);
 await db.query("update korlix_payroll_accounts set token_expires_at=now()-interval '1 minute' where id=$1",[a.id]);refreshFails=true;await api('/'+a.id+'/refresh',{},owner,503);refreshFails=false;await api('/'+a.id+'/refresh',{},owner,409);assert.equal((await api('/'+a.id)).account.needs_attention,true);
});
test('tier downgrade revokes all workspace and provider access immediately',async()=>{
 const a=await workspace();await ready(a);await db.query("update user_profiles set tier='basic' where id=$1",[owner]);
 try{await api('/'+a.id,null,owner,403);await api('/'+a.id+'/flows',{flow_type:'company_onboarding'},owner,403);await assert.rejects(rpc(owner,'get',a.id),/Enterprise/);}finally{await db.query("update user_profiles set tier='enterprise' where id=$1",[owner]);}
});
test('browser roles cannot read payroll tables, secrets, or execute privileged functions',async()=>{
 await db.exec('reset role');try{for(const role of ['anon','authenticated']){await db.exec('set role '+role);for(const table of ['korlix_payroll_accounts','korlix_payroll_audit','korlix_payroll_limits','korlix_payroll_addons','korlix_payroll_activation_requests'])await assert.rejects(db.query('select * from '+table),/permission denied/);await assert.rejects(rpc(owner,'list'),/permission denied/);for(const fn of ['korlix_payroll_addon_active_v1','korlix_payroll_addon_public_v1'])await assert.rejects(db.query('select '+fn+'($1)',[randomUUID()]),/permission denied/);await assert.rejects(db.query("select nextval('korlix_payroll_audit_id_seq')"),/permission denied/);await db.exec('reset role');}
 const rows=(await db.query("select relrowsecurity from pg_class where relname in ('korlix_payroll_accounts','korlix_payroll_audit','korlix_payroll_limits','korlix_payroll_addons','korlix_payroll_activation_requests')")).rows;assert.equal(rows.length,5);assert(rows.every(x=>x.relrowsecurity));}finally{await db.exec('set role service_role');}
});
test('provider HTTP requests pin version and origins, prohibit redirects and redact errors',async()=>{
 let seen;const gusto=createGustoProvider(configuration(env),async(url,options)=>{seen={url,options};return new Response(JSON.stringify({access_token:'system-token'}),{status:200});});
 await gusto.systemToken();assert.equal(seen.url,'https://api.gusto-demo.com/oauth/token');assert.equal(seen.options.redirect,'error');assert.equal(seen.options.headers['X-Gusto-API-Version'],'2026-06-15');
 const broken=createGustoProvider(configuration(env),async()=>new Response('private bank account secret',{status:422}));await assert.rejects(broken.onboarding(randomUUID(),'secret'),e=>e instanceof PayrollError&&!e.message.includes('private'));
});
