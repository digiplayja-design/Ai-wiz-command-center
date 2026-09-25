import {fail,id} from './core.mjs';
export const reportKinds=['profit_loss','balance_sheet','trial_balance','ledger'];
export function reportQuery(q,{exporting=false}={}){
 if(typeof q.period!=='string'||!/^20\d\d(?:-(?:0[1-9]|1[0-2]))?$/.test(q.period))fail('Choose YYYY or YYYY-MM between 2000 and 2099.');
 if(exporting&&!reportKinds.includes(q.kind))fail('Choose a report to export.');
 return {period:q.period,include_lines:exporting&&q.kind==='ledger'};
}
export const reportScope='Recorded USD books only; completeness and account classifications are owner supplied. Operating profit and loss includes recorded cash income and expenses. Bank reconciliation, accruals, depreciation, tax calculations and annual closing entries are not performed.';
export function buildReports(d){
 const sum=(kind,field)=>d.accounts.filter(a=>kind.includes(a.kind)).reduce((n,a)=>n+BigInt(a[field]),0n);
 const income=sum(['income'],'period_credit_cents')-sum(['income'],'period_debit_cents');
 const expense=sum(['expense'],'period_debit_cents')-sum(['expense'],'period_credit_cents');
 const assets=sum(['cash','asset'],'closing_cents'),liabilities=-sum(['liability'],'closing_cents'),bookedEquity=-sum(['equity'],'closing_cents');
 const earnings=-sum(['income','expense'],'closing_cents'),prior=-sum(['income','expense'],'prior_year_cents');
 const debit=d.accounts.reduce((s,a)=>s+(BigInt(a.closing_cents)>0n?BigInt(a.closing_cents):0n),0n);
 const credit=d.accounts.reduce((s,a)=>s+(BigInt(a.closing_cents)<0n?-BigInt(a.closing_cents):0n),0n);
 const warnings=[];
 if(!d.opening)warnings.push('No opening balances are recorded. Confirm a zero starting position or add prior closing balances.');
 else if(d.opening.entry_date>=d.from_date)warnings.push(d.opening.entry_date>d.as_of?'This period is before the recorded opening balances. Earlier activity is outside these books.':'This period includes the initial cutover. Activity on or before the opening date is outside these books.');
 if(d.cash_entry_count+d.journal_count===0)warnings.push('No activity was recorded in this period. Balance-sheet and trial-balance amounts can still include earlier records.');
 if(assets-liabilities-bookedEquity-earnings!==0n||debit!==credit)warnings.push('The recorded ledger does not balance. Review the entries before relying on this report.');
 return {...d,scope:reportScope,warnings,summary:Object.fromEntries(Object.entries({income_cents:income,expense_cents:expense,net_cents:income-expense,assets_cents:assets,liabilities_cents:liabilities,booked_equity_cents:bookedEquity,prior_earnings_cents:prior,current_earnings_cents:earnings-prior,total_equity_cents:bookedEquity+earnings,balance_difference_cents:assets-liabilities-bookedEquity-earnings,trial_debit_cents:debit,trial_credit_cents:credit}).map(([k,v])=>[k,String(v)]))};
}
const dollars=v=>{const n=BigInt(v),a=n<0n?-n:n;return `${n<0n?'-':''}${a/100n}.${(a%100n).toString().padStart(2,'0')}`;};
const number=v=>({numeric:dollars(v)});
const side=(v,debit)=>{const n=BigInt(v);return number(debit?(n>0n?n:0n):(n<0n?-n:0n));};
export function reportsCsv(d,kind){
 const titles={profit_loss:'Recorded profit and loss',balance_sheet:'Recorded balance sheet',trial_balance:'Recorded trial balance',ledger:'Recorded general ledger'};
 const rows=[[titles[kind]],['Business',d.business.name],['Business ID',d.business.id],['Currency','USD'],['Period start',d.from_date],['As of',d.as_of],['Generated at',d.generated_at],['Scope',d.scope],['Opening balances',d.opening?.entry_date??'Not recorded'],...d.warnings.map(w=>['Note',w]),[]];
 const s=d.summary;
 if(kind==='profit_loss'){
  rows.push(['Section','Account code','Account name','USD']);
  for(const a of d.accounts.filter(a=>['income','expense'].includes(a.kind)))rows.push([a.kind==='income'?'Income':'Expense',a.code,a.name,number(a.kind==='income'?BigInt(a.period_credit_cents)-BigInt(a.period_debit_cents):BigInt(a.period_debit_cents)-BigInt(a.period_credit_cents))]);
  rows.push(['Total income','','',number(s.income_cents)],['Total expenses','','',number(s.expense_cents)],['Recorded net profit / loss','','',number(s.net_cents)]);
 }else if(kind==='balance_sheet'){
  rows.push(['Section','Account code','Account name','USD']);
  for(const a of d.accounts.filter(a=>['cash','asset','liability','equity'].includes(a.kind)))rows.push([['cash','asset'].includes(a.kind)?'Assets':a.kind==='liability'?'Liabilities':'Booked equity',a.code,a.name,number(['cash','asset'].includes(a.kind)?a.closing_cents:-BigInt(a.closing_cents))]);
  rows.push(['Unclosed earnings','','Prior calendar years',number(s.prior_earnings_cents)],['Unclosed earnings','','Current calendar year to date',number(s.current_earnings_cents)],['Total assets','','',number(s.assets_cents)],['Total liabilities','','',number(s.liabilities_cents)],['Total equity including unclosed earnings','','',number(s.total_equity_cents)],['Balance check difference','','',number(s.balance_difference_cents)],[],['Note','Unclosed earnings are calculated from recorded income/expense accounts. No closing journal is posted; booked equity is separate. Calendar-year labels do not select a tax or fiscal year.']);
 }else if(kind==='trial_balance'){
  rows.push(['Account code','Account name','Type','Beginning debit USD','Beginning credit USD','Period debit USD','Period credit USD','Closing debit USD','Closing credit USD']);
  for(const a of d.accounts)rows.push([a.code,a.name,a.kind,side(a.beginning_cents,true),side(a.beginning_cents,false),number(a.period_debit_cents),number(a.period_credit_cents),side(a.closing_cents,true),side(a.closing_cents,false)]);
  const total=f=>d.accounts.reduce((n,a)=>n+BigInt(a[f]),0n);
  rows.push(['TOTAL','','',number(d.accounts.reduce((n,a)=>n+(BigInt(a.beginning_cents)>0n?BigInt(a.beginning_cents):0n),0n)),number(d.accounts.reduce((n,a)=>n+(BigInt(a.beginning_cents)<0n?-BigInt(a.beginning_cents):0n),0n)),number(total('period_debit_cents')),number(total('period_credit_cents')),number(s.trial_debit_cents),number(s.trial_credit_cents)]);
 }else{
  rows.push(['Entry ID','Date','Source','Type','Description','Account code','Account name','Account type','Debit USD','Credit USD','Reverses entry','Recorded at','Current receipt references (JSON)']);
  for(const l of d.lines)rows.push([l.entry_id,l.entry_date,l.source,l.kind,l.purpose,l.account_code,l.account_name,l.account_kind,number(l.debit_cents),number(l.credit_cents),l.reversal_of,l.created_at,JSON.stringify(l.receipts)]);
  rows.push([],['Note','Receipt references describe currently linked evidence, repeated on each cash-entry leg. Reversals reference original evidence. Original files remain private in the receipt inbox; files are not embedded. Journal attachments are not supported yet.']);
 }
 const cell=v=>{let value;if(v&&typeof v==='object'&&/^-?\d+\.\d{2}$/.test(v.numeric)){value=v.numeric;}else{value=String(v??'');if(/^\s*[=+\-@]/.test(value)||/^[\t\r\n]/.test(value))value="'"+value;}return '"'+value.replaceAll('"','""')+'"';};
 return {filename:`korlix-${kind.replaceAll('_','-')}-${d.business.id}-${d.period}.csv`,csv:'\uFEFF'+rows.map(r=>r.map(cell).join(',')).join('\r\n')+'\r\n',period:d.period,kind,generated_at:d.generated_at};
}
export function registerReportRoutes(app,{route,database}){
 const call=async(u,b,p)=>{const r=await database.rpc('korlix_bookkeeping_reports_v1',{p_actor:u,p_business:b,p_data:p});if(r.error){const e=r.error;const status={P0002:404,'54000':422,P0001:400}[e.code]??503;fail(['P0002','54000','P0001'].includes(e.code)?e.message:'Reports are temporarily unavailable. Try again.',status,'BOOKKEEPING_REPORT_ERROR');}if(!r.data)fail('Reports are temporarily unavailable.',503);return buildReports(r.data);};
 const base='/api/bookkeeping/businesses/:id/reports';
 app.get(base,route(async(q,r,u)=>r.json(await call(u,id(q.params.id),reportQuery(q.query)))));
 app.get(base+'/export',route(async(q,r,u)=>{const p=reportQuery(q.query,{exporting:true});r.json(reportsCsv(await call(u,id(q.params.id),p),q.query.kind));}));
}
