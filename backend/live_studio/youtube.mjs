import {LiveStudioError} from './core.mjs';

const OPERATIONS=Object.freeze({
  verify_channel:'verify the connected channel',create_broadcast:'create broadcast',
  update_disclosure:'save the AI disclosure',create_stream:'create stream',bind_stream:'bind stream',
  delete_broadcast:'remove the unused broadcast',delete_stream:'remove the unused stream',
  read_broadcast_status:'check broadcast status',read_stream_status:'check stream status',
  start_broadcast:'start broadcast',finish_broadcast:'finish broadcast',read_chat:'read live chat',
  youtube_request:'complete the YouTube request',
});
const PERMISSION_REASONS=new Set(['insufficientPermissions','insufficientLivePermissions','authError','expired']);
const QUOTA_REASONS=new Set(['quotaExceeded','dailyLimitExceeded']);
const RATE_REASONS=new Set(['rateLimitExceeded','userRateLimitExceeded','userRequestsExceedRateLimit']);
const BROADCAST_LIMIT_REASONS=new Set(['userBroadcastsExceedLimit','concurrentBroadcastsExceedLimit','sharedIngestionBroadcastsExceedLimit']);
const INVALID_REASONS=new Set(['badRequest','invalidValue','required','invalidAutoStart','invalidAutoStop','invalidDescription',
  'invalidEmbedSetting','invalidLatencyPreferenceOptions','invalidPrivacyStatus','invalidProjection','invalidScheduledEndTime',
  'invalidScheduledStartTime','invalidTitle','privacyStatusRequired','scheduledEndTimeRequired','scheduledStartTimeRequired',
  'titleRequired','idRequired','statusRequired','cdnRequired','formatRequired','frameRateRequired','ingestionTypeRequired',
  'invalidFormat','invalidFrameRate','invalidIngestionType','invalidResolution','resolutionRequired','invalidVideoMetadata',
  'invalidDefaultBroadcastPrivacySetting','forbiddenPrivacySetting']);
const BACKEND_REASONS=new Set(['backendError','internalError','errorExecutingTransition']);
const REASONS=new Set(['liveStreamingNotEnabled','livePermissionBlocked','accessNotConfigured','uploadLimitExceeded',
  'errorStreamInactive','invalidTransition','redundantTransition',...PERMISSION_REASONS,...QUOTA_REASONS,...RATE_REASONS,
  ...BROADCAST_LIMIT_REASONS,...INVALID_REASONS,...BACKEND_REASONS]);

// Provider text, resource IDs, URLs and response bodies never enter this error.
// The diagnostic is suitable for logs only because every field is constrained.
export function youtubeProviderError(operation,status,data){
  const stage=typeof operation==='string'&&Object.hasOwn(OPERATIONS,operation)?operation:'youtube_request';
  const httpStatus=Number.isInteger(status)&&status>=100&&status<=599?status:0;
  const errors=Array.isArray(data?.error?.errors)?data.error.errors:[];
  const reason=httpStatus===401?'auth401':errors.map(error=>error?.reason).find(value=>typeof value==='string'&&REASONS.has(value))||'unknown';
  let detail='Check channel access and status in YouTube Studio. If the problem continues, contact KORLIX support.',code=502;
  if(reason==='liveStreamingNotEnabled'){
    detail='Enable live streaming and complete channel verification in YouTube Studio. First activation can take up to 24 hours; try again once YouTube enables it.';code=409;
  }else if(reason==='livePermissionBlocked'){
    detail='YouTube has blocked live streaming for this channel. Review and resolve the channel restrictions in YouTube Studio before retrying.';code=409;
  }else if(reason==='auth401'||PERMISSION_REASONS.has(reason)){
    detail='Reconnect your YouTube channel in Live Studio and allow the requested permissions before starting a new show.';code=409;
  }else if(reason==='accessNotConfigured'){
    detail='The YouTube API is unavailable for the KORLIX application. Contact KORLIX support to check its Google Cloud API configuration.';code=503;
  }else if(QUOTA_REASONS.has(reason)){
    detail='The KORLIX application has reached its YouTube API quota. Wait for quota to reset or contact KORLIX support.';code=429;
  }else if(RATE_REASONS.has(reason)||httpStatus===429){
    detail='YouTube is limiting requests. Wait a few minutes before trying again.';code=429;
  }else if(BROADCAST_LIMIT_REASONS.has(reason)){
    detail='The channel has reached a YouTube broadcast limit. Review scheduled and live broadcasts in YouTube Studio; stop or remove unused broadcasts before retrying.';code=409;
  }else if(reason==='uploadLimitExceeded'){
    detail='This channel has reached its daily YouTube video limit. Wait for the channel limit to reset before trying again.';code=429;
  }else if(INVALID_REASONS.has(reason)||httpStatus===400){
    detail='YouTube rejected the request settings. Review the show title and schedule; contact KORLIX support if the problem continues.';code=400;
  }else if(reason==='errorStreamInactive'){
    detail='YouTube has not detected an active encoder stream. Check the broadcast worker and stream health before starting another show.';code=409;
  }else if(reason==='invalidTransition'||reason==='redundantTransition'){
    detail='YouTube cannot change the broadcast from its current state. Check its status in YouTube Studio before trying again.';code=409;
  }else if(BACKEND_REASONS.has(reason)||httpStatus>=500||httpStatus===0){
    detail='YouTube is temporarily unavailable. Check YouTube Studio for a partially created broadcast before trying again later.';code=503;
  }
  const error=new LiveStudioError(`YouTube could not ${OPERATIONS[stage]}. ${detail}`,code);
  error.providerDiagnostic=Object.freeze({operation:stage,status:httpStatus,reason});
  return error;
}
const isAbort=error=>error?.name==='AbortError'||error?.name==='TimeoutError';

export function createYouTube(config,{fetcher=fetch}={}) {
  let lastToken='';
  const createdSessions=new Map();
  async function access(signal){
    if(typeof config.accessToken!=='function'||!config.channelId)throw new LiveStudioError('Connect your YouTube channel before broadcasting.',503);
    const token=await config.accessToken(signal);
    if(typeof token!=='string'||!token)throw new LiveStudioError('Reconnect your YouTube channel before broadcasting.',409);
    lastToken=token;return token;
  }
  async function api(operation,resource,{method='GET',body,signal,cleanup=false}={}){
    // Cleanup can only be requested by the internal, ID-bound finish path.
    // It never refreshes a grant after an owner has stopped or disconnected it.
    const authorization=cleanup&&lastToken?lastToken:await access(signal);
    const requestSignal=AbortSignal.any([signal,AbortSignal.timeout(20000)].filter(Boolean));
    let r,data;
    try{
      r=await fetcher('https://www.googleapis.com/youtube/v3/'+resource,{method,signal:requestSignal,
        headers:{authorization:'Bearer '+authorization,'content-type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
    }catch(error){
      if(requestSignal.aborted)throw requestSignal.reason;
      if(isAbort(error))throw error;
      throw youtubeProviderError(operation,0);
    }
    try{data=r.status===204?{}:await r.json();}
    catch(error){
      if(requestSignal.aborted)throw requestSignal.reason;
      if(isAbort(error))throw error;
      throw youtubeProviderError(operation,r.status);
    }
    if(!r.ok||!data||typeof data!=='object'||Array.isArray(data))throw youtubeProviderError(operation,r.status,data);
    return data;
  }
  return {
    async setup(show,{signal}={}){
      // Verify the grant still identifies the exact channel reserved by this run.
      const channels=await api('verify_channel','channels?part=id&mine=true',{signal});
      if(!channels.items?.some(channel=>channel.id===config.channelId))throw new LiveStudioError('The connected YouTube channel changed. Reconnect it before starting a new show.',409);
      // Always unlisted during acceptance. No user/model text can change visibility.
      const broadcast=await api('create_broadcast','liveBroadcasts?part=snippet,status,contentDetails',{method:'POST',signal,body:{snippet:{title:show.config.title,
        description:'An AI-hosted KORLIX Live Studio show. Rici and the Analyst are AI-generated voices. Sources and uncertainty are discussed on air.',
        scheduledStartTime:new Date(Date.now()+60000).toISOString()},status:{privacyStatus:'unlisted',selfDeclaredMadeForKids:false},
        contentDetails:{enableAutoStart:false,enableAutoStop:true,recordFromStart:true,enableDvr:true,
          monitorStream:{enableMonitorStream:false,broadcastStreamDelayMs:0}}}});
      let stream;
      try{
        await api('update_disclosure','videos?part=status',{method:'PUT',signal,body:{id:broadcast.id,status:{privacyStatus:'unlisted',selfDeclaredMadeForKids:false,containsSyntheticMedia:true}}});
        stream=await api('create_stream','liveStreams?part=snippet,cdn,contentDetails',{method:'POST',signal,body:{snippet:{title:show.config.title},
          cdn:{frameRate:'30fps',ingestionType:'rtmp',resolution:'720p'},contentDetails:{isReusable:false}}});
        await api('bind_stream','liveBroadcasts/bind?part=id&'+new URLSearchParams({id:broadcast.id,streamId:stream.id}),{method:'POST',signal});
        const ingest=stream.cdn?.ingestionInfo;
        if(!ingest?.rtmpsIngestionAddress||!ingest?.streamName)throw new LiveStudioError('YouTube did not provide a secure ingest destination.',502);
        createdSessions.set(broadcast.id,stream.id);
        return {id:broadcast.id,streamId:stream.id,chatId:broadcast.snippet?.liveChatId,
          watchUrl:'https://www.youtube.com/watch?v='+encodeURIComponent(broadcast.id),
          ingest:ingest.rtmpsIngestionAddress.replace(/\/$/,'')+'/'+ingest.streamName};
      }catch(error){
        // Remove only the new resources created by this failed setup.
        await api('delete_broadcast','liveBroadcasts?id='+encodeURIComponent(broadcast.id),{method:'DELETE',cleanup:true}).catch(()=>{});
        if(stream?.id)await api('delete_stream','liveStreams?id='+encodeURIComponent(stream.id),{method:'DELETE',cleanup:true}).catch(()=>{});
        throw error;
      }
    },
    async start(session,{signal}={}){
      if(session.startRequested){
        const current=await api('read_broadcast_status','liveBroadcasts?part=status,snippet&id='+encodeURIComponent(session.id),{signal});
        session.chatId=current.items?.[0]?.snippet?.liveChatId||session.chatId;
        return current.items?.[0]?.status?.lifeCycleStatus==='live';
      }
      const status=await api('read_stream_status','liveStreams?part=status&id='+encodeURIComponent(session.streamId),{signal});
      if(status.items?.[0]?.status?.streamStatus!=='active')return false;
      const changed=await api('start_broadcast','liveBroadcasts/transition?part=status&'+new URLSearchParams({id:session.id,broadcastStatus:'live'}),{method:'POST',signal});
      session.startRequested=true;return changed.status?.lifeCycleStatus==='live';
    },
    async finish(session){
      if(!session||!createdSessions.has(session.id)||createdSessions.get(session.id)!==session.streamId)throw new LiveStudioError('This worker cannot close a different broadcast.',409);
      const cleanup=true;
      const current=await api('read_broadcast_status','liveBroadcasts?part=status&id='+encodeURIComponent(session.id),{cleanup});
      const status=current.items?.[0]?.status?.lifeCycleStatus;
      if(status==='complete'||!status)return;
      if(['created','ready'].includes(status)){
        // Only remove the never-started resources this worker created.
        await api('delete_broadcast','liveBroadcasts?id='+encodeURIComponent(session.id),{method:'DELETE',cleanup});
        if(session.streamId)await api('delete_stream','liveStreams?id='+encodeURIComponent(session.streamId),{method:'DELETE',cleanup}).catch(()=>{});
        return;
      }
      try{await api('finish_broadcast','liveBroadcasts/transition?part=status&'+new URLSearchParams({id:session.id,broadcastStatus:'complete'}),{method:'POST',cleanup});}
      catch(error){
        // Auto-stop may finish the broadcast between our read and transition.
        const confirmed=await api('read_broadcast_status','liveBroadcasts?part=status&id='+encodeURIComponent(session.id),{cleanup});
        if(confirmed.items?.[0]?.status?.lifeCycleStatus!=='complete')throw error;
      }
    },
    async chat(session,pageToken,{signal}={}){
      if(!session.chatId)return {items:[],nextPageToken:null,pollingIntervalMillis:10000};
      const data=await api('read_chat','liveChat/messages?'+new URLSearchParams({part:'snippet',liveChatId:session.chatId,maxResults:'200',...(pageToken?{pageToken}:{})}),{signal});
      return {items:(data.items||[]).filter(i=>i.snippet?.type==='textMessageEvent').map(i=>({id:i.id,text:i.snippet.textMessageDetails?.messageText||''})),
        nextPageToken:data.nextPageToken,pollingIntervalMillis:Math.max(5000,data.pollingIntervalMillis||10000)};
    },
  };
}
