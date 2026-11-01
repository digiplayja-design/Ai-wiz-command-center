const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const app = path.resolve(__dirname,'..');

(async()=>{
  const browser = await chromium.launch({headless:true,executablePath:process.env.BROWSER_EXECUTABLE_PATH||undefined,args:['--no-sandbox','--disable-dev-shm-usage']});
  const errors=[];
  for(const width of [320,390,768,1024]){
    const page=await browser.newPage({viewport:{width,height:width===1024?768:900},reducedMotion:'reduce'});
    page.on('pageerror',e=>errors.push(e.message));
    await page.addInitScript(()=>{
      window.testAccount={training:'Use plain language.',memories:[],canUndo:false};
      window.testCommands=[];window.testFailSave=false;window.testHoldStop=false;
      window.testMessages={};window.testSaved=JSON.parse(localStorage.getItem('testSavedMessages')||'{}');
      window.testFailTranscript=false;window.testCancelDelete=false;
      window.Korlix={postMessage:raw=>{
        const m=JSON.parse(raw);window.testCommands.push(m);
        const reply=(data,error)=>setTimeout(()=>window.KorlixBrainReceive({type:'reply',id:m.id,data,error}),0);
        switch(m.action){
          case 'load':return reply(window.testAccount);
          case 'listSavedTranscripts':return reply(Object.values(window.testSaved).reverse());
          case 'saveTranscript':
            if(window.testFailTranscript)return reply(null,'Device storage unavailable. Please retry.');
            window.testSaved[m.payload.messageId]=window.testMessages[m.payload.messageId];localStorage.setItem('testSavedMessages',JSON.stringify(window.testSaved));return reply(window.testSaved[m.payload.messageId]);
          case 'shareTranscript':return reply({shared:false});
          case 'deleteTranscript':
            if(window.testCancelDelete)return reply({deleted:false});
            if(window.testFailTranscript)return reply(null,'Device storage unavailable. Please retry.');
            delete window.testSaved[m.payload.messageId];localStorage.setItem('testSavedMessages',JSON.stringify(window.testSaved));return reply({deleted:true});
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
    // A native refresh replaces rows; wait for their final visible geometry.
    try{
      await page.waitForFunction(()=>{
        const buttons=[...document.querySelectorAll('#cinema-kb-saved-transcripts [data-transcript-action]')];
        return buttons.length===3&&buttons.every(button=>button.getBoundingClientRect().height>=44);
      },null,{timeout:5000});
    }catch(error){
      console.log('Transcript geometry at '+width,await page.evaluate(()=>({screen:document.querySelector('.kb-product').dataset.screen,motion:document.querySelector('.kb-product').dataset.motion,targets:[...document.querySelectorAll('#cinema-kb-saved-transcripts [data-transcript-action]')].map(button=>({action:button.dataset.transcriptAction,height:button.getBoundingClientRect().height,minHeight:getComputedStyle(button).minHeight,display:getComputedStyle(button).display}))})));
      if(process.env.UI_SCREENSHOTS)await page.screenshot({path:path.join(process.env.UI_SCREENSHOTS,'brain-saved-failure-'+width+'.png'),fullPage:true});
      throw error;
    }
    const actionSizes=await page.locator('#cinema-kb-saved-transcripts [data-transcript-action]').evaluateAll(buttons=>buttons.map(button=>({action:button.dataset.transcriptAction,height:button.getBoundingClientRect().height})));
    assert.equal(actionSizes.length,3,'Three transcript actions at '+width);
    for(const target of actionSizes)assert.ok(target.height>=44,'Accessible '+target.action+' target at '+width);
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
    assert.equal(await page.locator('#cinema-kb-stop-label').textContent(),'Stop conversation','Old stop reply cannot alter the new session');
    await page.evaluate(()=>window.testHoldStop=false);
    await page.getByRole('button',{name:'Stop conversation',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('.kb-product').dataset.voiceActive==='false');
    await page.getByRole('radio',{name:/Deep Think/}).check();
    await page.getByRole('button',{name:'Start conversation',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('#cinema-kb-voice-phase').textContent==='Rici is listening');
    assert.equal(await page.evaluate(()=>window.testCommands.filter(c=>c.action==='startVoice').at(-1).payload.mode),'deep');
    assert.equal(await page.getByRole('radio',{name:/Live Conversation/}).isDisabled(),true,'Mode is fixed during a conversation');
    assert.equal(await page.evaluate(()=>window.testCommands.find(c=>c.action==='startVoice').payload.mode),'live','Live is the default');
    await page.getByRole('button',{name:'Stop conversation',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('.kb-product').dataset.voiceActive==='false');
    await page.reload();
    await page.waitForFunction(()=>document.querySelector('#cinema-kb-account-status')?.textContent==='Account connected');
    await page.getByRole('button',{name:/My Brain/}).first().click();
    await page.locator('section[data-screen="brain"] [data-go="saved"]').click();
    await page.locator('section[data-screen="saved"]').waitFor({state:'visible'});
    const savedRow=page.locator('#cinema-kb-saved-transcripts [data-message-id="message-a"]');
    await savedRow.waitFor();
    assert.equal(await savedRow.locator('p').textContent(),'<img src=x onerror="window.injected=true">','Saved text survives reload');
    await page.evaluate(()=>window.testCancelDelete=true);
    await savedRow.getByRole('button',{name:'Delete',exact:true}).click();
    await page.waitForFunction(()=>!document.querySelector('#cinema-kb-saved-transcripts [data-transcript-action="delete"]').disabled);
    assert.equal(await savedRow.count(),1,'Cancel retains saved message');
    await page.evaluate(()=>{window.testCancelDelete=false;window.testFailTranscript=true;});
    await savedRow.getByRole('button',{name:'Delete',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('#cinema-kb-status').textContent.includes('storage unavailable'));
    assert.equal(await savedRow.count(),1,'Failed delete remains visible');
    await page.evaluate(()=>window.testFailTranscript=false);
    await savedRow.getByRole('button',{name:'Delete',exact:true}).click();
    await savedRow.waitFor({state:'detached'});
    assert.deepEqual(await page.evaluate(()=>JSON.parse(localStorage.getItem('testSavedMessages'))),{});
    await page.locator('#cinema-kb-saved-back').click();
    assert.equal(await page.evaluate(()=>window.testCommands.some(c=>c.action==='startVoice')),false,'Reading saved messages never starts a charged conversation');
    await page.close();
  }
  assert.deepEqual(errors,[]);
  await browser.close();
  console.log('PASS: four viewport layouts; approval gates; failure handling; exact deletion; live voice navigation; persistent Stop; transcript Save/Share/Delete; saved reload; canceled/failed deletion; 44px actions; inert transcript text; response reporting.');
})().catch(e=>{console.error(e);process.exit(1);});
