import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import crypto from 'node:crypto';
import vm from 'node:vm';
import {PGlite} from '@electric-sql/pglite';
import {createReceiptAppSessions, requestsReceiptApp, receiptAppRouteAllowed, messengerAppRouteAllowed} from '../security/receipt_app_sessions.mjs';
import {authenticatedDeveloperUser, hasUnlimitedAccess, UNLIMITED_COMPATIBILITY_LIMIT} from '../security/developer_access.mjs';
import {createKorlixSignupHandler, KORLIX_SIGNUP_POLICY_VERSION} from '../korlix_signup_eligibility.mjs';

const source = readFileSync(new URL('../server.js', import.meta.url), 'utf8');
const part = (start, end) => {
  const begin = source.indexOf(start), finish = source.indexOf(end, begin);
  assert(begin >= 0 && finish > begin);
  return source.slice(begin, finish);
};
const sourceUnderTest = part('function getRequestDeviceInfo(', 'async function getOrCreateProfile(')
  + part('app.post("/api/auth/signin"', 'app.get("/api/supabase-diagnostics"')
  + part('app.post("/api/auth/refresh"', 'app.post("/api/characters/select"')
  + part('app.post("/api/auth/signout"', 'app.get("/api/video-credits"');
const migration = readFileSync(new URL('../../supabase/migrations/20261024165108_receipt_wiz_app_sessions.sql', import.meta.url), 'utf8');
let db, userId, otherId, database, context, handlers, tokens, refreshes, revoked, writes, unavailable, revokeRace;

const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
function issue(uid = userId, sid = crypto.randomUUID()) {
  const access_token = `${encode({alg: 'fixture'})}.${encode({sub: uid, session_id: sid, exp: Math.floor(Date.now()/1000)+3600})}.${crypto.randomUUID()}`;
  const refresh_token = crypto.randomUUID();
  tokens.set(access_token, {uid, sid}); refreshes.set(refresh_token, {uid, sid});
  return {access_token, refresh_token};
}
const response = () => ({statusCode: 200, status(code) {this.statusCode = code; return this;}, json(body) {this.body = body; return this;}});
const user = uid => ({id: uid, email: `${uid}@example.test`, user_metadata: {client_app: 'korlix_ai', developer_unlimited: true}});
function request({session, device = 'receipt-phone', app = 'receipt_wiz', path = '/api/receipt-wiz', method = 'GET', body = {}} = {}) {
  return {method, originalUrl: path, headers: {
    ...(session ? {authorization: `Bearer ${session.access_token}`} : {}),
    ...(device ? {'x-korlix-device-id': device} : {}),
    ...(app ? {'x-korlix-app': app} : {}),
  }, body};
}
async function login({device = 'receipt-phone', app = 'receipt_wiz', uid = userId} = {}) {
  const req = request({device, app, path: '/api/auth/signin', method: 'POST', body: {
    email: `${uid}@example.test`, password: 'fixture-password', ...(app ? {client_app: app} : {}),
  }}), res = response();
  await handlers.get('/api/auth/signin')(req, res);
  return res;
}
async function refresh(session, changes = {}) {
  const req = request({session, method: 'POST', path: '/api/auth/refresh', body: {refresh_token: session.refresh_token}, ...changes}), res = response();
  await handlers.get('/api/auth/refresh')(req, res);
  return res;
}
async function signout(session, changes = {}) {
  const req = request({session, method: 'POST', path: '/api/auth/signout', ...changes}), res = response();
  await handlers.get('/api/auth/signout')(req, res);
  return res;
}
async function rows(table) {return (await db.query(`select * from ${table}`)).rows;}

test.before(async () => {
  db = new PGlite();
  await db.exec(`create role anon; create role authenticated; create role service_role bypassrls;
    create schema auth; create table auth.users(id uuid primary key);
    create table public.user_profiles(id uuid primary key references auth.users, tier text not null default 'basic', is_disabled boolean not null default false, max_devices_override integer);
    create table public.korlix_developer_access(user_id uuid primary key, enabled boolean not null default false);
    create table public.device_sessions(id uuid primary key default gen_random_uuid(), user_id uuid not null, device_id text not null,
      device_label text, platform text, status text, last_seen_at timestamptz, revoked_at timestamptz, unique(user_id,device_id));
    grant usage on schema public to anon,authenticated,service_role;
    grant select on user_profiles,korlix_developer_access to service_role;
    grant select,insert,update on device_sessions to service_role;`);
  await db.exec(migration);
  await db.exec(readFileSync(new URL('../../supabase/migrations/20261025014426_korlix_messenger_app_sessions.sql', import.meta.url), 'utf8'));
});
test.after(async () => {await db?.close();});
test.beforeEach(async () => {
  await db.exec('reset role; truncate auth.users cascade; truncate device_sessions,korlix_developer_access');
  userId = crypto.randomUUID(); otherId = crypto.randomUUID();
  await db.query('insert into auth.users values($1),($2)', [userId, otherId]);
  await db.query('insert into user_profiles(id) values($1),($2)', [userId, otherId]);
  tokens = new Map(); refreshes = new Map(); revoked = new Set(); writes = []; unavailable = false; revokeRace = false;
  handlers = new Map();
  database = {
    auth: {
      getUser: async token => ({data: {user: tokens.has(token) ? user(tokens.get(token).uid) : null}}),
      admin: {signOut: async token => {revoked.add(tokens.get(token)?.sid); return {error: null};}},
    },
    async rpc(name, args) {
      assert(['korlix_register_receipt_app_session','korlix_register_messenger_app_session'].includes(name));
      if (unavailable) return {error: new Error('private database details')};
      try {
        const result = await db.query(`select public.${name}($1,$2,$3,$4,$5) result`,
          [args.p_user_id,args.p_session_id,args.p_device_id,args.p_device_label,args.p_platform]);
        return {data: result.rows[0].result};
      } catch(error) {return {error};}
    },
    from(table) {
      assert(['user_profiles','device_sessions','korlix_receipt_app_sessions'].includes(table));
      const filters = []; let mode = 'select', values;
      const execute = async single => {
        if (unavailable) return {error: new Error('private database details')};
        if (revokeRace && table === 'korlix_receipt_app_sessions' && mode === 'update') return {data: null};
        const params = [], bind = value => {params.push(value); return `$${params.length}`;};
        let sql;
        if (mode === 'upsert') {
          const columns = Object.keys(values);
          sql = `insert into ${table}(${columns.join(',')}) values(${columns.map(k=>bind(values[k])).join(',')}) on conflict(user_id,device_id) do update set ${columns.map(k=>`${k}=excluded.${k}`).join(',')} returning *`;
        } else {
          sql = mode === 'update' ? `update ${table} set ${Object.keys(values).map(k=>`${k}=${bind(values[k])}`).join(',')}` : `select * from ${table}`;
          if (filters.length) sql += ' where ' + filters.map(([k,v])=>`${k}=${bind(v)}`).join(' and ');
          if (mode === 'update') sql += ' returning *';
        }
        if (mode !== 'select') writes.push({table, mode, values});
        try {const result = await db.query(sql, params); return {data: single ? result.rows[0] ?? null : result.rows};}
        catch(error) {return {error};}
      };
      const chain = {
        select() {return chain;}, eq(k,v) {assert(/^[a-z_]+$/.test(k));filters.push([k,v]);return chain;},
        update(v) {mode='update';values=v;return chain;}, upsert(v) {mode='upsert';values=v;return chain;},
        maybeSingle: () => execute(true), single: () => execute(true),
        then: (resolve,reject) => execute(false).then(resolve,reject),
      };return chain;
    },
  };
  const supabaseAuth = {auth: {
    signInWithPassword: async ({email}) => {const uid=email.split('@')[0];return {data: {user:user(uid),session:issue(uid)}};},
    refreshSession: async ({refresh_token}) => {
      const old=refreshes.get(refresh_token);
      if (!old || revoked.has(old.sid)) return {error: {status:401,message:'Invalid refresh token'}};
      return {data: {user:user(old.uid),session:issue(old.uid,old.sid)}};
    },
  }};
  context = vm.createContext({crypto, authenticatedDeveloperUser, hasUnlimitedAccess, UNLIMITED_COMPATIBILITY_LIMIT,
    requestsReceiptApp, receiptAppSessions: createReceiptAppSessions({database}), supabaseAdmin:database, supabaseAuth,
    getOrCreateProfile: async u => ({...(await db.query('select * from user_profiles where id=$1',[u.id])).rows[0]}),
    getKorlixUserFacingError:e=>e.message, sanitize:x=>x,
    onboardingMeasurement:{observeAuth:()=>()=>{}}, app:{post:(path,...handlersList)=>handlers.set(path,handlersList.at(-1))},
  });
  vm.runInContext(sourceUnderTest,context);
  await db.exec('set role service_role');
});

test('Basic user signs into both apps; each has its own bounded device allowance', async () => {
  const hub=await login({app:'korlix_ai',device:'hub-phone'}), receipt=await login();
  assert.equal(hub.statusCode,200);assert.equal(receipt.statusCode,200);
  assert.equal((await rows('device_sessions')).length,1);
  assert.equal((await rows('korlix_receipt_app_sessions')).length,1);
  assert.equal((await context.getAuthenticatedUser(request({session:hub.body.session,app:'korlix_ai',device:'hub-phone',path:'/api/generate',method:'POST'}))).id,userId);
  assert.equal((await context.getAuthenticatedUser(request({session:receipt.body.session}))).id,userId);
  const hub2=await login({app:'korlix_ai',device:'second-hub'}),receipt2=await login({device:'second-receipt'});
  assert.equal(hub2.statusCode,403);assert.equal(receipt2.statusCode,403);
  assert.match(receipt2.body.error,/Your KORLIX AI session can stay signed in/);
  assert.equal(hub2.body.session,undefined);assert.equal(receipt2.body.session,undefined);
  assert.equal(revoked.size,2);
});

test('both sign-in orders work without merging account storage or changing entitlements', async () => {
  const receipt=await login(),hub=await login({app:'korlix_ai',device:'hub-phone'});
  assert.equal(receipt.statusCode,200);assert.equal(hub.statusCode,200);
  assert.equal(receipt.body.user.id,hub.body.user.id);assert.equal(receipt.body.profile.tier,'basic');
  assert.equal(hub.body.profile.tier,'basic');assert.equal(receipt.body.deviceLimit,1);
});

test('refresh retains the server-bound app scope across restart and header changes', async () => {
  const receipt=await login(),original=receipt.body.session;
  context.receiptAppSessions=createReceiptAppSessions({database}); // new process, no memory binding
  const rotated=await refresh(original,{app:null});assert.equal(rotated.statusCode,200);
  assert.equal(tokens.get(rotated.body.session.access_token).sid,tokens.get(original.access_token).sid);
  for(const app of [null,'korlix_ai','receipt_wiz']) {
    await assert.rejects(context.getAuthenticatedUser(request({session:rotated.body.session,app,path:'/api/generate',method:'POST'})),e=>e.code==='receipt_app_scope');
    assert.equal((await context.getAuthenticatedUser(request({session:rotated.body.session,app}))).id,userId);
  }
});

test('forged app headers cannot convert a hub session into a companion allowance', async () => {
  const hub=await login({app:'korlix_ai',device:'hub-phone'});
  await assert.rejects(context.getAuthenticatedUser(request({session:hub.body.session,device:'hub-phone'})),e=>e.statusCode===401);
  assert.equal((await rows('korlix_receipt_app_sessions')).length,0);
});

test('signing out of Receipt Wiz preserves the hub; revoked JWT cannot escape by omitting headers', async () => {
  const hub=(await login({app:'korlix_ai',device:'hub-phone'})).body.session,receipt=(await login()).body.session;
  assert.equal((await signout(receipt)).statusCode,200);
  assert.equal((await rows('korlix_receipt_app_sessions'))[0].status,'revoked');
  assert.equal((await rows('device_sessions'))[0].status,'active');
  assert.equal(revoked.has(tokens.get(hub.access_token).sid),false);
  assert.equal((await context.getAuthenticatedUser(request({session:hub,device:'hub-phone',app:'korlix_ai',path:'/api/me'}))).id,userId);
  for(const device of ['receipt-phone',null]) for(const app of ['korlix_ai',null]) {
    await assert.rejects(context.getAuthenticatedUser(request({session:receipt,device,app})),e=>e.statusCode===403);
  }
});

test('signing out of hub preserves Receipt Wiz even when installation IDs collide', async () => {
  const hub=(await login({app:'korlix_ai',device:'receipt-phone'})).body.session,receipt=(await login()).body.session;
  assert.equal((await signout(hub,{app:'korlix_ai'})).statusCode,200);
  assert.equal((await rows('device_sessions'))[0].status,'revoked');
  assert.equal((await context.getAuthenticatedUser(request({session:receipt}))).id,userId);
});

test('new password sign-in on same installation replaces only its old companion session', async () => {
  const first=(await login()).body.session,next=(await login()).body.session;
  assert.equal((await rows('korlix_receipt_app_sessions')).filter(r=>r.status==='active').length,1);
  await assert.rejects(context.getAuthenticatedUser(request({session:first})),e=>e.statusCode===403);
  assert.equal((await context.getAuthenticatedUser(request({session:next}))).id,userId);
  const denied=await refresh(first,{app:null});assert.equal(denied.statusCode,403);assert.equal(denied.body.session,undefined);
  assert.equal(revoked.has(tokens.get(first.access_token).sid),true);
});

test('missing or mismatched installation and mismatched stored owner fail closed', async () => {
  const receipt=(await login()).body.session;
  for(const device of [null,'different']) await assert.rejects(context.getAuthenticatedUser(request({session:receipt,device})),e=>e.statusCode===403);
  await db.query('update korlix_receipt_app_sessions set user_id=$1',[otherId]);
  await assert.rejects(context.getAuthenticatedUser(request({session:receipt,app:null})),e=>e.statusCode===403);
});

test('database outages and revocation during authorization never permit a fallback to hub access', async () => {
  const receipt=(await login()).body.session;
  unavailable=true;
  await assert.rejects(context.getAuthenticatedUser(request({session:receipt,app:null})),e=>e.statusCode===503&&!e.message.includes('private database'));
  unavailable=false;revokeRace=true;
  await assert.rejects(context.getAuthenticatedUser(request({session:receipt})),e=>e.statusCode===403);
});

test('disabled accounts cannot refresh, access receipts, or obtain a new companion session', async () => {
  const receipt=(await login()).body.session;
  await db.exec('reset role');await db.query('update user_profiles set is_disabled=true where id=$1',[userId]);await db.exec('set role service_role');
  await assert.rejects(context.getAuthenticatedUser(request({session:receipt})),e=>e.statusCode===403);
  assert.equal((await refresh(receipt)).statusCode,403);
  assert.equal((await login()).statusCode,403);
});

test('server-owned tier and overrides determine companion limits', async () => {
  for(const [tier,override,limit] of [['pro',null,1],['ultra',null,2],['enterprise',null,2],['basic',3,3]]) {
    await db.exec('reset role;truncate korlix_receipt_app_sessions');
    await db.query('update user_profiles set tier=$1,max_devices_override=$2 where id=$3',[tier,override,userId]);await db.exec('set role service_role');
    for(let i=0;i<limit;i++)assert.equal((await login({device:`receipt-${i}`})).statusCode,200);
    assert.equal((await login({device:'one-too-many'})).statusCode,403);
  }
});

test('overlapping registrations cannot consume more than the allowance', async () => {
  const results=await Promise.all([login({device:'first'}),login({device:'second'})]);
  assert.deepEqual(results.map(r=>r.statusCode).sort(),[200,403]);
  assert.equal((await rows('korlix_receipt_app_sessions')).filter(r=>r.status==='active').length,1);
});

test('clients cannot read or mutate bindings or execute the registration RPC', async () => {
  for(const role of ['anon','authenticated']) {
    await db.exec('reset role;set role '+role);
    await assert.rejects(db.query('select * from korlix_receipt_app_sessions'),/permission denied/);
    await assert.rejects(db.query('update korlix_receipt_app_sessions set status=\'active\''),/permission denied/);
    await assert.rejects(db.query('select korlix_register_receipt_app_session($1,$2,$3)',[userId,crypto.randomUUID(),'forged']),/permission denied/);
  }
  await db.exec('reset role');
  const metadata=(await db.query("select c.relrowsecurity, p.prosecdef from pg_class c join pg_proc p on p.proname='korlix_register_receipt_app_session' where c.relname='korlix_receipt_app_sessions'")).rows[0];
  assert.equal(metadata.relrowsecurity,true);assert.equal(metadata.prosecdef,false);
});

test('confirmed signup binds its immediate session and failed registration revokes issued tokens', async () => {
  const issued=issue(),profile=(await rows('user_profiles')).find(r=>r.id===userId);
  const options={supabaseAuth:{auth:{signUp:async()=>({data:{user:user(userId),session:issued}})}},
    getRequestDeviceInfo:context.getRequestDeviceInfo,getOrCreateProfile:async()=>profile,registerDeviceSession:context.registerDeviceSession,
    revokeSession:async session=>database.auth.admin.signOut(session.access_token,'local'),getUserFacingError:e=>e.message};
  const req=request({method:'POST',path:'/api/auth/signup',body:{email:'new@example.test',password:'fixture-password',client_app:'receipt_wiz',
    signup_eligibility:{age_band:'18_plus',terms_accepted:true,privacy_acknowledged:true,policy_version:KORLIX_SIGNUP_POLICY_VERSION}}});
  const res=response();await createKorlixSignupHandler(options)(req,res);assert.equal(res.statusCode,200);
  assert.equal((await rows('device_sessions')).length,0);assert.equal((await rows('korlix_receipt_app_sessions')).length,1);
  const another=issue();options.supabaseAuth.auth.signUp=async()=>({data:{user:user(userId),session:another}});
  req.headers['x-korlix-device-id']='another';const denied=response();await createKorlixSignupHandler(options)(req,denied);
  assert.equal(denied.statusCode,403);assert.equal(denied.body.session,undefined);assert(revoked.has(tokens.get(another.access_token).sid));
});

test('receipt scope allowlist excludes neighboring and encoded paths and wrong methods', () => {
  const id=crypto.randomUUID();
  for(const [method,path] of [['GET','/api/receipt-wiz?year=2026'],['POST',`/api/receipt-wiz/${id}/scan`],['GET',`/api/receipt-wiz/${id}/file`],['POST','/api/auth/signout'],['POST','/api/account/delete-request']]) {
    assert.equal(receiptAppRouteAllowed({method,originalUrl:path}),true);
  }
  for(const [method,path] of [['GET','/api/receipt-wiz-admin'],['POST','/api/generate'],['GET','/api/receipt-wiz/../generate'],['GET','/api/receipt-wiz/%2e%2e/generate'],['GET','/api/auth/refresh'],['POST','/api/billing/apple/verify']]) {
    assert.equal(receiptAppRouteAllowed({method,originalUrl:path}),false);
  }
});


test('Messenger, Receipt Wiz and hub share identity with independent sessions and device slots', async () => {
  const hub=await login({app:'korlix_ai',device:'hub-phone'});
  const receipt=await login({device:'same-phone'});
  const messenger=await login({app:'korlix_messenger',device:'same-phone'});
  assert.equal(hub.statusCode,200); assert.equal(receipt.statusCode,200); assert.equal(messenger.statusCode,200);
  const bindings=await rows('korlix_receipt_app_sessions');
  assert.deepEqual(bindings.map(row=>row.client_app).sort(),['korlix_messenger','receipt_wiz']);
  assert.equal((await context.getAuthenticatedUser(request({session:messenger.body.session,app:'korlix_messenger',device:'same-phone',path:'/api/social/connections'}))).id,userId);
  const signedOut=await signout(messenger.body.session,{app:'korlix_messenger',device:'same-phone',path:'/api/messenger/auth/signout'});
  assert.equal(signedOut.statusCode,200);
  assert.equal((await context.getAuthenticatedUser(request({session:receipt.body.session,device:'same-phone'}))).id,userId);
  assert.equal((await context.getAuthenticatedUser(request({session:hub.body.session,app:'korlix_ai',device:'hub-phone',path:'/api/generate',method:'POST'}))).id,userId);
});

test('Messenger cannot gain hub or Receipt Wiz access by changing an app header', async () => {
  const messenger=await login({app:'korlix_messenger'});assert.equal(messenger.statusCode,200);
  for(const app of [null,'korlix_ai','receipt_wiz','korlix_messenger']) {
    for(const path of ['/api/generate','/api/receipt-wiz']) {
      await assert.rejects(context.getAuthenticatedUser(request({session:messenger.body.session,app,path,method:'POST'})),e=>e.code==='messenger_app_scope');
    }
  }
  const allowed=request({session:messenger.body.session,app:null,path:'/api/social/messages'});
  assert.equal((await context.getAuthenticatedUser(allowed)).id,userId);
});

test('Messenger refresh uses its saved binding and revoked JWT cannot become a hub session', async () => {
  const messenger=await login({app:'korlix_messenger'});
  const rotated=await refresh(messenger.body.session,{app:'korlix_messenger',path:'/api/messenger/auth/refresh'});
  assert.equal(rotated.statusCode,200);
  await signout(rotated.body.session,{app:'korlix_messenger',path:'/api/messenger/auth/signout'});
  context.receiptAppSessions=createReceiptAppSessions({database});
  await assert.rejects(context.getAuthenticatedUser(request({session:rotated.body.session,app:null,path:'/api/social/messages'})),e=>e.statusCode===403);
  await assert.rejects(context.getAuthenticatedUser(request({session:rotated.body.session,app:null,path:'/api/generate',method:'POST'})),e=>e.statusCode===403);
});

test('Messenger device limit is independent and wrong installation cannot read conversations', async () => {
  const messenger=await login({app:'korlix_messenger',device:'one'});
  assert.equal((await login({app:'korlix_messenger',device:'two'})).statusCode,403);
  await assert.rejects(context.getAuthenticatedUser(request({session:messenger.body.session,app:'korlix_messenger',device:'wrong',path:'/api/social/connections'})),e=>e.statusCode===403);
  assert.equal((await login({app:'receipt_wiz',device:'two'})).statusCode,200);
});

test('Messenger route scope only admits Social and namespaced account operations', () => {
  for(const [method,path] of [['GET','/api/social/connections'],['POST','/api/social/send'],['GET','/api/social/attachment/file-id'],['POST','/api/messenger/auth/refresh'],['POST','/api/messenger/account/delete-request']]) {
    assert.equal(messengerAppRouteAllowed({method,originalUrl:path}),true,path);
  }
  for(const path of ['/api/generate','/api/auth/signin','/api/receipt-wiz','/api/socialevil/messages','/api/social/../generate']) {
    assert.equal(messengerAppRouteAllowed({method:'POST',originalUrl:path}),false,path);
  }
});

test('Companion registration RPCs remain unavailable to anonymous and authenticated clients', async () => {
  await db.exec('reset role');
  for (const role of ['anon','authenticated']) {
    await db.exec('set role '+role);
    await assert.rejects(db.query('select public.korlix_register_messenger_app_session($1,$2,$3)',[userId,crypto.randomUUID(),'device']),/permission denied/);
    await assert.rejects(db.query('select * from public.korlix_receipt_app_sessions'),/permission denied/);
    await db.exec('reset role');
  }
});
