#!/usr/bin/env node
// Operator-only aggregate inspection. No mutations, customer text, email addresses,
// user IDs, object paths, signed links, credentials, or report payloads are exported.
import {pathToFileURL} from 'node:url';

export const coveragePlan = Object.freeze({
  mode:'source-plan', liveVerified:false,
  queues:[
    {name:'Account deletion',table:'account_deletion_requests',open:{column:'status',value:'requested'},fulfillment:'Manual review; no complete account/storage/provider purger implemented.'},
    {name:'AI safety reports',table:'korlix_ai_output_reports',open:{column:'state',value:'open'},fulfillment:'Durable intake; protected review endpoint; controlled manual resolution.'},
    {name:'Social reports',table:'korlix_social_reports',open:{column:'state',value:'open'},fulfillment:'Assigned moderator uses in-app reports and confirmed actions.'},
    {name:'Legacy reports',table:'reports',open:{column:'status',value:'new'},fulfillment:'Inspect legacy queue separately; no assumption that it is empty.'},
  ],
  deletionCoverage:[
    {area:'Authentication and sessions',action:'Verify exact account; revoke sessions and prevent further writes before final deletion. Auth deletion alone does not invalidate every issued JWT.'},
    {area:'Receipt Wiz, Bookkeeping, Tax Prep',action:'One shared receipt record; remove original and preview objects before associated rows. Review business retention and preserve unrelated owner records.'},
    {area:'FieldProof and Workforce',action:'Private photos, GPS, reports, attachment queues, attendance and organization membership have different ownership and retention paths.'},
    {area:'Social, studios and portals',action:'Inspect attachment/image/album/video/recording objects and asynchronous cleanup; evaluate shared recipient/business records separately.'},
    {area:'Main-chat, agent memory and Brain Vault',action:'Delete retained text and derived records, not only inactive retrieval flags; inspect file-backed learning storage.'},
    {area:'Connected providers and automations',action:'Pause jobs, revoke credentials, address calendar/Zoom/YouTube/payroll/telephony data with the correct provider; handle billing separately.'},
    {area:'Reports, audit, logs and backups',action:'Restrict justified exceptions; inspect pre-migration local report files/email copies; document backup expiry and provider retention.'},
  ],
  remainingGates:[
    'Named support/privacy owner and backup, inbox access and coverage agreed.',
    'Named Social/child-safety reviewer and authorized moderator account verified.',
    'End-to-end synthetic deletion rehearsal proves database, object bytes and provider handling.',
    'Real support receipt and completion workflow verified without exposing customer data.',
  ],
});

async function count(database, table, filters) {
  try {
    let query=database.from(table).select('id',{count:'exact',head:true});
    for(const [operator,key,value] of filters) query=query[operator](key,value);
    const {count:value,error}=await query.abortSignal(AbortSignal.timeout(8000));
    if(error || !Number.isSafeInteger(value) || value<0) return {verified:false};
    return {verified:true,count:value};
  } catch {return {verified:false};}
}

export async function inspectSupportAggregates(database,{now=new Date()}={}) {
  const queueResults=await Promise.all(coveragePlan.queues.map(async queue=>{
    const filters=[['eq',queue.open.column,queue.open.value]];
    const [open,olderThan24Hours,olderThan7Days]=await Promise.all([
      count(database,queue.table,filters),
      count(database,queue.table,[...filters,['lte','created_at',new Date(now.getTime()-86400000).toISOString()]]),
      count(database,queue.table,[...filters,['lte','created_at',new Date(now.getTime()-7*86400000).toISOString()]]),
    ]);
    return {queue:queue.name,open,olderThan24Hours,olderThan7Days};
  }));
  // Moderator table uses user_id rather than id. This count does not reveal identities.
  let moderators={verified:false};
  try {
    const result=await database.from('korlix_social_moderators').select('user_id',{count:'exact',head:true}).abortSignal(AbortSignal.timeout(8000));
    if(!result.error && Number.isSafeInteger(result.count)) moderators={verified:true,count:result.count};
  } catch {}
  const [unnotified,reviewing]=await Promise.all([
    count(database,'korlix_ai_output_reports',[['in','notification_state',['queued','failed']],['neq','state','resolved']]),
    count(database,'korlix_ai_output_reports',[['eq','state','reviewing']]),
  ]);
  return {
    mode:'live-aggregates',checkedAt:now.toISOString(),mutationsPerformed:false,
    customerContentExported:false,queues:queueResults,assignedModerators:moderators,
    aiReportsAwaitingNotification:unnotified,aiReportsInReview:reviewing,
    limitations:'Counts establish queue visibility, not inbox access, staffed coverage, fulfilled deletion, physical object cleanup or provider deletion.',
  };
}

export function validateTarget(env, expectedProject) {
  let url;
  try {url=new URL(env.SUPABASE_URL);} catch {throw new Error('A valid SUPABASE_URL is required.');}
  if(!/^[a-z0-9]{20}$/.test(expectedProject||'') || url.protocol!=='https:' ||
    url.hostname!==`${expectedProject}.supabase.co` || url.username || url.password ||
    (url.pathname!=='/' && url.pathname!=='') || url.search || url.hash || url.port) {
    throw new Error('The database URL must match --expect-project exactly.');
  }
  if(!env.SUPABASE_SERVICE_ROLE_KEY) throw new Error('A server-only database credential is required through the environment.');
  return url.origin;
}

async function main(args) {
  if(args.length===0 || (args.length===1 && args[0]==='--source-plan')) {
    process.stdout.write(JSON.stringify(coveragePlan,null,2)+'\n');return;
  }
  if(args.length===1 && args[0]==='--help') {
    process.stdout.write('Usage: node backend/ops/support_readiness.mjs [--source-plan]\n       node backend/ops/support_readiness.mjs --live-aggregates --expect-project PROJECT_REF\nReads environment SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY only in live mode. Outputs aggregate counts, never customer content. No writes or emails.\n');return;
  }
  if(args.length!==3 || args[0]!=='--live-aggregates' || args[1]!=='--expect-project') throw new Error('Use --help for supported read-only options.');
  const url=validateTarget(process.env,args[2]);
  const {createClient}=await import('@supabase/supabase-js');
  const database=createClient(url,process.env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
  const result=await inspectSupportAggregates(database);
  process.stdout.write(JSON.stringify(result,null,2)+'\n');
  if(result.queues.some(q=>!q.open.verified || !q.olderThan24Hours.verified || !q.olderThan7Days.verified) ||
    !result.assignedModerators.verified || !result.aiReportsAwaitingNotification.verified || !result.aiReportsInReview.verified) process.exitCode=2;
}

if(process.argv[1] && import.meta.url===pathToFileURL(process.argv[1]).href) {
  main(process.argv.slice(2)).catch(()=>{process.stderr.write('Readiness inspection could not run. Check the documented arguments, project and server-only environment. No changes were made.\n');process.exitCode=1;});
}
