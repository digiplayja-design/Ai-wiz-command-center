import test from 'node:test';
import assert from 'node:assert/strict';
import {createYouTube,youtubeProviderError} from '../live_studio/youtube.mjs';

const channelId='fixture-channel';
const show={config:{title:'Community technology'}};
const json=(body,status=200)=>new Response(JSON.stringify(body),{status,headers:{'content-type':'application/json'}});
const errorBody=reason=>({error:{code:403,message:'PRIVATE provider message with token-secret',errors:[{reason,message:'PRIVATE resource detail',location:'https://private.test/?token=token-secret'}]}});
const setupFail=async(reason,status=403)=>{
  const calls=[];
  const client=createYouTube({channelId,accessToken:async()=>'access-secret'},{fetcher:async(url,options)=>{
    calls.push({url,options});
    if(url.includes('/channels?'))return json({items:[{id:channelId}]});
    return json(errorBody(reason),status);
  }});
  let failure;try{await client.setup(show);}catch(error){failure=error;}
  assert(failure);assert.equal(calls.length,2);assert.equal(failure.providerDiagnostic.operation,'create_broadcast');
  assert(failure.message.length<300);assert(!JSON.stringify(failure).includes('token-secret'));assert(!failure.message.includes('PRIVATE'));
  return failure;
};

test('disabled live streaming reports the create stage and activation steps without suggesting another OAuth login',async()=>{
  const error=await setupFail('liveStreamingNotEnabled');
  assert.equal(error.status,409);assert.match(error.message,/create broadcast/);assert.match(error.message,/Enable live streaming/);assert.match(error.message,/First activation can take up to 24 hours/);
  assert(!error.message.includes('Reconnect'));
  assert.deepEqual(error.providerDiagnostic,{operation:'create_broadcast',status:403,reason:'liveStreamingNotEnabled'});
});

test('blocked live permission directs customers to channel restrictions',async()=>{
  const error=await setupFail('livePermissionBlocked');assert.match(error.message,/Review and resolve the channel restrictions/);assert(!error.message.includes('Reconnect'));
});

for(const reason of ['insufficientPermissions','insufficientLivePermissions','authError','expired']){
  test(reason+' gives fixed connection permission guidance',async()=>{
    const error=await setupFail(reason);assert.match(error.message,/Reconnect your YouTube channel/);assert.equal(error.providerDiagnostic.reason,reason);
  });
}

test('HTTP401 takes precedence and safely handles a non-JSON response',async()=>{
  const client=createYouTube({channelId,accessToken:async()=>'secret'},{fetcher:async()=>new Response('<html>token-secret private authorization body</html>',{status:401})});
  await assert.rejects(client.setup(show),error=>{
    assert.match(error.message,/Reconnect your YouTube channel/);assert.deepEqual(error.providerDiagnostic,{operation:'verify_channel',status:401,reason:'auth401'});
    assert(!error.message.includes('token-secret'));return true;
  });
});

for(const reason of ['quotaExceeded','dailyLimitExceeded']){
  test(reason+' is an application API quota limit, not a claimed channel daily live limit',async()=>{
    const error=await setupFail(reason);assert.equal(error.status,429);assert.match(error.message,/application has reached its YouTube API quota/);assert(!error.message.includes('24 hours'));
  });
}

for(const reason of ['rateLimitExceeded','userRateLimitExceeded','userRequestsExceedRateLimit']){
  test(reason+' gives pacing guidance',async()=>{
    const error=await setupFail(reason);assert.equal(error.status,429);assert.match(error.message,/Wait a few minutes/);
  });
}

test('broadcast count limits do not invent a daily reset or automatic deletion',async()=>{
  for(const reason of ['userBroadcastsExceedLimit','concurrentBroadcastsExceedLimit','sharedIngestionBroadcastsExceedLimit']){
    const error=await setupFail(reason);assert.match(error.message,/scheduled and live broadcasts/);assert(!/daily|24 hours/.test(error.message));
  }
  const daily=await setupFail('uploadLimitExceeded',400);assert.match(daily.message,/daily YouTube video limit/);assert.equal(daily.status,429);
});

test('invalid request bodies and backend errors are categorized without echoing their fields',async()=>{
  for(const reason of ['invalidTitle','invalidScheduledStartTime','invalidPrivacyStatus','titleRequired','invalidValue']){
    const error=await setupFail(reason,400);assert.equal(error.status,400);assert.match(error.message,/request settings/);
  }
  for(const reason of ['backendError','internalError','errorExecutingTransition']){
    const error=await setupFail(reason,503);assert.equal(error.status,503);assert.match(error.message,/temporarily unavailable/);
  }
  const config=await setupFail('accessNotConfigured');assert.match(config.message,/Google Cloud API configuration/);assert(!config.message.includes('Reconnect'));
});

test('unknown provider content and untrusted operation labels cannot enter user errors or diagnostic fields',()=>{
  const secret='https://private.example/video?id=private-id&token=access-secret';
  for(const operation of [secret,'__proto__','constructor',null,{toString:()=>secret}]){
    const error=youtubeProviderError(operation,403,{error:{message:secret,errors:[{reason:secret,domain:secret,location:secret}],details:[secret]}});
    assert.deepEqual(error.providerDiagnostic,{operation:'youtube_request',status:403,reason:'unknown'});
    assert(Object.isFrozen(error.providerDiagnostic));
    assert(![error.message,error.stack,JSON.stringify(error)].some(text=>text.includes(secret)||text.includes('access-secret')));
    assert.equal(Object.hasOwn(error,'cause'),false);assert(error.message.length<300);
  }
  for(const status of [-1,Infinity,NaN,600,403.5,'403',null])assert.equal(youtubeProviderError('create_broadcast',status).providerDiagnostic.status,0);
  const multiple=youtubeProviderError('create_broadcast',403,{error:{errors:[{reason:secret},{reason:'livePermissionBlocked'}]}});
  assert.equal(multiple.providerDiagnostic.reason,'livePermissionBlocked');
});

test('malformed JSON, primitive success bodies and non-JSON failures return safe fixed errors',async()=>{
  for(const [body,status] of [['<html>access-secret</html>',502],['not-json-access-secret',200],['null',200],['"access-secret"',200],['["access-secret"]',200]]){
    const client=createYouTube({channelId,accessToken:async()=>'access-secret'},{fetcher:async()=>new Response(body,{status})});
    await assert.rejects(client.setup(show),error=>{
      assert.deepEqual(error.providerDiagnostic,{operation:'verify_channel',status,reason:'unknown'});assert(!error.message.includes('access-secret'));return true;
    });
  }
});

test('network exceptions are sanitized but caller cancellation and timeouts preserve abort semantics',async()=>{
  const network=createYouTube({channelId,accessToken:async()=>'access-secret'},{fetcher:async()=>{throw Error('private URL ?token=access-secret');}});
  await assert.rejects(network.setup(show),error=>{assert.equal(error.providerDiagnostic.status,0);assert(!error.message.includes('access-secret'));return true;});
  for(const name of ['AbortError','TimeoutError']){
    const abort=new DOMException('fixture cancellation',name),client=createYouTube({channelId,accessToken:async()=>'fixture'},{fetcher:async()=>{throw abort;}});
    await assert.rejects(client.setup(show),error=>error===abort);
  }
  const controller=new AbortController(),reason=new DOMException('owner stopped the show','AbortError');controller.abort(reason);
  const cancelled=createYouTube({channelId,accessToken:async()=>'fixture'},{fetcher:async(_url,options)=>{throw options.signal.reason;}});
  await assert.rejects(cancelled.setup(show,{signal:controller.signal}),error=>error===reason);
});

test('broadcast/session identifiers and page tokens never become operation labels',async()=>{
  const secret='private-id-access-secret',client=createYouTube({channelId,accessToken:async()=>'access-secret'},{fetcher:async()=>json(errorBody('userRequestsExceedRateLimit'),403)});
  await assert.rejects(client.chat({chatId:secret},secret),error=>{
    assert.deepEqual(error.providerDiagnostic,{operation:'read_chat',status:403,reason:'userRequestsExceedRateLimit'});assert(!JSON.stringify(error).includes(secret));assert(!error.message.includes(secret));return true;
  });
  await assert.rejects(client.start({id:secret,streamId:secret}),error=>error.providerDiagnostic.operation==='read_stream_status');
});

test('setup cleanup preserves the original failing stage and only deletes newly created resources',async()=>{
  const calls=[],client=createYouTube({channelId,accessToken:async()=>'fixture'},{fetcher:async(url,options)=>{
    calls.push({url,options});if(options.method==='DELETE')return new Response(null,{status:204});
    if(url.includes('/channels?'))return json({items:[{id:channelId}]});
    if(url.includes('/liveBroadcasts?'))return json({id:'new-broadcast'});
    return json(errorBody('invalidPrivacyStatus'),400);
  }});
  await assert.rejects(client.setup(show),error=>error.providerDiagnostic.operation==='update_disclosure');
  assert.deepEqual(calls.filter(call=>call.options.method==='DELETE').map(call=>new URL(call.url).pathname),['/youtube/v3/liveBroadcasts']);
});

test('direct-live creation disables monitor testing and preserves unlisted visibility, AI disclosure and lifecycle',async()=>{
  const calls=[],client=createYouTube({channelId,accessToken:async()=>'fixture'},{fetcher:async(url,options)=>{
    calls.push({url,options});
    if(url.includes('/channels?'))return json({items:[{id:channelId}]});
    if(url.includes('/liveBroadcasts?part=snippet'))return json({id:'broadcast',snippet:{liveChatId:'chat'}});
    if(url.includes('/liveStreams?part=snippet'))return json({id:'stream',cdn:{ingestionInfo:{rtmpsIngestionAddress:'rtmps://a.rtmps.youtube.com/live2',streamName:'stream-key'}}});
    if(url.includes('/liveStreams?part=status'))return json({items:[{status:{streamStatus:'active'}}]});
    if(url.includes('/transition?'))return json({status:{lifeCycleStatus:new URL(url).searchParams.get('broadcastStatus')}});
    if(url.includes('/liveBroadcasts?part=status'))return json({items:[{status:{lifeCycleStatus:'live'}}]});
    return json({});
  }});
  const session=await client.setup(show);assert.equal(await client.start(session),true);await client.finish(session);
  const insert=JSON.parse(calls.find(call=>call.url.includes('/liveBroadcasts?part=snippet')).options.body);
  assert.deepEqual(insert.contentDetails.monitorStream,{enableMonitorStream:false,broadcastStreamDelayMs:0});
  assert.equal(insert.status.privacyStatus,'unlisted');assert.equal(insert.contentDetails.enableAutoStart,false);assert.equal(insert.contentDetails.enableAutoStop,true);
  const disclosure=JSON.parse(calls.find(call=>call.url.includes('/videos?part=status')).options.body);assert.equal(disclosure.status.containsSyntheticMedia,true);
  assert.deepEqual(calls.filter(call=>call.url.includes('/transition?')).map(call=>new URL(call.url).searchParams.get('broadcastStatus')),['live','complete']);
});
