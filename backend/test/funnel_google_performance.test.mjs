import test from 'node:test';
import assert from 'node:assert/strict';
import {googleReportQuery,googleReportRange,readGooglePerformance} from '../funnels/google_ads_performance.mjs';
import {createGoogleAdsProvider,googleAdsConfiguration,GoogleAdsAccessError} from '../funnels/google_ads_provider.mjs';
const account={id:'9876543210',name:'Advertiser',currency:'USD',timezone:'America/New_York',manager:false,status:'ENABLED',test_account:false},root='1234567890';
const range={from:'2026-09-14',to:'2026-09-20',days:7};
const row=(day='2026-09-20',metrics={costMicros:'1000001',impressions:'100',clicks:'7'})=>({customer:{id:account.id,currencyCode:account.currency,timeZone:account.timezone},segments:{date:day},metrics});
function load(pages,options={}){const calls=[];return{calls,result:readGooglePerformance(async(...args)=>{calls.push(args);return pages.shift();},'fixture-access',options.account||account,root,options.range||range)};}
test('Only bounded periods, current versions and numeric root/account IDs enter reporting',()=>{
 const good={days:'7',version:'12',account_id:account.id,root_id:root};assert.deepEqual(googleReportQuery(good),{days:7,version:12,account_id:account.id,root_id:root});
 for(const change of [{days:'365'},{days:['7']},{version:'1e2'},{version:'0'},{root_id:'../../x'},{account_id:'act_123'},{query:'SELECT secret'},{fields:'token'}])assert.throws(()=>googleReportQuery({...good,...change}));
});
test('Completed account days handle UTC midnight, DST and leap dates',()=>{
 assert.deepEqual(googleReportRange(7,'America/Los_Angeles',Date.parse('2026-09-22T01:00:00Z')),{from:'2026-09-14',to:'2026-09-20',days:7});
 assert.deepEqual(googleReportRange(7,'Pacific/Kiritimati',Date.parse('2026-09-22T12:00:00Z')),{from:'2026-09-16',to:'2026-09-22',days:7});
 assert.deepEqual(googleReportRange(7,'America/New_York',Date.parse('2026-03-09T05:00:00Z')),{from:'2026-03-02',to:'2026-03-08',days:7});
 assert.equal(googleReportRange(7,'UTC',Date.parse('2028-03-01T12:00:00Z')).to,'2028-02-29');
 assert.throws(()=>googleReportRange(7,'not/a/timezone'));assert.throws(()=>googleReportRange(1,'UTC'));
});
test('Daily reports retain exact micros, accept omitted scalar zeros, sort dates and sum returned rows only',async()=>{
 const {result,calls}=load([{results:[row('2026-09-18'),row('2026-09-20',{costMicros:'123456789012345678',impressions:0})],nextPageToken:'opaque-page'},{results:[row('2026-09-19',{clicks:'2'})]}]);
 const report=await result;assert.deepEqual(report.totals,{spend:'123456789013.345679',impressions:100,clicks:9});assert.equal(report.reported_days,3);assert.deepEqual(report.rows.map(r=>r.date),['2026-09-20','2026-09-19','2026-09-18']);assert.equal(report.rows[1].spend,'0.00');
 assert.equal(calls[0][0],`customers/${account.id}/googleAds:search`);assert.equal(calls[0][2],root);assert.equal(calls[0][3].query,calls[1][3].query);assert.equal(calls[1][3].pageToken,'opaque-page');
 assert(calls[0][3].query.includes('FROM customer'));assert(calls[0][3].query.includes("segments.date BETWEEN '2026-09-14' AND '2026-09-20'"));assert(!Object.hasOwn(calls[0][3],'pageSize'));
 assert.deepEqual(await load([{}]).result,{rows:[],totals:{spend:'0.00',impressions:0,clicks:0},reported_days:0});
});
test('The reporting adapter uses the configured fixed Google host, POST, manager header and access-token header',async()=>{
 const env={KORLIX_GOOGLE_ADS_ENABLED:'true',KORLIX_GOOGLE_ADS_CLIENT_ID:'12345-fixture.apps.googleusercontent.com',KORLIX_GOOGLE_ADS_CLIENT_SECRET:'fixture-client-secret',KORLIX_GOOGLE_ADS_ACCESS_MODEL:'cloud_project',KORLIX_GOOGLE_ADS_TOKEN_KEY:Buffer.alloc(32,8).toString('base64'),KORLIX_GOOGLE_ADS_REDIRECT_URI:'https://example.com/api/funnels/google-ads/callback'};
 const calls=[];const p=createGoogleAdsProvider(googleAdsConfiguration(env),{fetchImpl:async(url,options)=>{calls.push({url,options});return new Response(JSON.stringify({results:[row()]}));}});
 await p.performance('fixture-token',account,root,range);const {url,options}=calls[0];assert.equal(url.href,`https://googleads.googleapis.com/v25/customers/${account.id}/googleAds:search`);assert.equal(options.method,'POST');assert.equal(options.redirect,'error');assert(options.signal);assert.equal(options.headers.Authorization,'Bearer fixture-token');assert.equal(options.headers['login-customer-id'],root);assert(!Object.hasOwn(options.headers,'developer-token'));
});
test('Mismatched account, currency, timezone, date and malformed metrics fail without partial results',async()=>{
 const changes=[r=>r.customer.id=root,r=>r.customer.currencyCode='EUR',r=>r.customer.timeZone='UTC',r=>r.segments.date='2026-09-21',r=>r.segments.date='2026-02-30',r=>r.metrics=null,r=>r.metrics.costMicros='-1',r=>r.metrics.impressions='1.5',r=>r.metrics.clicks=null,r=>r.metrics.clicks=9007199254740992,r=>r.metrics.costMicros='1000000000000000001'];
 for(const change of changes){const broken=row('2026-09-19');change(broken);await assert.rejects(load([{results:[row()] ,nextPageToken:'p'},{results:[broken]}]).result,/inconsistent/);}
 await assert.rejects(load([{results:null}]).result,/inconsistent/);
 await assert.rejects(load([{results:[row()]}],{range:{...range,from:"2026-09-14' OR 1=1"}}).result,/inconsistent/);
});
test('Duplicate days, repeated/invalid cursors, row bounds and third-page continuation reject the whole report',async()=>{
 for(const pages of [
  [{results:[row(),row()]}],
  [{results:[row()],nextPageToken:'same'},{results:[],nextPageToken:'same'}],
  [{results:[],nextPageToken:null}],
  [{results:[],nextPageToken:4}],
  [{results:[],nextPageToken:'a'},{results:[],nextPageToken:'b'},{results:[],nextPageToken:'c'}],
  [{results:Array.from({length:8},(_,i)=>row(`2026-09-${13+i}`))}],
 ])await assert.rejects(load(pages).result);
});
test('Totals cannot overflow exact supported spend or counts across individually valid rows',async()=>{
 for(const metrics of [{costMicros:'1000000000000000000'},{impressions:String(Number.MAX_SAFE_INTEGER)},{clicks:String(Number.MAX_SAFE_INTEGER)}])await assert.rejects(load([{results:[row('2026-09-19',metrics),row('2026-09-20',metrics)]}]).result,/inconsistent/);
});
test('Reporting preserves Google revoked-access errors for version-guarded reconnect handling',async()=>{
 const p=createGoogleAdsProvider({apiVersion:'v25',developerToken:'fixture'},{fetchImpl:async()=>new Response(JSON.stringify({error:{message:'sensitive-token'}}),{status:401})});
 await assert.rejects(p.performance('fixture',account,root,range),e=>e instanceof GoogleAdsAccessError&&!e.message.includes('sensitive-token'));
});
