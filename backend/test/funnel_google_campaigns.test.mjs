import test from 'node:test';
import assert from 'node:assert/strict';
import {readGooglePerformance} from '../funnels/google_ads_performance.mjs';
import {createGoogleAdsProvider,GoogleAdsAccessError} from '../funnels/google_ads_provider.mjs';
const account={id:'9876543210',name:'Advertiser',currency:'USD',timezone:'America/New_York'},root='1234567890';
const range={from:'2026-09-14',to:'2026-09-20',days:7};
const row=(id='1000',metrics={costMicros:'1000001',impressions:'100',clicks:'7'})=>({customer:{id:account.id,currencyCode:account.currency,timeZone:account.timezone},campaign:{id,resourceName:`customers/${account.id}/campaigns/${id}`,name:'Campaign '+id,status:'ENABLED',advertisingChannelType:'SEARCH'},metrics});
function load(pages,options={}){const calls=[];return{calls,result:readGooglePerformance(async(...args)=>{calls.push(args);return pages.shift();},'fixture-access',options.account||account,root,options.range||range,'campaign')};}
test('Campaign totals aggregate the entire range with exact micros and campaign IDs beyond JS precision',async()=>{
 const r1=row('9223372036854775807',{costMicros:'123456789012345678',impressions:100,clicks:0});r1.campaign.status='REMOVED';r1.campaign.advertisingChannelType='PERFORMANCE_MAX';
 const r2=row('1001',{clicks:'2'});r2.campaign.status='PAUSED';
 const {result,calls}=load([{results:[r1,row()],nextPageToken:'opaque-page'},{results:[r2]}]);const data=await result;
 assert.deepEqual(data.totals,{spend:'123456789013.345679',impressions:200,clicks:9});assert.equal(data.reported_campaigns,3);assert.equal(data.reported_days,undefined);assert.deepEqual(data.rows.map(r=>r.campaign_id),['1000','1001','9223372036854775807']);assert.equal(data.rows[2].status,'REMOVED');assert.equal(data.rows[1].spend,'0.00');assert(data.rows.every(r=>r.date===undefined));
 const query=calls[0][3].query;assert.match(query,/FROM campaign/);assert.match(query,/LIMIT 501$/);assert.match(query,/ORDER BY campaign.id ASC/);assert(!query.split(' FROM ')[0].includes('segments.'));assert.match(query,/segments.date BETWEEN '2026-09-14' AND '2026-09-20'/);assert.match(query,/campaign.resource_name/);assert(!query.includes('include_drafts=true'));assert(!query.includes('campaign.status IN'));
 assert.equal(query,calls[1][3].query);assert.equal(calls[1][3].pageToken,'opaque-page');assert.equal(calls[0][0],`customers/${account.id}/googleAds:search`);assert.equal(calls[0][2],root);assert(!Object.hasOwn(calls[0][3],'pageSize'));
});
test('Empty campaign results remain empty and returned scalar zeros produce exact zero totals',async()=>{
 assert.deepEqual(await load([{}]).result,{rows:[],totals:{spend:'0.00',impressions:0,clicks:0},reported_campaigns:0});
 const report=await load([{results:[row('1000',{})]}]).result;assert.equal(report.reported_campaigns,1);assert.deepEqual(report.totals,{spend:'0.00',impressions:0,clicks:0});
});
test('Campaign provider adapter uses the fixed Google REST host, POST, manager context and redacts revoked errors',async()=>{
 const calls=[];const p=createGoogleAdsProvider({apiVersion:'v25',developerToken:'fixture-developer'},{fetchImpl:async(url,options)=>{calls.push({url,options});return new Response(JSON.stringify({results:[row()]}));}});
 await p.campaignPerformance('fixture-access',account,root,range);const {url,options}=calls[0];assert.equal(url.href,`https://googleads.googleapis.com/v25/customers/${account.id}/googleAds:search`);assert.equal(options.method,'POST');assert.equal(options.redirect,'error');assert(options.signal);assert.equal(options.headers.Authorization,'Bearer fixture-access');assert.equal(options.headers['login-customer-id'],root);assert.equal(options.headers['developer-token'],'fixture-developer');assert.match(JSON.parse(options.body).query,/FROM campaign/);
 const denied=createGoogleAdsProvider({apiVersion:'v25',developerToken:'fixture'},{fetchImpl:async()=>new Response(JSON.stringify({error:{message:'sensitive-token'}}),{status:401})});
 await assert.rejects(denied.campaignPerformance('fixture',account,root,range),e=>e instanceof GoogleAdsAccessError&&!e.message.includes('sensitive-token'));
});
test('Campaign metadata, resource ownership, metrics and unexpected daily segmentation fail without partial results',async()=>{
 const changes=[r=>r.customer.id=root,r=>r.customer.currencyCode='EUR',r=>r.customer.timeZone='UTC',r=>r.campaign=null,r=>r.campaign.id=1001,r=>r.campaign.id='0',r=>r.campaign.id='01',r=>r.campaign.id='9223372036854775808',r=>r.campaign.id='../../secret',r=>r.campaign.resourceName=`customers/${root}/campaigns/1001`,r=>r.campaign.name='',r=>r.campaign.name='a'.repeat(1001),r=>r.campaign.status='invented',r=>r.campaign.advertisingChannelType='bad',r=>r.segments={date:range.to},r=>r.metrics=null,r=>r.metrics.costMicros='-1',r=>r.metrics.costMicros='1000000000000000001',r=>r.metrics.impressions='1.5',r=>r.metrics.clicks=null,r=>r.metrics.clicks=9007199254740992];
 for(const change of changes){const bad=row('1001');change(bad);await assert.rejects(load([{results:[row()],nextPageToken:'p'},{results:[bad]}]).result,/inconsistent/);}
 await assert.rejects(load([{results:null}]).result,/inconsistent/);
 await assert.rejects(load([{results:[row()]}],{range:{...range,from:"2026-09-14' OR 1=1"}}).result,/inconsistent/);
});
test('Campaign reporting supports 500 unique rows across five pages and rejects excess instead of truncating',async()=>{
 const rows=Array.from({length:500},(_,i)=>row(String(1000+i),{costMicros:'1',impressions:'1',clicks:'1'}));
 const pages=Array.from({length:5},(_,i)=>({results:rows.slice(i*100,(i+1)*100),...(i<4?{nextPageToken:'page'+i}:{})}));
 const result=await load(pages).result;assert.equal(result.reported_campaigns,500);assert.deepEqual(result.totals,{spend:'0.0005',impressions:500,clicks:500});
 await assert.rejects(load([{results:[...rows,row('2000')]}]).result,/more than 500/);
 await assert.rejects(load([{results:rows,nextPageToken:'extra'},{results:[row('2000')]}]).result,/more than 500/);
});
test('Duplicate campaigns, repeated cursors and a sixth page reject the entire campaign report',async()=>{
 for(const pages of [[{results:[row(),row()]}],[{results:[row()],nextPageToken:'p'},{results:[row()]}],[{results:[],nextPageToken:'same'},{results:[],nextPageToken:'same'}],[{nextPageToken:null}],[{nextPageToken:4}],Array.from({length:5},(_,i)=>({results:[row(String(1000+i))],nextPageToken:'page'+i}))])await assert.rejects(load(pages).result);
});
test('Campaign totals reject aggregate metric overflow even when every individual row is valid',async()=>{
 for(const metrics of [{costMicros:'1000000000000000000'},{impressions:String(Number.MAX_SAFE_INTEGER)},{clicks:String(Number.MAX_SAFE_INTEGER)}])await assert.rejects(load([{results:[row('1000',metrics),row('1001',metrics)]}]).result,/inconsistent/);
});
