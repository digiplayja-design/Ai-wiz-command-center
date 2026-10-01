import {CATEGORIES,LiveStudioError,showInput,queueInput,uuid,text,publicShow,ACTIVE} from './core.mjs';
import {createLiveStore} from './store.mjs';
import {createLiveRuntime} from './runtime.mjs';

export function registerLiveStudio(app,{database,storage,requireUser,access,providers,env=process.env,store:createStore,
  startWorker=true,runtimeFactory=createLiveRuntime}={}){
  const store=createStore||createLiveStore(database);
  const rehearsalReady=Boolean(providers&&storage);
  const runtime=rehearsalReady?runtimeFactory({store,providers,storage,mode:'rehearsal'}):null;
  const route=fn=>async(q,r)=>{
    r.set('Cache-Control','no-store');r.set('X-Content-Type-Options','nosniff');
    try{
      let u;try{u=await requireUser(q);}catch{throw new LiveStudioError('Sign in to use Live Studio.',401);}
      if(!u?.id)throw new LiveStudioError('Sign in to use Live Studio.',401);
      if(u.banned_until&&Date.parse(u.banned_until)>Date.now())throw new LiveStudioError('This account is not available.',403);
      const a=await access(u);if(!a.allowed)throw new LiveStudioError(a.reason||'Live Studio is in a limited pilot.',403);
      await fn(q,r,u,a);
    }catch(error){if(!r.headersSent)r.status(error instanceof LiveStudioError?error.status:503).json({error:error instanceof LiveStudioError?error.message:'Live Studio is temporarily unavailable. Refresh before retrying.'});}
  };
  const base='/api/live-studio';
  const channelReady=async u=>(await store.call(u.id,'worker_status')).youtubeReady===true;
  app.get(base,route(async(q,r,u)=>{
    await store.call(null,'sweep');
    const data=await store.call(u.id,'list');
    const ready=await channelReady(u);
    r.json({shows:(data.shows||[]).map(publicShow),categories:CATEGORIES,
      access:{rehearsalReady,youtubeReady:ready,pilot:true,maxDailyStarts:3,
        message:ready?'YouTube worker connected. Broadcasts are unlisted.':'YouTube connection and a dedicated broadcast worker are required before going live.'}});
  }));
  app.post(base+'/shows',route(async(q,r,u)=>r.json({show:publicShow(await store.call(u.id,'save',uuid(q.body?.requestId),{config:showInput(q.body)}))})));
  app.get(base+'/shows/:id',route(async(q,r,u)=>r.json({show:publicShow(await store.call(u.id,'get',uuid(q.params.id)))})));
  app.post(base+'/shows/:id/start',route(async(q,r,u)=>{
    const id=uuid(q.params.id),input=queueInput(q.body);
    if(input.mode==='rehearsal'&&!rehearsalReady)throw new LiveStudioError('The rehearsal renderer is unavailable.',503);
    if(input.mode==='youtube'&&!await channelReady(u))throw new LiveStudioError('Connect YouTube and activate the dedicated worker before going live.',409);
    r.json({show:publicShow(await store.call(u.id,'queue',id,input))});
    if(input.mode==='rehearsal')void runtime?.tick();
  }));
  app.post(base+'/shows/:id/control',route(async(q,r,u)=>{
    const action=q.body?.action;if(!['pause','resume','skip','end','question'].includes(action))throw new LiveStudioError('Choose a studio control.');
    if(action==='end'&&q.body.confirmed!==true)throw new LiveStudioError('Confirm ending this show.');
    const data={action,requestId:uuid(q.body.requestId),...(action==='question'?{text:text(q.body.text,400,'Question')}:{})};
    if(action==='question'&&!data.text.includes('?'))throw new LiveStudioError('Enter a question ending in a question mark.');
    r.json({show:publicShow(await store.call(u.id,'control',uuid(q.params.id),data))});
  }));
  app.get(base+'/shows/:id/replay',route(async(q,r,u)=>{
    const show=await store.call(u.id,'get',uuid(q.params.id));
    if(!show.has_replay||!show.replay_path?.startsWith(u.id+'/'+show.id+'/'))throw new LiveStudioError('This private rehearsal is not ready yet.',404);
    const signed=await storage.from('korlix-live-studio').createSignedUrl(show.replay_path,300);
    if(signed.error||!signed.data?.signedUrl)throw new LiveStudioError('The rehearsal link could not be opened.',503);
    r.json({url:signed.data.signedUrl,expiresIn:300});
  }));
  app.delete(base+'/shows/:id',route(async(q,r,u)=>{
    if(q.body?.confirmed!==true)throw new LiveStudioError('Confirm removing this saved show and its rehearsal.');
    const id=uuid(q.params.id),show=await store.call(u.id,'get',id);
    if(ACTIVE.includes(show.state))throw new LiveStudioError('End the show before removing it.',409);
    if(show.replay_path){const removed=await storage.from('korlix-live-studio').remove([show.replay_path]);if(removed.error)throw new LiveStudioError('The rehearsal could not be removed. Try again later.',503);}
    r.json(await store.call(u.id,'delete',id));
  }));
  if(startWorker)runtime?.start();
  return {runtime,store,stop:()=>runtime?.stop()};
}
