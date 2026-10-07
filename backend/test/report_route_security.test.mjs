import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import crypto from 'node:crypto';
import {createReportSubmissionGuard} from '../security/report_submission.mjs';

const source=readFileSync(process.env.REPORT_SERVER_SOURCE || new URL('../server.js',import.meta.url),'utf8');
test('report administrator credentials work only in headers, never URL query parameters',()=>{
  const start=source.indexOf('function korlixReportDeliveryV2AdminAuthorized(req)');
  const end=source.indexOf('\napp.post(',start);
  const context={crypto,KORLIX_REPORT_DELIVERY_V2_ADMIN_TOKEN:'fixture-admin-secret',korlixReportDeliveryV2String:(value,fallback='')=>String(value??fallback)};
  vm.createContext(context);vm.runInContext(source.slice(start,end),context);
  const allowed=context.korlixReportDeliveryV2AdminAuthorized;
  assert.equal(allowed({headers:{},query:{token:'fixture-admin-secret'}}),false);
  assert.equal(allowed({headers:{authorization:'Bearer fixture-admin-secret'}}),true);
  assert.equal(allowed({headers:{'x-korlix-report-admin-token':'fixture-admin-secret'}}),true);
  assert.equal(allowed({headers:{authorization:'Bearer wrong'}}),false);
});
function fixture({authenticated=true,throws=false,delivered=true}={}) {
  const callbacks={};const persisted=[];const emailed=[];const logs=[];const reports=[];
  const start=source.indexOf('app.post(\n  ["/api/report-output",');
  const end=source.indexOf('app.get("/api/report-output/recent",',start);
  assert(start>=0 && end>start);
  vm.runInNewContext(source.slice(start,end),{
    app:{post:(paths,callback)=>{for(const path of paths)callbacks[path]=callback;},get:(path,callback)=>callbacks[path]=callback},
    requireUser:async()=>{if(!authenticated)throw Object.assign(new Error('secret auth diagnostic'),{statusCode:401});return {id:'real-user',email:'real@example.invalid'};},
    prepareSupportReport:createReportSubmissionGuard({idFactory:()=> 'synthetic-id'}),
    korlixReportDeliveryV2Persist:async report=>{persisted.push(report);if(throws)throw Object.assign(new Error('secret database diagnostic'),{statusCode:503});return {saved:true};},
    korlixReportDeliveryV2SendEmail:async report=>{emailed.push(report);return {delivered,response:{secret:'provider-internals'}};},
    supabaseAdmin:{},markAiReportNotification:async()=>true,
    console:{log:(...args)=>logs.push(args),error:(...args)=>logs.push(args)},
  });
  return {persisted,emailed,logs,reports,async call(path,body={}){
    const res={code:200,headers:{},set(key,value){this.headers[key]=value;return this;},status(code){this.code=code;return this;},json(body){this.body=body;return this;}};
    await callbacks[path]({body,headers:{}},res);return res;
  }};
}
test('all report aliases reject anonymous requests before writes, logs, and email',async()=>{
  const f=fixture({authenticated:false});
  for(const path of ['/api/report-output','/api/reports/content','/api/report']) assert.equal((await f.call(path)).code,401);
  assert.equal(f.persisted.length,0);assert.equal(f.emailed.length,0);assert.equal(f.logs.length,0);assert.equal(f.reports.length,0);
});
test('only verified actor fields are persisted and success exposes a receipt only',async()=>{
  const f=fixture();const res=await f.call('/api/report',{userId:'victim',userEmail:'victim@example.invalid',details:'private complaint'});
  assert.equal(res.code,200);assert.equal(f.persisted[0].userId,'real-user');assert.equal(f.persisted[0].userEmail,'real@example.invalid');
  assert.deepEqual(Object.keys(res.body).sort(),['message','ok','reportId']);
  assert.equal(res.headers['Cache-Control'],'no-store');
  assert(!JSON.stringify(f.logs).includes('private complaint'));assert(!JSON.stringify(res.body).includes('private'));assert(!JSON.stringify(res.body).includes('provider'));
});
test('oversized reports cause no logs, persistence, or email',async()=>{
  const f=fixture();const res=await f.call('/api/report-output',{details:'x'.repeat(40000)});
  assert.equal(res.code,413);assert.equal(f.persisted.length,0);assert.equal(f.emailed.length,0);assert.equal(f.logs.length,0);
});
test('alias rotation does not bypass per-user rate limits',async()=>{
  const f=fixture();for(let i=0;i<5;i++)await f.call('/api/report-output');
  const res=await f.call('/api/reports/content');
  assert.equal(res.code,429);assert(Number(res.headers['Retry-After'])>0);assert.equal(f.emailed.length,5);assert.equal(f.persisted.length,5);assert.equal(f.logs.length,5);
});
test('delivery and persistence internals never enter accepted or error responses',async()=>{
  const accepted=await fixture({delivered:false}).call('/api/report');assert.equal(accepted.code,202);assert(!JSON.stringify(accepted.body).includes('provider'));
  const f=fixture({throws:true});const error=await f.call('/api/report');assert.equal(error.code,503);assert(!JSON.stringify(error.body).includes('secret'));assert(!JSON.stringify(f.logs).includes('diagnostic'));
  assert.equal(f.emailed.length,0);assert.equal(f.logs.length,0);
});
test('public report health does not expose filesystem, provider, token configuration or report counts',async()=>{
  const response=await fixture().call('/api/report-output/health');
  assert.deepEqual(Object.keys(response.body).sort(),['feature','ok','reportDeliveryVersion']);assert.equal(response.code,200);
});
test('durable report review checks admin authority before any private database read',async()=>{
  const start=source.indexOf('app.get("/api/report-output/recent",');
  const end=source.indexOf('// KORLIX_REPORT_DELIVERY_V2_END',start);
  let callback;const reads=[];
  vm.runInNewContext(source.slice(start,end),{
    app:{get:(_path,fn)=>{callback=fn;}},supabaseAdmin:{},
    korlixReportDeliveryV2AdminAuthorized:req=>req.headers.authorization==='Bearer synthetic-admin',
    listAiReports:async(_db,limit)=>{reads.push(limit);return {reportCount:1,reports:[{details:'synthetic-private-report'}]};},
  });
  const invoke=async(headers)=>{
    const res={code:200,headers:{},set(k,v){this.headers[k]=v;return this;},status(c){this.code=c;return this;},json(b){this.body=b;return this;}};
    await callback({headers,query:{limit:'999'}},res);return res;
  };
  const denied=await invoke({});assert.equal(denied.code,403);assert.equal(reads.length,0);
  assert(!JSON.stringify(denied.body).includes('synthetic-private-report'));
  const allowed=await invoke({authorization:'Bearer synthetic-admin'});
  assert.equal(allowed.code,200);assert.equal(allowed.headers['Cache-Control'],'no-store');
  assert.deepEqual(reads,[100]);assert.equal(allowed.body.reports[0].details,'synthetic-private-report');
});
