import {fail,uuid} from './core.mjs';
import {googleCreativeAssets} from './google_creative.mjs';
import {googleKeywordsAssets} from './google_keywords.mjs';
import {googleTargetingAssets,googleTargetingCatalog} from './google_targeting.mjs';

const integer=(n,min,max)=>Number.isSafeInteger(n)&&n>=min&&n<=max;
const customer=v=>typeof v==='string'&&/^\d{10}$/.test(v);
const positive=v=>typeof v==='string'&&/^[1-9]\d{0,18}$/.test(v)&&BigInt(v)<=9223372036854775807n;
const date=v=>typeof v==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(v)&&Number.isFinite(Date.parse(v+'T00:00:00Z'))&&new Date(v+'T00:00:00Z').toISOString().slice(0,10)===v;
const wrong=()=>fail('The saved Google creation details could not be verified. Reload the campaign.',409);
const unclear=()=>fail('Google creation could not be verified. Check the saved creation record; do not create a duplicate.',409);
const stable=v=>Array.isArray(v)?'['+v.map(stable).join(',')+']':v&&typeof v==='object'?'{'+Object.keys(v).sort().map(k=>JSON.stringify(k)+':'+stable(v[k])).join(',')+'}':JSON.stringify(v);
const same=(a,b)=>stable(a)===stable(b);
const resource=(value,account,type)=>{if(typeof value!=='string')return false;const m=value.match(new RegExp(`^customers/${account}/${type}/([1-9]\\d{0,18})(?:~([1-9]\\d{0,18}))?$`));return !!m&&positive(m[1])&&(!m[2]||positive(m[2]))&&((['adGroupAds','adGroupCriteria','campaignCriteria'].includes(type))===!!m[2]);};
export function creationResources(value,account){
  if(!value||typeof value!=='object'||Object.keys(value).length!==4||!resource(value.budget,account,'campaignBudgets')||!resource(value.campaign,account,'campaigns')||!resource(value.ad_group,account,'adGroups')||!resource(value.ad,account,'adGroupAds')||value.ad.split('/')[3].split('~')[0]!==value.ad_group.split('/')[3])unclear();
  return {budget:value.budget,campaign:value.campaign,ad_group:value.ad_group,ad:value.ad};
}
export function googlePausedRequest(s){
  const p=s?.plan,a=s?.identity?.account,i=s?.identity;
  if(!p||!a||!customer(a.id)||a.currency!=='USD'||a.manager!==false||a.status!=='ENABLED'||a.test_account!==false||!customer(i.root_id)||!(i.login_customer_id===i.root_id||(i.login_customer_id===null&&i.root_id===a.id))||!integer(p.daily_cents,100,1000000)||!integer(p.days,1,90)||!date(s.start_date)||!date(s.end_date)||s.no_eu_political_ads!==true||s.budget_acknowledged!==true)wrong();
  const expectedEnd=new Date(Date.parse(s.start_date+'T00:00:00Z')+(p.days-1)*86400000).toISOString().slice(0,10);
  if(s.end_date!==expectedEnd||typeof s.provider_name!=='string'||!/^KORLIX [a-f0-9-]{36}$/.test(s.provider_name))wrong();uuid(s.provider_name.slice(7));
  const cr=googleCreativeAssets(s.creative),kw=googleKeywordsAssets(s.keywords),t=googleTargetingAssets(s.targeting);
  if(cr.headlines.length<3||cr.descriptions.length<2||kw.exact.length+kw.phrase.length+kw.broad.length===0||t.bidding!=='maximize_clicks'||!['presence','presence_or_interest'].includes(t.location_mode)||!t.content_languages.length||!(t.countries.length||t.proximities?.length||t.geo_locations?.length))wrong();
  let destination;try{destination=new URL(s.page?.destination);}catch{wrong();}
  if(destination.protocol!=='https:'||destination.username||destination.password||destination.hash||destination.searchParams.get('utm_source')!=='google'||destination.searchParams.get('utm_medium')!=='paid'||destination.searchParams.get('utm_campaign')!=='k143_'+uuid(p.id).replaceAll('-',''))wrong();
  const root=`customers/${a.id}`,budget=`${root}/campaignBudgets/-1`,campaign=`${root}/campaigns/-2`,group=`${root}/adGroups/-3`;
  const operations=[
    {campaignBudgetOperation:{create:{resourceName:budget,name:s.provider_name+' budget',amountMicros:String(BigInt(p.daily_cents)*10000n),deliveryMethod:'STANDARD',explicitlyShared:false}}},
    {campaignOperation:{create:{resourceName:campaign,name:s.provider_name,status:'PAUSED',advertisingChannelType:'SEARCH',campaignBudget:budget,targetSpend:{},startDateTime:s.start_date+' 00:00:00',endDateTime:s.end_date+' 23:59:59',containsEuPoliticalAdvertising:'DOES_NOT_CONTAIN_EU_POLITICAL_ADVERTISING',networkSettings:{targetGoogleSearch:true,targetSearchNetwork:false,targetContentNetwork:false,targetPartnerSearchNetwork:false},geoTargetTypeSetting:{positiveGeoTargetType:t.location_mode==='presence'?'PRESENCE':'PRESENCE_OR_INTEREST',negativeGeoTargetType:'PRESENCE'}}}},
    {adGroupOperation:{create:{resourceName:group,campaign,name:s.provider_name+' group',status:'PAUSED',type:'SEARCH_STANDARD'}}},
    {adGroupAdOperation:{create:{adGroup:group,status:'PAUSED',ad:{finalUrls:[destination.href],responsiveSearchAd:{headlines:cr.headlines.map(text=>({text})),descriptions:cr.descriptions.map(text=>({text})),...(cr.path1?{path1:cr.path1}:{}),...(cr.path2?{path2:cr.path2}:{})}}}}}
  ];
  const criterion=(value,negative=false)=>operations.push({campaignCriterionOperation:{create:{campaign,negative,...value}}});
  for(const [key,negative] of [['countries',false],['excluded_countries',true]])for(const code of t[key])criterion({location:{geoTargetConstant:'geoTargetConstants/'+googleTargetingCatalog.countries.find(x=>x.code===code).id}},negative);
  for(const location of t.geo_locations||[])criterion({location:{geoTargetConstant:'geoTargetConstants/'+location.id}});
  for(const area of t.proximities||[])criterion({proximity:{geoPoint:{latitudeInMicroDegrees:area.latitude_micro,longitudeInMicroDegrees:area.longitude_micro},radius:area.radius_meters/1000,radiusUnits:'KILOMETERS'}});
  for(const code of t.content_languages)criterion({language:{languageConstant:'languageConstants/'+googleTargetingCatalog.languages.find(x=>x.code===code).id}});
  for(const key of Object.keys(kw))for(const text of kw[key]){const negative=key.startsWith('negative_'),matchType=key.replace('negative_','').toUpperCase();operations.push({adGroupCriterionOperation:{create:{adGroup:group,negative,...(negative?{}:{status:'ENABLED'}),keyword:{text,matchType}}}});}
  if(operations.length>160)wrong();
  return {mutateOperations:operations,partialFailure:false,responseContentType:'RESOURCE_NAME_ONLY'};
}

// Only these narrow methods can mutate; the generic transport remains private.
export function googlePausedMethods(ads){
  async function mutate(access,s,validateOnly){
    const request=googlePausedRequest(s),account=s.identity.account.id;
    const response=await ads(`customers/${account}/googleAds:mutate`,access,s.identity.login_customer_id,{...request,validateOnly});
    if(response.partialFailureError)unclear();
    if(validateOnly){if(Object.keys(response).some(k=>k!=='mutateOperationResponses')||(Object.hasOwn(response,'mutateOperationResponses')&&(!Array.isArray(response.mutateOperationResponses)||response.mutateOperationResponses.length)))unclear();return {validated:true};}
    const rows=response.mutateOperationResponses;
    if(!Array.isArray(rows)||rows.length!==request.mutateOperations.length)unclear();
    const names=rows.map((row,n)=>{const key=Object.keys(request.mutateOperations[n])[0].replace('Operation','Result');if(!row||Object.keys(row).length!==1||!row[key]?.resourceName)unclear();return row[key].resourceName;});
    if(new Set(names).size!==names.length)unclear();
    const result=creationResources({budget:names[0],campaign:names[1],ad_group:names[2],ad:names[3]},account);
    for(let n=4;n<names.length;n++){const campaign=request.mutateOperations[n].campaignCriterionOperation!==undefined;if(!resource(names[n],account,campaign?'campaignCriteria':'adGroupCriteria')||names[n].split('/')[3].split('~')[0]!==result[campaign?'campaign':'ad_group'].split('/')[3])unclear();}
    return result;
  }
  async function rows(access,s,query){
    const r=await ads(`customers/${s.identity.account.id}/googleAds:search`,access,s.identity.login_customer_id,{query:query+' LIMIT 201'});
    if(r.nextPageToken||(r.results!==undefined&&!Array.isArray(r.results))||(r.results||[]).length>200)unclear();return r.results||[];
  }
  async function find(access,s,controls=null){
    const expected=googlePausedRequest(s).mutateOperations,id=s.identity.account.id;
    // Provider name contains only a fixed prefix and a server UUID; no GAQL input.
    const list=await rows(access,s,`SELECT campaign.resource_name, campaign.name, campaign.status, campaign.advertising_channel_type, campaign.start_date_time, campaign.end_date_time, campaign.campaign_budget, campaign.bidding_strategy_type, campaign.network_settings.target_google_search, campaign.network_settings.target_search_network, campaign.network_settings.target_content_network, campaign.network_settings.target_partner_search_network, campaign.geo_target_type_setting.positive_geo_target_type, campaign.geo_target_type_setting.negative_geo_target_type, campaign.contains_eu_political_advertising, campaign_budget.resource_name, campaign_budget.amount_micros, campaign_budget.explicitly_shared, campaign_budget.reference_count FROM campaign WHERE campaign.name = '${s.provider_name}'`);
    if(list.length===0)return null;if(list.length!==1)unclear();
    const c=list[0].campaign,b=list[0].campaignBudget;
    if(!resource(c?.resourceName,id,'campaigns')||!resource(b?.resourceName,id,'campaignBudgets')||c.name!==s.provider_name||!(controls?['PAUSED','ENABLED']:['PAUSED']).includes(c.status)||c.advertisingChannelType!=='SEARCH'||c.startDateTime!==s.start_date+' 00:00:00'||c.endDateTime!==s.end_date+' 23:59:59'||c.campaignBudget!==b.resourceName||c.biddingStrategyType!=='TARGET_SPEND'||b.amountMicros!==expected[0].campaignBudgetOperation.create.amountMicros||b.explicitlyShared===true||c.networkSettings?.targetGoogleSearch!==true||['targetSearchNetwork','targetContentNetwork','targetPartnerSearchNetwork'].some(k=>c.networkSettings[k]===true)||!same(c.geoTargetTypeSetting,expected[1].campaignOperation.create.geoTargetTypeSetting)||c.containsEuPoliticalAdvertising!=='DOES_NOT_CONTAIN_EU_POLITICAL_ADVERTISING')unclear();
    const campaignId=c.resourceName.split('/')[3];
    const adRows=await rows(access,s,`SELECT ad_group.resource_name, ad_group.name, ad_group.status, ad_group.type, ad_group_ad.resource_name, ad_group_ad.status, ad_group_ad.policy_summary.approval_status, ad_group_ad.policy_summary.review_status, ad_group_ad.ad.final_urls, ad_group_ad.ad.responsive_search_ad.headlines, ad_group_ad.ad.responsive_search_ad.descriptions, ad_group_ad.ad.responsive_search_ad.path1, ad_group_ad.ad.responsive_search_ad.path2 FROM ad_group_ad WHERE campaign.id = ${campaignId}`);
    if(adRows.length!==1)unclear();const g=adRows[0].adGroup,a=adRows[0].adGroupAd;
    if(!(controls?['PAUSED','ENABLED']:['PAUSED']).includes(g?.status)||g.type!=='SEARCH_STANDARD'||g.name!==s.provider_name+' group'||!(controls?['PAUSED','ENABLED']:['PAUSED']).includes(a?.status))unclear();
    const expectedAd=expected[3].adGroupAdOperation.create.ad;
    const cleanAssets=assets=>Array.isArray(assets)?assets.map(x=>({text:x.text,pinnedField:x.pinnedField||'UNSPECIFIED'})):null;
    const cleanAd=ad=>({finalUrls:ad?.finalUrls,responsiveSearchAd:{headlines:cleanAssets(ad?.responsiveSearchAd?.headlines),descriptions:cleanAssets(ad?.responsiveSearchAd?.descriptions),path1:ad?.responsiveSearchAd?.path1||'',path2:ad?.responsiveSearchAd?.path2||''}});
    if(!same(cleanAd(a.ad),cleanAd(expectedAd)))unclear();
    const result=creationResources({budget:b.resourceName,campaign:c.resourceName,ad_group:g.resourceName,ad:a.resourceName},id);
    const cc=await rows(access,s,`SELECT campaign_criterion.negative, campaign_criterion.type, campaign_criterion.location.geo_target_constant, campaign_criterion.language.language_constant, campaign_criterion.proximity.geo_point.latitude_in_micro_degrees, campaign_criterion.proximity.geo_point.longitude_in_micro_degrees, campaign_criterion.proximity.radius, campaign_criterion.proximity.radius_units FROM campaign_criterion WHERE campaign.id = ${campaignId} AND campaign_criterion.status != 'REMOVED'`);
    const ac=await rows(access,s,`SELECT ad_group_criterion.negative, ad_group_criterion.status, ad_group_criterion.keyword.text, ad_group_criterion.keyword.match_type FROM ad_group_criterion WHERE campaign.id = ${campaignId} AND ad_group.id = ${g.resourceName.split('/')[3]} AND ad_group_criterion.status != 'REMOVED'`);
    const cleanCriterion=v=>({negative:v.negative===true,...(v.location?{location:v.location}:{}),...(v.language?{language:v.language}:{}),...(v.proximity?{proximity:{geoPoint:{latitudeInMicroDegrees:v.proximity.geoPoint?.latitudeInMicroDegrees||0,longitudeInMicroDegrees:v.proximity.geoPoint?.longitudeInMicroDegrees||0},radius:v.proximity.radius,radiusUnits:v.proximity.radiusUnits}}:{})});
    const cleanKeyword=v=>({negative:v.negative===true,...(v.negative===true?{}:{status:v.status}),keyword:v.keyword});
    const sorted=(values,fn)=>values.map(v=>stable(fn(v))).sort();
    const expectedCriteria=expected.filter(x=>x.campaignCriterionOperation).map(x=>x.campaignCriterionOperation.create),expectedKeywords=expected.filter(x=>x.adGroupCriterionOperation).map(x=>x.adGroupCriterionOperation.create);
    if(!same(sorted(cc.map(x=>x.campaignCriterion||{}),cleanCriterion),sorted(expectedCriteria,cleanCriterion))||!same(sorted(ac.map(x=>x.adGroupCriterion||{}),cleanKeyword),sorted(expectedKeywords,cleanKeyword)))unclear();
    if(controls){
      if(!same(result,creationResources(controls,id))||String(b.referenceCount)!=='1'||a.policySummary?.approvalStatus!=='APPROVED'||a.policySummary?.reviewStatus!=='REVIEWED')unclear();
      const groups=await rows(access,s,`SELECT ad_group.resource_name FROM ad_group WHERE campaign.id = ${campaignId} AND ad_group.status != 'REMOVED'`);
      if(groups.length!==1||groups[0].adGroup?.resourceName!==result.ad_group)unclear();
      return {resources:result,statuses:{campaign:c.status,ad_group:g.status,ad:a.status},policy:'APPROVED'};
    }
    return result;
  }
  return {inspectCreatedSearch:(access,s,resources)=>find(access,s,resources),validatePausedSearch:(access,s)=>mutate(access,s,true),createPausedSearch:(access,s)=>mutate(access,s,false),findPausedSearch:find};
}
