import test from 'node:test';
import assert from 'node:assert/strict';
import {googlePausedRequest,googlePausedMethods,creationResources} from '../funnels/google_paused_provider.mjs';
import {createGoogleAdsProvider} from '../funnels/google_ads_provider.mjs';
const clone=v=>structuredClone(v);
const snapshot=()=>({search_language_mode:'automatic_from_creative_v1',plan:{id:'00000000-0000-4000-8000-000000000003',daily_cents:2500,days:14},page:{destination:'https://example.com/f/services?utm_source=google&utm_medium=paid&utm_campaign=k143_00000000000040008000000000000003'},identity:{root_id:'1234567890',login_customer_id:'1234567890',account:{id:'9876543210',currency:'USD',timezone:'America/New_York',manager:false,status:'ENABLED',test_account:false}},creative:{headlines:['Meet the team','Explore services','Start here'],descriptions:['Find support for your business.','Talk with our team today.'],path1:'services',path2:''},keywords:{exact:['service'],phrase:['business support'],broad:[],negative_exact:['free'],negative_phrase:[],negative_broad:[]},targeting:{countries:['US','JM'],excluded_countries:['CA'],content_languages:['en','es'],location_mode:'presence',bidding:'maximize_clicks'},start_date:'2026-11-01',end_date:'2026-11-14',provider_name:'KORLIX 00000000-0000-4000-8000-000000000099',no_eu_political_ads:true,budget_acknowledged:true});
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
test('K181 compiler creates all three delivery levels paused, separate exact USD budget and atomic v25 request',()=>{
 const r=googlePausedRequest(snapshot()),ops=r.mutateOperations;
 assert.equal(r.partialFailure,false);assert.equal(r.responseContentType,'RESOURCE_NAME_ONLY');assert.equal(ops[0].campaignBudgetOperation.create.amountMicros,'25000000');assert.equal(ops[0].campaignBudgetOperation.create.explicitlyShared,false);
 for(const [n,key]of [[1,'campaignOperation'],[2,'adGroupOperation'],[3,'adGroupAdOperation']])assert.equal(ops[n][key].create.status,'PAUSED');
 const c=ops[1].campaignOperation.create;assert.deepEqual(c.targetSpend,{});assert.equal(c.startDateTime,'2026-11-01 00:00:00');assert.equal(c.endDateTime,'2026-11-14 23:59:59');assert(!Object.hasOwn(c,'startDate'));assert.equal(c.containsEuPoliticalAdvertising,'DOES_NOT_CONTAIN_EU_POLITICAL_ADVERTISING');assert.equal(c.networkSettings.targetSearchNetwork,false);assert.equal(c.networkSettings.targetContentNetwork,false);assert.equal(c.geoTargetTypeSetting.negativeGeoTargetType,'PRESENCE');
 const criteria=ops.filter(x=>x.campaignCriterionOperation).map(x=>x.campaignCriterionOperation.create);assert(criteria.some(c=>c.location?.geoTargetConstant==='geoTargetConstants/2840'&&!c.negative));assert(criteria.some(c=>c.location?.geoTargetConstant==='geoTargetConstants/2124'&&c.negative));assert(criteria.every(c=>!Object.hasOwn(c,'language')));
 const kw=ops.filter(x=>x.adGroupCriterionOperation).map(x=>x.adGroupCriterionOperation.create);assert.deepEqual(kw.map(k=>[k.keyword.text,k.keyword.matchType,k.negative,k.status]),[['service','EXACT',false,'ENABLED'],['business support','PHRASE',false,'ENABLED'],['free','EXACT',true,undefined]]);
});
test('K181 compiler rejects unsupported bidding, dates, declaration, test/currency accounts and arbitrary destinations',()=>{
 for(const change of [s=>s.targeting.bidding='maximize_conversions',s=>s.start_date='not-date',s=>s.end_date='2026-11-15',s=>s.no_eu_political_ads=false,s=>s.budget_acknowledged=false,s=>s.identity.account.currency='EUR',s=>s.identity.account.test_account=true,s=>s.identity.login_customer_id=null,s=>s.provider_name="KORLIX ' OR 1=1",s=>s.page.destination='https://evil.example/?utm_source=google',s=>s.creative.headlines=[],s=>s.keywords.exact=[],s=>s.plan.daily_cents=1.5]){const s=snapshot();change(s);if(s.keywords.exact.length===0)s.keywords.phrase=[];assert.throws(()=>googlePausedRequest(s));}
});
test('K181 radius targets use exact microdegrees and kilometer units including zero coordinates',()=>{
 const s=snapshot();s.targeting.countries=[];s.targeting.proximities=[{label:'Center',latitude_micro:0,longitude_micro:0,radius_meters:1500}];
 const criterion=googlePausedRequest(s).mutateOperations.find(x=>x.campaignCriterionOperation?.create.proximity).campaignCriterionOperation.create;
 assert.deepEqual(criterion.proximity,{geoPoint:{latitudeInMicroDegrees:0,longitudeInMicroDegrees:0},radius:1.5,radiusUnits:'KILOMETERS'});
});
test('K181 real transport uses fixed v25 host, manager header, validate-only then exact response resources',async()=>{
 const calls=[],p=createGoogleAdsProvider({apiVersion:'v25',developerToken:'fixture-token'},{fetchImpl:async(url,options)=>{
  const body=JSON.parse(options.body);calls.push({url:url.href,options,body});return new Response(JSON.stringify(body.validateOnly?{}:mutationResponse(body)),{status:200});
 }});
 assert.deepEqual(await p.validatePausedSearch('fixture-access',snapshot()),{validated:true});assert.deepEqual(await p.createPausedSearch('fixture-access',snapshot()),expected);assert.equal(calls.length,2);
 for(const c of calls){assert.equal(c.url,'https://googleads.googleapis.com/v25/customers/9876543210/googleAds:mutate');assert.equal(c.options.headers['login-customer-id'],'1234567890');assert.equal(c.options.headers.Authorization,'Bearer fixture-access');assert.equal(c.options.redirect,'error');assert(c.options.signal);assert.equal(c.body.partialFailure,false);}
 assert.equal(calls[0].body.validateOnly,true);assert.equal(calls[1].body.validateOnly,false);assert.deepEqual(calls[0].body.mutateOperations,calls[1].body.mutateOperations);
});
test('K181 direct-access mutation omits manager header and has no automatic retry on transport failure',async()=>{
 const s=snapshot();s.identity.root_id=s.identity.account.id;s.identity.login_customer_id=null;let count=0;
 const p=createGoogleAdsProvider({apiVersion:'v25',developerToken:'fixture-token'},{fetchImpl:async(url,o)=>{count++;assert(!Object.hasOwn(o.headers,'login-customer-id'));throw Error('secret-network-detail');}});
 await assert.rejects(p.createPausedSearch('fixture-access',s),e=>!e.message.includes('secret-network-detail'));assert.equal(count,1);
});
test('K181 validation rejects results; mutation rejects partial, incomplete, cross-account and mismatched group identities',async()=>{
 const s=snapshot(),body=googlePausedRequest(s);
 for(const change of [r=>r.partialFailureError={code:3},r=>r.mutateOperationResponses.pop(),r=>r.mutateOperationResponses[1].campaignResult.resourceName='customers/1111111111/campaigns/102',r=>r.mutateOperationResponses[3].adGroupAdResult.resourceName='customers/9876543210/adGroupAds/999~104',r=>r.mutateOperationResponses[4].campaignCriterionResult.resourceName='customers/9876543210/campaignCriteria/999~105']){
  const r=mutationResponse(body);change(r);const p=googlePausedMethods(async()=>r);await assert.rejects(p.createPausedSearch('a',s));
 }
 await assert.rejects(googlePausedMethods(async()=>mutationResponse(body)).validatePausedSearch('a',s));
 for(const bad of [{mutateOperationResponses:{}},{unexpected:'not a validation response'}])await assert.rejects(googlePausedMethods(async()=>bad).validatePausedSearch('a',s));
 assert.throws(()=>creationResources({...expected,campaign:'customers/9876543210/campaigns/9223372036854775808'},'9876543210'));
});
test('K181 recovery only reads and verifies the entire paused structure, budget, copy and criteria',async()=>{
 const s=snapshot(),responses=recovered(s),queries=[];
 const p=googlePausedMethods(async(path,access,root,body)=>{assert(path.endsWith('/googleAds:search'));assert(!body.mutateOperations);queries.push(body.query);return {results:responses.shift()};});
 assert.deepEqual(await p.findPausedSearch('a',s),expected);assert.equal(queries.length,4);assert(queries[0].includes('campaign.start_date_time'));assert(queries[1].includes('responsive_search_ad.headlines'));assert(queries.every(q=>q.endsWith('LIMIT 201')));
});
test('K181 recovery never equates missing, duplicate, changed or enabled resources with success',async()=>{
 assert.equal(await googlePausedMethods(async()=>({})).findPausedSearch('a',snapshot()),null);
 for(const change of [r=>r[0].push(clone(r[0][0])),r=>r[0][0].campaign.status='ENABLED',r=>r[0][0].campaignBudget.amountMicros='50000000',r=>r[1][0].adGroupAd.ad.finalUrls=['https://evil.example'],r=>r[2].pop(),r=>r[3].pop(),r=>r[1][0].adGroup.status='ENABLED']){
  const s=snapshot(),responses=recovered(s);change(responses);await assert.rejects(googlePausedMethods(async()=>({results:responses.shift()})).findPausedSearch('a',s));
 }
 await assert.rejects(googlePausedMethods(async()=>({nextPageToken:'more',results:[]})).findPausedSearch('a',snapshot()));
});
test('K189 legacy language snapshots remain strictly readable but can never create or validate again',async()=>{
 const s=snapshot();delete s.search_language_mode;
 const criteria=googlePausedRequest(s).mutateOperations.filter(x=>x.campaignCriterionOperation).map(x=>x.campaignCriterionOperation.create);
 assert.deepEqual(criteria.filter(c=>c.language).map(c=>c.language.languageConstant),['languageConstants/1000','languageConstants/1003']);
 for(const method of ['validatePausedSearch','createPausedSearch']){let calls=0;await assert.rejects(googlePausedMethods(async()=>{calls++;})[method]('a',s));assert.equal(calls,0);}
 const responses=recovered(s);assert.deepEqual(await googlePausedMethods(async()=>({results:responses.shift()})).findPausedSearch('a',s),expected);
 const changed=recovered(s);changed[2]=changed[2].filter(x=>!x.campaignCriterion.language);await assert.rejects(googlePausedMethods(async()=>({results:changed.shift()})).findPausedSearch('a',s));
});
test('K189 unknown language contracts and unexpected provider language criteria fail closed',async()=>{
 for(const value of [null,'automatic',{},1]){const s={...snapshot(),search_language_mode:value};assert.throws(()=>googlePausedRequest(s));let calls=0;await assert.rejects(googlePausedMethods(async()=>{calls++;}).createPausedSearch('a',s));assert.equal(calls,0);}
 const s=snapshot(),responses=recovered(s);responses[2].push({campaignCriterion:{negative:false,language:{languageConstant:'languageConstants/1000'}}});await assert.rejects(googlePausedMethods(async()=>({results:responses.shift()})).findPausedSearch('a',s));
});
