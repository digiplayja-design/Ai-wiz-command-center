import test from 'node:test';
import assert from 'node:assert/strict';
import sharp from 'sharp';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {prepareReportImageEvidence, reportImageMetadata, reportImageAttachments, maxReportImageBytes} from '../security/report_image_evidence.mjs';
import {readAiReportImage} from '../security/ai_report_persistence.mjs';
import {createReportSubmissionGuard} from '../security/report_submission.mjs';
const input = await sharp({create:{width:1920,height:1080,channels:3,background:'#1284af'}})
  .withExif({IFD0:{Artist:'private fixture metadata'}}).png().toBuffer();
const dataUrl = 'data:image/png;base64,' + input.toString('base64');
const evidence = await prepareReportImageEvidence(dataUrl);

test('review copy preserves image proportions, bounds size and strips private metadata',async()=>{
  const bytes=Buffer.from(evidence.base64,'base64');
  const meta=await sharp(bytes).metadata();
  assert.equal(meta.format,'jpeg');assert.equal(meta.width,1280);assert.equal(meta.height,720);
  assert.equal(meta.exif,undefined);assert.equal(meta.icc,undefined);
  assert(bytes.length<=maxReportImageBytes);assert.equal(bytes.length,evidence.byteLength);
  assert.equal(evidence.sha256,createHash('sha256').update(bytes).digest('hex'));
  assert(!('base64' in reportImageMetadata(evidence)));
  assert.deepEqual(reportImageAttachments(evidence),[{filename:'reported-image.jpg',content:evidence.base64,content_type:'image/jpeg',content_id:'reported-image'}]);
});

test('malformed, oversized, non-raster, mislabeled and excessive-pixel input is rejected',async()=>{
  for(const value of ['https://example.invalid/image.png','data:image/png;base64,@@@',
    'data:image/png;base64,'+Buffer.from('<svg xmlns="http://www.w3.org/2000/svg"/>').toString('base64'),
    dataUrl.replace('image/png','image/jpeg'), 'data:image/png;base64,'+Buffer.alloc(1024*1024+1).toString('base64')]) {
    await assert.rejects(prepareReportImageEvidence(value),e=>[400,413].includes(e.statusCode));
  }
  const bomb=await sharp({create:{width:4097,height:1024,channels:3,background:'black'}}).png().toBuffer();
  await assert.rejects(prepareReportImageEvidence('data:image/png;base64,'+bomb.toString('base64')),e=>e.statusCode===400);
  assert.equal(await prepareReportImageEvidence(undefined),null);
});

test('image budget cannot bypass metadata size limits or change trusted identity',()=>{
  const prepare=createReportSubmissionGuard();
  const req={body:{contentType:'image',imageDataUrl:dataUrl,userId:'victim'},headers:{}};
  const report=prepare({req,user:{id:'owner'}});
  assert.equal(report.userId,'owner');assert(!JSON.stringify(report).includes('base64'));
  assert.throws(()=>prepare({req:{body:{...req.body,unknown:'x'.repeat(33000)}},user:{id:'owner'}}),e=>e.statusCode===413);
  assert.throws(()=>prepare({req:{body:{...req.body,contentType:'text'}},user:{id:'owner'}}),e=>e.statusCode===400);
});

test('private image lookup scopes ordinary accounts before reading bytes',async()=>{
  const calls=[];
  const database={from(table){assert.equal(table,'korlix_ai_output_reports');const filters={};return {
    select(columns){assert.equal(columns,'image_evidence');return this;},
    eq(key,value){filters[key]=value;return this;},maybeSingle(){return this;},
    async abortSignal(){calls.push(filters);return {data:filters.user_id && filters.user_id!=='owner' ? null : {image_evidence:evidence}};}
  };}};
  const id='korlix_report_20000000-0000-4000-8000-000000000001';
  await assert.rejects(readAiReportImage(database,id),e=>e.statusCode===401);assert.equal(calls.length,0);
  assert.equal(await readAiReportImage(database,id,{userId:'other'}),null);
  assert.equal(await readAiReportImage(database,id,{userId:'owner'}),evidence);
  assert.equal(await readAiReportImage(database,id,{admin:true}),evidence);
  assert.deepEqual(calls,[{id,user_id:'other'},{id,user_id:'owner'},{id}]);
});

test('support email embeds exactly the saved review copy using a CID attachment',async()=>{
  const source=readFileSync(new URL('../server.js',import.meta.url),'utf8');
  const start=source.indexOf('function korlixReportDeliveryV2String(');
  const end=source.indexOf('function korlixReportDeliveryV2AdminAuthorized(',start);
  let mail;
  const context={process:{env:{RESEND_API_KEY:'synthetic-only'}},AbortSignal,reportImageAttachments,
    KORLIX_REPORT_DELIVERY_V2_FROM_EMAIL:'fixture@example.invalid',KORLIX_REPORT_DELIVERY_V2_SUPPORT_EMAIL:'reviewer@example.invalid',
    fetch:async(_url,options)=>{mail=JSON.parse(options.body);return {ok:true,status:200,text:async()=>'{"id":"fixture"}'};},console:{error(){}}
  };
  vm.createContext(context);vm.runInContext(source.slice(start,end),context);
  const report={id:'fixture',contentType:'image',prompt:'<img src="bad">',imageEvidence:reportImageMetadata(evidence)};
  assert.equal((await context.korlixReportDeliveryV2SendEmail(report,evidence)).delivered,true);
  assert.equal(mail.attachments[0].content,evidence.base64);
  assert(mail.html.includes('src="cid:reported-image"'));assert(mail.html.includes('&lt;img'));
  assert(!mail.text.includes(evidence.base64));assert(!mail.html.includes(evidence.base64));
  await context.korlixReportDeliveryV2SendEmail({...report,imageEvidence:null},null);
  assert.equal(mail.attachments.length,0);assert(mail.html.includes('No image was attached'));
});
