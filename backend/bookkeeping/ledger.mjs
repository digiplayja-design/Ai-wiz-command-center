import {cents,fail,id,monthQuery} from './core.mjs';
export const journalKinds=['contribution','distribution','loan_received','loan_principal','asset_purchase','transfer','adjustment','opening'];
const text=(v,label,max)=>{if(typeof v!=='string'||!v.trim()||v.trim().length>max||/[\u0000-\u001f\u007f]/.test(v))fail(`${label} must contain 1–${max} characters without line breaks.`);return v.trim();};
function confirmed(v){if(!v||typeof v!=='object'||Array.isArray(v)||v.confirmed!==true)fail('Review and confirm first.');return {request_key:id(v.request_key),confirmed:true};}
export function accountPayload(v){const p=confirmed(v);if(!['cash','asset','liability','equity'].includes(v.kind))fail('Choose a cash, asset, liability or equity account.');return {...p,name:text(v.name,'Account name',80),kind:v.kind};}
export function journalPayload(v,journalId){
 const p=confirmed(v);if(journalId)return {...p,journal_id:id(journalId),reason:text(v.reason,'Reversal reason',500)};
 if(!journalKinds.includes(v.kind))fail('Choose a journal type.');
 if(typeof v.entry_date!=='string'||!/^20\d\d-\d\d-\d\d$/.test(v.entry_date))fail('Enter a date between 2000 and 2099.');
 const date=new Date(v.entry_date+'T00:00:00.000Z');if(!Number.isFinite(date.getTime())||date.toISOString().slice(0,10)!==v.entry_date)fail('Enter a valid calendar date.');
 if(!Array.isArray(v.lines)||v.lines.length<2||v.lines.length>100)fail('Use 2 to 100 balanced lines.');
 const seen=new Set();let debit=0n,credit=0n;
 const lines=v.lines.map(l=>{if(!l||typeof l!=='object'||typeof l.account!=='string'||!/^[0-9]{4}$/.test(l.account)||seen.has(l.account)||!['debit','credit'].includes(l.side))fail('Use each account once and select debit or credit.');seen.add(l.account);const n=cents(l.amount);debit+=l.side==='debit'?BigInt(n):0n;credit+=l.side==='credit'?BigInt(n):0n;return {account:l.account,debit_cents:l.side==='debit'?n:'0',credit_cents:l.side==='credit'?n:'0'};}).sort((a,b)=>a.account.localeCompare(b.account));
 if(debit!==credit)fail('Debits and credits must balance.');
 return {...p,kind:v.kind,entry_date:v.entry_date,purpose:text(v.purpose,'Description',500),lines};
}
export function ledgerCsv(d){
 const cell=v=>{let s=String(v??'');if(/^\s*[=+\-@]/.test(s)||/^[\t\r\n]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';};
 const dollars=n=>`${BigInt(n)/100n}.${(BigInt(n)%100n).toString().padStart(2,'0')}`;
 const rows=[['Business','Entry ID','Date','Source','Type','Description','Account code','Account name','Account type','Debit USD','Credit USD','Reverses entry','Recorded at']];
 for(const l of d.lines)rows.push([d.business.name,l.entry_id,l.entry_date,l.source,l.kind,l.purpose,l.account_code,l.account_name,l.account_kind,dollars(l.debit_cents),dollars(l.credit_cents),l.reversal_of,l.created_at]);
 return {filename:`korlix-ledger-${d.business.id}-${d.month}.csv`,count:d.lines.length,csv:'\uFEFF'+rows.map(r=>r.map(cell).join(',')).join('\r\n')+'\r\n'};
}
export function registerLedgerRoutes(app,{route,database}){
 const call=async(u,a,b,p)=>{const r=await database.rpc('korlix_bookkeeping_ledger_v1',{p_actor:u,p_action:a,p_business:b,p_data:p});if(r.error){const e=r.error;const status={P0002:404,'40001':409,'23505':409,'54000':422,P0001:400,'23514':400,'23502':400,'22P02':400,'22007':400,'22008':400}[e.code]??503;fail(['P0001','P0002','40001','54000'].includes(e.code)?e.message:e.code==='23505'?'An account name or request already exists. Refresh before retrying.':'Journal could not be saved. Check accounts, amounts and opening balance dates.',status,'BOOKKEEPING_LEDGER_ERROR');}if(!r.data)fail('Ledger storage is unavailable.',503);return r.data;};
 const base='/api/bookkeeping/businesses/:id/ledger';
 app.get(base,route(async(q,r,u)=>r.json(await call(u,'list',id(q.params.id),monthQuery(q.query)))));
 app.get(base+'/export',route(async(q,r,u)=>r.json(ledgerCsv(await call(u,'export',id(q.params.id),monthQuery(q.query))))));
 app.post(base+'/accounts',route(async(q,r,u)=>r.status(201).json(await call(u,'account',id(q.params.id),accountPayload(q.body)))));
 app.post(base+'/journals',route(async(q,r,u)=>r.status(201).json(await call(u,'post',id(q.params.id),journalPayload(q.body)))));
 app.post(base+'/journals/:journal/reverse',route(async(q,r,u)=>r.status(201).json(await call(u,'reverse',id(q.params.id),journalPayload(q.body,q.params.journal)))));
}
