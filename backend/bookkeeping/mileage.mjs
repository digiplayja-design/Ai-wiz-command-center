import {fail,id} from './core.mjs';
function text(v,label,max){if(typeof v!=='string'||!v.trim()||v.trim().length>max||/[\u0000-\u001f\u007f]/.test(v))fail(`${label} must contain 1–${max} characters without line breaks.`);return v.trim();}
export function tenths(v,{odometer=false}={}){
 if(typeof v!=='string'||!/^(?:0|[1-9][0-9]{0,6})(?:\.[0-9])?$/.test(v))fail('Use miles with at most one decimal place.');
 const [a,b='0']=v.split('.');const n=BigInt(a)*10n+BigInt(b);
 if(n<(odometer?0n:1n)||n>(odometer?99999999n:99999n))fail(odometer?'Odometer must be between 0 and 9,999,999.9 miles.':'Trip distance must be 0.1–9,999.9 miles.');return String(n);
}
export function mileagePayload(v,{tripId,voidOnly=false}={}){
 if(!v||typeof v!=='object'||Array.isArray(v)||v.confirmed!==true)fail('Review and confirm this mileage record.');
 const p={request_key:id(v.request_key),confirmed:true};
 if(tripId){p.trip_id=id(tripId);p.reason=text(v.reason,'Correction reason',500);}
 if(voidOnly)return p;
 if(typeof v.trip_date!=='string'||!/^20\d\d-\d\d-\d\d$/.test(v.trip_date))fail('Enter a valid trip date between 2000 and 2099.');
 const date=new Date(v.trip_date+'T00:00:00.000Z');if(!Number.isFinite(date.getTime())||date.toISOString().slice(0,10)!==v.trip_date)fail('Enter a valid trip date.');
 Object.assign(p,{trip_date:v.trip_date,vehicle:text(v.vehicle,'Vehicle nickname',80),origin:text(v.origin,'Starting place',160),destination:text(v.destination,'Destination',160),purpose:text(v.purpose,'Business purpose',500),method:v.method,manual_tenths:null,start_tenths:null,end_tenths:null});
 if(v.method==='miles')p.manual_tenths=tenths(v.miles);
 else if(v.method==='odometer'){p.start_tenths=tenths(v.odometer_start,{odometer:true});p.end_tenths=tenths(v.odometer_end,{odometer:true});const distance=BigInt(p.end_tenths)-BigInt(p.start_tenths);if(distance<1n||distance>99999n)fail('Ending odometer must be higher; trip distance must be 0.1–9,999.9 miles.');}
 else fail('Choose miles driven or odometer readings.');
 return p;
}
export function mileageQuery(q){if(typeof q.period!=='string'||!/^20\d\d(?:-(?:0[1-9]|1[0-2]))?$/.test(q.period))fail('Choose a month or year between 2000 and 2099.');const offset=q.offset??'0';if(typeof offset!=='string'||!/^\d{1,7}$/.test(offset)||Number(offset)>1000000)fail('Invalid page offset.');if(q.vehicle!==undefined&&(typeof q.vehicle!=='string'||q.vehicle.length>80))fail('Invalid vehicle filter.');return {period:q.period,vehicle:q.vehicle??'',offset:Number(offset)};}
const decimal=n=>n==null?'':`${BigInt(n)/10n}.${BigInt(n)%10n}`;
export function mileageCsv(d){
 const cell=v=>{let s=String(v??'');if(/^\s*[=+\-@]/.test(s)||/^[\t\r\n]/.test(s))s="'"+s;return '"'+s.replaceAll('"','""')+'"';};
 const rows=[['Business','Trip ID','Trip date','Vehicle','Starting place','Destination','Business purpose','Method','Odometer start (mi)','Odometer end (mi)','Recorded distance (mi)','Included distance (mi)','Status','Corrects trip','Replacement trip','Correction reason','Recorded at','Excluded at']];
 for(const t of d.trips)rows.push([d.business.name,t.id,t.trip_date,t.vehicle,t.origin,t.destination,t.purpose,t.method,decimal(t.start_tenths),decimal(t.end_tenths),decimal(t.distance_tenths),decimal(t.included_tenths),t.void_id?(t.replacement_id?'Corrected — excluded':'Voided — excluded'):'Included',t.correction_of,t.replacement_id,t.void_reason,t.created_at,t.voided_at]);
 return {filename:`korlix-mileage-${d.business.id}-${d.period}.csv`,count:d.trips.length,csv:'\uFEFF'+rows.map(r=>r.map(cell).join(',')).join('\r\n')+'\r\n'};
}
export function registerMileageRoutes(app,{route,database}){
 const call=async(u,a,b,p)=>{const r=await database.rpc('korlix_bookkeeping_mileage_v1',{p_actor:u,p_action:a,p_business:b,p_data:p});if(r.error){const e=r.error;const status={P0002:404,'40001':409,'23505':409,'54000':422,P0001:400,'23514':400,'23502':400,'22P02':400,'22007':400,'22008':400}[e.code]??503;fail(['P0001','P0002','40001','54000'].includes(e.code)?e.message:'Mileage could not be saved. Check the fields and refresh before retrying.',status,'BOOKKEEPING_MILEAGE_ERROR');}if(!r.data)fail('Mileage storage is unavailable.',503);return r.data;};
 const base='/api/bookkeeping/businesses/:id/mileage';
 app.get(base,route(async(q,r,u)=>r.json(await call(u,'list',id(q.params.id),mileageQuery(q.query)))));
 app.get(base+'/export',route(async(q,r,u)=>r.json(mileageCsv(await call(u,'export',id(q.params.id),mileageQuery(q.query))))));
 app.post(base,route(async(q,r,u)=>r.status(201).json(await call(u,'post',id(q.params.id),mileagePayload(q.body)))));
 for(const action of ['correct','void'])app.post(base+'/:trip/'+action,route(async(q,r,u)=>r.status(201).json(await call(u,action,id(q.params.id),mileagePayload(q.body,{tripId:q.params.trip,voidOnly:action==='void'})))));
}
