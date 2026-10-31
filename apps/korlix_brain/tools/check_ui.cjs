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
      window.testCommands=[];window.testFailSave=false;
      window.Korlix={postMessage:raw=>{
        const m=JSON.parse(raw);window.testCommands.push(m);
        const reply=(data,error)=>setTimeout(()=>window.KorlixBrainReceive({type:'reply',id:m.id,data,error}),0);
        switch(m.action){
          case 'load':return reply(window.testAccount);
          case 'saveMemory':
            if(window.testFailSave)return reply(null,'Connection interrupted. Refresh before retrying.');
            window.testAccount.memories.push({id:'m'+window.testAccount.memories.length,content:m.payload.text,source:m.payload.source});return reply(window.testAccount);
          case 'saveTraining':window.testAccount.training=m.payload.text;return reply(window.testAccount);
          case 'deleteMemory':window.testAccount.memories=window.testAccount.memories.filter(x=>x.id!==m.payload.key);return reply(window.testAccount);
          case 'startVoice':setTimeout(()=>window.KorlixBrainReceive({type:'voice',phase:'listening',message:'Rici is listening'}),0);return reply(null);
          case 'stopVoice':setTimeout(()=>window.KorlixBrainReceive({type:'voice',phase:'complete',message:'Microphone off'}),0);return reply(null);
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
    await page.evaluate(()=>window.KorlixBrainReceive({type:'transcript',role:'rici',text:'<img src=x onerror="window.injected=true">'}));
    assert.equal(await page.locator('#cinema-kb-transcript img').count(),0,'Transcript must remain inert text');
    assert.equal(await page.locator('#cinema-kb-transcript').getByRole('button',{name:'Report response'}).count(),1);
    if(process.env.UI_SCREENSHOTS)await page.screenshot({path:path.join(process.env.UI_SCREENSHOTS,'brain-talk-'+width+'.png'),fullPage:true});
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
    await page.locator('#cinema-kb-stop-voice').click();
    await page.waitForFunction(()=>document.querySelector('.kb-product').dataset.voiceActive==='false');
    await page.close();
  }
  assert.deepEqual(errors,[]);
  await browser.close();
  console.log('PASS: four viewport layouts; approval gates; server failure; exact deletion; live voice navigation; inert transcripts; response reporting.');
})().catch(e=>{console.error(e);process.exit(1);});
