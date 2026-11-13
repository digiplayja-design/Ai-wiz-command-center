const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const app = path.resolve(__dirname,'..');

// Runs entirely in the page: querying, measuring and accepting a snapshot must
// share one browser turn. Native refreshes replace rows, so a later evaluateAll
// can measure different (or detached) nodes from those accepted by an earlier wait.
function stableSavedTargetGeometry(){
  return new Promise(resolve=>{
    let previousButtons=[],previousSignature='',stableFrames=0,generation=0,frame,timer,last;
    const history=[],started=performance.now();
    function finish(stable){
      clearTimeout(timer);cancelAnimationFrame(frame);
      resolve({stable,...last,history});
    }
    function sample(){
      const root=document.querySelector('.kb-product');
      const section=document.querySelector('section[data-screen="saved"]');
      const buttons=[...document.querySelectorAll('#cinema-kb-saved-transcripts [data-transcript-action]')];
      const sameNodes=buttons.length===previousButtons.length&&buttons.every((button,index)=>button===previousButtons[index]);
      if(!sameNodes)generation++;
      const ancestors=new Set();
      const targets=buttons.map(button=>{
        for(let node=button;node;node=node.parentElement)ancestors.add(node);
        const rect=button.getBoundingClientRect(),style=getComputedStyle(button);
        return {action:button.dataset.transcriptAction,connected:button.isConnected,
          x:rect.x,y:rect.y,width:rect.width,height:rect.height,offsetHeight:button.offsetHeight,
          cssHeight:style.height,minHeight:style.minHeight,display:style.display,visibility:style.visibility,
          transform:style.transform,scale:style.scale,translate:style.translate};
      });
      const animations=[...ancestors].flatMap(node=>node.getAnimations().filter(animation=>
        animation.pending||animation.playState==='running').map(animation=>({
          target:node.id||node.dataset.screen||node.tagName,playState:animation.playState,
          pending:animation.pending,currentTime:animation.currentTime})));
      const ready=root?.dataset.screen==='saved'&&section&&!section.hidden&&
        window.testPendingSavedLoads===0&&document.fonts.status==='loaded'&&
        window.matchMedia('(prefers-reduced-motion: reduce)').matches&&animations.length===0&&
        buttons.length===3&&targets.every(target=>target.connected&&target.height>=44&&target.width>0&&
          target.display!=='none'&&target.visibility==='visible');
      const signature=JSON.stringify(targets);
      stableFrames=ready?(sameNodes&&signature===previousSignature?stableFrames+1:1):0;
      last={screen:root?.dataset.screen,motion:root?.dataset.motion,motionOverride:root?.dataset.motionOverride,
        reducedMotion:window.matchMedia('(prefers-reduced-motion: reduce)').matches,fonts:document.fonts.status,
        pendingSavedLoads:window.testPendingSavedLoads,generation,stableFrames,targets,animations};
      history.push({elapsedMs:performance.now()-started,generation,stableFrames,
        heights:targets.map(target=>target.height),pendingSavedLoads:window.testPendingSavedLoads});
      if(history.length>6)history.shift();
      previousButtons=buttons;previousSignature=signature;
      if(stableFrames>=3)finish(true);
      else frame=requestAnimationFrame(sample);
    }
    timer=setTimeout(()=>finish(false),5000);
    frame=requestAnimationFrame(sample);
  });
}

(async()=>{
  const browser = await chromium.launch({headless:true,executablePath:process.env.BROWSER_EXECUTABLE_PATH||undefined,args:['--no-sandbox','--disable-dev-shm-usage']});
  const errors=[];
  for(const width of [320,390,768,1024]){
    const page=await browser.newPage({viewport:{width,height:width===1024?768:900},reducedMotion:'reduce'});
    page.on('pageerror',e=>errors.push(e.message));
    // Transcripts belong to the native store, outside the WebView lifetime.
    // Keep that fixture across reloads without relying on file: localStorage.
    const savedTranscripts=new Map();
    await page.exposeFunction('__testTranscriptStore',(action,payload={})=>{
      switch(action){
        case 'listSavedTranscripts':return Array.from(savedTranscripts.values()).reverse();
        case 'saveTranscript':{
          const message=payload.message;
          assert.equal(message?.id,payload.messageId,'Save must reference an existing transcript fixture');
          savedTranscripts.set(message.id,structuredClone(message));
          return savedTranscripts.get(message.id);
        }
        case 'deleteTranscript':return {deleted:savedTranscripts.delete(payload.messageId)};
        default:throw new Error('Unexpected transcript store action: '+action);
      }
    });
    await page.addInitScript(()=>{
      localStorage.setItem('korlix-brain-welcome-v1-seen','true');
      window.testAccount={training:'Use plain language.',memories:[],canUndo:false};
      window.testCommands=[];window.testFailSave=false;window.testHoldStop=false;
      window.testMessages={};
      window.testFailTranscript=false;window.testCancelDelete=false;window.testPendingSavedLoads=0;
      window.Korlix={postMessage:raw=>{
        const m=JSON.parse(raw);window.testCommands.push(m);
        const reply=(data,error)=>setTimeout(()=>{
          window.KorlixBrainReceive({type:'reply',id:m.id,data,error});
          if(m.action==='listSavedTranscripts')window.testPendingSavedLoads--;
        },0);
        const storedReply=payload=>window.__testTranscriptStore(m.action,payload).then(
          data=>reply(data),error=>reply(null,error.message));
        switch(m.action){
          case 'welcomeState':return reply({native:false,automatic:false,foreground:true});
          case 'load':return reply(window.testAccount);
          case 'listSavedTranscripts':window.testPendingSavedLoads++;return storedReply();
          case 'saveTranscript':
            if(window.testFailTranscript)return reply(null,'Device storage unavailable. Please retry.');
            return storedReply({messageId:m.payload.messageId,message:window.testMessages[m.payload.messageId]});
          case 'shareTranscript':return reply({shared:false});
          case 'deleteTranscript':
            if(window.testCancelDelete)return reply({deleted:false});
            if(window.testFailTranscript)return reply(null,'Device storage unavailable. Please retry.');
            return storedReply({messageId:m.payload.messageId});
          case 'saveMemory':
            if(window.testFailSave)return reply(null,'Connection interrupted. Refresh before retrying.');
            window.testAccount.memories.push({id:'m'+window.testAccount.memories.length,content:m.payload.text,source:m.payload.source});return reply(window.testAccount);
          case 'saveTraining':window.testAccount.training=m.payload.text;return reply(window.testAccount);
          case 'deleteMemory':window.testAccount.memories=window.testAccount.memories.filter(x=>x.id!==m.payload.key);return reply(window.testAccount);
          case 'startVoice':setTimeout(()=>window.KorlixBrainReceive({type:'voice',phase:'listening',message:'Rici is listening'}),0);return reply(null);
          case 'stopVoice':if(window.testHoldStop)return;setTimeout(()=>window.KorlixBrainReceive({type:'voice',phase:'complete',message:'Microphone off'}),0);return reply(null);
          case 'pickFile':return reply({text:'Document draft, not yet saved.',filename:'guide.txt'});
          default:return reply(null);
        }
      }};
    });
    await page.goto('file://'+path.join(app,'assets/web/index.html'));
    await page.waitForFunction(()=>document.querySelector('#cinema-kb-account-status')?.textContent==='Account connected');
    assert.equal(await page.locator('section[data-screen="home"]').isVisible(),true);
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1),false,'Horizontal overflow at '+width);
    assert.equal(await page.locator('#cinema-kb-music-volume').inputValue(),'1');
    assert.equal(await page.evaluate(()=>window.testCommands.some(c=>c.action==='startVoice')),false);
    if(process.env.UI_SCREENSHOTS){fs.mkdirSync(process.env.UI_SCREENSHOTS,{recursive:true});await page.screenshot({path:path.join(process.env.UI_SCREENSHOTS,'brain-home-'+width+'.png'),fullPage:true});}
    await page.locator('[data-go="memory"]').first().click();
    await page.locator('#cinema-kb-memory').fill('Only save after approval.');
    await page.locator('#cinema-kb-memory-form button[type="submit"]').click();
    assert.equal(await page.evaluate(()=>window.testCommands.filter(c=>c.action==='saveMemory').length),0);
    await page.locator('#cinema-kb-approve').click();
    await page.waitForFunction(()=>document.querySelector('section[data-screen="transfer"]').hidden===false);
    assert.equal(await page.locator('#cinema-kb-transfer-title').textContent(),'Memory saved');
    await page.locator('section[data-screen="transfer"] [data-go="brain"]').click();
    await page.waitForFunction(()=>document.querySelector('#cinema-kb-memory-list').textContent.includes('Only save after approval.'));
    await page.locator('#cinema-kb-memory-list').getByRole('button',{name:'Delete memory',exact:true}).click();
    assert.equal(await page.evaluate(()=>window.testCommands.filter(c=>c.action==='deleteMemory').length),0);
    await page.locator('#cinema-kb-confirm-delete').click();
    await page.waitForFunction(()=>window.testAccount.memories.length===0);
    await page.locator('section[data-screen="brain"] [data-go="memory"]').click();
    await page.locator('#cinema-kb-memory').fill('This must not claim to be saved.');
    await page.locator('#cinema-kb-memory-form button[type="submit"]').click();
    await page.evaluate(()=>window.testFailSave=true);
    await page.locator('#cinema-kb-approve').click();
    await page.waitForFunction(()=>document.querySelector('#cinema-kb-status').textContent.includes('interrupted'));
    assert.equal(await page.locator('section[data-screen="review"]').isVisible(),true);
    assert.equal(await page.evaluate(()=>window.testAccount.memories.length),0);
    await page.locator('#cinema-kb-cancel').click();
    await page.getByRole('button',{name:/Talk to Rici/}).click();
    await page.waitForFunction(()=>document.querySelector('#cinema-kb-voice-phase').textContent==='Rici is listening');
    await page.evaluate(()=>{
      const item={type:'transcript',id:'message-a',role:'rici',text:'<img src=x onerror="window.injected=true">',createdAt:'2026-11-01T03:00:00Z'};
      window.testMessages[item.id]=item;window.KorlixBrainReceive(item);
    });
    assert.equal(await page.locator('#cinema-kb-transcript img').count(),0,'Transcript must remain inert text');
    assert.equal(await page.locator('#cinema-kb-transcript').getByRole('button',{name:'Report response'}).count(),1);
    const row=page.locator('#cinema-kb-transcript [data-message-id="message-a"]');
    await page.evaluate(()=>window.testFailTranscript=true);
    await row.getByRole('button',{name:'Save',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('#cinema-kb-status').textContent.includes('storage unavailable'));
    assert.equal(await row.getByRole('button',{name:'Save',exact:true}).isEnabled(),true);
    assert.equal(savedTranscripts.size,0,'Failed save does not persist a transcript');
    await page.evaluate(()=>window.testFailTranscript=false);
    await row.getByRole('button',{name:'Save',exact:true}).click();
    await row.getByRole('button',{name:'Saved',exact:true}).waitFor();
    await row.getByRole('button',{name:'Share',exact:true}).click();
    assert.deepEqual(await page.evaluate(()=>window.testCommands.filter(c=>c.action==='shareTranscript').at(-1).payload),{messageId:'message-a'},'Only selected message ID crosses bridge');
    await page.locator('section[data-screen="talk"] [data-go="saved"]').click();
    await page.locator('section[data-screen="saved"]').waitFor({state:'visible'});
    assert.equal(await page.locator('#cinema-kb-saved-transcripts img').count(),0);
    assert.equal(await page.locator('#cinema-kb-saved-transcripts p').textContent(),'<img src=x onerror="window.injected=true">');
    assert.equal(await page.evaluate(()=>window.testCommands.filter(c=>c.action==='saveMemory').length),2,'Transcript Save never calls Brain save');
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1),false,'Saved view fits '+width);
    // Assert the exact snapshot that was stable, without a second DOM query.
    let geometry;
    try{
      geometry=await page.evaluate(stableSavedTargetGeometry);
      assert.equal(geometry.stable,true,'Stable saved transcript geometry at '+width);
      assert.equal(geometry.targets.length,3,'Three transcript actions at '+width);
      assert.deepEqual(geometry.targets.map(target=>target.action).sort(),['delete','save','share'],'Exact transcript actions at '+width);
      for(const target of geometry.targets)assert.ok(target.height>=44,
        'Accessible '+target.action+' target at '+width+': measured '+target.height+'px');
    }catch(error){
      console.log('Transcript geometry at '+width,JSON.stringify(geometry||{observationFailed:true}));
      if(process.env.UI_SCREENSHOTS)await page.screenshot({path:path.join(process.env.UI_SCREENSHOTS,'brain-saved-failure-'+width+'.png'),fullPage:true});
      throw error;
    }
    if(process.env.UI_SCREENSHOTS)await page.screenshot({path:path.join(process.env.UI_SCREENSHOTS,'brain-saved-'+width+'.png'),fullPage:true});
    await page.locator('#cinema-kb-saved-back').click();
    if(process.env.UI_SCREENSHOTS)await page.screenshot({path:path.join(process.env.UI_SCREENSHOTS,'brain-talk-'+width+'.png'),fullPage:true});
    const stop=page.getByRole('button',{name:'Stop conversation',exact:true});
    for(const phase of ['connecting','listening','thinking','speaking']){
      await page.evaluate(phase=>window.KorlixBrainReceive({type:'voice',phase,message:'Rici '+phase}),phase);
      assert.equal(await stop.isVisible(),true,'Stop stays visible during '+phase);
      for(const scroll of [0,10000]){
        await page.evaluate(y=>window.scrollTo(0,y),scroll);
        const bounds=await stop.boundingBox();
        assert.ok(bounds.height>=56,'Large stop target');
        assert.ok(bounds.y>=0&&bounds.y+bounds.height<=page.viewportSize().height,'Stop remains inside viewport');
      }
    }
    if(process.env.UI_SCREENSHOTS){
      await page.evaluate(()=>{document.querySelector('#cinema-kb-transcript p').textContent="I'm Rici. How can I help?";window.scrollTo(0,0);});
      await page.screenshot({path:path.join(process.env.UI_SCREENSHOTS,'brain-stop-'+width+'.png')});
    }
    await page.evaluate(()=>window.scrollTo(0,0));
    await page.locator('section[data-screen="talk"] [data-go="home"]').click();
    assert.equal(await page.locator('.kb-live-banner').isVisible(),true,'Voice controls remain available while navigating');
    await page.evaluate(()=>{
      window.testAccount={training:'Use plain language.',memories:[{id:'spoken',content:'Always use metric units.',source:'voice_confirmed',tags:['instruction']}],canUndo:false};
      window.KorlixBrainReceive({type:'brainSnapshot',snapshot:window.testAccount});
      window.KorlixBrainReceive({type:'voiceSaved',message:'Saved that instruction to your brain.'});
    });
    assert.equal(await page.locator('#cinema-kb-status').textContent(),'Saved that instruction to your brain.');
    await page.getByRole('button',{name:/My Brain/}).first().click();
    assert.equal(await page.locator('#cinema-kb-memory-list').textContent().then(t=>t.includes('Always use metric units.')),true);
    assert.equal(await page.locator('#cinema-kb-memory-list').textContent().then(t=>t.includes('Voice instruction')),true);
    assert.equal(await page.locator('section[data-screen="review"]').isVisible(),false,'Voice save must not require an approval screen');
    await page.evaluate(()=>window.testHoldStop=true);
    await page.locator('#cinema-kb-stop-voice').click();
    assert.equal(await page.locator('#cinema-kb-stop-label').textContent(),'Stopping…','Feedback precedes native acknowledgement');
    assert.equal(await page.locator('#cinema-kb-stop-voice').isDisabled(),true);
    await page.evaluate(()=>window.KorlixBrainReceive({type:'voice',phase:'speaking',message:'Late event'}));
    assert.equal(await page.locator('#cinema-kb-stop-label').textContent(),'Stopping…','Late audio event cannot restart UI');
    assert.equal(await page.evaluate(()=>window.testCommands.filter(c=>c.action==='stopVoice').length),1);
    await page.evaluate(()=>window.KorlixBrainReceive({type:'voice',phase:'complete',message:'Microphone off'}));
    await page.waitForFunction(()=>document.querySelector('.kb-product').dataset.voiceActive==='false');
    await page.locator('section[data-screen="brain"] [data-go="home"]').click();
    await page.getByRole('button',{name:/Talk to Rici/}).click();
    await page.waitForFunction(()=>document.querySelector('#cinema-kb-voice-phase').textContent==='Rici is listening');
    await page.evaluate(()=>{const old=window.testCommands.find(c=>c.action==='stopVoice');window.KorlixBrainReceive({type:'reply',id:old.id,error:'Old cleanup failed'});});
    assert.equal(await page.locator('#cinema-kb-stop-label').textContent(),'Stop','Old stop reply cannot alter the new session');
    await page.evaluate(()=>window.testHoldStop=false);
    await page.getByRole('button',{name:'Stop conversation',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('.kb-product').dataset.voiceActive==='false');
    await page.getByRole('radio',{name:/Deep Think/}).check();
    assert.equal(await page.locator('#cinema-kb-replay-demo').textContent(),'Start Deep Think','Inline restart identifies the selected mode');
    assert.equal(await page.locator('#cinema-kb-start-label').textContent(),'Start Deep Think','Persistent restart identifies the selected mode');
    await page.locator('#cinema-kb-replay-demo').click();
    await page.waitForFunction(()=>document.querySelector('#cinema-kb-voice-phase').textContent==='Rici is listening');
    assert.equal(await page.evaluate(()=>window.testCommands.filter(c=>c.action==='startVoice').at(-1).payload.mode),'deep');
    assert.equal(await page.getByRole('radio',{name:/Live Conversation/}).isDisabled(),true,'Mode is fixed during a conversation');
    assert.equal(await page.evaluate(()=>window.testCommands.find(c=>c.action==='startVoice').payload.mode),'live','Live is the default');
    await page.getByRole('button',{name:'Stop conversation',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('.kb-product').dataset.voiceActive==='false');
    const savedRow=page.locator('#cinema-kb-saved-transcripts [data-message-id="message-a"]');
    try{
      assert.equal(savedTranscripts.get('message-a')?.text,'<img src=x onerror="window.injected=true">','Save committed before reload');
      await page.reload();
      await page.waitForFunction(()=>document.querySelector('#cinema-kb-account-status')?.textContent==='Account connected');
      await page.getByRole('button',{name:/My Brain/}).first().click();
      await page.locator('section[data-screen="brain"] [data-go="saved"]').click();
      await page.locator('section[data-screen="saved"]').waitFor({state:'visible'});
      await savedRow.waitFor();
      assert.equal(await savedRow.locator('p').textContent(),'<img src=x onerror="window.injected=true">','Saved text survives reload');
    }catch(error){
      const state=await page.evaluate(()=>({
        screen:document.querySelector('.kb-product')?.dataset.screen,
        account:document.querySelector('#cinema-kb-account-status')?.textContent,
        status:document.querySelector('#cinema-kb-status')?.textContent,
        pendingSavedLoads:window.testPendingSavedLoads,
        rows:[...document.querySelectorAll('#cinema-kb-saved-transcripts [data-message-id]')].map(row=>({id:row.dataset.messageId,height:row.getBoundingClientRect().height})),
        commands:(window.testCommands||[]).map(command=>({id:command.id,action:command.action,messageId:command.payload?.messageId}))
      })).catch(failure=>({inspectionError:failure.message}));
      console.error('Saved transcript reload failure',JSON.stringify({width,savedIds:[...savedTranscripts.keys()],pageErrors:errors,state}));
      const directory=process.env.UI_SCREENSHOTS||process.env.PROJECTION_SCREENSHOTS;
      if(directory){
        fs.mkdirSync(directory,{recursive:true});
        await page.screenshot({path:path.join(directory,'brain-saved-reload-failure-'+width+'.png'),fullPage:true}).catch(()=>{});
      }
      throw error;
    }
    await page.evaluate(()=>window.testCancelDelete=true);
    await savedRow.getByRole('button',{name:'Delete',exact:true}).click();
    await page.waitForFunction(()=>!document.querySelector('#cinema-kb-saved-transcripts [data-transcript-action="delete"]').disabled);
    assert.equal(await savedRow.count(),1,'Cancel retains saved message');
    assert.equal(savedTranscripts.has('message-a'),true,'Canceled delete retains the native store record');
    await page.evaluate(()=>{window.testCancelDelete=false;window.testFailTranscript=true;});
    await savedRow.getByRole('button',{name:'Delete',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('#cinema-kb-status').textContent.includes('storage unavailable'));
    assert.equal(await savedRow.count(),1,'Failed delete remains visible');
    assert.equal(savedTranscripts.has('message-a'),true,'Failed delete retains the native store record');
    await page.evaluate(()=>window.testFailTranscript=false);
    await savedRow.getByRole('button',{name:'Delete',exact:true}).click();
    await savedRow.waitFor({state:'detached'});
    assert.equal(savedTranscripts.size,0,'Successful delete removes the native store record');
    await page.locator('#cinema-kb-saved-back').click();
    assert.equal(await page.evaluate(()=>window.testCommands.some(c=>c.action==='startVoice')),false,'Reading saved messages never starts a charged conversation');
    await page.close();
  }
  assert.deepEqual(errors,[]);
  await browser.close();
  console.log('PASS: four viewport layouts; approval gates; failure handling; exact deletion; live voice navigation; persistent Stop; transcript Save/Share/Delete; saved reload; canceled/failed deletion; 44px actions; inert transcript text; response reporting.');
})().catch(e=>{console.error(e);process.exit(1);});
