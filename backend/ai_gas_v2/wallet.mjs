import {GasError,userId,productId,tokenHash} from './google.mjs';
export const PACKS=Object.freeze([
  ['korlix_ai_gas_1h',3600,3000],['korlix_ai_gas_2h',7200,5500],
  ['korlix_ai_gas_3h',10800,8000],['korlix_ai_gas_5h',18000,12499],
].map(([sku,seconds,referenceUsdCents])=>Object.freeze({sku,seconds,referenceUsdCents})));
const SQL_ERRORS=new Set(['GAS_PURCHASE_CONFLICT','GAS_PURCHASE_REVOKED','GAS_ALREADY_CONSUMED_UNRECORDED','GAS_PRODUCT_UNAVAILABLE','GAS_INSUFFICIENT_BALANCE','GAS_USAGE_CONFLICT','GAS_LEASE_STALE','GAS_BILLING_REVIEW_REQUIRED']);
export function createStore(database) {
  if(typeof database?.rpc!=='function') throw new GasError('GAS_DATABASE_REQUIRED');
  return async (action,data={})=>{
    try {
      const result=await database.rpc('korlix_gas_v2_rpc',{p_action:action,p_data:data});
      if(result.error) throw new GasError(SQL_ERRORS.has(result.error.message)?result.error.message:'GAS_STORAGE_UNAVAILABLE',SQL_ERRORS.has(result.error.message)?409:503);
      if(result.data===undefined || result.data===null && action!=='claim') throw new GasError('GAS_STORAGE_UNAVAILABLE');
      return result.data;
    } catch(error) {throw error instanceof GasError?error:new GasError('GAS_STORAGE_UNAVAILABLE');}
  };
}
export function validateCatalog(rows) {
  if(!Array.isArray(rows)||rows.length!==PACKS.length) throw new GasError('GAS_CATALOG_INVALID');
  const seen=new Set(),ids=new Set();
  return Object.freeze(PACKS.map(pack=>{
    const found=rows.filter(row=>row?.sku===pack.sku);
    if(found.length!==1)throw new GasError('GAS_CATALOG_INVALID');
    const row=found[0];
    if(row.seconds!==pack.seconds||row.referenceUsdCents!==pack.referenceUsdCents||typeof row.enabled!=='boolean') throw new GasError('GAS_CATALOG_INVALID');
    if(row.productId!==null) {productId(row.productId); if(ids.has(row.productId))throw new GasError('GAS_CATALOG_INVALID');ids.add(row.productId);}
    if(row.enabled && row.productId===null)throw new GasError('GAS_CATALOG_INVALID');
    seen.add(row.sku);return Object.freeze({...pack,productId:row.productId,enabled:row.enabled});
  }));
}
function balance(raw) {
  if(!raw||!Number.isSafeInteger(raw.balanceSeconds)||raw.balanceSeconds<0||typeof raw.reviewRequired!=='boolean')throw new GasError('GAS_BALANCE_INVALID');
  return Object.freeze({balanceSeconds:raw.balanceSeconds,reviewRequired:raw.reviewRequired});
}
export function createWallet({store,google,vault}={}) {
  if(typeof store!=='function'||['verify','consume','accountId'].some(k=>typeof google?.[k]!=='function')||['seal','open'].some(k=>typeof vault?.[k]!=='function')) throw new GasError('GAS_ADAPTER_REQUIRED');
  async function catalog(){return validateCatalog(await store('catalog'));}
  return Object.freeze({
    catalog,
    async purchaseContext(id){return {obfuscatedAccountId:google.accountId(userId(id))};},
    async balance(id){return balance(await store('balance',{userId:userId(id)}));},
    async verifyAndGrant({userId:id,productId:pid,purchaseToken}={}) {
      id=userId(id); productId(pid); const h=tokenHash(purchaseToken);
      const pack=(await catalog()).find(p=>p.productId===pid);
      if(!pack)throw new GasError('GAS_PRODUCT_UNAVAILABLE',409);
      // The trusted adapter makes a fresh Google API request. Never accept a client
      // receipt/state/amount/user ID as verified purchase facts.
      const proof=await google.verify({userId:id,productId:pid,purchaseToken});
      if(proof.state==='PENDING')return Object.freeze({state:'PENDING',granted:false});
      if(proof.state==='REVOKED') {
        await store('revoke',{tokenHash:h,reason:'revoked'});
        throw new GasError('GAS_PURCHASE_REVOKED',409);
      }
      if(proof.state!=='PURCHASED'||proof.productId!==pid||typeof proof.isTest!=='boolean'||typeof proof.consumed!=='boolean')throw new GasError('GOOGLE_RESPONSE_INVALID');
      const context={userId:id,productId:pid,tokenHash:h};
      const grant=await store('grant_google',{...context,sku:pack.sku,purchasedAt:proof.purchasedAt,isTest:proof.isTest,consumed:proof.consumed,sealedToken:vault.seal(purchaseToken,context)});
      if(typeof grant.granted!=='boolean'||typeof grant.idempotent!=='boolean')throw new GasError('GAS_GRANT_RESULT_INVALID');
      // Grant plus consume-job enqueue is one SQL transaction. There is no call
      // to Google consume before that transaction commits successfully.
      return Object.freeze({state:'PURCHASED',...balance(grant),granted:grant.granted,idempotent:grant.idempotent});
    },
    async processOneConsumptionJob() {
      const job=await store('claim'); if(job===null)return {processed:false};
      const lease={tokenHash:job.tokenHash,leaseId:job.leaseId};
      try {
        const context={userId:job.userId,productId:job.productId,tokenHash:job.tokenHash};
        const purchaseToken=vault.open(job.sealedToken,context);
        const proof=await google.verify({userId:job.userId,productId:job.productId,purchaseToken});
        if(proof.state==='REVOKED') await store('revoke',{tokenHash:job.tokenHash,reason:'revoked'});
        else if(proof.state==='PURCHASED') {
          if(!proof.consumed)await google.consume({productId:job.productId,purchaseToken});
        } else throw new GasError('GAS_PURCHASE_PENDING');
        await store('finish',lease);
        return {processed:true,state:proof.state==='REVOKED'?'REVOKED':'CONSUMED'};
      } catch(error) {
        const errorCode=error instanceof GasError&&/^[A-Z_]{1,80}$/.test(error.code)?error.code:'GAS_CONSUME_RETRY';
        await store('retry',{...lease,errorCode});
        return {processed:true,state:'RETRY_SCHEDULED',code:errorCode};
      }
    },
  });
}
// NOT mounted by this milestone. Require authenticated account checks and a
// reviewed limiter. No public generic SQL, debit, refund or worker endpoint.
export function registerWalletRoutes(app,{requireUser,limiter,wallet,enabled=false}={}) {
  if(enabled!==true)return {mounted:false};
  if(typeof app?.get!=='function'||typeof app?.post!=='function'||typeof requireUser!=='function'||typeof limiter!=='function'||!wallet)throw new GasError('GAS_ROUTE_ADAPTER_REQUIRED');
  const wrap=fn=>async(req,res)=>{
    res.set('Cache-Control','no-store');
    try {
      let actor; try{actor=await requireUser(req);}catch{throw new GasError('GAS_AUTH_REQUIRED',401);}
      await fn(req,res,userId(actor?.id));
    }catch(error){
      const safe=error instanceof GasError;
      res.status(safe?error.status:503).json({code:safe?error.code:'GAS_UNAVAILABLE'});
    }
  };
  app.get('/api/ai-gas/v2/catalog',limiter,wrap(async(_q,r)=>r.json({packs:(await wallet.catalog()).filter(p=>p.enabled),referencePricesOnly:true})));
  app.get('/api/ai-gas/v2/balance',limiter,wrap(async(_q,r,u)=>r.json(await wallet.balance(u))));
  app.get('/api/ai-gas/v2/purchase-context',limiter,wrap(async(_q,r,u)=>r.json(await wallet.purchaseContext(u))));
  app.post('/api/ai-gas/v2/purchase/google/verify',limiter,wrap(async(q,r,u)=>{
    if(!q.body||Array.isArray(q.body)||Object.keys(q.body).some(k=>!['productId','purchaseToken'].includes(k)))throw new GasError('GAS_REQUEST_INVALID',400);
    r.json(await wallet.verifyAndGrant({userId:u,productId:q.body.productId,purchaseToken:q.body.purchaseToken}));
  }));
  return {mounted:true};
}
