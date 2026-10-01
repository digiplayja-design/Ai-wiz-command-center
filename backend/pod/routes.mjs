import {PodError,POD_CATALOG,podUuid,podText,podInput,podVersion,podAudioBody,publicPodEpisode,publicPodTurn,podFailure} from './core.mjs';
import {createPodStore,POD_USAGE_LABEL} from './store.mjs';
import {createPodRuntime} from './runtime.mjs';
import {validatePodWav} from './providers.mjs';

const base='/api/pod';
export function registerPod(app,{database,requireUser,access,providers,store:providedStore,logger=console,
  runtimeOptions={},startSweep=true}={}) {
  const store=providedStore||createPodStore({database,logger});
  const runtime=createPodRuntime({store,providers,access,logger,...runtimeOptions});
  const route=fn=>async(q,r)=>{
    r.set('Cache-Control','no-store');r.set('X-Content-Type-Options','nosniff');
    try {
      let user;try{user=await requireUser(q);}catch{throw new PodError('Sign in to use The Pod and You.',401,'pod_sign_in');}
      if(!user?.id)throw new PodError('Sign in to use The Pod and You.',401,'pod_sign_in');
      if(user.banned_until&&Date.parse(user.banned_until)>Date.now())throw new PodError('This account is not available.',403);
      if(!providedStore&&!database)throw new PodError('The pod studio is temporarily unavailable.',503);
      await fn(q,r,user);
    }catch(error){if(!r.headersSent&&!r.destroyed){const f=podFailure(error);r.status(f.status).json({error:f.error,code:f.code});}}
  };
  const allowed=async user=>{
    const value=await access(user);
    if(!value?.allowed)throw new PodError(value?.reason||'The personal beta is available on Ultra Premium and Enterprise.',value?.status||403,'pod_access_denied');
    return value;
  };
  const reply=(r,data)=>r.json({episode:publicPodEpisode(data.episode),
    ...(data.turn!==undefined?{turn:publicPodTurn(data.turn)}:{}),
    ...(data.audio!==undefined?{audio:data.audio}:{}),
    ...(typeof data.text==='string'?{text:data.text}:{}),
    ...(data.replayed===true?{replayed:true}:{}),
    ...(data.audioUnavailable===true?{audioUnavailable:true}:{}),
    ...(typeof data.prepared==='boolean'?{prepared:data.prepared}:{}),
    ...(typeof data.preparedId==='string'?{preparedId:data.preparedId}:{})});
  app.get(base,route(async(_q,r,u)=>{
    const [a,list]=await Promise.all([access(u),store.list(u.id)]);
    const maxSeconds=a?.allowed?Math.min(900,a.limits?.maxSessionSeconds||900,a.remainingSeconds??900):0;
    r.json({catalog:POD_CATALOG,access:{allowed:a?.allowed===true,reason:a?.reason||null,maxSeconds,
      durations:[300,600,900].filter(s=>s<=maxSeconds),usageLabel:POD_USAGE_LABEL},
      episodes:(list.episodes||[]).map(publicPodEpisode)});
  }));
  app.post(base+'/episodes',route(async(q,r,u)=>{
    const requestId=podUuid(q.body?.requestId),input=podInput(q.body),a=await allowed(u);
    reply(r,await store.create(u.id,{requestId,input,limits:a.limits,unlimited:a.unlimited===true}));
  }));
  app.get(base+'/episodes/:id',route(async(q,r,u)=>reply(r,{episode:(await store.get(u.id,podUuid(q.params.id))).episode})));
  app.post(base+'/episodes/:id/control',route(async(q,r,u)=>{
    const id=podUuid(q.params.id),action=q.body?.action;
    if(!['pause','resume','interrupt','end','heartbeat'].includes(action))throw new PodError('Choose a valid episode control.');
    if(action==='resume')await allowed(u);
    const data=await store.control(u.id,id,action);
    // A normal heartbeat while the listener is recording/transcribing must not
    // cancel that paused-state operation. Only a lost heartbeat is an interruption.
    if(['pause','interrupt','end'].includes(action)||['ended','failed'].includes(data.episode?.state)||
      (data.episode?.state==='paused'&&data.episode?.endReason==='heartbeat_lost')) {
      runtime.abort(u.id,id,'Episode playback changed.',{preservePrepared:!['interrupt','end'].includes(action)&&data.episode?.state==='paused'});
    }
    reply(r,{episode:data.episode});
  }));
  app.post(base+'/episodes/:id/contributions',route(async(q,r,u)=>{
    const id=podUuid(q.params.id),requestId=podUuid(q.body?.requestId),text=podText(q.body?.text,1000,'Your contribution');
    await allowed(u);
    const data=await store.contribute(u.id,id,{requestId,text});runtime.abort(u.id,id);
    reply(r,{episode:data.episode});
  }));
  const generation=kind=>route(async(q,r,u)=>{
    const id=podUuid(q.params.id),requestId=podUuid(q.body?.requestId);
    await allowed(u);
    let wav,version;
    if(kind==='transcribe') {
      wav=podAudioBody(q.body?.audioBase64);validatePodWav(wav,{maxSeconds:30});
      version=(await store.get(u.id,id)).episode.version;
    } else {
      version=podVersion(q.body?.version);
      const current=(await store.get(u.id,id)).episode;
      if(current.summary&&current.state==='active') {
        if(kind==='prepare')return reply(r,{episode:current,prepared:false});
        const ended=await store.control(u.id,id,'end');return reply(r,{episode:ended.episode,turn:null,audio:null});
      }
    }
    const result=await runtime.run({user:u,id,requestId,version,kind,wav,onStart:controller=>{
      r.once('close',()=>{if(!r.writableEnded)controller.abort(new PodError('The listener disconnected.',409,'pod_disconnected'));});
      if(r.destroyed||q.aborted)controller.abort(new PodError('The listener disconnected.',409,'pod_disconnected'));
    }});
    reply(r,result);
  });
  app.post(base+'/episodes/:id/next',generation('next'));
  app.post(base+'/episodes/:id/prepare',generation('prepare'));
  app.post(base+'/episodes/:id/play-prepared',route(async(q,r,u)=>{
    const id=podUuid(q.params.id),requestId=podUuid(q.body?.requestId),version=podVersion(q.body?.version);
    await allowed(u);
    reply(r,await runtime.playPrepared({user:u,id,requestId,version}));
  }));
  app.post(base+'/episodes/:id/transcribe',generation('transcribe'));
  app.delete(base+'/episodes/:id',route(async(q,r,u)=>{
    if(q.body?.confirmed!==true)throw new PodError('Confirm before deleting this episode.');
    const id=podUuid(q.params.id);await store.remove(u.id,id,{confirmed:true});runtime.abort(u.id,id);r.json({deleted:true});
  }));
  let sweeping=false;
  const sweep=async()=>{
    if(sweeping||!store.sweep)return;sweeping=true;
    try{await store.sweep();}catch(error){logger.warn?.('Pod cleanup unavailable',{code:error?.code||'unavailable'});}finally{sweeping=false;}
  };
  const timer=startSweep&&database?setInterval(sweep,15000):null;timer?.unref?.();
  if(timer)void sweep();
  return {store,runtime,stop(){clearInterval(timer);runtime.stop();}};
}
