import {CATEGORIES,LiveStudioError,showInput,queueInput,uuid,text,publicShow,ACTIVE} from './core.mjs';
import {createLiveStore} from './store.mjs';
import {createLiveRuntime} from './runtime.mjs';
import {createLiveConnections} from './connections.mjs';

export function registerLiveStudio(app,{database,storage,requireUser,access=async()=>({allowed:false}),providers,env=process.env,store:createStore,
  connections:createConnections,startWorker=true,startMaintenance=startWorker,runtimeFactory=createLiveRuntime}={}){
  const store=createStore||createLiveStore(database);
  const connections=createConnections||createLiveConnections({database,env,
    publicRoot:env.LIVE_STUDIO_PUBLIC_ORIGIN||'https://chee-chai-chee-backend.onrender.com'});
  const rehearsalReady=Boolean(providers&&storage);
  const runtime=rehearsalReady?runtimeFactory({store,providers,storage,mode:'rehearsal'}):null;
  const route=fn=>async(q,r)=>{
    r.set('Cache-Control','no-store');r.set('X-Content-Type-Options','nosniff');
    try{
      let u;try{u=await requireUser(q);}catch{throw new LiveStudioError('Sign in to use Live Studio.',401);}
      if(!u?.id)throw new LiveStudioError('Sign in to use Live Studio.',401);
      await fn(q,r,u);
    }catch(error){if(!r.headersSent)r.status(error instanceof LiveStudioError?error.status:503).json({error:error instanceof LiveStudioError?error.message:'Live Studio is temporarily unavailable. Refresh before retrying.'});}
  };
  const available=u=>{
    if(u.banned_until&&Date.parse(u.banned_until)>Date.now())throw new LiveStudioError('This account is not available.',403);
  };
  const workspace=async u=>{
    // Only a server-verified developer entitlement can seed this bounded test grant.
    // Customers need an explicit server-side grant; no client tier or metadata is trusted.
    const developer=await access(u);
    if(developer.allowed===true){available(u);await store.call(u.id,'grant_developer');}
    return store.call(u.id,'workspace');
  };
  const base='/api/live-studio';
  connections.registerPublic(app,{base});
  const stateFor=async u=>{
    const [data,channel]=await Promise.all([workspace(u),connections.summary(u.id)]);
    const enabled=data.entitlement?.enabled===true;
    const canStart=enabled&&(data.usage?.dailyStarts||0)<(data.entitlement?.maxDailyStarts||0);
    const ready=channel.connectionConfigured===true&&channel.connection?.state==='connected'&&data.workerReady===true;
    let message='Activate a Live Studio allowance before generating shows. Your saved shows and channel controls remain available.';
    if(enabled)message=!channel.connectionConfigured?'YouTube setup is being completed. You can prepare shows and use your rehearsal allowance.'
      :!channel.connection?'Connect your YouTube channel to broadcast from this workspace.'
      :channel.connection.state!=='connected'?'Reconnect your YouTube channel to restore broadcasting.'
      :!data.workerReady?'Your channel is connected. Broadcasting will become available when the worker is ready.'
      :'Your channel is connected. Broadcasts are unlisted and use your own allowance.';
    return {...data,...channel,access:{rehearsalReady,youtubeReady:ready,pilot:false,canStart,message}};
  };
  app.get(base,route(async(q,r,u)=>{
    await store.call(null,'sweep');
    const [data,state]=await Promise.all([store.call(u.id,'list'),stateFor(u)]);
    r.json({...state,shows:(data.shows||[]).map(publicShow),categories:CATEGORIES});
  }));
  app.post(base+'/connections/youtube/start',route(async(q,r,u)=>{
    available(u);r.json(await connections.start(u.id,q.body||{}));
  }));
  app.post(base+'/connections/youtube/confirm',route(async(q,r,u)=>{
    available(u);r.json(await connections.confirm(u.id,q.body||{}));
  }));
  app.delete(base+'/connections/youtube',route(async(q,r,u)=>r.json(await connections.disconnect(u.id,q.body||{}))));
  app.post(base+'/shows',route(async(q,r,u)=>{
    available(u);r.json({show:publicShow(await store.call(u.id,'save',uuid(q.body?.requestId),{config:showInput(q.body)}))});
  }));
  app.get(base+'/shows/:id',route(async(q,r,u)=>r.json({show:publicShow(await store.call(u.id,'get',uuid(q.params.id)))})));
  app.post(base+'/shows/:id/start',route(async(q,r,u)=>{
    available(u);
    const id=uuid(q.params.id),input=queueInput(q.body);
    // Recover an uncertain start response even after the final allowance was
    // reserved or the worker went away. SQL verifies the identical request.
    const existing=await store.call(u.id,'get',id);
    if(existing.run_id===input.requestId){
      r.json({show:publicShow(await store.call(u.id,'queue',id,input))});return;
    }
    const state=await stateFor(u);
    if(!state.access.canStart)throw new LiveStudioError(state.entitlement?.enabled?'Your daily start allowance is used up.':'Activate a Live Studio allowance before starting a show.',state.entitlement?.enabled?429:403);
    if(input.mode==='rehearsal'&&!rehearsalReady)throw new LiveStudioError('The rehearsal renderer is unavailable.',503);
    if(input.mode==='youtube'&&!state.access.youtubeReady)throw new LiveStudioError('Connect your YouTube channel and wait for the broadcast worker before starting.',409);
    r.json({show:publicShow(await store.call(u.id,'queue',id,input))});
    if(input.mode==='rehearsal')void runtime?.tick();
  }));
  app.post(base+'/shows/:id/control',route(async(q,r,u)=>{
    const action=q.body?.action;if(!['pause','resume','skip','end','question'].includes(action))throw new LiveStudioError('Choose a studio control.');
    if(action!=='end')available(u);
    if(action==='end'&&q.body.confirmed!==true)throw new LiveStudioError('Confirm ending this show.');
    const data={action,requestId:uuid(q.body.requestId),...(action==='question'?{text:text(q.body.text,400,'Question')}:{})};
    if(action==='question'&&!data.text.includes('?'))throw new LiveStudioError('Enter a question ending in a question mark.');
    r.json({show:publicShow(await store.call(u.id,'control',uuid(q.params.id),data))});
  }));
  app.get(base+'/shows/:id/replay',route(async(q,r,u)=>{
    const show=await store.call(u.id,'get',uuid(q.params.id));
    if(!show.has_replay||!show.replay_path?.startsWith(u.id+'/'+show.id+'/'))throw new LiveStudioError('This private rehearsal is not ready yet.',404);
    if(!storage)throw new LiveStudioError('Private playback is temporarily unavailable.',503);
    const signed=await storage.from('korlix-live-studio').createSignedUrl(show.replay_path,300);
    if(signed.error||!signed.data?.signedUrl)throw new LiveStudioError('The rehearsal link could not be opened.',503);
    r.json({url:signed.data.signedUrl,expiresIn:300});
  }));
  app.delete(base+'/shows/:id',route(async(q,r,u)=>{
    if(q.body?.confirmed!==true)throw new LiveStudioError('Confirm removing this saved show and its rehearsal.');
    const id=uuid(q.params.id),show=await store.call(u.id,'get',id);
    if(ACTIVE.includes(show.state)||show.worker_token)throw new LiveStudioError('Wait for the show to finish stopping before removing it.',409);
    if(show.replay_path){
      if(!storage)throw new LiveStudioError('Private storage is temporarily unavailable.',503);
      const removed=await storage.from('korlix-live-studio').remove([show.replay_path]);if(removed.error)throw new LiveStudioError('The rehearsal could not be removed. Try again later.',503);
    }
    r.json(await store.call(u.id,'delete',id));
  }));
  if(startWorker)runtime?.start();
  if(startMaintenance)connections.startMaintenance?.();
  return {runtime,store,connections,stop:()=>Promise.all([runtime?.stop(),connections.stopMaintenance?.()])};
}
