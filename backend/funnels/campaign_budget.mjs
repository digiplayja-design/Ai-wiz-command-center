import {fail,uuid,version} from './core.mjs';

const DAY=86400000;
const date=s=>typeof s==='string'&&/^\d{4}-\d{2}-\d{2}$/.test(s)&&Number.isFinite(Date.parse(s))&&new Date(s).toISOString().slice(0,10)===s;
const integer=(n,min,max)=>Number.isSafeInteger(n)&&n>=min&&n<=max;
const invalid=()=>fail('Budget tracking data is incomplete. Refresh before using these totals.',503);
// Dates are UTC calendar days; money remains integer USD cents throughout.
export function campaignBudgetSummary(data) {
  if(!data||!date(data.as_of_date)||!integer(data.daily_cents,100,1000000)||!integer(data.days,1,90)
    ||!Array.isArray(data.reports)||data.reports.length>731||data.currency!=='USD'||data.reporting_source!=='manual'
    ||data.budget_enforced!==false||data.ad_publishing_ready!==false)invalid();
  const reports=new Map();
  for(const r of data.reports){
    if(!r||!date(r.day)||r.day>data.as_of_date||!integer(r.spend_cents,0,100000000)||reports.has(r.day))invalid();
    reports.set(r.day,r.spend_cents);
  }
  if(data.start_date===null)return {...data,pacing:null};
  if(!date(data.start_date))invalid();
  const start=Date.parse(data.start_date),rows=[];
  let recorded=0,completedSpend=0,completed=0,reportedCompleted=0,reported=0;
  const missing=[];
  for(let i=0;i<data.days;i++){
    const day=new Date(start+i*DAY).toISOString().slice(0,10),spend=reports.get(day)??null;
    const status=day>data.as_of_date?'future':day===data.as_of_date?'today':spend===null?'missing':'recorded';
    if(spend!==null){recorded+=spend;reported++;}
    if(day<data.as_of_date){completed++;if(spend===null)missing.push(day);else{completedSpend+=spend;reportedCompleted++;}}
    rows.push({day,spend_cents:spend,status});
  }
  const end=rows.at(-1).day,total=data.daily_cents*data.days;
  return {...data,pacing:{end_date:end,phase:data.as_of_date<data.start_date?'upcoming':data.as_of_date>end?'finished':'active',
    planned_total_cents:total,recorded_spend_cents:recorded,balance_cents:total-recorded,
    completed_days:completed,reported_days:reported,reported_completed_days:reportedCompleted,
    completed_spend_cents:completedSpend,reported_days_plan_cents:reportedCompleted*data.daily_cents,
    reported_days_variance_cents:completedSpend-reportedCompleted*data.daily_cents,
    missing_dates:missing,excluded_report_days:reports.size-reported,rows}};
}

export function registerCampaignBudget(app,{base,owner,database}) {
  const path=base+'/:id/campaigns/:campaign_id/budget';
  const action=action=>owner(async(q,r,u)=>{
    if(Object.keys(q.query).length)fail('Use the saved budget window without extra parameters.');
    const data={campaign_id:uuid(q.params.campaign_id)};
    if(action!=='read'){
      const b=q.body;
      const fields=action==='save'?['version','campaign_version','start_date']:['version','campaign_version','confirmed'];
      if(!b||Array.isArray(b)||typeof b!=='object'||Object.keys(b).length!==fields.length||Object.keys(b).some(k=>!fields.includes(k)))fail('Check the budget tracking fields.');
      if(!integer(b.version,0,2147483646))fail('Refresh the reporting window before saving.');
      Object.assign(data,{version:b.version,campaign_version:version(b.campaign_version)});
      if(action==='save'){if(!date(b.start_date))fail('Choose a valid UTC start date.');data.start_date=b.start_date;}
      else{if(b.confirmed!==true)fail('Confirm clearing the reporting window.');data.confirmed=true;}
    }
    if(!database)fail('Budget tracking storage is not configured.',503);
    const {data:out,error}=await database.rpc('korlix_funnel_campaign_budget_v1',{p_actor:u,p_action:action,p_funnel:uuid(q.params.id),p_data:data});
    if(error){const status={'42501':403,'P0002':404,'40001':409,'P0001':400,'23514':400}[error.code];fail(status?error.message:'Budget tracking storage is temporarily unavailable.',status||503);}
    r.json(campaignBudgetSummary(out));
  },{ratePrefix:'campaign-budget:',max:30});
  app.get(path,action('read'));
  app.post(path+'/save',action('save'));
  app.post(path+'/clear',action('clear'));
}
