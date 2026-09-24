import test from 'node:test';
import assert from 'node:assert/strict';
import {createGoogleAdsProvider} from '../funnels/google_ads_provider.mjs';
import {googleConversionMethods,googleDestination,googleDestinationList} from '../funnels/google_conversion_provider.mjs';
const advertiser='1234567890',root='9999999999',conversion='8888888888';
const tracking=(owner=conversion,status='CONVERSION_TRACKING_MANAGED_BY_ANOTHER_MANAGER')=>({results:[{customer:{id:advertiser,conversionTrackingSetting:{googleAdsConversionCustomer:'customers/'+owner,conversionTrackingStatus:status}}}]});
const raw=(id='9223372036854775807',owner=conversion)=>({resourceName:`customers/${owner}/conversionActions/${id}`,id,ownerCustomer:'customers/'+owner,name:'Inquiry submitted',status:'ENABLED',type:'UPLOAD_CLICKS',category:'SUBMIT_LEAD_FORM',countingType:'ONE_PER_CLICK',primaryForGoal:false,clickThroughLookbackWindowDays:'30',attributionModelSettings:{attributionModel:'GOOGLE_ADS_LAST_CLICK'},valueSettings:{defaultValue:0,defaultCurrencyCode:'USD',alwaysUseDefaultValue:false}});
const expected=(owner=conversion)=>({conversion_customer_id:owner,conversion_action_id:'9223372036854775807',resource_name:`customers/${owner}/conversionActions/9223372036854775807`,name:'Inquiry submitted',status:'ENABLED',type:'UPLOAD_CLICKS',category:'SUBMIT_LEAD_FORM',counting_type:'ONE_PER_CLICK',primary_for_goal:false,click_window_days:30,attribution_model:'GOOGLE_ADS_LAST_CLICK',default_value:0,default_currency:'USD',always_use_default_value:false});
function mock(bodies){const calls=[];return{calls,p:googleConversionMethods(async(...args)=>{calls.push(args);return bodies.shift();})};}
test('K190 discovery follows the conversion owner, preserves int64 IDs, uses only fixed queries and rechecks owner',async()=>{
 const {p,calls}=mock([tracking(),{results:[{conversionAction:raw()}]},tracking()]);
 assert.deepEqual(await p.conversionDestinations('token',{id:advertiser},root),[expected()]);assert.equal(calls.length,3);assert.equal(calls[1][0],`customers/${conversion}/googleAds:search`);assert(calls.every(c=>c[2]===root));assert(calls.every(c=>!c[3].mutateOperations));assert.match(calls[1][3].query,/SUBMIT_LEAD_FORM/);assert.match(calls[1][3].query,/LIMIT 201$/);
});
test('K190 self-owned and root-owned tracking use exact owner IDs and optional protobuf zeros',async()=>{
 for(const [owner,manager,status]of [[advertiser,null,'CONVERSION_TRACKING_MANAGED_BY_SELF'],[root,root,'CONVERSION_TRACKING_MANAGED_BY_THIS_MANAGER']]){
  const a=raw(undefined,owner);a.valueSettings={};const {p,calls}=mock([tracking(owner,status),{results:[{conversionAction:a}]},tracking(owner,status)]);
  assert.deepEqual(await p.conversionDestinations('a',{id:advertiser},manager),[{...expected(owner),default_currency:''}]);assert(calls.every(c=>c[2]===manager));
 }
});
test('K190 empty eligible actions are explicit; paging, duplicates, overflow and partial lists never escape',async()=>{
 assert.deepEqual(await mock([tracking(),{},tracking()]).p.conversionDestinations('a',{id:advertiser},root),[]);
 const bodies=[tracking(),{results:[{conversionAction:raw('1')}],nextPageToken:'page'}, {results:[{conversionAction:raw('2')}]},tracking()];
 assert.equal((await mock(bodies).p.conversionDestinations('a',{id:advertiser},root)).length,2);
 for(const pages of [
  [{results:[{conversionAction:raw()},{conversionAction:raw()}]}],
  [{results:Array.from({length:201},(_,i)=>({conversionAction:raw(String(i+1))}))}],
  [{results:[],nextPageToken:'same'},{results:[],nextPageToken:'same'}],
  Array.from({length:5},(_,i)=>({nextPageToken:'page'+i})),
  [{results:{}}],
 ])await assert.rejects(mock([tracking(),...pages,tracking()]).p.conversionDestinations('a',{id:advertiser},root));
});
test('K190 malformed/foreign actions, unknown settings and unsupported categories fail closed',async()=>{
 for(const change of [a=>a.ownerCustomer='customers/1111111111',a=>a.resourceName='customers/1111111111/conversionActions/1',a=>a.id='9223372036854775808',a=>a.status='REMOVED',a=>a.type='WEBPAGE',a=>a.category='PURCHASE',a=>delete a.primaryForGoal,a=>a.primaryForGoal='false',a=>a.clickThroughLookbackWindowDays='91',a=>a.valueSettings.defaultValue=-1,a=>a.valueSettings.defaultValue=null,a=>a.valueSettings.alwaysUseDefaultValue=null,a=>a.attributionModelSettings.attributionModel='EXTERNAL',a=>a.name='private\ninvalid']){
  const a=raw();change(a);await assert.rejects(mock([tracking(),{results:[{conversionAction:a}]},tracking()]).p.conversionDestinations('a',{id:advertiser},root));
 }
 const d=expected();assert.deepEqual(googleDestination(d),d);for(const patch of [{unknown:1},{default_value:Infinity},{click_window_days:1.5},{name:' trailing '},{default_currency:'usd'}])assert.throws(()=>googleDestination({...d,...patch}));
 assert.throws(()=>googleDestinationList([d,{...expected(root),conversion_action_id:'1',resource_name:`customers/${root}/conversionActions/1`}]));
});
test('K190 conversion-account drift, unknown/disabled tracking and mismatched customer cannot return choices',async()=>{
 const changed=tracking(root,'CONVERSION_TRACKING_MANAGED_BY_THIS_MANAGER');
 await assert.rejects(mock([tracking(),{results:[]},changed]).p.conversionDestinations('a',{id:advertiser},root),/changed/);
 for(const r of [tracking(conversion,'NOT_CONVERSION_TRACKED'),tracking(conversion,'UNKNOWN'),tracking(conversion,'CONVERSION_TRACKING_MANAGED_BY_SELF'),tracking(conversion,'CONVERSION_TRACKING_MANAGED_BY_THIS_MANAGER'),{results:[]},{...tracking(),nextPageToken:'more'}])await assert.rejects(mock([r]).p.conversionDestinations('a',{id:advertiser},root));
});
test('K190 actual transport is read-only, bounded, uses manager header and never sends retired developer token',async()=>{
 const bodies=[tracking(),{results:[{conversionAction:raw()}]},tracking()],calls=[];
 const p=createGoogleAdsProvider({apiVersion:'v25',developerToken:'never-send'},{fetchImpl:async(url,o)=>{calls.push({url,o});return new Response(JSON.stringify(bodies.shift()));}});
 assert.equal((await p.conversionDestinations('fixture',{id:advertiser},root)).length,1);
 for(const {url,o} of calls){assert.equal(url.hostname,'googleads.googleapis.com');assert.equal(url.search,'');assert.equal(o.redirect,'error');assert(o.signal);assert.equal(o.headers.Authorization,'Bearer fixture');assert.equal(o.headers['login-customer-id'],root);assert(!Object.hasOwn(o.headers,'developer-token'));assert(url.pathname.endsWith('/googleAds:search'));}
});
