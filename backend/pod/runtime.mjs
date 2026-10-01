import {PodError,podUsage} from './core.mjs';
import {podWelcomeTurn} from './providers.mjs';

/** Paid work is always client-driven, owner-scoped, leased, and separately receipted. */
export function createPodRuntime({store,providers,access,logger=console,now=Date.now,
  operationTimeoutMs=210000,watchdogMs=5000,maxConcurrent=8}={}) {
  const pending = new Map(), audioCache = new Map();
  let cacheBytes=0,closed=false;
  const key=(actor,id)=>`${actor}:${id}`;
  function discardAudio(k) {
    const old=audioCache.get(k);if(old)cacheBytes-=old.bytes;audioCache.delete(k);
  }
  function cacheAudio(k,requestId,audio) {
    discardAudio(k);
    if(!audio)return;
    const bytes=audio.base64.length;
    while(audioCache.size>=24 || cacheBytes+bytes>48*1024*1024) {
      const first=audioCache.keys().next().value;if(!first)break;discardAudio(first);
    }
    audioCache.set(k,{requestId,audio,bytes,expires:now()+120000});cacheBytes+=bytes;
  }
  function cachedAudio(k,requestId) {
    const cached=audioCache.get(k);
    if(cached?.expires<=now()){discardAudio(k);return null;}
    return cached?.requestId===requestId?cached.audio:null;
  }
  function abort(actor,id,reason='Episode playback changed.') {
    const k=key(actor,id);pending.get(k)?.controller.abort(new PodError(reason,409,'pod_interrupted'));discardAudio(k);
  }
  async function paid({user,id,requestId,callKey,method,args,signal}) {
    signal.throwIfAborted();
    const entitlement=await access(user);
    if(!entitlement?.allowed)throw new PodError(entitlement?.reason||'This account cannot continue the pod.',entitlement?.status||403,'pod_access_denied');
    signal.throwIfAborted();
    const authorization=await store.authorizeDispatch(user.id,id,requestId,callKey);
    if(authorization?.allowed!==true)throw new PodError('This episode paused, ended, or reached its allowance. Refresh before continuing.',409,'pod_interrupted');
    // Cancellation between the durable dispatch marker and the SDK call is treated as uncertain,
    // never an invitation to repeat a possibly paid request.
    let result;
    try {signal.throwIfAborted();result=await providers[method]({...args,signal});}
    catch(error) {
      const evidence=error?.usage||{kind:callKey,status:'uncertain',usageKnown:false};
      await store.recordUsage(user.id,id,requestId,{callKey,usage:podUsage(evidence,callKey),evidence});
      throw error;
    }
    let evidence=result?.usage||{kind:callKey,status:'completed',usageKnown:false};
    const validCount=v=>Number.isSafeInteger(v)&&v>=0&&v<=10000000;
    const unknownTextUsage=callKey!=='speak'&&(!validCount(evidence.totalTokens)||
      (callKey!=='transcribe'&&(!validCount(evidence.inputTokens)||!validCount(evidence.outputTokens))));
    if(unknownTextUsage)evidence={...evidence,status:'uncertain',usageKnown:false};
    const receipt=await store.recordUsage(user.id,id,requestId,{callKey,usage:podUsage(evidence,callKey),evidence});
    if(unknownTextUsage)throw new PodError('The provider could not confirm AI usage. This episode has stopped; no automatic retry was made.',503,'pod_usage_unknown');
    if(receipt?.allowed===false)throw new PodError('This episode paused, ended, or reached its allowance. Refresh before continuing.',409,'pod_interrupted');
    signal.throwIfAborted();
    return result;
  }
  async function run({user,id,requestId,version,kind,wav,onStart}) {
    if(closed)throw new PodError('The pod service is restarting. Please reopen your pod.',503);
    const k=key(user.id,id);
    if(pending.has(k))throw new PodError('A turn is still finishing. Please wait a moment.',409,'pod_request_active');
    if(pending.size>=maxConcurrent)throw new PodError('The pod studio is busy. Please try again shortly.',429,'pod_busy');
    // Same-process reservation before await; database lease supplies cross-process exclusion.
    const controller=new AbortController();
    const entry={controller,user,id,requestId,version};pending.set(k,entry);
    let timer,watchdog,claimed=false,checking=false;
    try {
      const claim=await store.claim(user.id,id,{requestId,version,kind});
      if(!claim.dispatch) {
        const old=claim.result||{},audio=kind==='next'?cachedAudio(k,requestId):null;
        return {episode:claim.episode,turn:old.turn||null,...(kind==='transcribe'?{text:old.text||''}:{audio,audioUnavailable:!!old.turn&&!audio}),replayed:true};
      }
      claimed=true;
      entry.version=claim.episode?.version??version;
      onStart?.(controller);
      const remainingDeadline=claim.episode?.deadlineAt?Math.max(0,Date.parse(claim.episode.deadlineAt)-now()):operationTimeoutMs;
      timer=setTimeout(()=>controller.abort(new PodError('This turn took too long or reached the episode limit. Refresh before trying again.',504,'pod_timeout')),Math.min(operationTimeoutMs,remainingDeadline));timer.unref?.();
      watchdog=setInterval(async()=>{
        if(checking||controller.signal.aborted)return;checking=true;
        try {
          const current=await store.get(user.id,id),e=current.episode;
          if(!e||['ended','failed'].includes(e.state)||e.version!==entry.version||
            (kind==='next'&&e.state==='paused')||
            (e.deadlineAt&&Date.parse(e.deadlineAt)<=now()))controller.abort(new PodError('This episode paused, ended or changed. Refresh to continue.',409,'pod_interrupted'));
        }catch(error){controller.abort(error);}finally{checking=false;}
      },watchdogMs);watchdog.unref?.();
      const signal=controller.signal;
      if(kind==='transcribe') {
        const value=await paid({user,id,requestId,callKey:'transcribe',method:'transcribe',args:{wav},signal});
        const done=await store.finish(user.id,id,requestId,{text:value.text});
        if(!done.committed)throw new PodError('The episode changed while your voice was transcribed. Please refresh.',409,'pod_interrupted');
        signal.throwIfAborted();
        return {episode:done.episode,text:done.text??value.text};
      }
      let brief=claim.brief,turn;
      const hostTurns=(claim.episode.turns||[]).filter(t=>t.speaker!=='user').length;
      const welcome=hostTurns===0&&!brief?.text;
      const seconds=claim.episode.deadlineAt?Math.max(0,(Date.parse(claim.episode.deadlineAt)-now())/1000):claim.episode.durationSeconds;
      if(seconds<=0)throw new PodError('This episode has reached its time limit.',409,'pod_ended');
      const closing=!welcome&&(seconds<=60||hostTurns>=35);
      if(welcome) {
        // A factual-claim-free introduction reaches the listener before slow research.
        // It uses only a real speech receipt; no language-model usage is fabricated.
        turn=podWelcomeTurn(claim.episode);
      } else if(!brief?.text) {
        // Research supplies the first sourced Analyst turn in the same response.
        // Avoid a second full reasoning request before the discussion can begin.
        const researched=await paid({user,id,requestId,callKey:'research',method:'research',
          args:{category:claim.episode.category,topic:claim.episode.topic,style:claim.episode.style,
            contributions:(claim.episode.turns||[]).filter(t=>t.speaker==='user').map(t=>t.text)},signal});
        brief=researched.brief;turn=researched.initialTurn;
        if(!turn)throw new PodError('The research did not include a usable opening. Please start a new episode.',502,'pod_opening_unavailable');
      } else {
        turn=await paid({user,id,requestId,callKey:'turn',method:'turn',
          args:{episode:claim.episode,brief,remainingSeconds:seconds,closing},signal});
      }
      const speech=await paid({user,id,requestId,callKey:'speak',method:'speak',args:{speaker:turn.speaker,text:turn.text},signal});
      const result={turn:{speaker:turn.speaker,text:turn.text,sourceIds:turn.sourceIds||[]},
        ...(welcome?{welcome:true}:{brief,sources:brief.sources||[],checkedAt:brief.checkedAt}),
        ...(closing?{summary:turn.text}:{})};
      const done=await store.finish(user.id,id,requestId,result);
      if(!done.committed)throw new PodError('The episode changed before this turn could play. Refresh to continue.',409,'pod_interrupted');
      signal.throwIfAborted();
      const audio={base64:Buffer.from(speech.wav).toString('base64'),mime:'audio/wav',durationSeconds:speech.durationSeconds};
      cacheAudio(k,requestId,audio);
      return {episode:done.episode,turn:done.turn||done.episode.turns?.at(-1),audio};
    } catch(error) {
      if(claimed) {
        try{await store.fail(user.id,id,requestId,{error:error?.name==='PodProviderError'?error.message:
          controller.signal.aborted?'The turn was interrupted. Resume when you are ready.':'This turn could not finish. Refresh the pod before continuing.',
          uncertain:error?.usage?.status==='uncertain'});}catch(failure){logger.warn?.('Pod operation settlement failed',{code:failure?.code||'unavailable'});}
      }
      throw controller.signal.aborted?controller.signal.reason:error;
    } finally {
      clearTimeout(timer);clearInterval(watchdog);
      if(pending.get(k)===entry)pending.delete(k);
    }
  }
  return {
    run,abort,
    stop(){closed=true;for(const p of pending.values())p.controller.abort(new PodError('Pod service is restarting.',503));for(const k of audioCache.keys())discardAudio(k);},
    get activeCount(){return pending.size;},
  };
}
