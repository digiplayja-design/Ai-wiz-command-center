import {fail,id} from './core.mjs';

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
 const ledger=(report.lines??[]).filter(l=>l.account_code===input.cash_account);
 for(const entry of entries){
  if(entry.error)continue;
  entry.duplicate_in_file=seen.get(entry.fingerprint)>1;
  const time=Date.parse(entry.date+'T00:00:00Z');
  const candidates=ledger.filter(l=>{
   const v=BigInt(l.debit_cents)-BigInt(l.credit_cents);
   return v===BigInt(entry.amount_cents)&&Math.abs(Date.parse(l.entry_date+'T00:00:00Z')-time)<=3*86400000;
  });
  entry.candidates=candidates.slice(0,5).map(l=>({entry_id:l.entry_id,date:l.entry_date,kind:l.kind,source:l.source,amount_cents:entry.amount_cents}));
  entry.status=entry.duplicate_in_file?'duplicate_in_file':candidates.length===1?'suggested':candidates.length>1?'ambiguous':'unmatched';
  delete entry.fingerprint;
 }
 return {account:input.cash_account,year:input.year,row_count:entries.length,invalid_count:entries.filter(e=>e.error).length,duplicate_count:entries.filter(e=>e.duplicate_in_file).length,entries,scope:'Read-only suggestions. Nothing is imported, posted, reconciled, or saved. Review your bank statement and books before making corrections.'};
}
export function registerStatementPreviewRoutes(app,{route,database}){
 app.post('/api/bookkeeping/businesses/:id/statements/preview',route(async(q,r,u)=>{
  const business=id(q.params.id),body=q.body;
  if(!body||typeof body.csv!=='string'||Buffer.byteLength(body.csv,'utf8')>256*1024)fail('Choose a CSV statement up to 256 KB.');
  if(typeof body.year!=='string'||!/^20\d\d$/.test(body.year))fail('Choose a calendar year.');
  const result=await database.rpc('korlix_bookkeeping_reports_v1',{p_actor:u,p_business:business,p_data:{period:body.year,include_lines:true}});
  if(result.error){const e=result.error;fail(e.code==='P0002'?'Business not found.':'Statement preview is unavailable. Try again.',e.code==='P0002'?404:503);}
  if(!result.data)fail('Statement preview is unavailable.',503);
  r.json(previewStatement(body,result.data));
 }));
}
