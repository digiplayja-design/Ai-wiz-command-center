import test from 'node:test';
import assert from 'node:assert/strict';
import {googlePausedRequest,googlePausedMethods,creationResources} from '../funnels/google_paused_provider.mjs';
import {createGoogleAdsProvider} from '../funnels/google_ads_provider.mjs';
import {googleControlRequest,googleControlsMethods} from '../funnels/google_controls_provider.mjs';
const clone=v=>structuredClone(v);
const snapshot=()=>({plan:{id:'00000000-0000-4000-8000-000000000003',daily_cents:2500,days:14},page:{destination:'https://example.com/f/services?utm_source=google&utm_medium=paid&utm_campaign=k143_00000000000040008000000000000003'},identity:{root_id:'1234567890',login_customer_id:'1234567890',account:{id:'9876543210',currency:'USD',timezone:'America/New_York',manager:false,status:'ENABLED',test_account:false}},creative:{headlines:['Meet the team','Explore services','Start here'],descriptions:['Find support for your business.','Talk with our team today.'],path1:'services',path2:''},keywords:{exact:['service'],phrase:['business support'],broad:[],negative_exact:['free'],negative_phrase:[],negative_broad:[]},targeting:{countries:['US','JM'],excluded_countries:['CA'],content_languages:['en','es'],location_mode:'presence',bidding:'maximize_clicks'},start_date:'2026-11-01',end_date:'2026-11-14',provider_name:'KORLIX 00000000-0000-4000-8000-000000000099',no_eu_political_ads:true,budget_acknowledged:true});
const expected={budget:'customers/9876543210/campaignBudgets/101',campaign:'customers/9876543210/campaigns/102',ad_group:'customers/9876543210/adGroups/103',ad:'customers/9876543210/adGroupAds/103~104'};
function mutationResponse(body){return {mutateOperationResponses:body.mutateOperations.map((op,n)=>{
 const key=Object.keys(op)[0],type=key.replace('Operation','Result');
 const resourceName=n<4?Object.values(expected)[n]:key==='campaignCriterionOperation'?`customers/9876543210/campaignCriteria/102~${100+n}`:`customers/9876543210/adGroupCriteria/103~${100+n}`;
 return {[type]:{resourceName}};
})};}
function recovered(s){
 const ops=googlePausedRequest(s).mutateOperations;
 const campaign=clone(ops[1].campaignOperation.create);delete campaign.targetSpend;
 Object.assign(campaign,{resourceName:expected.campaign,campaignBudget:expected.budget,biddingStrategyType:'TARGET_SPEND'});
 const budget=clone(ops[0].campaignBudgetOperation.create);budget.resourceName=expected.budget;
 const group=clone(ops[2].adGroupOperation.create);group.resourceName=expected.ad_group;
 const ad=clone(ops[3].adGroupAdOperation.create);ad.resourceName=expected.ad;
 return [
 [{campaign,campaignBudget:budget}],
 [{adGroup:group,adGroupAd:ad}],
 ops.filter(x=>x.campaignCriterionOperation).map(x=>({campaignCriterion:clone(x.campaignCriterionOperation.create)})),
 ops.filter(x=>x.adGroupCriterionOperation).map(x=>({adGroupCriterion:clone(x.adGroupCriterionOperation.create)}))
 ];
}

function controlResponse(body){return {mutateOperationResponses:body.mutateOperations.map(op=>{const key=Object.keys(op)[0];return {[key.replace('Operation','Result')]:{resourceName:op[key].update.resourceName}};})};}
function controlGraph(s){const r=recovered(s);r[0][0].campaignBudget.referenceCount='1';r[1][0].adGroupAd.policySummary={approvalStatus:'APPROVED',reviewStatus:'REVIEWED'};r.push([{adGroup:{resourceName:expected.ad_group}}]);return r;}
test('K182 activation atomically enables only the saved three resources; pause only changes campaign status',()=>{
 const s=snapshot(),activate=googleControlRequest(s,expected,'activate'),pause=googleControlRequest(s,expected,'pause');
 assert.equal(activate.partialFailure,false);assert.equal(activate.responseContentType,'RESOURCE_NAME_ONLY');assert.equal(activate.mutateOperations.length,3);
 assert.deepEqual(activate.mutateOperations.map(op=>{const v=Object.values(op)[0];assert.equal(v.updateMask,'status');assert.deepEqual(Object.keys(v.update).sort(),['resourceName','status']);return [v.update.resourceName,v.update.status];}),[[expected.ad,'ENABLED'],[expected.ad_group,'ENABLED'],[expected.campaign,'ENABLED']]);
 assert.deepEqual(pause.mutateOperations,[{campaignOperation:{update:{resourceName:expected.campaign,status:'PAUSED'},updateMask:'status'}}]);
 assert.throws(()=>googleControlRequest(s,{...expected,campaign:'customers/1111111111/campaigns/102'},'activate'));
 assert.throws(()=>googleControlRequest(s,expected,'budget'));
});
test('K182 fixed transport validates first then sends exact status mask and confirms exact receipt',async()=>{
 const calls=[],p=createGoogleAdsProvider({apiVersion:'v25',developerToken:'fixture'},{fetchImpl:async(url,o)=>{const b=JSON.parse(o.body);calls.push({url:url.href,o,b});return new Response(JSON.stringify(b.validateOnly?{}:controlResponse(b)));}});
 assert.deepEqual(await p.validateSearchControl('a',snapshot(),expected,'activate'),{validated:true});assert.deepEqual(await p.applySearchControl('a',snapshot(),expected,'activate'),{confirmed:true,action:'activate'});
 assert.equal(calls.length,2);assert.deepEqual(calls[0].b.mutateOperations,calls[1].b.mutateOperations);assert.equal(calls[0].b.validateOnly,true);assert.equal(calls[1].b.validateOnly,false);for(const x of calls){assert.equal(x.url,'https://googleads.googleapis.com/v25/customers/9876543210/googleAds:mutate');assert.equal(x.o.redirect,'error');assert.equal(x.o.headers['login-customer-id'],'1234567890');}
});
test('K182 missing, malformed, partial and cross-resource control receipts are not confirmation',async()=>{
 for(const bad of [{},{partialFailureError:{code:3}},{mutateOperationResponses:[]},{mutateOperationResponses:[{campaignResult:{resourceName:expected.ad}}]}])await assert.rejects(googleControlsMethods(async()=>bad).applySearchControl('a',snapshot(),expected,'pause'));
 for(const bad of [{unexpected:true},{mutateOperationResponses:{}},{mutateOperationResponses:[{}]}])await assert.rejects(googleControlsMethods(async()=>bad).validateSearchControl('a',snapshot(),expected,'pause'));
 let calls=0;await assert.rejects(googleControlsMethods(async()=>{calls++;throw Error();}).applySearchControl('a',snapshot(),expected,'pause'));assert.equal(calls,1);
});
test('K182 status reads only the exact saved campaign and rejects missing, paging, cross-account or malformed data',async()=>{
 const s=snapshot(),data={campaign:{resourceName:expected.campaign,name:'Campaign',status:'ENABLED'}};
 let query;const p=googleControlsMethods(async(path,a,root,body)=>{assert(path.endsWith('googleAds:search'));query=body.query;return {results:[data]};});
 assert.deepEqual(await p.createdSearchStatus('a',s,expected),{resource:expected.campaign,name:'Campaign',status:'ENABLED'});assert(query.includes('campaign.id = 102 LIMIT 2'));
 for(const bad of [{},{results:[]},{results:[data,data]},{results:[data],nextPageToken:'more'},{results:[{campaign:{...data.campaign,status:'UNKNOWN'}}]},{results:[{campaign:{...data.campaign,resourceName:'customers/1111111111/campaigns/102'}}]}])await assert.rejects(googleControlsMethods(async()=>bad).createdSearchStatus('a',s,expected));
});
test('K182 activation inspection checks exact resources, policy, single budget reference and all active groups',async()=>{
 const s=snapshot(),responses=controlGraph(s);responses[1][0].adGroup.status='ENABLED';responses[1][0].adGroupAd.status='ENABLED';let calls=0;
 const found=await googlePausedMethods(async(path,a,root,body)=>{calls++;assert(path.endsWith('googleAds:search'));return {results:responses.shift()};}).inspectCreatedSearch('a',s,expected);
 assert.equal(calls,5);assert.deepEqual(found,{resources:expected,statuses:{campaign:'PAUSED',ad_group:'ENABLED',ad:'ENABLED'},policy:'APPROVED'});
});
test('K182 unapproved ads, budget changes, unexpected groups, resources and altered copy cannot activate',async()=>{
 for(const change of [r=>r[1][0].adGroupAd.policySummary.approvalStatus='APPROVED_LIMITED',r=>r[1][0].adGroupAd.policySummary.reviewStatus='REVIEW_IN_PROGRESS',r=>r[0][0].campaignBudget.referenceCount='2',r=>r[0][0].campaignBudget.amountMicros='9990000',r=>r[4].push({adGroup:{resourceName:'customers/9876543210/adGroups/999'}}),r=>r[1][0].adGroupAd.ad.responsiveSearchAd.headlines[0].text='Changed']){
  const responses=controlGraph(snapshot());change(responses);await assert.rejects(googlePausedMethods(async()=>({results:responses.shift()})).inspectCreatedSearch('a',snapshot(),expected));
 }
 const responses=controlGraph(snapshot());await assert.rejects(googlePausedMethods(async()=>({results:responses.shift()})).inspectCreatedSearch('a',snapshot(),{...expected,campaign:'customers/9876543210/campaigns/999'}));
});

function budgetRow(s=snapshot()){return {campaign:{resourceName:expected.campaign,name:s.provider_name,status:'ENABLED',advertisingChannelType:'SEARCH',campaignBudget:expected.budget},campaignBudget:{resourceName:expected.budget,amountMicros:'25000000',explicitlyShared:false,referenceCount:'1',period:'DAILY',deliveryMethod:'STANDARD'}};}
test('K183 budget changes mutate only the saved amount with exact integer micros and strict receipt',async()=>{
 const request=googleControlRequest(snapshot(),expected,'budget',12345);assert.deepEqual(request,{mutateOperations:[{campaignBudgetOperation:{update:{resourceName:expected.budget,amountMicros:'123450000'},updateMask:'amountMicros'}}],partialFailure:false,responseContentType:'RESOURCE_NAME_ONLY'});
 const calls=[],p=googleControlsMethods(async(path,a,root,body)=>{calls.push(body);assert.equal(path,'customers/9876543210/googleAds:mutate');return body.validateOnly?{}:controlResponse(body);});
 assert.deepEqual(await p.validateSearchBudget('a',snapshot(),expected,12345),{validated:true});assert.deepEqual(await p.applySearchBudget('a',snapshot(),expected,12345),{confirmed:true,action:'budget'});assert.equal(calls[0].validateOnly,true);assert.equal(calls[1].validateOnly,false);
 for(const cents of [99,1000001,null,123.5,'2500'])assert.throws(()=>googleControlRequest(snapshot(),expected,'budget',cents));
 await assert.rejects(googleControlsMethods(async()=>({mutateOperationResponses:[{campaignBudgetResult:{resourceName:'customers/9876543210/campaignBudgets/999'}}]})).applySearchBudget('a',snapshot(),expected,3000));
});
test('K183 budget inspection rejects sharing, drift, total budgets, removed campaigns and wrong resources',async()=>{
 let query;const p=googleControlsMethods(async(path,a,root,body)=>{query=body.query;return {results:[budgetRow()]};});assert.deepEqual(await p.inspectSearchBudget('a',snapshot(),expected),{status:{resource:expected.campaign,name:snapshot().provider_name,status:'ENABLED'},budget:{resource:expected.budget,daily_cents:2500}});assert(query.includes('campaign.id = 102 LIMIT 2'));
 for(const edit of [r=>r.campaign.campaignBudget='wrong',r=>r.campaign.name='Changed',r=>r.campaign.status='REMOVED',r=>r.campaign.advertisingChannelType='DISPLAY',r=>r.campaignBudget.resourceName='wrong',r=>r.campaignBudget.explicitlyShared=true,r=>r.campaignBudget.referenceCount='2',r=>r.campaignBudget.period='CUSTOM_PERIOD',r=>r.campaignBudget.deliveryMethod='ACCELERATED',r=>r.campaignBudget.amountMicros='25000001']){const row=budgetRow();edit(row);await assert.rejects(googleControlsMethods(async()=>({results:[row]})).inspectSearchBudget('a',snapshot(),expected));}
 for(const response of [{results:[]},{results:[budgetRow(),budgetRow()]},{results:[budgetRow()],nextPageToken:'more'}])await assert.rejects(googleControlsMethods(async()=>response).inspectSearchBudget('a',snapshot(),expected));
});
test('K183 activation inspection accepts the latest confirmed budget and rejects the original amount after a change',async()=>{
 const s=snapshot();s.plan.daily_cents=3000;let responses=controlGraph(s);assert.equal((await googlePausedMethods(async()=>({results:responses.shift()})).inspectCreatedSearch('a',s,expected)).policy,'APPROVED');responses=controlGraph(snapshot());await assert.rejects(googlePausedMethods(async()=>({results:responses.shift()})).inspectCreatedSearch('a',s,expected));
});
