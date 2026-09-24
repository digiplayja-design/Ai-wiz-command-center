import test from 'node:test';
import assert from 'node:assert/strict';
import {googleAdsConfiguration} from '../funnels/google_ads_provider.mjs';
import {googleUploadConfiguration,googleUploadScopes,createGoogleUploadProvider,GoogleUploadAccessError} from '../funnels/google_upload_provider.mjs';
const env={KORLIX_GOOGLE_ADS_ENABLED:'true',KORLIX_GOOGLE_ADS_ACCESS_MODEL:'cloud_project',KORLIX_GOOGLE_ADS_CLIENT_ID:'fixture-google-client.apps.googleusercontent.com',KORLIX_GOOGLE_ADS_CLIENT_SECRET:'fixture-google-secret',KORLIX_GOOGLE_ADS_TOKEN_KEY:Buffer.alloc(32,7).toString('base64'),KORLIX_GOOGLE_ADS_REDIRECT_URI:'https://example.com/api/funnels/google-ads/callback',KORLIX_GOOGLE_UPLOAD_AUTH_ENABLED:'true',KORLIX_GOOGLE_UPLOAD_REDIRECT_URI:'https://example.com/api/funnels/google-upload-access/callback'},config=googleUploadConfiguration(env);
const body=()=>({access_token:'private-access',token_type:'Bearer',expires_in:3600,refresh_token:'private-refresh',scope:googleUploadScopes.join(' ')});
const provider=(value,status=200)=>createGoogleUploadProvider(config,{fetchImpl:async()=>new Response(JSON.stringify(value),{status})});
test('K191 upload authorization has an independent default-off gate and callback, without changing Ads configuration',()=>{
 assert(config.ready);assert.equal(googleUploadConfiguration({}).ready,false);for(const patch of [{KORLIX_GOOGLE_UPLOAD_AUTH_ENABLED:'false'},{KORLIX_GOOGLE_ADS_ENABLED:'false'},{KORLIX_GOOGLE_UPLOAD_REDIRECT_URI:env.KORLIX_GOOGLE_ADS_REDIRECT_URI},{KORLIX_GOOGLE_UPLOAD_REDIRECT_URI:'http://example.com/api/funnels/google-upload-access/callback'},{KORLIX_GOOGLE_UPLOAD_REDIRECT_URI:env.KORLIX_GOOGLE_UPLOAD_REDIRECT_URI+'?x=1'},{KORLIX_GOOGLE_ADS_API_VERSION:'v24'}])assert.equal(googleUploadConfiguration({...env,...patch}).ready,false);
 const prior={...env};delete prior.KORLIX_GOOGLE_UPLOAD_AUTH_ENABLED;delete prior.KORLIX_GOOGLE_UPLOAD_REDIRECT_URI;assert.deepEqual(googleAdsConfiguration(prior),googleAdsConfiguration(env));assert.notEqual(config.hash,config.ads.hash);
});
test('K191 authorization URL requests exactly two explicit scopes, offline consent and PKCE with a separate callback',()=>{
 const u=new URL(createGoogleUploadProvider(config).authorizationUrl('fixture-state','fixture-challenge'));assert.equal(u.origin,'https://accounts.google.com');assert.equal(u.pathname,'/o/oauth2/v2/auth');assert.equal(u.searchParams.get('redirect_uri'),config.callback);assert.deepEqual(u.searchParams.get('scope').split(' '),googleUploadScopes);assert.equal(u.searchParams.get('access_type'),'offline');assert.equal(u.searchParams.get('prompt'),'consent select_account');assert.equal(u.searchParams.get('code_challenge_method'),'S256');assert(!u.href.includes(config.secret));
});
test('K191 token exchange uses fixed POST transport and scope checking; refresh supports omitted unchanged scope',async()=>{
 const calls=[],p=createGoogleUploadProvider(config,{now:()=>1000000,fetchImpl:async(url,o)=>{calls.push({url,o});return new Response(JSON.stringify({...body(),refresh_token_expires_in:7200}));}});
 assert.deepEqual(await p.exchange('private-code','private-verifier'),{refresh_token:'private-refresh',scopes:[...googleUploadScopes],refresh_expires_at:new Date(8200000).toISOString()});assert.equal(await p.refresh('private-refresh'),'private-access');
 for(const {url,o}of calls){assert.equal(url.href,'https://oauth2.googleapis.com/token');assert.equal(o.method,'POST');assert.equal(o.redirect,'error');assert(o.signal);assert.equal(o.headers['Content-Type'],'application/x-www-form-urlencoded');const values=new URLSearchParams(o.body);assert.equal(values.get('client_secret'),config.secret);}
 assert.equal(new URLSearchParams(calls[0].o.body).get('code_verifier'),'private-verifier');assert.equal(new URLSearchParams(calls[1].o.body).get('grant_type'),'refresh_token');
 const b=body();delete b.scope;assert.equal(await provider(b).refresh('r'),'private-access');await assert.rejects(provider(b).exchange('c','v'),/both/);
});
test('K191 partial grants, malformed tokens and invalid expiration fail before storage',async()=>{
 for(const patch of [{scope:googleUploadScopes[0]},{scope:googleUploadScopes[1]},{scope:null},{access_token:'bad token'},{token_type:'Basic'},{expires_in:60},{expires_in:Infinity},{refresh_token:''},{refresh_token_expires_in:0},{refresh_token_expires_in:'3600'}])await assert.rejects(provider({...body(),...patch}).exchange('c','v'));
 await assert.rejects(provider({...body(),scope:googleUploadScopes[0]}).refresh('r'),/both/);
});
test('K191 OAuth revocation is distinct from generic errors and provider bodies stay redacted',async()=>{
 await assert.rejects(provider({error:'invalid_grant'},400).refresh('r'),GoogleUploadAccessError);
 for(const [data,status]of [[{error:'private-provider-body'},500],[{error:{message:'private-provider-body'}},403],[{error:'private-provider-body'},429]])await assert.rejects(provider(data,status).exchange('c','v'),e=>!e.message.includes('private-provider-body')&&[429,503].includes(e.status));
 for(const response of [new Response('not json'),new Response(JSON.stringify([])),new Response('x'.repeat(128*1024+1))]){const p=createGoogleUploadProvider(config,{fetchImpl:async()=>response});await assert.rejects(p.exchange('c','v'),/could not be reached or read/);}
});
