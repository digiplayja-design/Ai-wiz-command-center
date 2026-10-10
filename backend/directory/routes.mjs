import {randomUUID} from 'node:crypto';
import sharp from 'sharp';
import {adminIds,CATEGORIES,PRICES,details,DirectoryError,fail,id,slug,storeFor,text} from './core.mjs';
import {directoryBilling} from './billing.mjs';
import {sandboxWebhookProbe} from './webhook_probe.mjs';
import {directoryPassport} from './passport.mjs';
export function registerDirectory(app,{database,requireUser,environment=process.env,store,billing,now=Date.now}={}){
 const persistence=store||(database?storeFor(database):null),admins=adminIds(environment),pay=billing||directoryBilling(environment),limits=new Map();
 const root='/api/directory';
 const passport=directoryPassport(database,environment);
 const deliveryProbe=sandboxWebhookProbe(environment,now);
 function rate(key,max=60,period=60000){const time=now();let v=limits.get(key);if(!v||time-v.at>period)v={at:time,n:0};v.n++;limits.set(key,v);if(limits.size>20000)for(const [k,x]of limits)if(time-x.at>3600000)limits.delete(k);if(v.n>max)fail('Please wait before trying again.',429);}
 const ip=q=>environment.RENDER==='true'?String(q.headers['x-forwarded-for']||q.ip).split(',').at(-1).trim():q.ip;
 const admin=user=>admins.has(user?.id?.toLowerCase());
 const command=(user,action,business,p)=>persistence.command(user?.id,admin(user),action,business,p);
 const wrap=(fn,auth=false)=>async(q,r)=>{r.set('Cache-Control','no-store');try{if(!persistence)fail('Directory storage is not configured.',503);let user=null;if(auth){try{user=await requireUser(q);}catch{fail('Sign in to manage your business.',401);}if(!user?.id||user.is_anonymous)fail('Sign in with a permanent account.',401);rate('owner:'+user.id,80);}else rate('public:'+ip(q),120);await fn(q,r,user);}catch(e){r.status(e instanceof DirectoryError?e.status:503).json({error:e instanceof DirectoryError?e.message:'Directory request could not be completed. Please retry.'});}};
 app.get(root+'/health',async(q,r)=>{r.set('Cache-Control','no-store');const paymentConnection=pay.checkConnection?await pay.checkConnection():'unchecked';r.json({version:1,freeListings:true,publicBrowsing:true,paymentsReady:pay.ready,paymentCredentialsConfigured:pay.configured===true,checkoutEnabled:pay.enabled===true,paymentConnection,paymentApiVersion:pay.apiVersion,livePayments:pay.live,adminConfigured:admins.size>0,prices:{currency:'USD',monthlyCents:499,yearlyCents:4900},sandboxWebhookProbe:deliveryProbe.status()});});
 app.get(root+'/businesses',wrap(async(q,r)=>r.json({...await command(null,'browse',null,{q:text(q.query.q,120),category:text(q.query.category,80),city:text(q.query.city,100),...(q.query.ids?{ids:text(q.query.ids,2000).split(',').slice(0,50).map(id)}:{}),offset:Math.min(10000,Math.max(0,Number(q.query.offset)||0))}),categories:CATEGORIES})));
 app.get(root+'/businesses/:slug',wrap(async(q,r)=>r.json(await passport.enrich(await command(null,'public',null,{slug:text(q.params.slug,120,true)})))));
 app.get(root+'/businesses/:slug/passport-qr',wrap(async(q,r)=>{
  const card=await command(null,'public',null,{slug:text(q.params.slug,120,true)});
  r.type('image/png').set('X-Content-Type-Options','nosniff').send(await passport.qr(card));
 }));
 app.get(root+'/booking-options',wrap(async(q,r,u)=>r.json({events:await passport.events(u.id)}),true));
 app.post(root+'/businesses/:id/report',wrap(async(q,r)=>{rate('report:'+ip(q),5,3600000);if(q.body?.website)fail('Report could not be submitted.');r.json(await command(null,'report',id(q.params.id),{reason:text(q.body?.reason,1000,true)}));}));
 app.post(root+'/businesses/:id/metrics',wrap(async(q,r)=>{const business=id(q.params.id),kind=q.body?.kind;if(!['view','contact'].includes(kind))fail('Invalid metric.');rate(`metric:${ip(q)}:${business}:${kind}`,1,600000);r.json(await command(null,'metrics',business,{kind}));}));
 app.get(root+'/businesses/:id/photos/:asset',wrap(async(q,r)=>{
  const business=id(q.params.id),asset=id(q.params.asset),card=await command(null,'public',business,{});
  if(!card.details?.photos?.includes(asset))fail('Photo not found.',404);
  const {data,error}=await database.from('korlix_directory_assets').select('path,mime').eq('business_id',business).eq('id',asset).eq('purpose','photo').maybeSingle();if(error||!data)fail('Photo not found.',404);
  const file=await database.storage.from('korlix-directory').download(data.path);if(file.error)fail('Photo not found.',404);r.type('image/jpeg').set('X-Content-Type-Options','nosniff').send(Buffer.from(await file.data.arrayBuffer()));
 }));
 app.get(root+'/me',wrap(async(q,r,u)=>{
  const [mine,bookingOptions]=await Promise.all([command(u,'mine'),passport.events(u.id).catch(()=>[])]);
  r.json({...mine,bookingOptions,isAdmin:admin(u),categories:CATEGORIES,paymentsReady:pay.ready,livePayments:pay.live,prices:PRICES});
 },true));
 app.post(root+'/owner',wrap(async(q,r,u)=>{rate('create:'+u.id,10,3600000);const d=details(q.body?.details);await passport.validate(u.id,d);r.json(await command(u,'create',null,{details:d,owner_name:text(q.body?.owner_name,100,true),slug:slug(d.name)}));},true));
 app.get(root+'/owner/:id',wrap(async(q,r,u)=>r.json(await command(u,'get',id(q.params.id))),true));
 app.post(root+'/owner/:id/action',wrap(async(q,r,u)=>{
  const action=q.body?.action,p=q.body||{};if(!['save','submit','hide','verification_submit'].includes(action))fail('Unsupported owner action.');
  let payload={};if(action==='save'||action==='submit'){if(!Number.isInteger(p.version)||p.version<1)fail('Refresh this listing before saving.');payload={details:details(p.details),owner_name:text(p.owner_name,100,true),version:p.version,consent:p.consent===true};}
  if(action==='verification_submit')payload={evidence_note:text(p.evidence_note,4000,true)};
  const snapshot=await command(u,'get',id(q.params.id));if(snapshot.business.owner_id!==u.id)fail('Only the business owner can change this listing.',403);
  if(payload.details)await passport.validate(u.id,payload.details);
  r.json(await command(u,action,id(q.params.id),payload));
 },true));
 app.post(root+'/owner/:id/assets',wrap(async(q,r,u)=>{
  rate('upload:'+u.id,20,3600000);const business=id(q.params.id),snapshot=await command(u,'get',business);if(snapshot.business.owner_id!==u.id)fail('Owner access required.',403);
  const purpose=q.body?.purpose;if(!['photo','evidence'].includes(purpose))fail('Choose photo or evidence.');
  const raw=q.body?.base64;if(typeof raw!=='string'||raw.length>7100000||!/^[A-Za-z0-9+/]*={0,2}$/.test(raw))fail('Upload an image or PDF under 5 MB.');let bytes=Buffer.from(raw,'base64');if(!bytes.length||bytes.length>5242880)fail('Upload a file under 5 MB.');let mime='image/jpeg';
  if(purpose==='evidence'&&bytes.subarray(0,5).toString()==='%PDF-'){mime='application/pdf';}else{try{bytes=await sharp(bytes,{limitInputPixels:40000000,animated:false}).rotate().resize({width:1600,height:1600,fit:'inside',withoutEnlargement:true}).jpeg({quality:85}).toBuffer();}catch{fail('Use a valid JPEG, PNG or WebP image.');}}
  const aid=randomUUID(),path=`${business}/${purpose}/${aid}.${mime==='application/pdf'?'pdf':'jpg'}`;
  const uploaded=await database.storage.from('korlix-directory').upload(path,bytes,{contentType:mime,upsert:false});if(uploaded.error)fail('File upload failed. Please retry.',503);
  try{await command(u,'asset',business,{id:aid,purpose,path,mime});}catch(e){await database.storage.from('korlix-directory').remove([path]);throw e;}r.json({id:aid,purpose,mime});
 },true));
 app.delete(root+'/owner/:id/assets/:asset',wrap(async(q,r,u)=>{
  const asset=await command(u,'asset_remove',id(q.params.id),{id:id(q.params.asset)});
  const removed=await database.storage.from('korlix-directory').remove([asset.path]);
  if(removed.error)fail('The file is no longer attached to the listing. Storage cleanup needs support.',503);
  r.json({ok:true});
 },true));
 app.get(root+'/owner/:id/assets/:asset',wrap(async(q,r,u)=>{
  const file=await command(u,'asset_get',id(q.params.id),{id:id(q.params.asset)}),download=await database.storage.from('korlix-directory').download(file.path);if(download.error)fail('File unavailable.',404);
  r.type(file.mime).set('X-Content-Type-Options','nosniff').set('Content-Disposition',`attachment; filename="business-file.${file.mime==='application/pdf'?'pdf':'jpg'}"`).send(Buffer.from(await download.data.arrayBuffer()));
 },true));
 app.get(root+'/admin',wrap(async(q,r,u)=>r.json(await command(u,'admin_queue',null,{q:text(q.query.q,120)})),true));
 app.post(root+'/admin/:id',wrap(async(q,r,u)=>{
  if(!admin(u))fail('Administrator access required.',403);const p=q.body||{};
  if(!['review','verification_review','resolve_reports'].includes(p.action))fail('Choose a review action.');if(!['approve','changes','hide','revoke','resolve'].includes(p.decision))fail('Choose a review decision.');
  if(!Number.isInteger(p.version))fail('Refresh before reviewing.');
  r.json(await command(u,p.action,id(q.params.id),{version:p.version,decision:p.decision,note:text(p.note,2000,true),checks:Array.isArray(p.checks)?p.checks.filter(v=>['email','phone','ownership'].includes(v)):[]}));
 },true));
 async function apply(s){if(!s)return;return command(null,'billing_apply',id(s.business_id),s);}
 app.post(root+'/owner/:id/membership',wrap(async(q,r,u)=>{
  const business=id(q.params.id),snapshot=await command(u,'get',business);if(snapshot.business.owner_id!==u.id)fail('Only the owner can manage membership.',403);
  const action=q.body?.action;if(!pay.configured&&!pay.ready)fail('Membership checkout is not configured yet. You can still create a free listing and apply for verification.',503);
  if(action==='checkout'){
   if(!pay.ready)fail('New membership checkout is paused. Free listings and existing membership management remain available.',503);
   if(q.body?.acceptRecurring!==true||!Object.hasOwn(PRICES,q.body?.interval))fail('Review and accept the recurring price first.');
   let expired_generation;
   const previous={...snapshot.membership,business_id:business};
   if(previous.state==='checkout'&&previous.checkout_expires){
    if(!previous.checkout_id){const recovered=await pay.checkout(business,previous,u.email);await command(u,'checkout_saved',business,{generation:previous.generation,checkout_id:recovered.id,checkout_url:recovered.url});previous.checkout_id=recovered.id;}
    const existing=await pay.session(previous);
    if(existing.subscription){await apply(await pay.subscription(typeof existing.subscription==='string'?existing.subscription:existing.subscription.id));fail('Your payment was reconciled. Refresh membership instead of starting another purchase.',409);}
    if(existing.status==='expired')expired_generation=previous.generation;
   }
   const m=await command(u,'checkout_start',business,{interval:q.body.interval,livemode:pay.live,expired_generation});const session=await pay.checkout(business,m,u.email);
   await command(u,'checkout_saved',business,{generation:m.generation,checkout_id:session.id,checkout_url:session.url});if(!session.url)fail('Checkout expired. Refresh and try again.',409);return r.json({url:session.url});
  }
  const m=snapshot.membership;
  if(action==='refresh'){await apply(await pay.refresh({...m,business_id:business}));return r.json({ok:true});}
  if(action==='cancel'){if(q.body?.confirm!==true)fail('Confirm cancellation of renewal.');await apply(await pay.cancel(m.subscription_id));return r.json({ok:true});}
  if(action==='portal')return r.json({url:await pay.portal(m.customer_id)});
  fail('Choose a membership action.');
 },true));
 app.post(root+'/billing/webhook',async(q,r)=>{
  try{const probe=deliveryProbe.receive(q.korlixDirectoryRawBody,q.headers['stripe-signature']);
   if(probe)return r.status(probe.status).json(probe.body);
   if(!pay.verify(q.korlixDirectoryRawBody,q.headers['stripe-signature']))return r.status(400).json({error:'Invalid payment signature.'});
   const event=JSON.parse(q.korlixDirectoryRawBody.toString());if(event.livemode!==pay.live)return r.status(400).json({error:'Payment mode mismatch.'});
   const o=event.data?.object;
   if(event.type.startsWith('customer.subscription.')){
    if(o?.metadata?.korlix_directory)await apply(await pay.subscription(o.id));
   }else if(['invoice.paid','invoice.payment_failed','invoice.payment_action_required','invoice.marked_uncollectible'].includes(event.type)){
    const sub=o?.parent?.subscription_details?.subscription||o?.subscription;if(sub){const m=await command(null,'billing_lookup',null,{subscription_id:typeof sub==='string'?sub:sub.id});if(m)await apply(await pay.subscription(typeof sub==='string'?sub:sub.id));}
   }else if(['checkout.session.completed','checkout.session.async_payment_succeeded','checkout.session.async_payment_failed'].includes(event.type)){
    if(o?.metadata?.korlix_directory&&o.subscription)await apply(await pay.subscription(typeof o.subscription==='string'?o.subscription:o.subscription.id));
   }else if(['charge.refunded','charge.dispute.created'].includes(event.type)){
    const customer=await pay.chargeCustomer(event.type==='charge.refunded'?o.id:typeof o.charge==='string'?o.charge:o.charge.id);
    if(customer){const m=await command(null,'billing_lookup',null,{customer_id:customer});if(m)await command(null,'billing_hold',m.business_id,{customer_id:customer});}
   }
   r.json({received:true});
  }catch(e){r.status(e instanceof DirectoryError&&e.status<500?400:503).json({error:'Payment event could not be reconciled.'});}
 });
 return {capabilities:{version:1,freeListings:true,paymentsReady:pay.ready,adminConfigured:admins.size>0}};
}
