import {fail,id} from './core.mjs';
import {createHash} from 'node:crypto';

// A read-only preview. Statement bytes and candidate decisions are never stored.
export function parseStatementCsv(csv) {
 if(typeof csv!=='string'||Buffer.byteLength(csv,'utf8')>256*1024||!csv.trim())fail('Choose a CSV statement up to 256 KB.');
 const text=csv.replace(/^\uFEFF/,'');let rows=[],row=[],field='',quoted=false,closed=false;
 for(let i=0;i<text.length;i++){
  const ch=text[i];
  if(quoted){if(ch==='"'&&text[i+1]==='"'){field+='"';i++;}else if(ch==='"'){quoted=false;closed=true;}else field+=ch;}
  else if(ch==='"'){if(field||closed)fail('Malformed CSV quotation.');quoted=true;}
  else if(ch===','||ch==='\n'||ch==='\r'){
   row.push(field);field='';closed=false;
   if(ch!==','){if(row.some(v=>v!==''))rows.push(row);row=[];if(ch==='\r'&&text[i+1]==='\n')i++;}
  }else{if(closed)fail('Malformed CSV quotation.');field+=ch;}
  if(field.length>1000||rows.length>501)fail('Statement exceeds 500 rows or 1,000 characters per field.');
 }
 if(quoted)fail('CSV contains an unclosed quotation.');
 row.push(field);if(row.some(v=>v!==''))rows.push(row);
 if(rows.length<2||rows.length>501)fail('Choose a CSV with a header and 1–500 statement rows.');
 const header=rows.shift().map(h=>h.trim());
 if(header.some(h=>!h||h.length>80)||new Set(header.map(h=>h.toLowerCase())).size!==header.length)fail('CSV headers must be distinct and nonempty.');
 if(rows.some(r=>r.length!==header.length))fail('Every statement row must have the same number of columns.');
 return {header,rows};
}
function amount(value,{signed=false}={}) {
 const raw=value.trim();if(!/^-?(?:0|[1-9]\d{0,9})(?:\.\d{1,2})?$/.test(raw)||(raw.startsWith('-')&&!signed))fail('Use exact decimal USD amounts with no symbols or separators.');
 const neg=raw.startsWith('-'),v=neg?raw.slice(1):raw,[whole,fraction='']=v.split('.');
 const cents=BigInt(whole)*100n+BigInt(fraction.padEnd(2,'0'));
 if(cents>999999999999n)fail('Statement amount is outside the supported range.');
 return neg?-cents:cents;
}
function isoDate(s){
 if(!/^20\d\d-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])$/.test(s))fail('Use YYYY-MM-DD statement dates.');
 const d=new Date(s+'T00:00:00Z');if(!Number.isFinite(d.getTime())||d.toISOString().slice(0,10)!==s)fail('Statement has an invalid date.');
 return s;
}
export function suggestStatementMatches(entries,report,cashAccount){
 const reversed=new Set((report.lines??[]).filter(l=>l.reversal_of).map(l=>l.reversal_of));
 const ledger=(report.lines??[]).filter(l=>l.account_code===cashAccount&&l.kind!=='reversal'&&!reversed.has(l.entry_id));
 return entries.map(entry=>{
  if(entry.error)return entry;
  const time=Date.parse(entry.date+'T00:00:00Z');
  const candidates=ledger.filter(l=>{
   const v=BigInt(l.debit_cents)-BigInt(l.credit_cents);
   return v===BigInt(entry.amount_cents)&&Math.abs(Date.parse(l.entry_date+'T00:00:00Z')-time)<=3*86400000;
  });
  return {...entry,candidates:candidates.slice(0,5).map(l=>({entry_id:l.entry_id,date:l.entry_date,kind:l.kind,source:l.source,amount_cents:entry.amount_cents})),status:entry.duplicate_in_file?'duplicate_in_file':candidates.length===1?'suggested':candidates.length>1?'ambiguous':'unmatched'};
 });
}
export function statementCoverage(rows,decisions){
 const latest=new Map();
 for(const decision of decisions??[])latest.set(Number(decision.row_line),decision);
 let matched=0,total=0n,matchedTotal=0n;
 let from=null,through=null;
 for(const row of rows){
  const value=BigInt(row.amount_cents);
  total+=value;
  if(latest.get(Number(row.line))?.action==='match'){matched++;matchedTotal+=value;}
  if(from===null||row.date<from)from=row.date;
  if(through===null||row.date>through)through=row.date;
 }
 return {row_count:rows.length,matched_count:matched,open_count:rows.length-matched,
  statement_net_cents:String(total),matched_net_cents:String(matchedTotal),open_net_cents:String(total-matchedTotal),
  from_date:from,through_date:through,
  scope:'Review progress for imported rows only. These signed totals are not a cleared bank balance or proof of complete reconciliation.'};
}
export function statementReviewCsv(data){
 const s=data.statement,decisions=data.decisions??[];
 if(!s||!Array.isArray(s.rows)||!Array.isArray(decisions)||s.rows.length>500||decisions.length>5000)fail('Statement history is too large to export. Contact support.',422);
 const latest=new Map();
 for(const decision of decisions)latest.set(Number(decision.row_line),decision);
 const coverage=statementCoverage(s.rows,decisions);
 const cents=v=>({exactCents:String(v)});
 const rows=[['KORLIX saved statement review'],['Statement ID',s.id],['Cash account',s.cash_account],['Calendar year',s.statement_year],['Repeated-row review reason',s.duplicate_review_reason??''],['Scope',coverage.scope],['Imported dates',coverage.from_date,coverage.through_date],['Matched rows',coverage.matched_count],['Open rows',coverage.open_count],['Signed statement cents',cents(coverage.statement_net_cents)],['Matched signed cents',cents(coverage.matched_net_cents)],['Open signed cents',cents(coverage.open_net_cents)],[],['Line','Date','Description','Signed cents (text for precision)','Current status','Current entry ID']];
 for(const row of s.rows){const d=latest.get(Number(row.line));rows.push([row.line,row.date,row.description,cents(row.amount_cents),d?.action==='match'?'matched':'open',d?.action==='match'?d.entry_id:'']);}
 rows.push([],['Decision history (chronological)'],['Decision ID','Line','Action','Entry ID','Corrects decision ID','Reason','Recorded at']);
 for(const d of decisions)rows.push([d.id,d.row_line,d.action,d.entry_id,d.previous_match_id,d.reason,d.created_at]);
 const cell=v=>{let value;if(v&&typeof v==='object'&&/^-?\d+$/.test(v.exactCents)){value="'"+v.exactCents;}else{value=String(v??'');if(/^\s*[=+\-@]/.test(value)||/^[\t\r\n]/.test(value))value="'"+value;}return '"'+value.replaceAll('"','""')+'"';};
 return {filename:`korlix-statement-review-${s.id}.csv`,csv:'\uFEFF'+rows.map(r=>r.map(cell).join(',')).join('\r\n')+'\r\n',scope:coverage.scope};
}
export function previewStatement(input,report){
 if(!input||typeof input!=='object'||Array.isArray(input))fail('Choose a statement and its columns.');
 const {header,rows}=parseStatementCsv(input.csv);
 const m=input.mapping;if(!m||typeof m!=='object'||Array.isArray(m))fail('Map the statement columns.');
 const keys=['date','description',...(m.amount?['amount']:['debit','credit'])];
 if(keys.length!==new Set(keys.map(k=>m[k])).size||keys.some(k=>typeof m[k]!=='string'||!header.includes(m[k])))fail('Map distinct date, description and amount columns.');
 if(m.amount&&(m.debit||m.credit)||!m.amount&&(!m.debit||!m.credit))fail('Map a signed amount or separate debit and credit columns.');
 if(typeof input.year!=='string'||!/^20\d\d$/.test(input.year))fail('Choose a calendar year.');
 if(typeof input.cash_account!=='string'||!report?.accounts?.some(a=>a.kind==='cash'&&a.code===input.cash_account))fail('Choose a cash account for this business.');
 const indices=Object.fromEntries(keys.map(k=>[k,header.indexOf(m[k])]));
 const seen=new Map(),entries=[];
 for(let i=0;i<rows.length;i++){
  const r=rows[i];let date,delta,description;
  try{
   date=isoDate(r[indices.date].trim());if(!date.startsWith(input.year+'-'))fail('Statement dates must be in the selected calendar year.');
   description=r[indices.description].trim();if(!description||description.length>160)fail('Description must contain 1–160 characters.');
   if(m.amount){delta=amount(r[indices.amount],{signed:true});}
   else {const dr=r[indices.debit].trim(),cr=r[indices.credit].trim();if((!!dr)===(!!cr))fail('Enter exactly one debit or credit per row.');delta=cr?amount(cr): -amount(dr);}
   if(delta===0n)fail('Zero-amount statement rows cannot be matched.');
  }catch(e){entries.push({line:i+2,error:e.message});continue;}
  const fingerprint=`${date}|${delta}|${description.toLowerCase()}`;
  seen.set(fingerprint,(seen.get(fingerprint)??0)+1);
  entries.push({line:i+2,date,description,amount_cents:String(delta),fingerprint});
 }
 for(const entry of entries){if(!entry.error){entry.duplicate_in_file=seen.get(entry.fingerprint)>1;delete entry.fingerprint;}}
 const suggestions=suggestStatementMatches(entries,report,input.cash_account);
 return {account:input.cash_account,year:input.year,row_count:entries.length,invalid_count:entries.filter(e=>e.error).length,duplicate_count:entries.filter(e=>e.duplicate_in_file).length,entries:suggestions,scope:'Read-only suggestions. Repeated rows in this file need explicit owner review and a reason before import. Nothing is imported, posted, reconciled, or saved.'};
}
export function registerStatementPreviewRoutes(app,{route,database}){
 const base='/api/bookkeeping/businesses/:id/statements';
 const call=async(u,b,action,data={})=>{
  const result=await database.rpc('korlix_bookkeeping_statements_v1',{p_actor:u,p_action:action,p_business:b,p_data:data});
  if(result.error){
   const e=result.error,status={P0002:404,'40001':409,P0001:400,'23514':400}[e.code]??503;
   fail(['P0002','40001','P0001'].includes(e.code)?e.message:'Statement operation failed. Refresh before retrying.',status,'BOOKKEEPING_STATEMENT_ERROR');
  }
  if(!result.data)fail('Statement operation is unavailable.',503);
  return result.data;
 };
 app.post('/api/bookkeeping/businesses/:id/statements/preview',route(async(q,r,u)=>{
  const business=id(q.params.id),body=q.body;
  if(!body||typeof body.csv!=='string'||Buffer.byteLength(body.csv,'utf8')>256*1024)fail('Choose a CSV statement up to 256 KB.');
  if(typeof body.year!=='string'||!/^20\d\d$/.test(body.year))fail('Choose a calendar year.');
  const result=await database.rpc('korlix_bookkeeping_reports_v1',{p_actor:u,p_business:business,p_data:{period:body.year,include_lines:true}});
  if(result.error){const e=result.error;fail(e.code==='P0002'?'Business not found.':'Statement preview is unavailable. Try again.',e.code==='P0002'?404:503);}
  if(!result.data)fail('Statement preview is unavailable.',503);
  r.json(previewStatement(body,result.data));
 }));
 app.get(base,route(async(q,r,u)=>r.json(await call(u,id(q.params.id),'list'))));
 app.get(base+'/:statement/export',route(async(q,r,u)=>{
  const data=await call(u,id(q.params.id),'get',{statement_id:id(q.params.statement)});
  r.json(statementReviewCsv(data));
 }));
 app.get(base+'/:statement',route(async(q,r,u)=>{
  const business=id(q.params.id),data=await call(u,business,'get',{statement_id:id(q.params.statement)});
  const s=data.statement;
  data.coverage=statementCoverage(s.rows,data.decisions);
  const report=await database.rpc('korlix_bookkeeping_reports_v1',{p_actor:u,p_business:business,p_data:{period:String(s.statement_year),include_lines:true}});
  data.statement.rows=report.error||!report.data?s.rows.map(row=>({...row,candidates:[],status:'candidates_unavailable'})):suggestStatementMatches(s.rows,report.data,s.cash_account);
  r.json(data);
 }));
 app.post(base+'/import',route(async(q,r,u)=>{
  const business=id(q.params.id),body=q.body;
  if(body?.confirmed!==true)fail('Review and confirm the statement rows first.');
  const requestKey=id(body.request_key);
  if(typeof body.csv!=='string'||Buffer.byteLength(body.csv,'utf8')>256*1024)fail('Choose a CSV statement up to 256 KB.');
  if(typeof body.year!=='string'||!/^20\d\d$/.test(body.year))fail('Choose a calendar year.');
  const report=await database.rpc('korlix_bookkeeping_reports_v1',{p_actor:u,p_business:business,p_data:{period:body.year,include_lines:false}});
  if(report.error)fail(report.error.code==='P0002'?'Business not found.':'Statement report is unavailable.',report.error.code==='P0002'?404:503);
  if(!report.data)fail('Statement report is unavailable.',503);
  const preview=previewStatement(body,report.data);
  if(preview.invalid_count)fail('Fix invalid statement rows before importing. Nothing was saved.');
  const reason=typeof body.duplicate_review_reason==='string'?body.duplicate_review_reason.trim():'';
  if(preview.duplicate_count&&(reason.length<10||reason.length>500))fail('Repeated rows require an explanation of 10–500 characters after checking the original bank statement.');
  if(!preview.duplicate_count&&reason)fail('A repeated-row explanation is only needed for repeated rows in this CSV.');
  const rows=preview.entries.map(({line,date,description,amount_cents})=>({line,date,description,amount_cents}));
  const source_sha256=createHash('sha256').update(body.csv,'utf8').digest('hex');
  r.status(201).json(await call(u,business,'import',{request_key:requestKey,confirmed:true,cash_account:body.cash_account,year:body.year,source_sha256,rows,...(reason?{duplicate_review_reason:reason}:{})}));
 }));
 app.post(base+'/:statement/rows/:line/match',route(async(q,r,u)=>{
  if(q.body?.confirmed!==true)fail('Review and confirm the match first.');
  const line=Number(q.params.line);if(!Number.isInteger(line)||line<2||line>501)fail('Choose a statement row.');
  r.status(201).json(await call(u,id(q.params.id),'match',{statement_id:id(q.params.statement),row_line:line,entry_id:id(q.body.entry_id),request_key:id(q.body.request_key),confirmed:true}));
 }));
 app.post(base+'/:statement/rows/:line/unmatch',route(async(q,r,u)=>{
  if(q.body?.confirmed!==true||typeof q.body.reason!=='string'||!q.body.reason.trim()||q.body.reason.length>500)fail('Enter a reason and confirm the correction.');
  const line=Number(q.params.line);if(!Number.isInteger(line)||line<2||line>501)fail('Choose a statement row.');
  r.status(201).json(await call(u,id(q.params.id),'unmatch',{statement_id:id(q.params.statement),row_line:line,previous_match_id:id(q.body.previous_match_id),reason:q.body.reason.trim(),request_key:id(q.body.request_key),confirmed:true}));
 }));
}
