import test from 'node:test';
import assert from 'node:assert/strict';
import {metaReportQuery,metaReportRange,readMetaInsights} from '../funnels/meta_performance.mjs';
import {createMetaProvider,metaConfiguration} from '../funnels/meta.mjs';
const account={id:'act_123',name:'Business',currency:'USD',timezone:'America/New_York'};
const range={from:'2026-09-01',to:'2026-09-07',days:7};
const row=(patch={})=>({account_id:'123',account_currency:'USD',date_start:'2026-09-01',date_stop:'2026-09-01',spend:'0.1',impressions:'20',clicks:'4',...patch});
test('Only bounded reporting periods and the current account/version are accepted',()=>{
 const q={days:'7',version:'3',account_id:'act_123'};assert.deepEqual(metaReportQuery(q),{days:7,version:3,account_id:'act_123'});
 for(const patch of [{days:'365'},{days:['7']},{version:'1e2'},{version:'0'},{account_id:'../me'},{fields:'access_token'},{account_id:['act_123']}])assert.throws(()=>metaReportQuery({...q,...patch}));
});
test('Completed account-calendar dates handle local midnight, DST and leap days without current-day partials',()=>{
 assert.deepEqual(metaReportRange(7,'America/New_York',Date.parse('2026-09-22T01:00:00Z')),{from:'2026-09-14',to:'2026-09-20',days:7});
 assert.deepEqual(metaReportRange(7,'Pacific/Kiritimati',Date.parse('2026-09-22T12:00:00Z')),{from:'2026-09-16',to:'2026-09-22',days:7});
 assert.deepEqual(metaReportRange(7,'America/New_York',Date.parse('2026-03-09T12:00:00Z')),{from:'2026-03-02',to:'2026-03-08',days:7});
 assert.equal(metaReportRange(7,'UTC',Date.parse('2024-03-01T12:00:00Z')).to,'2024-02-29');
 for(const timezone of ['',null,'Not/A_Timezone'])assert.throws(()=>metaReportRange(7,timezone));
});
test('Daily totals use exact decimals, selected currency and only validated returned rows',async()=>{
 const rows=[row(),row({date_start:'2026-09-02',date_stop:'2026-09-02',spend:'0.2',impressions:'30',clicks:'6'})];
 const r=await readMetaInsights(async()=>({data:rows}),'t',account,range);assert.deepEqual(r.totals,{spend:'0.30',impressions:50,clicks:10});assert.equal(r.reported_days,2);assert.deepEqual(r.rows.map(x=>x.date),['2026-09-02','2026-09-01']);
 const precise=await readMetaInsights(async()=>({data:[row({spend:'15.123456',account_currency:'KWD'})]}),'t',{...account,currency:'KWD'},range);assert.equal(precise.totals.spend,'15.123456');
 const empty=await readMetaInsights(async()=>({data:[]}),'t',account,range);assert.deepEqual(empty.rows,[]);assert.equal(empty.reported_days,0);
});
test('Mismatched accounts, currency, dates, missing metrics and invalid numeric values fail without partial results',async()=>{
 for(const patch of [{account_id:'999'},{account_currency:'EUR'},{date_start:'2026-08-30',date_stop:'2026-08-30'},{date_stop:'2026-09-03'},{spend:'-1'},{spend:'NaN'},{spend:'1e2'},{spend:'0.1234567'},{spend:'1000000000001'},{spend:null},{clicks:'-1'},{clicks:'2.5'},{impressions:'9007199254740992'},{impressions:3},{clicks:undefined}])await assert.rejects(readMetaInsights(async()=>({data:[row(),row({...patch,date_start:patch.date_start??'2026-09-02',date_stop:patch.date_stop??'2026-09-02'})]}),'t',account,range),e=>e.status===503);
 await assert.rejects(readMetaInsights(async()=>({data:[row(),row()]}),'t',account,range));
 await assert.rejects(readMetaInsights(async()=>({data:[row({date_start:'2026-02-30',date_stop:'2026-02-30'})]}),'t',account,{from:'2026-02-01',to:'2026-03-03',days:90}));
 await assert.rejects(readMetaInsights(async()=>({data:[row({impressions:'9007199254740991'}),row({date_start:'2026-09-02',date_stop:'2026-09-02'})]}),'t',account,range));
});
test('Graph insights use GET, fixed host, header token, exact fields and bounded cursor pagination',async()=>{
 const cfg=metaConfiguration({KORLIX_META_API_VERSION:'v26.0',KORLIX_META_APP_SECRET:'fixture-secret'}),calls=[];
 const pages=[{data:[row()],paging:{next:'https://evil.example/steal',cursors:{after:'cursor&access_token=not-a-token'}}},{data:[row({date_start:'2026-09-02',date_stop:'2026-09-02'})]}];
 const provider=createMetaProvider(cfg,{fetchImpl:async(url,options)=>{calls.push({url,options});return{ok:true,json:async()=>pages.shift()};}});
 const report=await provider.insights('fixture-token',account,range);assert.equal(report.reported_days,2);
 for(const {url,options} of calls){assert.equal(url.origin,'https://graph.facebook.com');assert.equal(url.pathname,'/v26.0/act_123/insights');assert.equal(url.searchParams.get('level'),'account');assert.equal(url.searchParams.get('time_increment'),'1');assert.deepEqual(JSON.parse(url.searchParams.get('time_range')),{since:range.from,until:range.to});assert.equal(options.headers.Authorization,'Bearer fixture-token');assert(url.searchParams.get('appsecret_proof'));assert(!url.searchParams.has('access_token'));assert.equal(options.redirect,'error');assert.equal(options.method,undefined);}
 assert.equal(calls[1].url.searchParams.get('after'),'cursor&access_token=not-a-token');
});
test('Missing, repeated and over-limit cursors fail; provider errors never expose token or payload',async()=>{
 for(const paging of [{next:'x'}, {next:'x',cursors:{after:''}}, {next:'x',cursors:{after:'same'}}])await assert.rejects(readMetaInsights(async()=>({data:[],paging}),'t',account,range));
 let n=0;await assert.rejects(readMetaInsights(async()=>({data:[],paging:{next:'x',cursors:{after:'cursor-'+(++n)}}}),'t',account,range),/page limit/);assert.equal(n,3);
 const cfg=metaConfiguration({KORLIX_META_APP_SECRET:'fixture'});
 for(const code of [190,4,100]){const p=createMetaProvider(cfg,{fetchImpl:async()=>({ok:false,json:async()=>({error:{code,message:'private-sensitive-token'}})})});await assert.rejects(p.insights('private-sensitive-token',account,range),e=>!e.message.includes('private-sensitive-token'));}
});
test('Performance has its own ten-per-minute request limit and platform setup remains a gate',async()=>{
 const {default:express}=await import('express');const {registerFunnels}=await import('../funnels/routes.mjs');const {tokenCipher}=await import('../funnels/meta.mjs');
 const user='00000000-0000-4000-8000-000000000001',binding='00000000-0000-4000-8000-000000000002';
 const environment={KORLIX_META_ENABLED:'true',KORLIX_META_APP_ID:'1234567',KORLIX_META_APP_SECRET:'fixture-secret-no-provider',KORLIX_META_LOGIN_CONFIG_ID:'7654321',KORLIX_META_TOKEN_KEY:Buffer.alloc(32,7).toString('base64'),KORLIX_META_REDIRECT_URI:'https://example.com/api/funnels/meta/callback'};
 const cfg=metaConfiguration(environment),c={version:1,config_hash:cfg.hash,expires_at:new Date(Date.now()+86400000).toISOString(),binding_id:binding,selected_account:account.id,accounts:[account],sealed:tokenCipher(cfg.key).seal('fixture-token',`korlix-meta:${user}:${binding}`)};
 for(const enabled of [true,false]){
  let reads=0;const app=express(),handler=registerFunnels(app,{environment:{...environment,KORLIX_META_ENABLED:enabled?'true':'false'},requireUser:async()=>({id:user}),metaStore:{command:async()=>c},metaProvider:{account:async()=>account,insights:async()=>{reads++;return{rows:[],totals:{spend:'0.00',impressions:0,clicks:0},reported_days:0};},campaignInsights:async()=>{reads++;return{rows:[],totals:{spend:'0.00',impressions:0,clicks:0},reported_campaigns:0};}}});
  const server=app.listen(0,'127.0.0.1');await new Promise(r=>server.once('listening',r));
  try{const url=`http://127.0.0.1:${server.address().port}/api/funnels/meta/performance?days=7&version=1&account_id=act_123`;
   if(enabled){for(let i=0;i<10;i++)assert.equal((await fetch(i%2?url.replace('/performance?','/campaign-performance?'):url)).status,200);assert.equal((await fetch(url)).status,429);assert.equal(reads,10);}
   else{assert.equal((await fetch(url)).status,503);assert.equal((await fetch(url.replace('/performance?','/campaign-performance?'))).status,503);assert.equal(reads,0);}
  }finally{handler.close();server.closeAllConnections();await new Promise(r=>server.close(r));}
 }
});
