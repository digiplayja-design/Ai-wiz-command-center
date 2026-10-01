import {LiveStudioError} from './core.mjs';

export function createYouTube(config,{fetcher=fetch}={}) {
  let lastToken='';
  const createdSessions=new Map();
  async function access(signal){
    if(typeof config.accessToken!=='function'||!config.channelId)throw new LiveStudioError('Connect your YouTube channel before broadcasting.',503);
    const token=await config.accessToken(signal);
    if(typeof token!=='string'||!token)throw new LiveStudioError('Reconnect your YouTube channel before broadcasting.',409);
    lastToken=token;return token;
  }
  async function api(resource,{method='GET',body,signal,cleanup=false}={}){
    // Cleanup can only be requested by the internal, ID-bound finish path.
    // It never refreshes a grant after an owner has stopped or disconnected it.
    const authorization=cleanup&&lastToken?lastToken:await access(signal);
    const r=await fetcher('https://www.googleapis.com/youtube/v3/'+resource,{method,signal:AbortSignal.any([signal,AbortSignal.timeout(20000)].filter(Boolean)),
      headers:{authorization:'Bearer '+authorization,'content-type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
    const data=r.status===204?{}:await r.json();
    if(!r.ok)throw new LiveStudioError('YouTube could not complete this action. Check channel eligibility and connection.',502);
    return data;
  }
  return {
    async setup(show,{signal}={}){
      // Verify the grant still identifies the exact channel reserved by this run.
      const channels=await api('channels?part=id&mine=true',{signal});
      if(!channels.items?.some(channel=>channel.id===config.channelId))throw new LiveStudioError('The connected YouTube channel changed. Reconnect it before starting a new show.',409);
      // Always unlisted during acceptance. No user/model text can change visibility.
      const broadcast=await api('liveBroadcasts?part=snippet,status,contentDetails',{method:'POST',signal,body:{snippet:{title:show.config.title,
        description:'An AI-hosted KORLIX Live Studio show. K-Nova and the Analyst are AI-generated voices. Sources and uncertainty are discussed on air.',
        scheduledStartTime:new Date(Date.now()+60000).toISOString()},status:{privacyStatus:'unlisted',selfDeclaredMadeForKids:false},
        contentDetails:{enableAutoStart:false,enableAutoStop:true,recordFromStart:true,enableDvr:true}}});
      let stream;
      try{
        await api('videos?part=status',{method:'PUT',signal,body:{id:broadcast.id,status:{privacyStatus:'unlisted',selfDeclaredMadeForKids:false,containsSyntheticMedia:true}}});
        stream=await api('liveStreams?part=snippet,cdn,contentDetails',{method:'POST',signal,body:{snippet:{title:show.config.title},
          cdn:{frameRate:'30fps',ingestionType:'rtmp',resolution:'720p'},contentDetails:{isReusable:false}}});
        await api('liveBroadcasts/bind?part=id&'+new URLSearchParams({id:broadcast.id,streamId:stream.id}),{method:'POST',signal});
        const ingest=stream.cdn?.ingestionInfo;
        if(!ingest?.rtmpsIngestionAddress||!ingest?.streamName)throw new LiveStudioError('YouTube did not provide a secure ingest destination.',502);
        createdSessions.set(broadcast.id,stream.id);
        return {id:broadcast.id,streamId:stream.id,chatId:broadcast.snippet?.liveChatId,
          watchUrl:'https://www.youtube.com/watch?v='+encodeURIComponent(broadcast.id),
          ingest:ingest.rtmpsIngestionAddress.replace(/\/$/,'')+'/'+ingest.streamName};
      }catch(error){
        // Remove only the new resources created by this failed setup.
        await api('liveBroadcasts?id='+encodeURIComponent(broadcast.id),{method:'DELETE',cleanup:true}).catch(()=>{});
        if(stream?.id)await api('liveStreams?id='+encodeURIComponent(stream.id),{method:'DELETE',cleanup:true}).catch(()=>{});
        throw error;
      }
    },
    async start(session,{signal}={}){
      if(session.startRequested){
        const current=await api('liveBroadcasts?part=status,snippet&id='+encodeURIComponent(session.id),{signal});
        session.chatId=current.items?.[0]?.snippet?.liveChatId||session.chatId;
        return current.items?.[0]?.status?.lifeCycleStatus==='live';
      }
      const status=await api('liveStreams?part=status&id='+encodeURIComponent(session.streamId),{signal});
      if(status.items?.[0]?.status?.streamStatus!=='active')return false;
      const changed=await api('liveBroadcasts/transition?part=status&'+new URLSearchParams({id:session.id,broadcastStatus:'live'}),{method:'POST',signal});
      session.startRequested=true;return changed.status?.lifeCycleStatus==='live';
    },
    async finish(session){
      if(!session||!createdSessions.has(session.id)||createdSessions.get(session.id)!==session.streamId)throw new LiveStudioError('This worker cannot close a different broadcast.',409);
      const cleanup=true;
      const current=await api('liveBroadcasts?part=status&id='+encodeURIComponent(session.id),{cleanup});
      const status=current.items?.[0]?.status?.lifeCycleStatus;
      if(status==='complete'||!status)return;
      if(['created','ready'].includes(status)){
        // Only remove the never-started resources this worker created.
        await api('liveBroadcasts?id='+encodeURIComponent(session.id),{method:'DELETE',cleanup});
        if(session.streamId)await api('liveStreams?id='+encodeURIComponent(session.streamId),{method:'DELETE',cleanup}).catch(()=>{});
        return;
      }
      try{await api('liveBroadcasts/transition?part=status&'+new URLSearchParams({id:session.id,broadcastStatus:'complete'}),{method:'POST',cleanup});}
      catch(error){
        // Auto-stop may finish the broadcast between our read and transition.
        const confirmed=await api('liveBroadcasts?part=status&id='+encodeURIComponent(session.id),{cleanup});
        if(confirmed.items?.[0]?.status?.lifeCycleStatus!=='complete')throw error;
      }
    },
    async chat(session,pageToken,{signal}={}){
      if(!session.chatId)return {items:[],nextPageToken:null,pollingIntervalMillis:10000};
      const data=await api('liveChat/messages?'+new URLSearchParams({part:'snippet',liveChatId:session.chatId,maxResults:'200',...(pageToken?{pageToken}:{})}),{signal});
      return {items:(data.items||[]).filter(i=>i.snippet?.type==='textMessageEvent').map(i=>({id:i.id,text:i.snippet.textMessageDetails?.messageText||''})),
        nextPageToken:data.nextPageToken,pollingIntervalMillis:Math.max(5000,data.pollingIntervalMillis||10000)};
    },
  };
}
