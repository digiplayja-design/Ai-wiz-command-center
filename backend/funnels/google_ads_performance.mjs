import {fail,version} from './core.mjs';

const DAY=86400000,MAX_COUNT=BigInt(Number.MAX_SAFE_INTEGER),MAX_SPEND=1000000000000000000n;
const unreadable=()=>fail('Google returned incomplete or inconsistent performance data. Refresh or try a shorter period.',503);
const date=value=>{
  if(typeof value!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(value))unreadable();
  const stamp=Date.parse(value+'T00:00:00Z');
  if(!Number.isFinite(stamp)||new Date(stamp).toISOString().slice(0,10)!==value)unreadable();return stamp;
};
export function googleReportQuery(query={}) {
  if(Object.keys(query).some(k=>!['days','version','account_id','root_id'].includes(k))||!['7','30','90'].includes(query.days)||typeof query.version!=='string'||!/^\d{1,10}$/.test(query.version)||typeof query.account_id!=='string'||!/^\d{10}$/.test(query.account_id)||typeof query.root_id!=='string'||!/^\d{10}$/.test(query.root_id))fail('Choose a reporting period and the current selected Google account.');
  return {days:Number(query.days),version:version(Number(query.version)),account_id:query.account_id,root_id:query.root_id};
}
export function googleReportRange(days,timezone,now=Date.now()) {
  if(![7,30,90].includes(days))fail('Choose 7, 30 or 90 completed days.');
  let parts;
  try{if(typeof timezone!=='string'||!timezone)throw Error();parts=new Intl.DateTimeFormat('en-US',{timeZone:timezone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date(now));}catch{fail('Google returned an unavailable account timezone. Refresh your accounts.',503);}
  const get=k=>parts.find(p=>p.type===k).value;
  const today=Date.parse(`${get('year')}-${get('month')}-${get('day')}T00:00:00Z`);
  // Work in account-calendar dates across DST; never subtract local hours.
  return {from:new Date(today-days*DAY).toISOString().slice(0,10),to:new Date(today-DAY).toISOString().slice(0,10),days};
}
function integer(value,max) {
  // Requested scalar zero fields can be omitted by ProtoJSON. Explicit null,
  // floats and imprecise JS numbers are not silently converted into zero.
  if(value===undefined)return 0n;
  if(typeof value==='number'){if(!Number.isSafeInteger(value)||value<0)unreadable();value=String(value);}
  if(typeof value!=='string'||!/^\d{1,19}$/.test(value))unreadable();
  const result=BigInt(value);if(result>max)unreadable();return result;
}
const money=n=>`${n/1000000n}.${(n%1000000n).toString().padStart(6,'0').replace(/0+$/,'').padEnd(2,'0')}`;
const campaignStatuses=['ENABLED','PAUSED','REMOVED','UNKNOWN','UNSPECIFIED'];
const campaignChannels=['DEMAND_GEN','DISPLAY','HOTEL','LOCAL','LOCAL_SERVICES','MULTI_CHANNEL','PERFORMANCE_MAX','SEARCH','SHOPPING','SMART','TRAVEL','UNKNOWN','UNSPECIFIED','VIDEO'];
export async function readGooglePerformance(ads,token,account,root,range,scope='account') {
  if(!['account','campaign'].includes(scope))unreadable();
  const campaign=scope==='campaign',maxRows=campaign?500:range?.days,maxPages=campaign?5:3;
  const capacity=()=>campaign?fail('Google returned more than 500 campaign rows. Try another advertising account or a shorter period.',409):unreadable();
  if(!account||!/^\d{10}$/.test(account.id)||!/^[A-Z]{3}$/.test(account.currency)||typeof account.timezone!=='string'||!account.timezone||!range||![7,30,90].includes(range.days)||(date(range.to)-date(range.from))/DAY+1!==range.days||(root!=null&&!/^\d{10}$/.test(root)))unreadable();
  const query=campaign
    ? `SELECT customer.id, customer.currency_code, customer.time_zone, campaign.resource_name, campaign.id, campaign.name, campaign.status, campaign.advertising_channel_type, metrics.cost_micros, metrics.impressions, metrics.clicks FROM campaign WHERE segments.date BETWEEN '${range.from}' AND '${range.to}' ORDER BY campaign.id ASC LIMIT 501`
    : `SELECT customer.id, customer.currency_code, customer.time_zone, segments.date, metrics.cost_micros, metrics.impressions, metrics.clicks FROM customer WHERE segments.date BETWEEN '${range.from}' AND '${range.to}' ORDER BY segments.date DESC LIMIT 91`;
  const rows=[],dates=new Set(),pages=new Set();let pageToken,totalSpend=0n,totalImpressions=0n,totalClicks=0n;
  for(let page=0;page<maxPages;page++){
    const result=await ads(`customers/${account.id}/googleAds:search`,token,root,{query,...(pageToken?{pageToken}:{})});
    if(!result||typeof result!=='object'||Array.isArray(result)||(result.results!==undefined&&!Array.isArray(result.results)))unreadable();
    const data=result.results??[];if(data.length>maxRows)capacity();
    for(const row of data){
      if(!row||row.customer?.id!==account.id||row.customer?.currencyCode!==account.currency||row.customer?.timeZone!==account.timezone||!row.metrics||typeof row.metrics!=='object'||Array.isArray(row.metrics))unreadable();
      let identity,details;
      if(campaign){
        const c=row.campaign;
        if(!c||typeof c.id!=='string'||!/^([1-9]\d{0,18})$/.test(c.id)||BigInt(c.id)>9223372036854775807n||c.resourceName!==`customers/${account.id}/campaigns/${c.id}`||typeof c.name!=='string'||!c.name.trim()||c.name.length>1000||!campaignStatuses.includes(c.status)||!campaignChannels.includes(c.advertisingChannelType)||(row.segments!==undefined&&(!row.segments||typeof row.segments!=='object'||Object.keys(row.segments).length)))unreadable();
        identity=c.id;details={campaign_id:c.id,campaign_name:c.name.trim(),status:c.status,channel:c.advertisingChannelType};
      }else{
        identity=row.segments?.date;date(identity);if(identity<range.from||identity>range.to)unreadable();details={date:identity};
      }
      if(dates.has(identity))unreadable();dates.add(identity);
      const spend=integer(row.metrics.costMicros,MAX_SPEND),impressions=integer(row.metrics.impressions,MAX_COUNT),clicks=integer(row.metrics.clicks,MAX_COUNT);
      totalSpend+=spend;totalImpressions+=impressions;totalClicks+=clicks;
      if(dates.size>maxRows)capacity();
      if(totalSpend>MAX_SPEND||totalImpressions>MAX_COUNT||totalClicks>MAX_COUNT)unreadable();
      rows.push({...details,spend:money(spend),impressions:Number(impressions),clicks:Number(clicks)});
    }
    if(result.nextPageToken===undefined||result.nextPageToken==='')return {rows:rows.sort((a,b)=>campaign?a.campaign_id.localeCompare(b.campaign_id):b.date.localeCompare(a.date)),totals:{spend:money(totalSpend),impressions:Number(totalImpressions),clicks:Number(totalClicks)},[campaign?'reported_campaigns':'reported_days']:rows.length};
    pageToken=result.nextPageToken;
    if(typeof pageToken!=='string'||!pageToken||pageToken.length>4000||pages.has(pageToken))unreadable();pages.add(pageToken);
  }
  fail(campaign?'Google campaign reporting exceeded the page limit. Try a shorter period or another advertising account.':'Google reporting exceeded the page limit. Try a shorter period.',503);
}
