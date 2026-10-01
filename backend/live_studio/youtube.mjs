import {LiveStudioError,channelConfigured} from './core.mjs';

export function createYouTube(config,{fetcher=fetch}={}) {
  let token='',expires=0;
  async function access(signal){
    if(!channelConfigured(config))throw new LiveStudioError('Connect the pilot YouTube channel first.',503);
    if(token&&Date.now()<expires)return token;
    const r=await fetcher('https://oauth2.googleapis.com/token',{method:'POST',signal:AbortSignal.any([signal,AbortSignal.timeout(15000)].filter(Boolean)),
      headers:{'content-type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:config.clientId,client_secret:config.clientSecret,refresh_token:config.refreshToken,grant_type:'refresh_token'})});
    const data=await r.json();if(!r.ok||typeof data.access_token!=='string')throw new LiveStudioError('Reconnect the YouTube channel before broadcasting.',503);
    token=data.access_token;expires=Date.now()+Math.min(3000,Number(data.expires_in)||3000)*1000;return token;
  }
  async function api(resource,{method='GET',body,signal}={}){
    const authorization=await access(signal);
    const r=await fetcher('https://www.googleapis.com/youtube/v3/'+resource,{method,signal:AbortSignal.any([signal,AbortSignal.timeout(20000)].filter(Boolean)),
      headers:{authorization:'Bearer '+authorization,'content-type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
    const data=r.status===204?{}:await r.json();
    if(!r.ok)throw new LiveStudioError('YouTube could not complete this action. Check channel eligibility and connection.',502);
    return data;
  }
  return {
    async setup(show,{signal}={}){
      // Always unlisted for the pilot. No user/model text can change visibility.
      const broadcast=await api('liveBroadcasts?part=snippet,status,contentDetails',{method:'POST',signal,body:{snippet:{title:show.config.title,
        description:'An AI-hosted KORLIX Live Studio pilot. K-Nova and the Analyst are AI-generated voices. Sources and uncertainty are discussed on air.',
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
        return {id:broadcast.id,streamId:stream.id,chatId:broadcast.snippet?.liveChatId,
          watchUrl:'https://www.youtube.com/watch?v='+encodeURIComponent(broadcast.id),
          ingest:ingest.rtmpsIngestionAddress.replace(/\/$/,'')+'/'+ingest.streamName};
      }catch(error){
        // Remove only the new resources created by this failed setup.
        await api('liveBroadcasts?id='+encodeURIComponent(broadcast.id),{method:'DELETE'}).catch(()=>{});
        if(stream?.id)await api('liveStreams?id='+encodeURIComponent(stream.id),{method:'DELETE'}).catch(()=>{});
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
      await api('liveBroadcasts/transition?part=status&'+new URLSearchParams({id:session.id,broadcastStatus:'complete'}),{method:'POST'});
    },
    async chat(session,pageToken,{signal}={}){
      if(!session.chatId)return {items:[],nextPageToken:null,pollingIntervalMillis:10000};
      const data=await api('liveChat/messages?'+new URLSearchParams({part:'snippet',liveChatId:session.chatId,maxResults:'200',...(pageToken?{pageToken}:{})}),{signal});
      return {items:(data.items||[]).filter(i=>i.snippet?.type==='textMessageEvent').map(i=>({id:i.id,text:i.snippet.textMessageDetails?.messageText||''})),
        nextPageToken:data.nextPageToken,pollingIntervalMillis:Math.max(5000,data.pollingIntervalMillis||10000)};
    },
  };
}
