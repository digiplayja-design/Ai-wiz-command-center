export class BookkeepingError extends Error {
 constructor(message,status=400,code='BOOKKEEPING_INVALID'){super(message);this.status=status;this.code=code;}
}
export const fail=(message,status,code)=>{throw new BookkeepingError(message,status,code);};
export function id(value){if(typeof value!=='string'||! /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value))fail('Invalid record identifier.');return value.toLowerCase();}
function object(value){if(!value||typeof value!=='object'||Array.isArray(value))fail('Invalid request.');return value;}
function str(value,label,max,required=false){
 if(value===undefined&&!required)return '';
 if(typeof value!=='string')fail(`${label} must be text.`);
 const text=value.trim();if((required&&!text)||text.length>max||/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(text))fail(`${label} must contain ${required?'1–':'at most '}${max} characters.`);
 return text;
}
export const structures=['sole_proprietor','llc','corporation','partnership','other'];
export const treatments=['sole_proprietor','partnership','c_corporation','s_corporation','unsure'];
export function profile(value,{update=false}={}){
 const v=object(value);const p={name:str(v.name,'Business name',120,true),legal_structure:v.legal_structure,tax_treatment:v.tax_treatment,contractor_income:v.contractor_income};
 if(!structures.includes(p.legal_structure)||!treatments.includes(p.tax_treatment)||typeof p.contractor_income!=='boolean')fail('Choose a business structure and tax treatment.');
 const allowed={sole_proprietor:['sole_proprietor','unsure'],partnership:['partnership','unsure'],corporation:['c_corporation','s_corporation','unsure']};
 if(allowed[p.legal_structure]&&!allowed[p.legal_structure].includes(p.tax_treatment))fail('Tax treatment does not match this legal structure. Choose Not sure if needed.');
 if(update){if(!Number.isSafeInteger(v.version)||v.version<1)fail('Refresh this business before saving.');p.version=v.version;}
 else p.request_key=id(v.request_key);
 return p;
}
export function cents(value){
 if(typeof value!=='string'||! /^(?:0|[1-9][0-9]{0,9})(?:\.[0-9]{1,2})?$/.test(value))fail('Enter a positive USD amount with up to two decimal places.');
 const [whole,part='']=value.split('.');const n=BigInt(whole)*100n+BigInt(part.padEnd(2,'0'));
 if(n<1n||n>999999999999n)fail('Amount must be between $0.01 and $9,999,999,999.99.');return String(n);
}
export function monthQuery(q={}){
 const month=q.month;
 if(typeof month!=='string'||! /^20[0-9]{2}-(0[1-9]|1[0-2])$/.test(month))fail('Choose a month between 2000 and 2099.');
 const raw=q.offset??'0';if(typeof raw!=='string'||! /^\d{1,7}$/.test(raw)||Number(raw)>1000000)fail('Invalid page offset.');
 return {month,offset:Number(raw)};
}
export function entry(value){
 const v=object(value);if(v.confirmed!==true)fail('Review and confirm the entry first.');
 if(!['income','expense'].includes(v.kind))fail('Choose Income or Expense.');
 if(typeof v.entry_date!=='string'||! /^20\d\d-\d\d-\d\d$/.test(v.entry_date))fail('Enter a valid received or paid date.');
 const date=new Date(v.entry_date+'T00:00:00.000Z');if(!Number.isFinite(date.getTime())||date.toISOString().slice(0,10)!==v.entry_date)fail('Enter a valid received or paid date.');
 if(typeof v.category!=='string'||! /^[45]\d{3}$/.test(v.category))fail('Choose a category.');
 return {kind:v.kind,entry_date:v.entry_date,amount_cents:cents(v.amount),category:v.category,counterparty:str(v.counterparty,'Customer or vendor',160),purpose:str(v.purpose,'Business purpose',500,true),receipt_reference:str(v.receipt_reference,'Receipt reference',160),request_key:id(v.request_key),confirmed:true};
}
export function reversal(value,entryId){const v=object(value);if(v.confirmed!==true)fail('Confirm reversing this entry.');return {entry_id:id(entryId),reason:str(v.reason,'Reason for correction',500,true),request_key:id(v.request_key),confirmed:true};}
export function csv(data){
 const cell=v=>{let s=String(v??'');if(/^[\s]*[=+\-@]/.test(s)||/^[\t\r\n]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';};
 const money=n=>{const x=BigInt(n);return `${x/100n}.${(x%100n).toString().padStart(2,'0')}`;};
 const rows=[['Entry ID','Date received or paid','Entry type','Category','Amount USD','Debit account','Credit account','Customer or vendor','Business purpose or correction reason','Receipt reference (not attachment)','Reversal of','Reversed by','Recorded at']];
 for(const e of data.entries)rows.push([e.id,e.entry_date,e.kind,e.category_name,money(e.amount_cents),e.debit_account,e.credit_account,e.counterparty,e.purpose,e.receipt_reference,e.reversal_of,e.reversed_by,e.created_at]);
 return {filename:`korlix-activity-${data.business.id}-${data.month}.csv`,count:data.entries.length,csv:'\uFEFF'+rows.map(r=>r.map(cell).join(',')).join('\r\n')+'\r\n'};
}
