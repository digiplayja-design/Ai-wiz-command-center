import test from 'node:test';
import assert from 'node:assert/strict';
import {readMetaInsights} from '../funnels/meta_performance.mjs';
import {createMetaProvider,metaConfiguration} from '../funnels/meta.mjs';
const account={id:'act_123',currency:'KWD'},range={from:'2026-09-01',to:'2026-09-07',days:7};
const row=(patch={})=>({account_id:'123',account_currency:'KWD',campaign_id:'456',campaign_name:'Summer campaign',date_start:range.from,date_stop:range.to,spend:'0.123456',impressions:'20',clicks:'3',...patch});
const read=graph=>readMetaInsights(graph,'fixture-token',account,range,'campaign');
test('Campaign reporting uses account-scoped full-period insights and exact totals across fixed-host cursor pages',async()=>{
 const calls=[],pages=[{data:[row()],paging:{next:'https://untrusted.example/ignored',cursors:{after:'opaque'}}},{data:[row({campaign_id:'789',campaign_name:'Summer campaign',spend:'0.20'})]}];
 const provider=createMetaProvider(metaConfiguration({KORLIX_META_API_VERSION:'v26.0',KORLIX_META_APP_SECRET:'fixture'}),{fetchImpl:async(url,options)=>{calls.push({url,options});return{ok:true,json:async()=>pages.shift()};}});
 const report=await provider.campaignInsights('fixture-token',account,range);
 assert.equal(report.reported_campaigns,2);assert(!('reported_days' in report));assert.deepEqual(report.totals,{spend:'0.323456',impressions:40,clicks:6});assert.deepEqual(report.rows.map(r=>r.campaign_id),['456','789']);assert.equal(report.rows[0].campaign_name,report.rows[1].campaign_name);
 for(const {url,options} of calls){assert.equal(url.origin,'https://graph.facebook.com');assert.equal(url.pathname,'/v26.0/act_123/insights');assert.equal(url.searchParams.get('level'),'campaign');assert.equal(url.searchParams.has('time_increment'),false);assert.equal(url.searchParams.has('filtering'),false);assert.deepEqual(JSON.parse(url.searchParams.get('time_range')),{since:range.from,until:range.to});assert.equal(url.searchParams.get('fields'),'account_id,account_currency,date_start,date_stop,spend,impressions,clicks,campaign_id,campaign_name');assert.equal(url.searchParams.get('limit'),'100');assert.equal(options.headers.Authorization,'Bearer fixture-token');assert.equal(options.redirect,'error');assert(url.searchParams.get('appsecret_proof'));assert(!url.searchParams.has('access_token'));assert.equal(options.method,undefined);}
 assert.equal(calls[1].url.searchParams.get('after'),'opaque');
});
test('Campaign identities, names, full reporting periods and metric/account consistency are mandatory',async()=>{
 for(const patch of [{campaign_id:null},{campaign_id:123},{campaign_id:'../other'},{campaign_id:'1'.repeat(41)},{campaign_name:null},{campaign_name:' '},{campaign_name:'x'.repeat(1001)},{date_start:'2026-09-02'},{date_stop:'2026-09-06'},{account_id:'999'},{account_currency:'USD'},{spend:null},{spend:'-1'},{clicks:'NaN'},{impressions:'2.5'}])await assert.rejects(read(async()=>({data:[row(),row({campaign_id:'789',...patch})]})),e=>e.status===503);
 for(const data of [null,{},'invalid'])await assert.rejects(read(async()=>({data})));
 await assert.rejects(readMetaInsights(async()=>({data:[]}),'t',account,range,'ad'));
});
test('Duplicate campaign IDs across pages cannot double-count while missing or repeated cursors fail completely',async()=>{
 let page=0;await assert.rejects(read(async()=>page++?{data:[row()]}:{data:[row()],paging:{next:'ignored',cursors:{after:'next'}}}));
 for(const paging of [{next:'ignored'},{next:'ignored',cursors:{after:'same'}}])await assert.rejects(read(async()=>({data:[],paging})));
});
test('Campaign reports accept exactly 300 rows but fail without partial totals when another page is required',async()=>{
 for(const overflow of [false,true]){
  let calls=0;
  const task=read(async()=>{const page=calls++;return{data:Array.from({length:100},(_,i)=>row({campaign_id:String(page*100+i+1)})),...(page<2||overflow?{paging:{next:'ignored',cursors:{after:'page-'+page}}}:{})};});
  if(overflow)await assert.rejects(task,/page limit/);else{const report=await task;assert.equal(report.reported_campaigns,300);assert.equal(report.rows.length,300);assert.equal(report.totals.spend,'37.0368');}
  assert.equal(calls,3);
 }
});
test('Campaign sums preserve micro-decimals and reject total count or spend overflow',async()=>{
 const report=await read(async()=>({data:[row({spend:'999999999999.000001'}),row({campaign_id:'789',spend:'0.000001'})]}));assert.equal(report.totals.spend,'999999999999.000002');
 for(const patch of [{impressions:'9007199254740991'},{spend:'1000000000000'}])await assert.rejects(read(async()=>({data:[row(patch),row({campaign_id:'789'})]})));
});
test('An empty campaign response remains distinct from a real campaign with zero reported metrics',async()=>{
 const empty=await read(async()=>({data:[]}));assert.deepEqual(empty.rows,[]);assert.equal(empty.reported_campaigns,0);
 const zero=await read(async()=>({data:[row({spend:'0',impressions:'0',clicks:'0'})]}));assert.equal(zero.reported_campaigns,1);assert.deepEqual(zero.totals,{spend:'0.00',impressions:0,clicks:0});
});
