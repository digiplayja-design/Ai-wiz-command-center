import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, readdir, rm, stat} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {applicationBackupConfig, sealPart, openPart, hash, SOURCE_PROJECT, MAX_PART} from '../application_backup/archive.mjs';
import {createApplicationBackupStore} from '../application_backup/store.mjs';
import {connectionConfig, readInventory, createPostgresBackupSource, APPLICATION_SCHEMAS} from '../application_backup/postgres.mjs';
import {runApplicationBackup, runApplicationProbe, recoveryConfiguration, releaseSources} from '../application_backup/runner.mjs';
import {extractApplicationBackup} from '../application_backup/recovery.mjs';
import {startApplicationBackupRuntime} from '../application_backup/runtime.mjs';
import {createReceiptBackupAlerts} from '../receipt_backup/alerts.mjs';

const recoveryKey = Buffer.alloc(32, 42);
const environment = () => ({KORLIX_BACKUP_MODE:'enabled', KORLIX_BACKUP_B2_KEY_ID:'synthetic_key_12345'.replaceAll('_',''),
  KORLIX_BACKUP_B2_APPLICATION_KEY:'synthetic_secret_12345678',RECEIPT_BACKUP_RECOVERY_KEY_BASE64:recoveryKey.toString('base64'),
  RECEIPT_BACKUP_RECOVERY_KEY_ESCROWED:'true',RECEIPT_BACKUP_RECOVERY_KEY_FINGERPRINT:hash(recoveryKey).slice(0,16),
  KORLIX_BACKUP_RETENTION_CONFIGURED:'true',KORLIX_BACKUP_PRIVACY_DISCLOSURE_READY:'true',
  KORLIX_BACKUP_DATABASE_URL:`postgresql://postgres.${SOURCE_PROJECT}:synthetic-password@aws-0-us-east-2.pooler.supabase.com:5432/postgres`,
  SUPABASE_URL:`https://${SOURCE_PROJECT}.supabase.co`,SUPABASE_SERVICE_ROLE_KEY:'synthetic-service-role',
  RENDER_GIT_COMMIT:'a'.repeat(40),KORLIX_ZOOM_TOKEN_ENCRYPTION_KEY:'synthetic-zoom-secret',LIVE_STUDIO_TOKEN_KEY:'never-export-youtube-key'});
const object = () => ({id:'b'.repeat(36),bucket_id:'korlix-fieldproof',name:'owner/job/evidence.jpg',owner_id:'owner',
  created_at:'2026-10-09T00:00:00.000Z',updated_at:'2026-10-09T00:00:00.000Z',version:'v1',metadata:{size:4},user_metadata:null,
  archived_at:null,is_delete_marker:false,is_versioned:false});
function memoryStore() {
  const files = new Map(), puts = [], deletes = [];
  return {files,puts,deletes,closed:false,async put(key,bytes){files.set(key,Buffer.from(bytes));puts.push(key);return {versionId:'synthetic-v1'};},
    async get(key){return files.has(key)?Buffer.from(files.get(key)):null;},async assertPrivate(){},
    async deleteProbe(key,version){deletes.push([key,version]);files.delete(key);},close(){this.closed=true;}};
}
function sourceFixture({changed=false,failDump=false}={}) {
  const inventory={buckets:[{id:'korlix-fieldproof',public:false}],objects:[object()],sourceBytes:4};
  return {closed:false,downloads:0,dumps:0,async begin(){return {inventory,capturedAt:'2026-10-09T01:00:00.000Z',
    recoveryControls:{account_deletion_requests:[{id:'deleted-fixture',status:'requested'}],activeProfileInventory:[{id:'owner',is_disabled:false}]},
    databaseMetadata:{includedSchemas:APPLICATION_SCHEMAS,excludedTableData:['public.korlix_live_studio_*']}};},
    async download(){this.downloads++;return Buffer.from('file');},async dump(){this.dumps++;if(failDump)throw Error('sensitive-provider-error');return Buffer.from('PGDMP-synthetic');},
    async unchanged(){return !changed;},async close(){this.closed=true;}};
}
const codeFixture = async () => [{component:'backend',commit:'a'.repeat(40),bytes:Buffer.from([31,139,1,2])}];
const clock=()=>new Date('2026-10-09T01:00:00.000Z');
const quiet={info(){},error(){}};

test('configuration requires separate credentials, escrow, retention and disclosure; default is off',()=>{
  assert.deepEqual(applicationBackupConfig({}),{mode:'off'});
  for(const key of ['KORLIX_BACKUP_B2_KEY_ID','KORLIX_BACKUP_B2_APPLICATION_KEY','RECEIPT_BACKUP_RECOVERY_KEY_BASE64',
    'RECEIPT_BACKUP_RECOVERY_KEY_ESCROWED','RECEIPT_BACKUP_RECOVERY_KEY_FINGERPRINT','KORLIX_BACKUP_RETENTION_CONFIGURED','KORLIX_BACKUP_PRIVACY_DISCLOSURE_READY']) {
    assert.throws(()=>applicationBackupConfig({...environment(),[key]:''}));
  }
  const cfg=applicationBackupConfig(environment());assert.equal(cfg.prefix,'application/');assert(!cfg.key.equals(recoveryKey));
  assert.deepEqual(cfg.key,applicationBackupConfig(environment()).key);
});
test('archive encrypts metadata and content, authenticates scope, key, kind and integrity',()=>{
  const cfg=applicationBackupConfig(environment()),bytes=Buffer.from('private evidence');
  const a=sealPart(cfg,'object','owner-123',{name:'private-filename.jpg'},bytes);
  assert(!a.includes(bytes));assert(!a.includes(Buffer.from('private-filename.jpg')));
  assert.deepEqual(openPart(cfg,'object','owner-123',a).bytes,bytes);
  assert.throws(()=>openPart(cfg,'object','owner-456',a));assert.throws(()=>openPart(cfg,'database','owner-123',a));
  assert.throws(()=>openPart({...cfg,key:Buffer.alloc(32,1)},'object','owner-123',a));
  for(const index of [0,10,25,a.length-1]){const broken=Buffer.from(a);broken[index]^=1;assert.throws(()=>openPart(cfg,'object','owner-123',broken));}
});
test('database connection pins project and region, rejects TLS downgrades and URL injection',()=>{
  const cfg=connectionConfig(environment());assert.equal(cfg.ssl.rejectUnauthorized,true);
  const u=environment().KORLIX_BACKUP_DATABASE_URL;
  for(const bad of [u.replace(SOURCE_PROJECT,'anotherproject'),u.replace('us-east-2','us-west-1'),u.replace('5432','6543'),
    u+'?sslmode=disable',u+'?options=-c%20statement_timeout=0',u.replace('postgresql:','https:'),u+'#bad']) {
    assert.throws(()=>connectionConfig({...environment(),KORLIX_BACKUP_DATABASE_URL:bad}));
  }
  assert.throws(()=>connectionConfig({}));
});
test('inventory refuses unreviewed/public buckets, path traversal, oversized and versioned files',async()=>{
  async function load(o=object(),b={id:'korlix-fieldproof',public:false}) {
    return readInventory({query:async sql=>({rows:sql.includes('storage.buckets')?[b]:[o]})});
  }
  assert.equal((await load()).sourceBytes,4);
  await assert.rejects(load(object(),{id:'unreviewed',public:false}));
  await assert.rejects(load(object(),{id:'korlix-fieldproof',public:true}));
  for(const change of [{name:'../secret'},{name:'a//b'},{metadata:{size:65*1024*1024}},{is_versioned:true},{is_delete_marker:true}]) {
    await assert.rejects(load({...object(),...change}));
  }
});
test('B2 adapter confines access to application and allows deletion only of exact synthetic versions',async()=>{
  const cfg=applicationBackupConfig(environment()),commands=[];
  const store=createApplicationBackupStore(cfg,{client:{async send(c){commands.push(c);return {VersionId:'v'};},destroy(){}}});
  await assert.rejects(store.put('receipts/data.enc',Buffer.from('x')));
  await assert.rejects(store.put('application/../data.enc',Buffer.from('x')));
  await assert.rejects(store.deleteProbe('application/v1/customer.enc','v'));
  await assert.rejects(store.deleteProbe('application/_probe/11111111-1111-1111-1111-111111111111.enc',''));
  await store.put('application/v1/test.enc',Buffer.from('x'));
  assert.equal(commands[0].input.ServerSideEncryption,'AES256');assert.equal(commands[0].input.Bucket,'korlix-backups');
});
test('probe verifies encryption, private access, corruption and binding, then removes only its own object',async()=>{
  const cfg=applicationBackupConfig(environment()),store=memoryStore();
  const result=await runApplicationProbe({store,config:cfg});assert.equal(result.status,'passed');
  assert.equal(store.files.size,0);assert.equal(store.deletes.length,1);assert.match(store.deletes[0][0],/^application\/_probe\//);
});
test('complete database/file snapshot can be decrypted and extracted in an isolated directory',async()=>{
  const env=environment(),cfg=applicationBackupConfig(env),store=memoryStore(),source=sourceFixture();
  const result=await runApplicationBackup({source,store,config:cfg,env,now:clock,sourceCodeProvider:codeFixture});
  assert.equal(result.databaseIncluded,true);assert.equal(result.objectCount,1);assert.equal(result.verified,6);assert(source.closed);
  const temp=await mkdtemp(join(tmpdir(),'korlix-recovery-test-')),output=join(temp,'isolated');
  try {
    const restored=await extractApplicationBackup({store,config:cfg,catalogKey:result.catalogKey,output,expectedProject:SOURCE_PROJECT,acknowledgeIsolatedRecovery:true});
    assert.equal(restored.verifiedParts,5);assert.equal(restored.productionModified,false);
    const manifest=JSON.parse(await readFile(join(output,'recovery-manifest.json'),'utf8'));
    const file=manifest.parts.find(p=>p.kind==='object');assert.equal(await readFile(join(output,file.filename),'utf8'),'file');
    assert.equal((await stat(output)).mode&0o777,0o700);assert.equal((await stat(join(output,file.filename))).mode&0o777,0o600);
    const conf=manifest.parts.find(p=>p.kind==='configuration'),settings=JSON.parse(await readFile(join(output,conf.filename),'utf8'));
    assert.equal(settings.encryptionKeys.KORLIX_ZOOM_TOKEN_ENCRYPTION_KEY,'synthetic-zoom-secret');
    assert(!JSON.stringify(settings).includes('synthetic-password'));assert(!JSON.stringify(settings).includes('never-export-youtube-key'));
    await assert.rejects(extractApplicationBackup({store,config:cfg,catalogKey:result.catalogKey,output,expectedProject:SOURCE_PROJECT,acknowledgeIsolatedRecovery:true}));
    assert.equal(await readFile(join(output,file.filename),'utf8'),'file');
  } finally {await rm(temp,{recursive:true,force:true});}
});
test('same-day object versions are verified and reused; next day creates fresh copies for lifecycle retention',async()=>{
  const cfg=applicationBackupConfig(environment()),store=memoryStore();
  for(let i=0;i<2;i++) {
    const source=sourceFixture();const r=await runApplicationBackup({source,store,config:cfg,includeDatabase:false,now:clock});
    assert.equal(r.reused,i);assert.equal(source.downloads,1-i);assert.equal(source.dumps,0);
  }
  const source=sourceFixture();const r=await runApplicationBackup({source,store,config:cfg,includeDatabase:false,
    now:()=>new Date('2026-10-10T01:00:00Z')});assert.equal(r.reused,0);assert.equal(source.downloads,1);
});
test('changes during capture or failed database dump never publish a complete catalog',async()=>{
  for(const options of [{changed:true},{failDump:true}]) {
    const cfg=applicationBackupConfig(environment()),store=memoryStore(),source=sourceFixture(options);
    await assert.rejects(runApplicationBackup({source,store,config:cfg,env:environment(),now:clock,sourceCodeProvider:codeFixture}));
    assert(!store.puts.some(k=>k.includes('/catalogs/')));assert(source.closed);
  }
});
test('corrupt readback and corrupt reused archives stop completion',async()=>{
  const cfg=applicationBackupConfig(environment()),store=memoryStore();
  await runApplicationBackup({source:sourceFixture(),store,config:cfg,includeDatabase:false,now:clock});
  const key=[...store.files.keys()].find(k=>k.includes('/objects/'));store.files.get(key)[30]^=1;
  await assert.rejects(runApplicationBackup({source:sourceFixture(),store,config:cfg,includeDatabase:false,now:clock}));
  const badStore=memoryStore(),get=badStore.get.bind(badStore);badStore.get=async k=>{const b=await get(k);if(b)b[30]^=1;return b;};
  await assert.rejects(runApplicationBackup({source:sourceFixture(),store:badStore,config:cfg,includeDatabase:false,now:clock}));
});
test('recovery denies wrong project and removes partial output after corruption',async()=>{
  const cfg=applicationBackupConfig(environment()),store=memoryStore();
  const result=await runApplicationBackup({source:sourceFixture(),store,config:cfg,includeDatabase:false,now:clock});
  const temp=await mkdtemp(join(tmpdir(),'korlix-recovery-corrupt-')),output=join(temp,'isolated');
  try {
    await assert.rejects(extractApplicationBackup({store,config:cfg,catalogKey:result.catalogKey,output,expectedProject:'other',acknowledgeIsolatedRecovery:true}));
    const key=[...store.files.keys()].find(k=>k.includes('/objects/'));store.files.get(key)[30]^=1;
    await assert.rejects(extractApplicationBackup({store,config:cfg,catalogKey:result.catalogKey,output,expectedProject:SOURCE_PROJECT,acknowledgeIsolatedRecovery:true}));
    assert.deepEqual(await readdir(temp),[]);
  } finally {await rm(temp,{recursive:true,force:true});}
});
test('source-code backup pins repository and commits and refuses unexpected refs',async()=>{
  const urls=[];
  const mock=async url=>{urls.push(url);return url.includes('api.github.com')?new Response(JSON.stringify({ref:'refs/heads/release/k135z-frontend-20260919',object:{sha:'b'.repeat(40)}})):
    new Response(Buffer.from([31,139,1,2]));};
  const sources=await releaseSources(environment(),undefined,mock);assert.equal(sources.length,2);
  assert(urls[1].endsWith('/'+'a'.repeat(40)));assert(urls[2].endsWith('/'+'b'.repeat(40)));
  await assert.rejects(releaseSources(environment(),undefined,async()=>new Response(JSON.stringify({ref:'refs/heads/other',object:{sha:'b'.repeat(40)}}))));
});
test('recovery configuration excludes master/backup keys, provider credentials and YouTube encryption material',()=>{
  const env=environment(),settings=recoveryConfiguration(env),text=JSON.stringify(settings);
  for(const v of [env.RECEIPT_BACKUP_RECOVERY_KEY_BASE64,env.KORLIX_BACKUP_B2_APPLICATION_KEY,env.SUPABASE_SERVICE_ROLE_KEY,env.LIVE_STUDIO_TOKEN_KEY]) assert(!text.includes(v));
  assert(text.includes('synthetic-zoom-secret'));
});
test('runtime keeps existing deployment inert until enabled and schedules hourly files/daily database',async()=>{
  let touched=false;startApplicationBackupRuntime({env:{},storeFactory(){touched=true;}});assert.equal(touched,false);
  const queue=[],runs=[],store=memoryStore();let date=clock();
  const runtime=startApplicationBackupRuntime({env:environment(),logger:quiet,now:()=>date,
    timers:{setTimeout(fn,ms){queue.push({fn,ms});return {unref(){}};},clearTimeout(){}},storeFactory:()=>store,sourceFactory:()=>({}),
    alertsFactory:()=>({failure:async()=>{}}),probe:async()=>({status:'passed'}),run:async args=>{runs.push(args.includeDatabase);return {completedAt:date.toISOString()};}});
  assert.equal(queue[0].ms,60000);await queue.shift().fn();assert.equal(queue[0].ms,3600000);
  await queue.shift().fn();date=new Date('2026-10-10T00:01:00Z');await queue.shift().fn();
  assert.deepEqual(runs,[true,false,true]);runtime.stop();assert(store.closed);
});
test('runtime retries failures and keeps failure notifications free of provider secrets',async()=>{
  const queue=[],logs=[],alerts=[];
  const runtime=startApplicationBackupRuntime({env:environment(),logger:{info:v=>logs.push(v),error:v=>logs.push(v)},
    timers:{setTimeout(fn,ms){queue.push({fn,ms});return {unref(){}};},clearTimeout(){}},storeFactory:()=>memoryStore(),sourceFactory:()=>({}),
    alertsFactory:()=>({failure:async e=>alerts.push(e)}),probe:async()=>({status:'passed'}),run:async()=>{throw Error('SECRET_PASSWORD');}});
  await queue.shift().fn();assert.equal(queue[0].ms,900000);assert.equal(alerts.length,1);assert(!logs.join('').includes('SECRET_PASSWORD'));runtime.stop();
});
test('application alert has a separate deduplication key and cannot trigger the receipt test',async()=>{
  const requests=[];
  const alerts=createReceiptBackupAlerts({scope:'application',env:{RECEIPT_BACKUP_ALERT_EMAIL:'support@korlixdeveloper.com',
    KORLIX_SUPPORT_FROM_EMAIL:'support@korlixdeveloper.com',RESEND_API_KEY:'re_synthetic_key_123456'},logger:quiet,now:clock,
    fetchImpl:async(u,o)=>{requests.push(o);return new Response(JSON.stringify({id:'11111111-1111-1111-1111-111111111111'}),{status:200});}});
  await alerts.failure({code:'BACKUP_APP_SOURCE_CHANGED_RETRY'});await alerts.failure({code:'BACKUP_APP_SOURCE_CHANGED_RETRY'});
  assert.equal(requests.length,1);assert(requests[0].headers['Idempotency-Key'].startsWith('korlix-application-backup/'));
  assert.equal(JSON.parse(requests[0].body).subject,'[KORLIX] Application backup needs attention');assert.equal((await alerts.test()).skipped,true);
});
test('Postgres export uses one read-only snapshot, covers private/auth schemas, and keeps password out of arguments',async()=>{
  const queries=[],processes=[];let ended=false;
  class Client {
    on(){} async connect(){} async end(){ended=true;}
    async query(sql){
      queries.push(sql);
      if(sql.includes('pg_export_snapshot'))return {rows:[{version:170011,snapshot:'00000003-0000001B-1',captured_at:clock(),vault_secrets:0}]};
      if(sql.includes('pg_namespace'))return {rows:[...APPLICATION_SCHEMAS,'extensions','vault'].map(nspname=>({nspname}))};
      if(sql.includes('storage.buckets'))return {rows:[{id:'korlix-fieldproof',public:false}]};
      if(sql.includes('storage.objects'))return {rows:[object()]};
      return {rows:[]};
    }
  }
  const source=createPostgresBackupSource({env:environment(),Client,processRunner:async(command,args,options)=>{
    processes.push({command,args,env:options.env});
    return Buffer.from(command==='pg_dump'?(args.includes('--version')?'pg_dump (PostgreSQL) 17.11':'PGDMP-fixture'):'');
  }});
  try {
    const snapshot=await source.begin();assert.equal(snapshot.databaseMetadata.includedSchemas.includes('auth'),true);
    assert(snapshot.recoveryControls.account_deletion_requests);await source.dump();
    const dump=processes.find(p=>p.command==='pg_dump'&&!p.args.includes('--version'));
    assert(dump.args.includes('--snapshot=00000003-0000001B-1'));assert(dump.args.includes('--schema=k135z_b5b_private'));
    assert(dump.args.includes('--schema=storage'));assert(dump.args.includes('--exclude-table-data=public.korlix_live_studio_*'));
    assert.equal(dump.env.PGSSLMODE,'verify-full');assert.equal(dump.env.PGPASSWORD,'synthetic-password');
    assert(!JSON.stringify(dump.args).includes('synthetic-password'));
    assert.equal(processes.filter(p=>p.command==='pg_restore').length,2);
    assert.equal(await source.unchanged(snapshot.inventory),true);
    assert.equal(queries.filter(q=>q==='begin isolation level repeatable read read only').length,2);
    assert(queries.includes('commit'));assert(!queries.some(q=>/\b(insert|update|delete|alter|create|drop)\b/i.test(q)));
  } finally {await source.close();}assert(ended);
});
test('a newly used Supabase Vault stops export until its separate root-key custody is resolved',async()=>{
  let toolsCalled=false;
  class Client {on(){}async connect(){}async end(){}async query(sql){return {rows:sql.includes('pg_export_snapshot')?
    [{version:170011,snapshot:'00000003-0000001B-1',captured_at:clock(),vault_secrets:1}]:[]};}}
  const source=createPostgresBackupSource({env:environment(),Client,processRunner:async()=>{toolsCalled=true;}});
  try {await assert.rejects(source.begin(),{code:'BACKUP_APP_VAULT_KEY_ESCROW_REQUIRED'});assert.equal(toolsCalled,false);}
  finally {await source.close();}
});
