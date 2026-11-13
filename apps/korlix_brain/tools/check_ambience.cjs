const assert = require('node:assert/strict');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');

async function observeSavedVolume(page){
  return page.evaluate(()=>{
    let savedVolume;
    try{savedVolume=localStorage.getItem('korlix-brain-ambience-volume');}
    catch(error){savedVolume={unavailable:error.name};}
    return {
      savedVolume,
      sliderValue:document.querySelector('#cinema-kb-music-volume')?.value??null,
      displayedVolume:document.querySelector('#cinema-kb-music-volume-value')?.textContent??null,
      activeElement:document.activeElement?.id||document.activeElement?.tagName||null,
      readyState:document.readyState,
      visibilityState:document.visibilityState,
      hasFocus:document.hasFocus()
    };
  });
}

(async()=>{
  const browser=await chromium.launch({headless:true,args:['--no-sandbox','--disable-dev-shm-usage']});
  try{
    // Exercise real decoding and AudioContext transitions. Model the optional
    // iOS category API; audible output in Silent Mode still needs an iPhone.
    for(const supported of [true,false]){
      const page=await browser.newPage({viewport:{width:390,height:900},reducedMotion:'reduce'});
      const errors=[];page.on('pageerror',error=>errors.push(error.message));
      await page.addInitScript(supported=>{
        localStorage.setItem('korlix-brain-welcome-v1-seen','true');
        window.testAudioType='auto';window.testCommands=[];
        Object.defineProperty(navigator,'audioSession',{configurable:true,value:supported?{
          get type(){return window.testAudioType;},
          set type(value){window.testAudioType=value;}
        }:undefined});
        const Original=window.AudioContext||window.webkitAudioContext;
        window.AudioContext=class extends Original{
          constructor(...args){super(...args);window.testMusicContext=this;}
        };
        window.Korlix={postMessage:raw=>{
          const m=JSON.parse(raw);window.testCommands.push({...m,audioType:window.testAudioType});
          const send=data=>window.KorlixBrainReceive(data);
          let result=null;
          if(m.action==='welcomeState')result={native:false,automatic:false,foreground:true};
          if(m.action==='load')result={training:'',memories:[],canUndo:false};
          if(m.action==='listSavedTranscripts')result=[];
          if(m.action==='startVoice'){send({type:'voice',phase:'listening',message:'Rici is listening'});result={active:true};}
          if(m.action==='stopVoice')send({type:'voice',phase:'complete',message:'Microphone off'});
          if(m.action==='dictate')send({type:'dictationStatus',active:true,message:'Listening…'});
          setTimeout(()=>send({type:'reply',id:m.id,data:result}),0);
        }};
      },supported);
      await page.goto('file://'+path.resolve(__dirname,'../assets/web/index.html'));
      await page.waitForFunction(()=>document.querySelector('#cinema-kb-account-status').textContent==='Account connected');
      const play=page.locator('#cinema-kb-music-toggle');
      assert.equal(await page.evaluate(()=>window.testMusicContext===undefined),true,'No audio starts without a tap');
      await play.click();
      await page.waitForFunction(()=>document.querySelector('.kb-product').dataset.music==='playing'&&window.testMusicContext.state==='running');
      assert.equal(await page.evaluate(()=>window.testAudioType),supported?'playback':'auto','Playback category when supported');
      assert.equal(await page.evaluate(()=>window.testCommands.some(c=>c.action==='startVoice'||c.action==='dictate')),false,'Music never opens a microphone');
      await page.locator('#cinema-kb-music-settings').click();
      await page.locator('#cinema-kb-music-volume').evaluate(el=>{el.value='8';el.dispatchEvent(new Event('input',{bubbles:true}));});
      await page.getByRole('button',{name:/Talk to Rici/}).click();
      await page.waitForFunction(()=>window.testMusicContext.state==='suspended');
      assert.equal(await page.evaluate(()=>window.testCommands.find(c=>c.action==='startVoice').audioType),'auto','Release playback override before native voice starts');
      assert.equal(await page.evaluate(()=>document.querySelector('.kb-product').dataset.music),'quiet');
      await play.click(); // Turn the wanted bed off, then try enabling during a call.
      await play.click();
      assert.equal(await page.evaluate(()=>window.testAudioType),'auto','Music controls cannot replace the voice session');
      assert.equal(await page.evaluate(()=>window.testMusicContext.state),'suspended');
      await page.getByRole('button',{name:'Stop conversation',exact:true}).click();
      await page.getByRole('button',{name:'Home',exact:true}).click();
      await page.waitForFunction(()=>document.querySelector('.kb-product').dataset.music==='playing'&&window.testMusicContext.state==='running');
      assert.equal(await page.evaluate(()=>window.testAudioType),supported?'playback':'auto','Resume on Home after Stop');
      await page.getByRole('button',{name:'Add Memory by voice example',exact:true}).click();
      await page.waitForFunction(()=>window.testMusicContext.state==='suspended');
      assert.equal(await page.evaluate(()=>window.testCommands.find(c=>c.action==='dictate').audioType),'auto','Release playback override before native dictation');
      await page.evaluate(()=>window.KorlixBrainReceive({type:'dictationStatus',active:false,message:'Dictation stopped.'}));
      await page.getByRole('button',{name:'Home',exact:true}).click();
      await page.waitForFunction(()=>document.querySelector('.kb-product').dataset.music==='playing');
      await play.click();
      assert.equal(await page.evaluate(()=>window.testAudioType),'auto','Stop releases media category');
      const volumeBeforeReload=await observeSavedVolume(page);
      await page.reload();
      try{
        await page.waitForFunction(()=>document.querySelector('#cinema-kb-music-volume').value==='8');
      }catch(error){
        const volumeAfterReload=await observeSavedVolume(page).catch(()=>({unavailable:true}));
        console.error('Ambience saved-volume reload diagnostic:',JSON.stringify({
          audioSessionSupported:supported,beforeReload:volumeBeforeReload,afterReload:volumeAfterReload
        }));
        throw error;
      }
      assert.equal(await page.evaluate(()=>window.testMusicContext===undefined),true,'Remember volume without autoplay');
      assert.deepEqual(errors,[]);
      await page.close();
    }
    console.log('PASS: ambience playback category; real MP3 decode; native voice/dictation handoff; no microphone from music; pause/resume; saved volume; optional-API fallback. iPhone audible check remains required.');
  }finally{await browser.close();}
})().catch(error=>{console.error(error);process.exit(1);});
