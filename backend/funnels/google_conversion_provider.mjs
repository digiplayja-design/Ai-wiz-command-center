import {fail} from './core.mjs';
const bad=()=>fail('Google conversion destinations could not be verified. Refresh account access and try again.',503);
const customer=v=>typeof v==='string'&&/^\d{10}$/.test(v);
const id=v=>typeof v==='string'&&/^[1-9]\d{0,18}$/.test(v)&&BigInt(v)<=9223372036854775807n;
export const googleDestinationFields=['conversion_customer_id','conversion_action_id','resource_name','name','status','type','category','counting_type','primary_for_goal','click_window_days','attribution_model','default_value','default_currency','always_use_default_value'];
export function googleDestination(v){
 if(!v||typeof v!=='object'||Array.isArray(v)||Object.keys(v).length!==googleDestinationFields.length||!googleDestinationFields.every(k=>Object.hasOwn(v,k))||!customer(v.conversion_customer_id)||!id(v.conversion_action_id)||v.resource_name!==`customers/${v.conversion_customer_id}/conversionActions/${v.conversion_action_id}`||typeof v.name!=='string'||!v.name||v.name.length>1000||v.name.trim()!==v.name||/[\x00-\x1f\x7f]/.test(v.name)||v.status!=='ENABLED'||v.type!=='UPLOAD_CLICKS'||v.category!=='SUBMIT_LEAD_FORM'||!['ONE_PER_CLICK','MANY_PER_CLICK'].includes(v.counting_type)||typeof v.primary_for_goal!=='boolean'||!Number.isSafeInteger(v.click_window_days)||v.click_window_days<1||v.click_window_days>90||!['GOOGLE_ADS_LAST_CLICK','GOOGLE_SEARCH_ATTRIBUTION_DATA_DRIVEN'].includes(v.attribution_model)||typeof v.default_value!=='number'||!Number.isFinite(v.default_value)||v.default_value<0||v.default_value>1e12||typeof v.default_currency!=='string'||!/^([A-Z]{3})?$/.test(v.default_currency)||typeof v.always_use_default_value!=='boolean')bad();
 return Object.fromEntries(googleDestinationFields.map(k=>[k,v[k]]));
}
export function googleDestinationList(v){
 if(!Array.isArray(v)||v.length>200)bad();const seen=new Set();if(new Set(v.map(x=>x?.conversion_customer_id)).size>1)bad();
 return v.map(row=>{const d=googleDestination(row);if(seen.has(d.resource_name))bad();seen.add(d.resource_name);return d;});
}
export function googleConversionMethods(ads){
 async function tracking(access,account,root){
  if(!customer(account)||!(root===null||customer(root)))bad();
  const r=await ads(`customers/${account}/googleAds:search`,access,root,{query:'SELECT customer.id, customer.conversion_tracking_setting.google_ads_conversion_customer, customer.conversion_tracking_setting.conversion_tracking_status FROM customer LIMIT 1'});
  if(r.nextPageToken||!Array.isArray(r.results)||r.results.length!==1||r.results[0].customer?.id!==account)bad();
  const t=r.results[0].customer.conversionTrackingSetting,match=typeof t?.googleAdsConversionCustomer==='string'&&t.googleAdsConversionCustomer.match(/^customers\/(\d{10})$/);
  if(!match)bad();
  if(t.conversionTrackingStatus==='NOT_CONVERSION_TRACKED')fail('Enable an imported lead-form conversion action in the Google Ads conversion account first.',409);
  if(!['CONVERSION_TRACKING_MANAGED_BY_SELF','CONVERSION_TRACKING_MANAGED_BY_THIS_MANAGER','CONVERSION_TRACKING_MANAGED_BY_ANOTHER_MANAGER'].includes(t.conversionTrackingStatus))bad();
  if((t.conversionTrackingStatus==='CONVERSION_TRACKING_MANAGED_BY_SELF'&&match[1]!==account)||(t.conversionTrackingStatus==='CONVERSION_TRACKING_MANAGED_BY_THIS_MANAGER'&&match[1]!==root))bad();
  return {id:match[1],status:t.conversionTrackingStatus};
 }
 return {async conversionDestinations(access,account,root){
  // The advertiser's conversion-tracking account, not an arbitrary browser ID,
  // determines the destination owner. This supports cross-account tracking.
  const before=await tracking(access,account.id,root),out=[],seen=new Set();let pageToken;
  const query="SELECT conversion_action.resource_name, conversion_action.id, conversion_action.name, conversion_action.owner_customer, conversion_action.status, conversion_action.type, conversion_action.category, conversion_action.counting_type, conversion_action.primary_for_goal, conversion_action.click_through_lookback_window_days, conversion_action.attribution_model_settings.attribution_model, conversion_action.value_settings.default_value, conversion_action.value_settings.default_currency_code, conversion_action.value_settings.always_use_default_value FROM conversion_action WHERE conversion_action.status = 'ENABLED' AND conversion_action.type = 'UPLOAD_CLICKS' AND conversion_action.category = 'SUBMIT_LEAD_FORM' AND conversion_action.attribution_model_settings.attribution_model IN ('GOOGLE_ADS_LAST_CLICK', 'GOOGLE_SEARCH_ATTRIBUTION_DATA_DRIVEN') LIMIT 201";
  for(let page=0;page<5;page++){
   const r=await ads(`customers/${before.id}/googleAds:search`,access,root,{query,...(pageToken?{pageToken}:{})});
   if(r.results!==undefined&&!Array.isArray(r.results))bad();
   for(const row of r.results||[]){
    const a=row?.conversionAction;if(!a||a.ownerCustomer!==`customers/${before.id}`||typeof a.primaryForGoal!=='boolean'||!a.valueSettings)bad();
    // Optional bool/zero protobuf fields may be omitted. Optional primary_for_goal
    // has presence and is required here rather than assuming a bidding setting.
    const days=a.clickThroughLookbackWindowDays;if(typeof days!=='string'||!/^\d{1,2}$/.test(days))bad();
    out.push(googleDestination({conversion_customer_id:before.id,conversion_action_id:a.id,resource_name:a.resourceName,name:a.name,status:a.status,type:a.type,category:a.category,counting_type:a.countingType,primary_for_goal:a.primaryForGoal,click_window_days:Number(days),attribution_model:a.attributionModelSettings?.attributionModel,default_value:(Object.hasOwn(a.valueSettings,'defaultValue')?a.valueSettings.defaultValue:0),default_currency:(Object.hasOwn(a.valueSettings,'defaultCurrencyCode')?a.valueSettings.defaultCurrencyCode:''),always_use_default_value:(Object.hasOwn(a.valueSettings,'alwaysUseDefaultValue')?a.valueSettings.alwaysUseDefaultValue:false)}));
   }
   if(out.length>200)fail('More than 200 eligible conversion actions were returned. Use a smaller conversion account.',409);
   if(!r.nextPageToken){const after=await tracking(access,account.id,root);if(JSON.stringify(before)!==JSON.stringify(after))fail('The Google conversion account changed while loading. Try again.',409);return googleDestinationList(out);}
   pageToken=r.nextPageToken;if(typeof pageToken!=='string'||pageToken.length>4000||seen.has(pageToken))bad();seen.add(pageToken);
  }
  bad();
 }};
}
