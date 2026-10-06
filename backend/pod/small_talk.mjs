import {PodError} from './core.mjs';
import {validatePodWav} from './providers.mjs';

// Shared studio assets: fixed, claim-free lines, never listener text or a second
// generated discussion. At most nine syntheses per process, with two in flight.
export const POD_SMALL_TALK = Object.freeze(Object.fromEntries(Object.entries({
 host: [
  "Let's give that a little room. There are a few ways to look at it.",
  "This is where a conversation gets interesting. Let's follow that thought.",
  "And if you're listening, keep your own take in mind. There's room for you here.",
 ],
 analyst: [
  "A little context goes a long way. Let's keep the bigger picture in view.",
  "It's useful to slow down for a moment and look at the details.",
  "Let's take this one piece at a time. A clear question is a good place to start.",
 ],
 challenger: [
  "Let's leave a little room for another perspective. That's part of the fun.",
  "There's room to see this differently. Let's keep an open mind.",
  "I like a conversation that leaves room for questions. Let's keep exploring.",
 ],
}).flatMap(([speaker,lines])=>lines.map((text,i)=>[`${speaker}-${i}`,{id:`${speaker}-${i}`,speaker,text}]))));

export function createPodSmallTalk({providers,logger=console}={}) {
 const assets=new Map(),controllers=new Set();let closed=false,nextLane=0;
 const lanes=[Promise.resolve(),Promise.resolve()];
 function audio(id) {
  if(closed)throw new PodError('The pod studio is restarting.',503);
  const clip=Object.hasOwn(POD_SMALL_TALK,id)?POD_SMALL_TALK[id]:null;
  if(!clip)throw new PodError('Choose an available studio transition.',400);
  if(!assets.has(id)) {
   const lane=nextLane++%lanes.length;
   const result=lanes[lane].then(async()=>{
    if(closed)throw new PodError('The pod studio is restarting.',503);
    const controller=new AbortController();controllers.add(controller);
    const timer=setTimeout(()=>controller.abort(),15000);timer.unref?.();
    try {
     const speech=await providers.speak({...clip,signal:controller.signal});
     controller.signal.throwIfAborted();
     const {durationSeconds}=validatePodWav(speech.wav,{maxSeconds:10});
     logger.info?.('Pod studio asset prepared',{id,seconds:durationSeconds,characters:clip.text.length,
      providerRequestId:speech.usage?.providerRequestId||null});
     return {...clip,audio:{base64:Buffer.from(speech.wav).toString('base64'),mime:'audio/wav',durationSeconds}};
    }finally{clearTimeout(timer);controllers.delete(controller);}
   });
   // Keep failures too: repeated requests cannot create an unbounded paid retry.
   assets.set(id,result);lanes[lane]=result.then(()=>{},()=>{});
  }
  return assets.get(id);
 }
 return {audio,stop(){closed=true;for(const c of controllers)c.abort();assets.clear();}};
}
