import {createPodProviders} from '../pod/providers.mjs';
import {LiveStudioError} from './core.mjs';

export function createLiveProviders(client){
  const shared=createPodProviders({client});
  const moderate=async(value,signal)=>{
    const result=await client.moderations.create({model:'omni-moderation-latest',input:value},{signal,timeout:15000,maxRetries:0});
    if(result.results?.length!==1||typeof result.results[0]?.flagged!=='boolean')throw new LiveStudioError('Content review is temporarily unavailable.',503);
    return !result.results[0].flagged;
  };
  return {...shared,moderate,
    async speak(args){
      if(!await moderate(args.text,args.signal))throw new LiveStudioError('This segment needs a producer review before broadcast.',422);
      return shared.speak(args);
    },
  };
}
