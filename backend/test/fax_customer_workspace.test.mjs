import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHandler } from '../../supabase/functions/korlix-fax/handler.mjs';
import { services } from '../../supabase/functions/korlix-fax/services.mjs';
import { fail } from '../../supabase/functions/korlix-fax/rules.mjs';

const account = crypto.randomUUID();
const other = crypto.randomUUID();
const record = crypto.randomUUID();
const device = crypto.randomUUID();
const app = 'https://korlix-fax-number.onrender.com';
const hub = 'https://korlixdeveloper.com';
const phone = '+12125550101';
const user = { user_id: account, email: 'member@example.test', operator: false };
test('public store notices match the packaged privacy text and never access a mailbox', async () => {
  const handle = createHandler({});
  const url = 'https://edge.example.test/functions/v1/korlix-fax';
  const full = await handle(new Request(url + '/privacy'));
  assert.equal(full.status, 200);
  assert.match(full.headers.get('content-type'), /text\/plain/);
  const page = await readFile(new URL('../../website/fax-number/privacy.html', import.meta.url), 'utf8');
  const expected = [...page.matchAll(/<(header|h1|h2|p)\b[^>]*>(.*?)<\/\1>/gs)]
    .map(match => match[2].replace(/<[^>]+>/g, ''));
  assert.equal((await full.text()).trim(), expected.join('\n\n'));
  const removal = await handle(new Request(url + '/account-deletion'));
  assert.equal(removal.status, 200);
  assert.match(await removal.text(), /support@korlixdeveloper\.com.*72 hours/s);
  const head = await handle(new Request(url + '/privacy', { method: 'HEAD' }));
  assert.equal(head.status, 200);
  assert.equal(await head.text(), '');
});
const request = (path, method = 'GET', body, headers = {}) =>
  new Request('https://edge.example.test/functions/v1/korlix-fax' + path, {
    method, headers, body: body && JSON.stringify(body),
  });

test('only trusted hub origins may initiate a handoff, never access a private workspace cross-origin', async () => {
  const handler = createHandler({ identity: async () => fail(401, 'Sign in.') });
  const allowed = await handler(request('/hub-handoff', 'OPTIONS', null, { origin: hub }));
  assert.equal(allowed.status, 204);
  assert.equal(allowed.headers.get('access-control-allow-origin'), hub);
  assert.match(allowed.headers.get('access-control-allow-headers'), /authorization/);
  for (const [path, origin] of [['/workspace', hub], ['/hub-handoff', 'https://else.example.test']]) {
    const response = await handler(request(path, 'OPTIONS', null, { origin }));
    assert.equal(response.status, 403);
    assert.equal(response.headers.get('access-control-allow-origin'), null);
  }
  for (const path of ['/workspace', '/contacts', '/document/' + record, '/file/' + record]) {
    assert.equal((await handler(request(path, 'GET', null, { origin: app }))).status, 401);
  }
});

test('a hub sign-in verifies the identity, stores a short-lived digest and exchanges the code exactly once', async () => {
  let hashed, consumed = false, confirmed = true;
  const svc = services(name => ({
    KORLIX_FAX_CUSTOMER_ENROLLMENT:'true',
    SUPABASE_URL:'https://project.example.test', SUPABASE_ANON_KEY:'anon-fixture',
    SUPABASE_SERVICE_ROLE_KEY:'backend-fixture',
  })[name] || '', async (url, options) => {
    const path = new URL(url).pathname;
    if (path === '/auth/v1/user') {
      assert.equal(options.headers.Authorization, 'Bearer ' + 'A'.repeat(28));
      return Response.json({id: account, email_confirmed_at: confirmed ? new Date().toISOString() : null});
    }
    const payload = JSON.parse(options.body);
    if (path.endsWith('/korlix_fax_handoffs')) {
      assert.equal(payload.user_id, account);
      assert.ok(Date.parse(payload.expires_at) - Date.now() <= 90000);
      hashed = payload.code_hash;
      return new Response(null, {status: 204});
    }
    assert.match(path, /rpc\/korlix_fax_redeem_handoff$/);
    assert.equal(payload.p_code, hashed);
    assert.equal(payload.p_device, device);
    assert.match(payload.p_hash, /^[a-f0-9]{64}$/);
    const permitted = !consumed;
    consumed = true;
    return Response.json(permitted);
  });
  const handler = createHandler(svc);
  assert.equal((await handler(request('/hub-handoff', 'POST'))).status, 401);
  const exchange = () => handler(request('/hub-handoff','POST',null,{origin:hub,authorization:'Bearer '+'A'.repeat(28)}));
  confirmed = false;
  assert.equal((await exchange()).status, 403);
  confirmed = true;
  const {code} = await (await exchange()).json();
  assert.match(code, /^[a-f0-9]{64}$/);
  assert.notEqual(code, hashed);
  const redeem = () => handler(request('/redeem','POST',{code,device},{origin:app}));
  const {token} = await (await redeem()).json();
  assert.match(token, /^[a-f0-9]{64}$/);
  assert.notEqual(token,code);
  assert.equal((await redeem()).status,401);
});

test('contacts and receipts are owner-scoped, and document responses exclude storage paths', async () => {
  let contact;
  const handler = createHandler({
    customerEnrollmentOpen: true,
    identity: async () => user,
    db: async (table,filter,method,body) => {
      if (method === 'POST') {
        assert.equal(table,'korlix_fax_contacts');
        assert.equal(body.user_id,account);
        contact = {name:body.name,phone:body.phone};
        return;
      }
      assert.equal(filter.user_id,'eq.'+account);
      if (table === 'korlix_fax_contacts') return [contact];
      return filter.id === 'eq.'+record ? [{id:record,object_path:account+'/proof.pdf'}] : [];
    },
  });
  assert.equal((await handler(request('/contacts','POST',{name:'Empty',phone:[phone]}))).status,400);
  const res = await handler(request('/contacts','POST',{name:'  Studio  ',phone,user_id:other}));
  assert.deepEqual(await res.json(),{name:'Studio',phone});
  assert.deepEqual(await (await handler(request('/contacts'))).json(),{items:[{name:'Studio',phone}]});
  assert.deepEqual(await (await handler(request('/document/'+record))).json(),{id:record,hasFile:true});
  assert.equal((await handler(request('/document/'+other))).status,404);
});

test('new customers can request local or toll-free service without triggering a charge or an order', async () => {
  let saved;
  const handler = createHandler({
    customerEnrollmentOpen: true,
    identity: async () => user,
    db: async (table,filter,method,body,prefer) => {
      assert.equal(table,'korlix_fax_lines');
      assert.equal(method,'POST');
      assert.equal(filter.on_conflict,'user_id');
      assert.match(prefer,/ignore-duplicates/);
      saved ??= {...body,state:'requested'};
    },
    lineFor: async (filter) => {assert.equal(filter.user_id,'eq.'+account);return saved;},
  });
  assert.equal((await handler(request('/line','POST',{preference:'toll_free',plan:'fake'}))).status,400);
  const result = await (await handler(request('/line','POST',{preference:'212',plan:'solo',user_id:other}))).json();
  assert.deepEqual(result.line,{user_id:account,preference:'212',requested_plan:'solo',state:'requested'});
  const duplicate = await (await handler(request('/line','POST',{preference:'toll_free',plan:'business'}))).json();
  assert.deepEqual(duplicate,result);
});

test('monthly usage is determined by the private server aggregate for the current UTC month', async () => {
  const handler = createHandler({
    customerEnrollmentOpen: true, ready:true, identity:async()=>user, lineFor:async()=>null,
    rpc:async(name, args) => {
      assert.equal(name,'monthly_usage');
      assert.equal(args.p_user,account);
      assert.ok(new Date(args.p_start) <= new Date() && new Date() < new Date(args.p_end));
      assert.ok(args.p_start.endsWith('01T00:00:00.000Z') && args.p_end.endsWith('01T00:00:00.000Z'));
      return {pages:7,inboundPages:2,outboundPages:5,pendingReports:1};
    },
  });
  const answer = await (await handler(request('/workspace'))).json();
  assert.equal(answer.usage.pages,7);
  assert.equal(answer.usage.pendingReports,1);
  assert.equal(answer.line,null);
  assert.equal(answer.plans.solo.name,'Solo');
});

test('the default private launch rejects new requests and cached customer sessions before any writes', async () => {
  let operator = false;
  const companyLine = { is_company: true, state: 'active', phone };
  const handler = createHandler({
    identity: async () => ({ ...user, operator }),
    lineFor: async () => companyLine,
    rpc: async () => ({ pages: 2, inboundPages: 1, outboundPages: 1, pendingReports: 0 }),
    db: async () => assert.fail('a stopped enrollment must not read or write customer data'),
  });
  for (const path of ['/workspace','/contacts','/history?direction=inbound','/document/'+record,'/file/'+record])
    assert.equal((await handler(request(path))).status, 403);
  assert.equal((await handler(request('/send','POST',{to:phone}))).status, 403);
  assert.equal((await handler(request('/contacts','POST',{phone,name:'Fixture'}))).status, 403);
  for (operator of [false,true]) {
    const response = await handler(request('/line','POST',{preference:'toll_free',plan:'business',customerEnrollmentOpen:true}));
    assert.equal(response.status,403);
    assert.match((await response.json()).error,/enrollment is closed/);
  }
  const company = await handler(request('/workspace'));
  assert.equal(company.status, 200);
  const workspace = await company.json();
  assert.deepEqual(workspace.line,companyLine);
  assert.equal(workspace.customerEnrollmentOpen,false);
  assert.equal(workspace.plans,undefined);
  assert.equal((await handler(request('/health'))).status,200);
});

test('only the verified company identity can open a password session or use an SSO handoff during the hold', async () => {
  let company = false, opens = 0, handoffs = 0, redeemed = 0;
  const settings = {SUPABASE_URL:'https://project.example.test',SUPABASE_ANON_KEY:'fixture',SUPABASE_SERVICE_ROLE_KEY:'fixture'};
  const member = { id: account, email_confirmed_at:new Date().toISOString() };
  const svc = services(name=>settings[name] || '', async (input, options) => {
    const url = new URL(input);
    if (url.pathname === '/auth/v1/token') return Response.json({user:member,access_token:'fixture'});
    if (url.pathname === '/auth/v1/logout') return new Response(null,{status:204});
    if (url.pathname === '/auth/v1/user') return Response.json(member);
    if (url.pathname.endsWith('/korlix_fax_lines')) {
      assert.equal(url.searchParams.get('user_id'),'eq.'+account);
      assert.equal(url.searchParams.get('is_company'),'eq.true');
      return Response.json(company?[{id:record}]:[]);
    }
    if (url.pathname.endsWith('/korlix_fax_handoffs')) {
      if (options.method === 'GET') return Response.json([{user_id:account}]);
      handoffs++; return new Response(null,{status:204});
    }
    if (url.pathname.endsWith('/korlix_fax_open_session')) {opens++;return Response.json(true);}
    if (url.pathname.endsWith('/korlix_fax_redeem_handoff')) {redeemed++;return Response.json(true);}
    assert.fail('unexpected service call: '+url.pathname);
  });
  const handler = createHandler(svc);
  const calls = [
    () => handler(request('/signin','POST',{email:'fixture@example.test',password:'test-only',device})),
    () => handler(request('/hub-handoff','POST',null,{origin:hub,authorization:'Bearer '+'a'.repeat(40)})),
    () => handler(request('/redeem','POST',{code:'a'.repeat(64),device})),
  ];
  for (const call of calls) assert.equal((await call()).status,403);
  assert.deepEqual([opens,handoffs,redeemed],[0,0,0]);
  company = true;
  for (const call of calls) assert.equal((await call()).status,200);
  assert.deepEqual([opens,handoffs,redeemed],[1,1,1]);
});

test('packaged apps can use the company mailbox only with a valid session', async () => {
  const handler = createHandler({ identity: async () => fail(401, 'Sign in.') });
  for (const origin of ['https://fax.localhost', 'capacitor://fax.localhost']) {
    for (const path of ['/signin', '/send', '/activity', '/file/' + record]) {
      const headers = (await handler(request(path, 'OPTIONS', null, { origin }))).headers;
      assert.equal(headers.get('access-control-allow-origin'), origin);
    }
    assert.equal((await handler(request('/workspace', 'GET', null, { origin }))).status, 401);
    for (const path of ['/hub-handoff', '/redeem', '/line', '/carrier']) {
      assert.equal((await handler(request(path, 'OPTIONS', null, { origin }))).status, 403);
    }
  }
  for (const origin of ['https://fax.localhost.example.com', 'http://fax.localhost', 'null']) {
    assert.equal((await handler(request('/workspace', 'OPTIONS', null, { origin }))).status, 403);
  }
});

test('store customers have owner-scoped workspaces and can request lines without opening the public website', async () => {
  const pending = [];
  const handler = createHandler({
    identity: async req => {
      if (req.headers.get('x-fax-session') !== 'test-session') fail(401, 'Sign in.');
      return user;
    },
    lineFor: async where => { assert.equal(where.user_id, 'eq.' + account); return pending[0]; },
    rpc: async (name,args) => {
      assert.equal(name,'monthly_usage');
      assert.equal(args.p_user,account);
      return {pages:0,inboundPages:0,outboundPages:0,pendingReports:0};
    },
    db: async (table, where, method, value) => {
      assert.equal(value.user_id,account);
      assert.equal(table,'korlix_fax_lines');
      assert.equal(method,'POST');
      pending.push({...value,state:'requested'});
    }
  });
  for (const origin of ['https://fax.localhost','capacitor://fax.localhost']) {
    const headers = {origin,'x-fax-session':'test-session'};
    const ws = await handler(request('/mobile/workspace','GET',null,headers));
    assert.equal(ws.status,200);
    assert.equal((await ws.json()).customerEnrollmentOpen,true);
    assert.equal((await handler(request('/mobile/workspace','GET',null,{origin}))).status,401);
    assert.equal((await handler(request('/mobile/operator/requests','GET',null,headers))).status,403);
  }
  const result = await handler(request('/mobile/line','POST',{preference:'212',plan:'solo',user_id:other},
    {origin:'https://fax.localhost','x-fax-session':'test-session'}));
  assert.equal(result.status,200);
  assert.equal((await result.json()).line.user_id,account);
  for (const origin of [app,hub,'https://unrelated.example']) {
    assert.equal((await handler(request('/mobile/line','POST',{preference:'212'},{origin}))).status,403);
  }
  assert.equal((await handler(request('/mobile/line','POST',{preference:'212'}))).status,403);
  assert.equal((await handler(request('/workspace','GET',null,{origin:app,'x-fax-session':'test-session'}))).status,403);
  assert.equal(pending.length,1);
});

test('mobile sign-in uses a verified Korlix user and registrations never return shared account tokens', async () => {
  const origins = { origin: 'https://fax.localhost' };
  const usr = {id:account,email_confirmed_at:new Date().toISOString()};
  let registered = false;
  const svc = services(name => ({
    SUPABASE_URL:'https://project.example.test',SUPABASE_ANON_KEY:'test-anon',SUPABASE_SERVICE_ROLE_KEY:'test-role'
  })[name] || '', async (url,options) => {
    const path = new URL(url).pathname;
    if (path === '/api/auth/signup') {
      assert.equal(JSON.parse(options.body).client_app,'fax_by_korlix');
      registered = true;
      return Response.json({success:true,session:{access_token:'test-account-token'}});
    }
    if (path === '/auth/v1/token') return Response.json({user:usr,access_token:'test-account-token'});
    if (path === '/auth/v1/logout') return new Response(null,{status:204});
    if (path.endsWith('/korlix_fax_open_session')) {
      assert.equal(JSON.parse(options.body).p_user,account); return Response.json(true);
    }
    assert.fail('Unexpected account request: '+path);
  });
  const handler = createHandler(svc);
  const credentials = {email:'new@example.test',password:'fixture123',device};
  const registeredResponse = await handler(request('/mobile/signup','POST',credentials,origins));
  assert.equal(registeredResponse.status,200);
  assert.deepEqual(Object.keys(await registeredResponse.json()),['message']);
  assert.equal(registered,true);
  const session = await handler(request('/mobile/signin','POST',credentials,origins));
  assert.match((await session.json()).token,/^[a-f0-9]{64}$/);
  usr.email_confirmed_at=null;
  assert.equal((await handler(request('/mobile/signin','POST',credentials,origins))).status,403);
});

test('mobile deletion requests require confirmation and use only the signed-in account', async () => {
  let writes=0;
  const handler=createHandler({identity:async()=>user,db:async (table,where,method,body)=>{
    assert.equal(table,'rpc/korlix_request_account_deletion');
    assert.equal(body.p_user_id,account); assert.equal(body.p_email,user.email); writes++;
  }});
  const call=confirm=>handler(request('/mobile/account/delete-request','POST',{user_id:other,confirm},{origin:'capacitor://fax.localhost'}));
  assert.equal((await call(false)).status,400);
  assert.equal((await call(true)).status,200);
  assert.equal(writes,1);
});
