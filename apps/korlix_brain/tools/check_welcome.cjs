const assert=require('node:assert/strict');
const path=require('node:path');
const fs=require('node:fs');
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const url='file://'+path.resolve(__dirname,'../assets/web/index.html');

(async()=>{
  const browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage','--autoplay-policy=no-user-gesture-required']});
  try{
    async function pageFor(mode='normal'){
      const page=await browser.newPage({viewport:{width:390,height:900},reducedMotion:'reduce'});
      const errors=[],remote=[];
      page.on('pageerror',e=>errors.push(e.message));
      page.on('request',r=>{if(/^https?:/.test(r.url()))remote.push(r.url());});
      await page.addInitScript(mode=>{
        window.testAudioType='auto';window.testCommands=[];
        Object.defineProperty(navigator,'audioSession',{configurable:true,value:{
          get type(){return window.testAudioType;},set type(value){window.testAudioType=value;}
        }});
        const originalPlay=HTMLMediaElement.prototype.play;
        let first=true;
        HTMLMediaElement.prototype.play=function(){
          if(first&&mode==='blocked'){
            first=false;return Promise.reject(new DOMException('Tap required','NotAllowedError'));
          }
          if(first&&mode==='delayed'){
            first=false;return new Promise((resolve,reject)=>{window.testReleasePlay=()=>originalPlay.call(this).then(resolve,reject);});
          }
          return originalPlay.call(this);
        };
        window.Korlix={postMessage:raw=>{
          const m=JSON.parse(raw);
          window.testCommands.push({...m,audioType:window.testAudioType,welcomePaused:document.querySelector('audio').paused});
          const send=data=>window.KorlixBrainReceive(data);
          let result=null;
          if(m.action==='load')result={training:'',memories:[],canUndo:false};
          if(m.action==='listSavedTranscripts')result=[];
          if(m.action==='startVoice'){send({type:'voice',phase:'listening',message:'Rici is listening'});result={active:true};}
          if(m.action==='stopVoice')send({type:'voice',phase:'complete',message:'Microphone off'});
          if(m.action==='dictate')send({type:'dictationStatus',active:true,message:'Listening…'});
          setTimeout(()=>send({type:'reply',id:m.id,data:result}),0);
        }};
      },mode);
      await page.goto(url);
      await page.waitForFunction(()=>document.querySelector('#cinema-kb-account-status').textContent==='Account connected');
      return {page,errors,remote};
    }
    const {page,errors,remote}=await pageFor();
    const audio=page.locator('#cinema-kb-welcome-audio');
    const playing=()=>page.waitForFunction(()=>{const a=document.querySelector('audio');return !a.paused&&a.currentTime>0;});
    await playing();
    assert.equal(await page.evaluate(()=>window.testAudioType),'playback');
    assert.equal(await page.evaluate(()=>window.testCommands.some(c=>c.action==='startVoice'||c.action==='dictate')),false,'Welcome never opens the microphone');
    assert.equal(await audio.evaluate(a=>a.volume),.9,'Voice is separate from the soft music volume');
    const seconds=await audio.evaluate(a=>a.duration);assert(seconds>8&&seconds<30,'Bundled short clip is decodable');
    const skip=page.getByRole('button',{name:'Skip introduction',exact:true});
    assert((await skip.boundingBox()).height>=44);
    assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1),false);
    if(process.env.UI_SCREENSHOTS){
      fs.mkdirSync(process.env.UI_SCREENSHOTS,{recursive:true});
      await page.screenshot({path:path.join(process.env.UI_SCREENSHOTS,'brain-welcome-390.png'),fullPage:true});
    }
    await skip.click();assert.equal(await audio.evaluate(a=>a.paused),true);
    assert.equal(await page.evaluate(()=>window.testAudioType),'auto');
    await page.getByRole('button',{name:'Replay welcome',exact:true}).click();await playing();
    await page.getByRole('button',{name:/Talk to Rici/}).click();
    await page.waitForFunction(()=>window.testCommands.some(c=>c.action==='startVoice'));
    const start=await page.evaluate(()=>window.testCommands.find(c=>c.action==='startVoice'));
    assert(start.welcomePaused,'Stop the welcome before native microphone startup');assert.equal(start.audioType,'auto');
    await page.getByRole('button',{name:'Stop conversation',exact:true}).click();
    await page.getByRole('button',{name:'Home',exact:true}).click();
    assert.equal(await audio.evaluate(a=>a.paused),true,'Returning Home does not repeat the intro');
    await page.getByRole('button',{name:'Replay welcome',exact:true}).click();await playing();
    await page.evaluate(()=>window.KorlixBrainReceive({type:'appLifecycle',active:false}));
    assert.equal(await audio.evaluate(a=>a.paused),true,'Backgrounding stops the greeting');
    await page.evaluate(()=>window.KorlixBrainReceive({type:'appLifecycle',active:true}));
    assert.equal(await audio.evaluate(a=>a.paused),true,'Foregrounding does not repeat it');
    await page.getByRole('button',{name:'Replay welcome',exact:true}).click();await playing();
    await page.getByRole('button',{name:'Add Memory by voice example',exact:true}).click();
    const dictation=await page.evaluate(()=>window.testCommands.find(c=>c.action==='dictate'));
    assert(dictation.welcomePaused);assert.equal(dictation.audioType,'auto');
    await page.reload();
    await page.waitForFunction(()=>document.querySelector('#cinema-kb-account-status').textContent==='Account connected');
    assert.equal(await audio.evaluate(a=>a.paused),true,'First-use setting survives reload');
    await page.getByRole('button',{name:'Replay welcome',exact:true}).click();await playing();
    await audio.evaluate(a=>{a.currentTime=a.duration-.15;});
    await page.waitForFunction(()=>document.querySelector('.kb-product').dataset.welcome==='idle');
    assert.equal(await page.evaluate(()=>window.testAudioType),'auto','Natural ending releases playback category');
    await page.getByRole('button',{name:'Play ambient music',exact:true}).click();
    await page.waitForFunction(()=>document.querySelector('.kb-product').dataset.music==='playing');
    await page.getByRole('button',{name:'Replay welcome',exact:true}).click();await playing();
    assert.equal(await page.evaluate(()=>document.querySelector('.kb-product').dataset.music),'quiet','Music ducks for the welcome');
    await skip.click();
    await page.waitForFunction(()=>document.querySelector('.kb-product').dataset.music==='playing');
    await page.getByRole('button',{name:'Pause ambient music',exact:true}).click();
    assert.deepEqual(remote,[],'Welcome works entirely from bundled assets');assert.deepEqual(errors,[]);
    await page.close();

    const blocked=await pageFor('blocked');
    await blocked.page.getByText('Tap Play welcome to listen.',{exact:true}).waitFor();
    await blocked.page.getByRole('button',{name:'Play welcome',exact:true}).click();
    await blocked.page.waitForFunction(()=>!document.querySelector('audio').paused);
    await blocked.page.getByRole('button',{name:'Skip introduction',exact:true}).click();
    assert.deepEqual(blocked.errors,[]);await blocked.page.close();

    const delayed=await pageFor('delayed');
    await delayed.page.getByRole('button',{name:'Skip introduction',exact:true}).click();
    await delayed.page.evaluate(()=>window.testReleasePlay());
    await delayed.page.waitForFunction(()=>document.querySelector('audio').paused);
    assert.equal(await delayed.page.evaluate(()=>document.querySelector('.kb-product').dataset.welcome),'idle');
    assert.deepEqual(delayed.errors,[]);await delayed.page.close();
    console.log('PASS: local welcome decode; first-use autoplay; Skip/Replay; no microphone or network; background stop; native voice/dictation handoff; replay after reload; blocked and late playback; natural completion. Physical iPhone listening remains required.');
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});
