import test from 'node:test';
import assert from 'node:assert/strict';
import {createGoogleAdsProvider,googleAdsConfiguration,googleTokenCipher,googleAdsScope,GoogleAdsAccessError} from '../funnels/google_ads_provider.mjs';
const env={KORLIX_GOOGLE_ADS_ENABLED:'true',KORLIX_GOOGLE_ADS_CLIENT_ID:'12345-fixture.apps.googleusercontent.com',KORLIX_GOOGLE_ADS_CLIENT_SECRET:'fixture-client-secret',KORLIX_GOOGLE_ADS_DEVELOPER_TOKEN:'fixture-developer-token',KORLIX_GOOGLE_ADS_TOKEN_KEY:Buffer.alloc(32,8).toString('base64'),KORLIX_GOOGLE_ADS_REDIRECT_URI:'https://example.com/api/funnels/google-ads/callback'},cfg=googleAdsConfiguration(env);
const root='1234567890',id='9876543210';
const raw={id,descriptiveName:'Advertiser',currencyCode:'USD',timeZone:'UTC',status:'ENABLED'};
const tokens={access_token:'access-fixture',refresh_token:'refresh-fixture',scope:googleAdsScope,token_type:'Bearer',expires_in:3600};
function mock(bodies){const calls=[];return {calls,provider:createGoogleAdsProvider(cfg,{now:()=>1000000,fetchImpl:async(url,options)=>{calls.push({url,options});const b=bodies.shift();if(b instanceof Error)throw b;return b instanceof Response?b:new Response(JSON.stringify(b));}})};}
test('Disabled or malformed configuration fails closed, and encryption binds owner, attempt and purpose',()=>{
 assert(cfg.ready);for(const key of Object.keys(env))assert.equal(googleAdsConfiguration({...env,[key]:''}).ready,false);
 for(const redirect of ['http://example.com/api/funnels/google-ads/callback','https://example.com/other','https://x@y.example/api/funnels/google-ads/callback','https://example.com/api/funnels/google-ads/callback?x=1'])assert.equal(googleAdsConfiguration({...env,KORLIX_GOOGLE_ADS_REDIRECT_URI:redirect}).ready,false);
 assert.equal(googleAdsConfiguration({...env,KORLIX_GOOGLE_ADS_API_VERSION:'v25/../../token'}).ready,false);
 const cipher=googleTokenCipher(cfg.key),sealed=cipher.seal('credential-fixture','refresh:owner:attempt');assert.equal(cipher.open(sealed,'refresh:owner:attempt'),'credential-fixture');
 for(const binding of ['refresh:other:attempt','pkce:owner:attempt','refresh:owner:other'])assert.throws(()=>cipher.open(sealed,binding),/Reconnect/);
 assert.throws(()=>cipher.open({...sealed,tag:'x'.repeat(22)},'refresh:owner:attempt'),/Reconnect/);
});
test('OAuth uses PKCE, offline consent, exact redirect, form POST and minimal Ads scope',async()=>{
 const {provider:p,calls}=mock([{...tokens,refresh_token_expires_in:7200},{...tokens,scope:undefined,refresh_token:undefined}]);
 const u=new URL(p.authorizationUrl('state-fixture','challenge-fixture'));assert.equal(u.origin,'https://accounts.google.com');assert.equal(u.searchParams.get('code_challenge_method'),'S256');assert.equal(u.searchParams.get('scope'),googleAdsScope);assert.equal(u.searchParams.get('access_type'),'offline');assert.equal(u.searchParams.get('prompt'),'consent select_account');assert.equal(u.searchParams.get('redirect_uri'),cfg.callback);
 assert.deepEqual(await p.exchange('code-fixture','verifier-fixture'),{refresh_token:'refresh-fixture',refresh_expires_at:new Date(8200000).toISOString()});assert.equal(await p.refresh('refresh-fixture'),'access-fixture');
 for(const {url,options} of calls){assert.equal(url.href,'https://oauth2.googleapis.com/token');assert.equal(options.method,'POST');assert.equal(options.redirect,'error');assert(options.signal);assert.equal(url.search,'');}
 const initial=new URLSearchParams(calls[0].options.body);assert.equal(initial.get('code_verifier'),'verifier-fixture');assert.equal(initial.get('redirect_uri'),cfg.callback);assert.equal(initial.get('client_secret'),cfg.secret);
 const refresh=new URLSearchParams(calls[1].options.body);assert.equal(refresh.get('refresh_token'),'refresh-fixture');assert.equal(refresh.get('grant_type'),'refresh_token');assert.equal(refresh.get('code'),null);
});
test('Missing permission, refresh token and invalid token expiry fail before storage',async()=>{
 for(const change of [{scope:'https://example.com/wrong'},{refresh_token:undefined},{access_token:'bad\nheader'},{expires_in:30},{expires_in:'3600'},{token_type:'DPoP'},{refresh_token_expires_in:-1}]){const {provider}=mock([{...tokens,...change}]);await assert.rejects(provider.exchange('code','verifier'));}
 const {provider}=mock([{...tokens,scope:'other'}]);await assert.rejects(provider.refresh('refresh'),/permission/);
});
test('Direct account and nested manager clients use fixed queries and correct login customer header',async()=>{
 let {provider:p,calls}=mock([{resourceNames:['customers/'+root]},{results:[{customer:{...raw,id:root}}]}]);assert.deepEqual(await p.roots('access'),[root]);const direct=await p.accounts('access',root);assert.equal(direct.accounts[0].id,root);assert.equal(direct.accounts[0].test_account,false);assert.equal(calls[0].options.headers['login-customer-id'],undefined);assert.equal(calls[1].options.headers['login-customer-id'],undefined);
 ({provider:p,calls}=mock([{results:[{customer:{...raw,id:root,manager:true}}]},{results:[{customerClient:raw}],nextPageToken:'opaque-page'},{results:[{customerClient:{...raw,id:'5555555555',testAccount:true}}]},{results:[{customer:raw}]}]));
 const result=await p.accounts('access',root);assert.equal(result.accounts.length,2);assert.equal(result.accounts[1].test_account,true);assert.equal(calls[1].options.headers['login-customer-id'],root);
 const query=JSON.parse(calls[1].options.body).query;assert(query.includes('customer_client.manager = FALSE'));assert(!query.includes('level'));assert(query.endsWith('LIMIT 501'));
 assert.equal(JSON.parse(calls[2].options.body).pageToken,'opaque-page');await p.account('access',id,root);assert.equal(calls[3].options.headers['login-customer-id'],root);
 for(const call of calls){assert.equal(call.url.hostname,'googleads.googleapis.com');assert.equal(call.url.search,'');assert.equal(call.options.headers.Authorization,'Bearer access');assert.equal(call.options.headers['developer-token'],cfg.developerToken);assert.equal(call.options.redirect,'error');}
});
test('Pagination, duplicate IDs, incorrect target and oversized lists fail without returning partial account lists',async()=>{
 const manager={results:[{customer:{...raw,id:root,manager:true}}]};
 for(const pages of [
  [manager,{results:[{customerClient:raw}],nextPageToken:'same'},{results:[],nextPageToken:'same'}],
  [manager,{results:[{customerClient:raw},{customerClient:raw}]}],
  [manager,{results:[{customerClient:{...raw,manager:true}}]}],
  [manager,{results:Array.from({length:501},(_,i)=>({customerClient:{...raw,id:String(1000000000+i)}}))}],
  [manager,...Array.from({length:5},(_,i)=>({results:[],nextPageToken:'page-'+i}))],
 ])await assert.rejects(mock(pages).provider.accounts('access',root));
 await assert.rejects(mock([{results:[{customer:raw}]}]).provider.account('access',root),/confirm access/);
 await assert.rejects(mock([{resourceNames:['https://evil.example/steal']}]).provider.roots('access'));
 await assert.rejects(mock([{resourceNames:Array(501).fill('customers/'+root)}]).provider.roots('access'));
 await assert.rejects(mock([]).provider.account('access','../../evil'),/available/);
});
test('Provider failures are redacted, oversized bodies bounded, and only revoked OAuth forces reconnect',async()=>{
 const secret='sensitive-provider-token';
 for(const response of [new Response(JSON.stringify({error:'invalid_grant',error_description:secret}),{status:400}),new Response(JSON.stringify({error:{message:secret}}),{status:401})]){
  const p=mock([response]).provider;await assert.rejects(response.status===400?p.refresh('refresh'):p.roots('access'),e=>e instanceof GoogleAdsAccessError&&!e.message.includes(secret));
 }
 for(const code of [403,429,500]){const p=mock([new Response(JSON.stringify({error:{message:secret}}),{status:code})]).provider;await assert.rejects(p.roots('access'),e=>!(e instanceof GoogleAdsAccessError)&&!e.message.includes(secret));}
 await assert.rejects(mock([new Response('x'.repeat(2*1024*1024+1))]).provider.roots('access'),/unreadable/);
 await assert.rejects(mock([new Error(secret)]).provider.roots('access'),e=>!e.message.includes(secret));
});
