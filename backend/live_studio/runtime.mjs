import {randomUUID} from 'node:crypto';
import {mkdtemp,rm,readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {LiveStudioError,workerToken} from './core.mjs';
import {renderSegment,makeReplay,musicWav,broadcastSink} from './media.mjs';

const safeQuestion = value => typeof value==='string' && value.length>=6 && value.length<=400 &&
  !/[\u0000-\u001f\u007f]|https?:\/\/|www\.|@|```/.test(value) && value.includes('?');

export function createLiveRuntime({store,providers,storage,youtube:defaultYouTube,youtubeFactory,mode='rehearsal',ownerId=null,workerId=null,
  logger=console,render=renderSegment,replay=makeReplay,sinkFactory=broadcastSink,now=Date.now,pollMs=3000}={}) {
  let busy=false,timer,activeController,stopped=false;
  async function run(show) {
    const token=show.worker_token,controller=new AbortController();activeController=controller;
    const signal=controller.signal,dir=await mkdtemp(path.join(tmpdir(),'korlix-live-'));
    const call=(action,data={})=>store.call(show.owner_id,action,show.id,{...data,token});
    const event=(kind,data)=>call('event',{eventId:randomUUID(),kind,data});
    let heartbeating=false,heartbeat,current=show,sink,session,streamLive=false,errorMessage=null,replayPath=null,youtube=defaultYouTube;
    let index=0,offset=0,history=[],brief,staged=null,generating=null,callCount=0,seenCommand=0,ended=false,generationEpoch=0;
    let questionQueue=[],seenQuestions=new Set(),pageToken,chatNext=0,chatInitialized=false;
    const files=[];
    const paid=async(kind,operation)=>{
      signal.throwIfAborted();
      const state=await call('heartbeat');
      if(!['preparing','live','paused'].includes(state.state))throw new LiveStudioError('The producer ended this show.',409);
      if(++callCount>(mode==='rehearsal'?10:200))throw new LiveStudioError('The generation limit was reached.');
      const dispatchId=randomUUID();await event('dispatch',{dispatchId,kind});
      try{const result=await operation();await event('receipt',{dispatchId,kind,status:'completed',usage:result.usage??null});return result;}
      catch(error){await event('receipt',{dispatchId,kind,status:'failed_or_uncertain',usage:error.usage??null}).catch(()=>{});throw error;}
    };
    const beat=async()=>{
      if(heartbeating)return;heartbeating=true;
      try{
        current=await call('heartbeat');
        if(current.state==='cancelled'){ended=true;controller.abort(new LiveStudioError('The producer ended this show.',409));return;}
        const events=await store.call(show.owner_id,'events',show.id);
        for(const e of events.events||[])if(e.kind==='control'&&e.data.action==='question'&&!seenQuestions.has(e.id)){
          seenQuestions.add(e.id);if(safeQuestion(e.data.text))questionQueue.push(e.data.text);
        }
        questionQueue=questionQueue.slice(-10);
      }catch{controller.abort(new LiveStudioError('Studio control connection was lost. The show stopped.',503));}
      finally{heartbeating=false;}
    };
    heartbeat=setInterval(()=>void beat(),5000);heartbeat.unref?.();
    const pollChat=async()=>{
      if(!streamLive||!youtube?.chat||now()<chatNext)return;
      chatNext=now()+10000;
      try{
        const result=await youtube.chat(session,pageToken,{signal});pageToken=result.nextPageToken;
        chatNext=now()+Math.max(5000,result.pollingIntervalMillis);
        // The first response can contain pre-show history; begin with new messages.
        if(chatInitialized)for(const q of result.items||[])if(!seenQuestions.has(q.id)){
          seenQuestions.add(q.id);if(safeQuestion(q.text))questionQueue.push(q.text);
        }
        chatInitialized=true;questionQueue=questionQueue.slice(-10);
      }catch{chatNext=now()+60000;}
    };
    const speak=turn=>paid('speech',()=>providers.speak({...turn,signal}));
    const generate=async(closing=false)=>{
      // Keep server-selected roles and source-backed facts from the existing provider.
      let recent=history.slice(-24),segmentBrief=brief;
      let question=questionQueue.shift();
      if(question){try{if(!providers.moderate||!await providers.moderate(question,signal))question=null;}catch{question=null;}}
      if(question){
        // Research checks factual premises before the public host responds.
        const refreshed=await paid('research',()=>providers.research({...show.config,style:'balanced',contributions:[question],signal}));
        segmentBrief=refreshed.brief;recent=[...recent,{speaker:'user',text:question}];
      }
      const turn=await paid('turn',()=>providers.turn({episode:{...show.config,hostCount:2,style:'balanced',turns:recent},
        brief:segmentBrief,remainingSeconds:Math.min(900,Math.max(1,show.config.durationSeconds-offset)),closing,signal}));
      if(show.config.hostCount===1)turn.speaker='host';
      const audio=await speak(turn);
      return {turn,audio,brief:segmentBrief};
    };
    const segment=async(turn,audio,{paused=false,segmentBrief=brief}={})=>{
      signal.throwIfAborted();
      const seconds=Math.min(audio.durationSeconds,(mode==='rehearsal'?60:show.config.durationSeconds)-offset);
      if(seconds<=0)return;
      const result=await render({dir,index:index++,show,turn,wav:audio.wav,offset,seconds,signal,
        width:mode==='rehearsal'?640:1280,rehearsal:mode==='rehearsal',paused,sources:segmentBrief?.sources||[]});
      files.push(result.file);
      if(sink)await sink.write(result.file);
      offset+=result.duration;
      if(!paused){history.push(turn);await event('segment',{speaker:turn.speaker,text:turn.text,sourceIds:turn.sourceIds||[],seconds:result.duration});}
      await call('progress',{started:streamLive,watchUrl:session?.watchUrl,progress:{seconds:Math.round(offset),
        stage:mode==='rehearsal'?'Rendering private rehearsal':streamLive?'Broadcasting':'Connecting to YouTube',
        speaker:turn.speaker,caption:turn.text,sources:segmentBrief?.sources||[],checkedAt:segmentBrief?.checkedAt,providerCalls:callCount}});
    };
    try{
      if(mode==='youtube'&&youtubeFactory)youtube=await youtubeFactory(show);
      if(mode==='youtube'&&!youtube)throw new LiveStudioError('The channel connection is unavailable.',503);
      if(mode==='youtube'){
        // Confirm YouTube accepts this broadcast before spending on research or
        // speech. The existing finally path closes this session if generation fails.
        session=await youtube.setup(show,{signal});
        await event('destination',{broadcastId:session.id,streamId:session.streamId,watchUrl:session.watchUrl});
      }
      const researched=await paid('research',()=>providers.research({...show.config,style:'balanced',signal}));brief=researched.brief;
      const welcome={speaker:'host',sourceIds:[],text:`Welcome to KORLIX Live Studio. I’m Rici, your AI host${show.config.hostCount===2?', joined by our AI Analyst':''}. This is ${show.config.title}. We’ll separate verified facts from opinions and show our sources.`};
      // The provider enforces the 480-character speech bound.
      const welcomeAudio=await speak(welcome);
      const opening={...researched.initialTurn,speaker:show.config.hostCount===1?'host':'analyst'};
      const openingAudio=await speak(opening);
      if(mode==='youtube'){
        sink=sinkFactory(session.ingest,{signal});
        const connectDeadline=now()+90000;
        while(!streamLive){
          await segment({speaker:'host',sourceIds:[],text:'KORLIX Live Studio is connecting. Our AI hosts will begin shortly.'},
            {wav:musicWav(5),durationSeconds:5},{paused:true});
          streamLive=await youtube.start(session,{signal});
          if(!streamLive&&now()>connectDeadline)throw new LiveStudioError('YouTube did not confirm the live broadcast. Check channel status.',503);
        }
      }
      await segment(welcome,welcomeAudio);
      await segment(opening,openingAudio);
      if(mode==='rehearsal'){
        if(offset<55){const next=await generate(true);await segment(next.turn,next.audio,{segmentBrief:next.brief});}
        const output=path.join(dir,'rehearsal.mp4');await replay(files,output,{signal});
        const bytes=await readFile(output);signal.throwIfAborted();
        if(bytes.length>50*1024*1024)throw new LiveStudioError('The rehearsal video exceeded its size limit.');
        replayPath=`${show.owner_id}/${show.id}/${show.run_id}.mp4`;
        const uploaded=await storage.from('korlix-live-studio').upload(replayPath,bytes,{contentType:'video/mp4',upsert:false});
        if(uploaded.error)throw new LiveStudioError('The rehearsal finished but could not be saved. Start a new rehearsal after checking storage.',503);
      }else{
        const broadcastDeadline=now()+show.config.durationSeconds*1000;
        const prepare=()=>{if(!generating&&!staged){const epoch=generationEpoch;generating=generate(offset>show.config.durationSeconds-60)
          .then(value=>{if(epoch===generationEpoch)staged=value;},error=>{if(epoch===generationEpoch)staged={error};}).finally(()=>{generating=null;});}};
        prepare();
        while(offset<show.config.durationSeconds&&now()<broadcastDeadline){
          signal.throwIfAborted();await pollChat();
          const command=current.command||{};
          if(command.seq>seenCommand){
            seenCommand=command.seq;
            if(command.action==='skip'){generationEpoch++;staged=null;await event('producer_note',{text:'Skipped the next prepared segment.'});}
          }
          if(current.state==='paused'||!staged){
            const paused=current.state==='paused';
            await segment({speaker:'host',sourceIds:[],text:paused?'The producer has paused this discussion.':'A short studio interlude while the next segment is prepared.'},
              {wav:musicWav(5),durationSeconds:5},{paused:true});
            if(!paused)prepare();
          }else{
            const next=staged;staged=null;if(next.error)throw next.error;
            brief=next.brief;
            history.push(next.turn);prepare();history.pop();await segment(next.turn,next.audio,{segmentBrief:next.brief});
          }
        }
        await sink.close();sink=null;
        await youtube.finish(session);
      }
    }catch(error){
      errorMessage=ended?null:error instanceof LiveStudioError?error.message:'The show stopped while preparing its next segment. Review its status before starting again.';
      if(!ended)logger.warn?.('Live Studio run stopped',{code:error?.name||'unavailable',showId:show.id,
        ...(error?.providerDiagnostic?{youtube:error.providerDiagnostic}:{})});
    }finally{
      clearInterval(heartbeat);controller.abort();sink?.stop();
      if(session&&(!streamLive||errorMessage||ended)){
        try{await youtube.finish(session);}
        catch{errorMessage=errorMessage||'The encoder stopped, but YouTube did not confirm that the broadcast ended. Check the show in YouTube Studio.';}
      }
      if(generating)await generating.catch(()=>{});
      const saved=await call('finish',{error:errorMessage,replayPath:errorMessage?null:replayPath}).catch(()=>null);
      if(saved&&!errorMessage&&replayPath&&show.replay_path&&show.replay_path!==replayPath)await storage.from('korlix-live-studio').remove([show.replay_path]).catch(()=>{});
      if((!saved||errorMessage)&&replayPath)await storage.from('korlix-live-studio').remove([replayPath]).catch(()=>{});
      await rm(dir,{recursive:true,force:true});activeController=null;
    }
  }
  async function tick(){
    if(stopped||busy)return;busy=true;
    try{const show=await store.call(ownerId,'claim',null,{token:workerToken(),mode,...(workerId?{workerId}:{})});if(show?.id)await run(show);}
    catch(error){logger.warn?.('Live Studio worker unavailable',{code:error?.name||'unavailable'});}
    finally{busy=false;}
  }
  return {run,tick,start(){if(timer)return;timer=setInterval(()=>void tick(),pollMs);timer.unref?.();void tick();},
    stop(){stopped=true;clearInterval(timer);activeController?.abort(new LiveStudioError('The broadcast worker is restarting.',503));},get busy(){return busy;}};
}
