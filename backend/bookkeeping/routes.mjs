import {BookkeepingError,fail,id,profile,entry,reversal,monthQuery,csv} from './core.mjs';
export function registerBookkeeping(app,{database,requireUser}={}){
 const call=async(actor,action,business=null,data={})=>{
  const result=await database.rpc('korlix_bookkeeping_v1',{p_actor:actor,p_action:action,p_business:business,p_data:data});
  if(result.error){
   const e=result.error;
   const statuses={P0002:404,'40001':409,'23505':409,'42501':403,'54000':422,P0001:400,'23514':400,'23502':400,'22P02':400,'22007':400,'22008':400};
   const status=statuses[e.code];
   // Only intentionally raised messages are safe for the client. PostgreSQL
   // constraints can include raw rows and must never be forwarded.
   const safe=['P0001','P0002','40001','54000'].includes(e.code);
   fail(safe?e.message:(status?'The entry could not be saved. Check its fields and refresh.':'Bookkeeping storage is temporarily unavailable.'),status??503,'BOOKKEEPING_STORAGE_ERROR');
  }
  if(!result.data)fail('Bookkeeping storage returned no result.',503,'BOOKKEEPING_STORAGE_ERROR');
  return result.data;
 };
 const route=fn=>async(req,res)=>{
  res.set('Cache-Control','no-store');
  try{
   let user;try{user=await requireUser(req);}catch{fail('Sign in to use Bookkeeping.',401,'BOOKKEEPING_AUTH_REQUIRED');}
   if(!user?.id)fail('Sign in to use Bookkeeping.',401,'BOOKKEEPING_AUTH_REQUIRED');
   if(!database)fail('Bookkeeping storage is not configured.',503,'BOOKKEEPING_UNAVAILABLE');
   await fn(req,res,user.id);
  }catch(e){res.status(e instanceof BookkeepingError?e.status:503).json({error:e instanceof BookkeepingError?e.message:'Bookkeeping is temporarily unavailable. Refresh before retrying a save.',code:e instanceof BookkeepingError?e.code:'BOOKKEEPING_UNAVAILABLE'});}
 };
 const base='/api/bookkeeping/businesses';
 app.get(base,route(async(_q,r,u)=>r.json(await call(u,'list'))));
 app.post(base,route(async(q,r,u)=>r.status(201).json(await call(u,'create_business',null,profile(q.body)))));
 app.put(base+'/:id',route(async(q,r,u)=>r.json(await call(u,'update_business',id(q.params.id),profile(q.body,{update:true})))));
 app.get(base+'/:id/overview',route(async(q,r,u)=>r.json(await call(u,'overview',id(q.params.id),monthQuery(q.query)))));
 app.post(base+'/:id/entries',route(async(q,r,u)=>r.status(201).json(await call(u,'post',id(q.params.id),entry(q.body)))));
 app.post(base+'/:id/entries/:entry/reverse',route(async(q,r,u)=>r.status(201).json(await call(u,'reverse',id(q.params.id),reversal(q.body,q.params.entry)))));
 app.get(base+'/:id/export',route(async(q,r,u)=>r.json(csv(await call(u,'export',id(q.params.id),monthQuery(q.query))))));
}
