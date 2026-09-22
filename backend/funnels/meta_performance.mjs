import {fail,version} from './core.mjs';
const unreadable=()=>fail('Meta returned incomplete or inconsistent performance data. Refresh or try a shorter period.',503);
const DAY=86400000,MAX_COUNT=BigInt(Number.MAX_SAFE_INTEGER),MAX_SPEND=1000000000000000000n;
export function metaReportQuery(query={}) {
  if(Object.keys(query).some(k=>!['days','version','account_id'].includes(k))||!['7','30','90'].includes(query.days)||typeof query.version!=='string'||!/^\d{1,10}$/.test(query.version)||typeof query.account_id!=='string'||!/^act_\d{1,40}$/.test(query.account_id))fail('Choose a reporting period and the current selected Meta account.');
  return{days:Number(query.days),version:version(Number(query.version)),account_id:query.account_id};
}
export function metaReportRange(days,timezone,now=Date.now()) {
  if(![7,30,90].includes(days))fail('Choose 7, 30 or 90 completed days.');
  let parts;
  try{if(typeof timezone!=='string'||!timezone)throw Error();parts=new Intl.DateTimeFormat('en-US',{timeZone:timezone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date(now));}catch{fail('Meta returned an unavailable account timezone. Refresh your ad accounts.',503);}
  const get=k=>parts.find(p=>p.type===k).value;
  const today=Date.parse(`${get('year')}-${get('month')}-${get('day')}T00:00:00Z`);
  // Subtract calendar dates, not elapsed local hours, across DST transitions.
  return{from:new Date(today-days*DAY).toISOString().slice(0,10),to:new Date(today-DAY).toISOString().slice(0,10),days};
}
function count(value) {
  if(typeof value!=='string'||!/^\d{1,16}$/.test(value))unreadable();
  const n=BigInt(value);if(n>MAX_COUNT)unreadable();return n;
}
function spend(value) {
  if(typeof value!=='string'||!/^\d{1,13}(\.\d{1,6})?$/.test(value))unreadable();
  const [whole,fraction='']=value.split('.'),n=BigInt(whole)*1000000n+BigInt(fraction.padEnd(6,'0'));
  if(n>MAX_SPEND)unreadable();return n;
}
function money(n) {
  const fraction=(n%1000000n).toString().padStart(6,'0').replace(/0+$/,'').padEnd(2,'0');
  return(n/1000000n).toString()+'.'+fraction;
}
export async function readMetaInsights(graph,token,account,range) {
  if(!/^act_\d{1,40}$/.test(account.id)||!/^[A-Z]{3}$/.test(account.currency))unreadable();
  const rows=[],dates=new Set(),cursors=new Set();let after,totalSpend=0n,totalImpressions=0n,totalClicks=0n;
  for(let page=0;page<3;page++){
    const result=await graph(`${account.id}/insights`,{
      fields:'account_id,account_currency,date_start,date_stop,spend,impressions,clicks',level:'account',
      time_range:JSON.stringify({since:range.from,until:range.to}),time_increment:1,limit:100,...(after?{after}:{}),
    },token);
    if(!Array.isArray(result?.data)||result.data.length>100)unreadable();
    for(const row of result.data){
      if(!row||row.account_id!==account.id.slice(4)||row.account_currency!==account.currency||typeof row.date_start!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(row.date_start)||row.date_stop!==row.date_start||row.date_start<range.from||row.date_start>range.to||dates.has(row.date_start))unreadable();
      const parsed=Date.parse(row.date_start+'T00:00:00Z');if(!Number.isFinite(parsed)||new Date(parsed).toISOString().slice(0,10)!==row.date_start)unreadable();
      const s=spend(row.spend),impressions=count(row.impressions),clicks=count(row.clicks);dates.add(row.date_start);
      totalSpend+=s;totalImpressions+=impressions;totalClicks+=clicks;
      if(rows.length>=range.days||totalSpend>MAX_SPEND||totalImpressions>MAX_COUNT||totalClicks>MAX_COUNT)unreadable();
      rows.push({date:row.date_start,spend:money(s),impressions:Number(impressions),clicks:Number(clicks)});
    }
    if(!result.paging?.next)return{rows:rows.sort((a,b)=>b.date.localeCompare(a.date)),totals:{spend:money(totalSpend),impressions:Number(totalImpressions),clicks:Number(totalClicks)},reported_days:rows.length};
    after=result.paging?.cursors?.after;
    if(typeof after!=='string'||!after||after.length>4000||cursors.has(after))unreadable();
    cursors.add(after); // Never follow the provider's pagination URL.
  }
  fail('Meta reporting could not finish within the page limit. Try a shorter period.',503);
}
