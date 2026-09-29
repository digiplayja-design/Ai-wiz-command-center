import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes} from 'node:crypto';
import {GasError,PACKAGE_NAME,GOOGLE_BASE,createAccountBinding,parseGooglePurchase,createGoogleClient,tokenHash,token,userId,productId} from './google.mjs';
import {createTokenVault} from './vault.mjs';
import {PACKS,createStore,validateCatalog,createWallet,registerWalletRoutes} from './wallet.mjs';
const USER='10000000-0000-4000-8000-000000000001', OTHER='10000000-0000-4000-8000-000000000002';
const PID='synthetic_gas_1h', TOKEN='SYNTHETIC_NOT_A_REAL_PURCHASE_TOKEN_0123456789';
const NOW=Date.parse('2026-09-29T20:00:00Z');
const binding=createAccountBinding(Buffer.alloc(32,7));
const context={userId:USER,productId:PID,tokenHash:tokenHash(TOKEN)};
const vault=()=>createTokenVault({activeKeyId:'synthetic',keys:new Map([['synthetic',Buffer.alloc(32,8)]])});
function fixture(){return {
  productLineItem:[{productId:PID,productOfferDetails:{quantity:1,refundableQuantity:1,consumptionState:'CONSUMPTION_STATE_YET_TO_BE_CONSUMED'}}],
  purchaseStateContext:{purchaseState:'PURCHASED'},obfuscatedExternalAccountId:binding(USER),
  purchaseCompletionTime:'2026-09-29T19:00:00Z',acknowledgementState:'ACKNOWLEDGEMENT_STATE_PENDING',
};}
const parse=(body=fixture(),options={})=>parseGooglePurchase(body,{expectedProductId:PID,expectedAccountId:binding(USER),now:NOW,...options});
const cat=()=>PACKS.map((p,i)=>({...p,enabled:true,productId:i===0?PID:`synthetic_gas_${i}`}));
function service({verify,consume,store,vaultOverride,proof={}}={}){
  const calls=[];let granted=false;
  const v=vault();
  const google={accountId:binding,verify:verify??(async ()=>({...parse(),...proof})),consume:consume??(async ()=>{calls.push('google_consume');})};
  const defaultStore=async(action,data={})=>{
    calls.push([action,structuredClone(data)]);
    if(action==='catalog')return cat();
    if(action==='balance')return {balanceSeconds:granted?3600:0,reviewRequired:false};
    if(action==='grant_google') {const duplicate=granted;granted=true;return {balanceSeconds:3600,reviewRequired:false,granted:!duplicate,idempotent:duplicate};}
    if(action==='claim')return {tokenHash:context.tokenHash,userId:USER,productId:PID,leaseId:USER,sealedToken:v.seal(TOKEN,context)};
    return {ok:true};
  };
  return {calls,wallet:createWallet({google,vault:vaultOverride??v,store:store??defaultStore})};
}

test('approved five-hour reference price remains exactly $124.99',()=>{
 assert.deepEqual(PACKS[3],{sku:'korlix_ai_gas_5h',seconds:18000,referenceUsdCents:12499});
 assert.throws(()=>{PACKS[3].referenceUsdCents=12500;},TypeError);
});
test('account binding is stable, account-specific and not raw UUID',()=>{
 assert.equal(binding(USER),binding(USER.toUpperCase()));assert.notEqual(binding(USER),binding(OTHER));
 assert.ok(binding(USER).length<64);assert.ok(!binding(USER).includes(USER));
});
for(const key of [undefined,'secret',Buffer.alloc(16),Buffer.alloc(64)])test(`binding rejects invalid key ${typeof key}`,()=>assert.throws(()=>createAccountBinding(key),/GAS_BINDING_KEY_INVALID/));
for(const value of ['', '..','x'.repeat(2049),'a\nb'.repeat(8),'é'.repeat(20),null,123,{},[]])test(`reject malformed purchase token ${typeof value}:${String(value).slice(0,8)}`,()=>assert.throws(()=>token(value),/GAS_TOKEN_INVALID/));
for(const value of ['../sku','HTTPS://evil.test','',null,{},'X','x'.repeat(201)])test(`reject malformed product ${String(value).slice(0,8)}`,()=>assert.throws(()=>productId(value),/GAS_PRODUCT_INVALID/));
for(const value of ['',USER+'/x',null,{},123])test('reject malformed actor '+String(value),()=>assert.throws(()=>userId(value),/GAS_AUTH_REQUIRED/));

test('strict purchased proof includes neither token nor order ID',()=>{
 const b=fixture();b.orderId='not-an-idempotency-key';const p=parse(b);
 assert.deepEqual(p,{state:'PURCHASED',productId:PID,isTest:false,consumed:false,purchasedAt:'2026-09-29T19:00:00.000Z'});
});
test('pending does not become purchased',()=>{const b=fixture();b.purchaseStateContext.purchaseState='PENDING';delete b.purchaseCompletionTime;assert.equal(parse(b).state,'PENDING');});
test('cancelled becomes revocation decision',()=>{const b=fixture();b.purchaseStateContext.purchaseState='CANCELLED';delete b.purchaseCompletionTime;assert.equal(parse(b).state,'REVOKED');});
test('full quantity refund becomes revocation decision',()=>{const b=fixture();b.productLineItem[0].productOfferDetails.refundableQuantity=0;assert.equal(parse(b).state,'REVOKED');});
test('consumed purchase is recognized for database-controlled replay handling',()=>{const b=fixture();b.productLineItem[0].productOfferDetails.consumptionState='CONSUMPTION_STATE_CONSUMED';assert.equal(parse(b).consumed,true);});
test('test cards require explicit isolated-test configuration',()=>{const b=fixture();b.testPurchaseContext={fopType:'TEST'};assert.throws(()=>parse(b),/GAS_TEST_PURCHASE_REJECTED/);assert.equal(parse(b,{allowTestPurchases:true}).isTest,true);});
const invalidCases=[
 ['missing account',b=>delete b.obfuscatedExternalAccountId],['wrong account',b=>b.obfuscatedExternalAccountId=binding(OTHER)],
 ['plain UUID',b=>b.obfuscatedExternalAccountId=USER],['wrong product',b=>b.productLineItem[0].productId='other_product'],
 ['multiple items',b=>b.productLineItem.push(structuredClone(b.productLineItem[0]))],['no items',b=>b.productLineItem=[]],
 ['unknown state',b=>b.purchaseStateContext.purchaseState='SUCCESS'],['missing state',b=>delete b.purchaseStateContext],
 ['unknown consumption',b=>b.productLineItem[0].productOfferDetails.consumptionState='CONSUMED'],
 ['missing consumption',b=>delete b.productLineItem[0].productOfferDetails.consumptionState],
 ['unknown acknowledgement',b=>b.acknowledgementState='YES'],['missing acknowledgment',b=>delete b.acknowledgementState],
 ['quantity two',b=>b.productLineItem[0].productOfferDetails.quantity=2],['quantity string',b=>b.productLineItem[0].productOfferDetails.quantity='1'],
 ['quantity zero',b=>b.productLineItem[0].productOfferDetails.quantity=0],['missing quantity',b=>delete b.productLineItem[0].productOfferDetails.quantity],
 ['refund invalid',b=>b.productLineItem[0].productOfferDetails.refundableQuantity=2],['refund string',b=>b.productLineItem[0].productOfferDetails.refundableQuantity='1'],
 ['rental',b=>b.productLineItem[0].productOfferDetails.rentOfferDetails={}],['preorder',b=>b.productLineItem[0].productOfferDetails.preorderOfferDetails={}],
 ['missing completion',b=>delete b.purchaseCompletionTime],['bad completion',b=>b.purchaseCompletionTime='yesterday'],
 ['future completion',b=>b.purchaseCompletionTime='2099-09-29T20:00:00Z'],['unqualified time',b=>b.purchaseCompletionTime='2026-09-29'],
 ['unknown test marker',b=>b.testPurchaseContext={fopType:'CASH'}],['null test marker',b=>b.testPurchaseContext=null],
];
for(const [name,mutate]of invalidCases)test('reject provider response: '+name,()=>{const b=fixture();mutate(b);assert.throws(()=>parse(b),GasError);});
for(const body of [null,[],1,'PURCHASED'])test('reject non-object provider response '+String(body),()=>assert.throws(()=>parse(body),GasError));
for(const options of [{now:NaN},{now:Infinity},{allowTestPurchases:'true'},{expectedAccountId:USER}])test('reject verifier misconfiguration '+JSON.stringify(options),()=>assert.throws(()=>parse(fixture(),options),GasError));

test('AES-GCM round trip and non-deterministic IV',()=>{const v=vault(),a=v.seal(TOKEN,context),b=v.seal(TOKEN,context);assert.notEqual(a.iv,b.iv);assert.ok(!JSON.stringify(a).includes(TOKEN));assert.equal(v.open(a,context),TOKEN);});
for(const field of ['iv','tag','data','kid'])test('encrypted token tampering rejected: '+field,()=>{const v=vault(),a={...v.seal(TOKEN,context)};a[field]='bad_value';assert.throws(()=>v.open(a,context),/GAS_TOKEN_DECRYPT_FAILED/);});
for(const change of [{userId:OTHER},{productId:'other_product'},{tokenHash:'b'.repeat(64)}])test('encrypted token cannot move across context '+JSON.stringify(change),()=>{const v=vault(),a=v.seal(TOKEN,context);assert.throws(()=>v.open(a,{...context,...change}),/GAS_TOKEN_DECRYPT_FAILED/);});
test('new encryption key can decrypt pending work encrypted by retained old key',()=>{const old=vault(),sealed=old.seal(TOKEN,context);const next=createTokenVault({activeKeyId:'new',keys:new Map([['new',Buffer.alloc(32,9)],['synthetic',Buffer.alloc(32,8)]])});assert.equal(next.open(sealed,context),TOKEN);assert.equal(next.seal(TOKEN,context).kid,'new');});
test('seal rejects token-hash mismatch',()=>assert.throws(()=>vault().seal(TOKEN,{...context,tokenHash:'a'.repeat(64)}),/GAS_TOKEN_CONTEXT_INVALID/));
test('vault rejects missing configuration',()=>assert.throws(()=>createTokenVault(),/GAS_TOKEN_KEY_INVALID/));

test('Google adapter sends only fixed package API requests and no request body',async()=>{
 const calls=[];const client=createGoogleClient({accountBindingKey:Buffer.alloc(32,7),getAccessToken:async()=>'SYNTHETIC_ACCESS_TOKEN_NOT_REAL',now:()=>NOW,fetchImpl:async(url,opts)=>{calls.push([url,opts]);return opts.method==='GET'?Response.json(fixture()):new Response(null,{status:204});}});
 assert.equal((await client.verify({userId:USER,productId:PID,purchaseToken:TOKEN})).state,'PURCHASED');
 await client.consume({productId:PID,purchaseToken:TOKEN});
 assert.equal(calls[0][0],GOOGLE_BASE+'/purchases/productsv2/tokens/'+TOKEN);
 assert.equal(calls[1][0],GOOGLE_BASE+'/purchases/products/'+PID+'/tokens/'+TOKEN+':consume');
 for(const [,o]of calls){assert.equal(o.redirect,'error');assert.equal(o.body,undefined);assert.ok(o.signal instanceof AbortSignal);}
});
for(const code of [401,403,404,409,429,500])test('Google HTTP failure is sanitized '+code,async()=>{
 const client=createGoogleClient({accountBindingKey:Buffer.alloc(32,7),getAccessToken:async()=>'SYNTHETIC_ACCESS_TOKEN_NOT_REAL',fetchImpl:async()=>new Response('private:'+TOKEN,{status:code})});
 await assert.rejects(client.verify({userId:USER,productId:PID,purchaseToken:TOKEN}),e=>e instanceof GasError&&!e.message.includes(TOKEN));
});
test('network exception with secret URL is sanitized',async()=>{
 const client=createGoogleClient({accountBindingKey:Buffer.alloc(32,7),getAccessToken:async()=>'SYNTHETIC_ACCESS_TOKEN_NOT_REAL',fetchImpl:async()=>{throw Error('https://host/'+TOKEN);}});
 await assert.rejects(client.verify({userId:USER,productId:PID,purchaseToken:TOKEN}),/GOOGLE_UNAVAILABLE/);
});
for(const body of ['not json','x'.repeat(65537)])test('malformed/oversized Google body is rejected '+body.length,async()=>{
 const client=createGoogleClient({accountBindingKey:Buffer.alloc(32,7),getAccessToken:async()=>'SYNTHETIC_ACCESS_TOKEN_NOT_REAL',fetchImpl:async()=>new Response(body)});
 await assert.rejects(client.verify({userId:USER,productId:PID,purchaseToken:TOKEN}),/GOOGLE_RESPONSE_INVALID/);
});

test('catalog accepts disabled unmapped products without inventing store IDs',()=>assert.ok(validateCatalog(PACKS.map(p=>({...p,enabled:false,productId:null}))).every(p=>!p.enabled)));
for(const [name,change]of [
 ['wrong price',c=>c[3].referenceUsdCents=12500],['wrong seconds',c=>c[0].seconds=7200],['duplicate SKU',c=>c[1]=c[0]],
 ['duplicate provider ID',c=>c[1].productId=c[0].productId],['missing mapping',c=>c[0].productId=null],['wrong enable type',c=>c[0].enabled='true'],
 ['missing pack',c=>c.pop()],['extra pack',c=>c.push(c[0])],
])test('catalog fails closed: '+name,()=>{const c=cat();change(c);assert.throws(()=>validateCatalog(c),GasError);});
test('grant uses authoritative package, records once, exposes no token, never consumes before commit',async()=>{
 const {wallet,calls}=service();const r=await wallet.verifyAndGrant({userId:USER,productId:PID,purchaseToken:TOKEN,seconds:999999,tier:'enterprise'});
 assert.equal(r.balanceSeconds,3600);assert.equal(r.granted,true);
 const entry=calls.find(c=>c[0]==='grant_google')[1];assert.equal(entry.sku,'korlix_ai_gas_1h');assert.equal(entry.seconds,undefined);assert.equal(entry.tier,undefined);assert.equal(entry.tokenHash,context.tokenHash);
 assert.ok(!JSON.stringify(entry).includes(TOKEN));assert.ok(!JSON.stringify(r).includes(TOKEN));assert.ok(!calls.includes('google_consume'));
 const again=await wallet.verifyAndGrant({userId:USER,productId:PID,purchaseToken:TOKEN});assert.equal(again.idempotent,true);assert.equal(again.balanceSeconds,3600);
});
test('pending never reaches ledger grant',async()=>{const h=service({proof:{state:'PENDING'}});assert.deepEqual(await h.wallet.verifyAndGrant({userId:USER,productId:PID,purchaseToken:TOKEN}),{state:'PENDING',granted:false});assert.ok(!h.calls.some(c=>c[0]==='grant_google'));});
test('cancelled proof records revocation not a grant',async()=>{const h=service({proof:{state:'REVOKED'}});await assert.rejects(h.wallet.verifyAndGrant({userId:USER,productId:PID,purchaseToken:TOKEN}),/GAS_PURCHASE_REVOKED/);assert.ok(h.calls.some(c=>c[0]==='revoke'));assert.ok(!h.calls.some(c=>c[0]==='grant_google'));});
test('storage failure cannot trigger early Google consumption',async()=>{let consumed=false;const h=service({consume:async()=>{consumed=true;},store:async(a)=>a==='catalog'?cat():Promise.reject(new GasError('GAS_STORAGE_UNAVAILABLE'))});await assert.rejects(h.wallet.verifyAndGrant({userId:USER,productId:PID,purchaseToken:TOKEN}),/GAS_STORAGE_UNAVAILABLE/);assert.equal(consumed,false);});
test('unknown product never calls Google verification',async()=>{let calls=0;const h=service({verify:async()=>{calls++;}});await assert.rejects(h.wallet.verifyAndGrant({userId:USER,productId:'not_mapped',purchaseToken:TOKEN}),/GAS_PRODUCT_UNAVAILABLE/);assert.equal(calls,0);});
test('worker re-verifies then consumes and records completion',async()=>{const h=service();assert.deepEqual(await h.wallet.processOneConsumptionJob(),{processed:true,state:'CONSUMED'});const i=h.calls.indexOf('google_consume');assert.ok(i>=0);assert.ok(h.calls.findIndex(c=>c[0]==='finish')>i);});
test('worker resumes after prior consume succeeded without consuming twice',async()=>{const h=service({proof:{consumed:true}});assert.equal((await h.wallet.processOneConsumptionJob()).state,'CONSUMED');assert.ok(!h.calls.includes('google_consume'));});
test('worker records durable retry after provider failure',async()=>{const h=service({consume:async()=>{throw new GasError('GOOGLE_UNAVAILABLE');}});assert.equal((await h.wallet.processOneConsumptionJob()).state,'RETRY_SCHEDULED');assert.ok(h.calls.some(c=>c[0]==='retry'&&c[1].errorCode==='GOOGLE_UNAVAILABLE'));assert.ok(!h.calls.some(c=>c[0]==='finish'));});
test('worker revokes cancelled purchase and does not consume it',async()=>{const h=service({proof:{state:'REVOKED'}});assert.equal((await h.wallet.processOneConsumptionJob()).state,'REVOKED');assert.ok(h.calls.some(c=>c[0]==='revoke'));assert.ok(!h.calls.includes('google_consume'));});
test('worker retries missing/broken decryption without leaking secrets',async()=>{const h=service({vaultOverride:{seal(){},open(){throw Error(TOKEN);}}});const r=await h.wallet.processOneConsumptionJob();assert.equal(r.state,'RETRY_SCHEDULED');assert.ok(!JSON.stringify(r).includes(TOKEN));});
test('empty queue is a clean no-op',async()=>{const h=service({store:async()=>null});assert.deepEqual(await h.wallet.processOneConsumptionJob(),{processed:false});});
test('unknown database error strips raw details',async()=>{const store=createStore({rpc:async()=>({error:{message:'private receipt '+TOKEN}})});await assert.rejects(store('grant_google'),/GAS_STORAGE_UNAVAILABLE/);});
test('database adapter always calls fixed server RPC',async()=>{let call;const store=createStore({rpc:async(...a)=>{call=a;return {data:[]};}});await store('catalog');assert.deepEqual(call,['korlix_gas_v2_rpc',{p_action:'catalog',p_data:{}}]);});
test('routes remain disabled without explicit activation',()=>assert.deepEqual(registerWalletRoutes(),{mounted:false}));
function routes(options={}){
 const entries=[];let actor;
 const wallet={catalog:async()=>cat(),balance:async u=>{actor=u;return {balanceSeconds:0,reviewRequired:false};},purchaseContext:async()=>({}),verifyAndGrant:async x=>{actor=x.userId;return {state:'PENDING'};}};
 registerWalletRoutes({get:(...a)=>entries.push(a),post:(...a)=>entries.push(a)},{enabled:true,requireUser:async()=>({id:USER}),limiter:()=>{},wallet,...options});
 const res={statusCode:200,set(){return this;},status(n){this.statusCode=n;return this;},json(b){this.body=b;return this;}};
 return {entries,res,getActor:()=>actor};
}
test('routes expose no refund/debit/worker operations',()=>{const r=routes();assert.equal(r.entries.length,4);assert.ok(!r.entries.some(e=>/revoke|debit|worker/.test(e[0])));});
test('route balance is bound to validated actor, never query user',async()=>{const r=routes();await r.entries.find(e=>e[0].endsWith('/balance'))[2]({query:{userId:OTHER}},r.res);assert.equal(r.getActor(),USER);});
test('purchase route rejects forged amount/tier/identity fields',async()=>{const r=routes();await r.entries.find(e=>e[0].endsWith('/verify'))[2]({body:{productId:PID,purchaseToken:TOKEN,userId:OTHER,tier:'enterprise',seconds:99999}},r.res);assert.equal(r.res.statusCode,400);assert.equal(r.getActor(),undefined);});
test('unauthenticated route fails before loading wallet',async()=>{const r=routes({requireUser:async()=>{throw Error(TOKEN);}});await r.entries[0][2]({},r.res);assert.equal(r.res.statusCode,401);assert.ok(!JSON.stringify(r.res.body).includes(TOKEN));});
test('route adapters cannot be omitted on activation',()=>assert.throws(()=>registerWalletRoutes({get(){},post(){}},{enabled:true}),/GAS_ROUTE_ADAPTER_REQUIRED/));

test('pending response with no completed offer fields remains pending, not an error',()=>{
 const b=fixture(); b.purchaseStateContext.purchaseState='PENDING';
 delete b.productLineItem[0].productOfferDetails;delete b.purchaseCompletionTime;delete b.acknowledgementState;
 assert.equal(parse(b).state,'PENDING');
});
test('cancelled response without completed purchase fields cannot grant',()=>{
 const b=fixture(); b.purchaseStateContext.purchaseState='CANCELLED';
 delete b.productLineItem[0].productOfferDetails;delete b.purchaseCompletionTime;delete b.acknowledgementState;
 assert.equal(parse(b).state,'REVOKED');
});
