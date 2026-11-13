const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const app = path.resolve(__dirname,'..');
const screenDirectory = process.env.PROJECTION_SCREENSHOTS;

async function fixture(page,{connect=true}={}) {
  await page.addInitScript(({connect}) => {
    // Playwright also evaluates init scripts in child frames. Only the bundled
    // top-level shell receives the native workspace fixture and session nonce.
    if(window !== window.top)return;
    window.projectionCommands = [];
    window.projectionTimeouts = [];
    const browserSetTimeout=window.setTimeout.bind(window);
    let lastScheduledTimeout=0;
    window.setTimeout=(callback,delay,...args)=>{lastScheduledTimeout=delay;return browserSetTimeout(callback,delay,...args);};
    window.testFailSave = false;
    window.testSaveResponse = 'success';
    window.testResearchCalls = 0;
    window.testHoldStart = false;
    window.testHoldPause = false;
    window.testHoldResume = false;
    window.testHoldStop = false;
    window.testGeocodingProvider = 'Test geocoder';
    window.projectionState = {
      open:true,foreground:true,room:'command',loading:false,selectedPlace:null,candidates:[],answer:null,notice:'',
      camera:{sequence:0,operation:'reset',viewMode:'street'},
      config:{rendererUrl:null,mapAvailable:false,geocodingAvailable:true,directionsAvailable:true,answersAvailable:true,answerCredits:4,answerCostLabel:'4 credits per successful sourced lookup.'},
      voice:{active:false,paused:false,phase:'complete',message:'Ready when you are'}
    };
    window.sendSnapshot = () => window.KorlixProjectionReceive({type:'snapshot',state:window.projectionState});
    window.Projection = {postMessage:raw => {
      const command = JSON.parse(raw); window.projectionCommands.push(command);
      window.projectionTimeouts.push({action:command.action,timeout:lastScheduledTimeout});
      const reply = (data,error) => setTimeout(() => window.KorlixProjectionReceive({type:'reply',id:command.id,data,error}),0);
      const state = window.projectionState;
      switch(command.action) {
        case 'room': state.room=command.payload.room; window.sendSnapshot(); return reply({room:state.room});
        case 'search':
          state.candidates = [
            {id:'fixture-a',label:'First destination candidate',address:'A location fixture for UI testing',userQuery:command.payload.query,latitude:40.71,longitude:-74,provider:window.testGeocodingProvider},
            {id:'fixture-b',label:'Second destination candidate',address:'A different location fixture for UI testing',userQuery:command.payload.query,latitude:40.72,longitude:-73.98,provider:window.testGeocodingProvider,partialMatch:true}
          ];
          state.notice='Choose a matching destination to confirm.'; window.sendSnapshot(); return reply({requiresConfirmation:true});
        case 'select':
          state.selectedPlace=state.candidates.find(place=>place.id===command.payload.placeId); state.candidates=[]; state.answer=null;
          state.camera={sequence:state.camera.sequence+1,operation:'flyTo',viewMode:'street',latitude:state.selectedPlace.latitude,longitude:state.selectedPlace.longitude,height:800};
          state.notice='Destination confirmed.'; window.sendSnapshot(); return reply({selected:true});
        case 'ask':
          if(/\b(live|real[ -]?time)\b.*\b(view|camera|feed|video|imagery)\b/i.test(command.payload.question)){
            state.answer={text:'There is no connected, permitted live camera for this place. Earth imagery is recorded, not a live feed.',sources:[],isLive:false};
            window.sendSnapshot();return reply({isLive:false,local:true});
          }
          window.testResearchCalls++;
          state.answer={text:'This is a sourced response fixture, not a claim about a real place. [1]',scope:'Confirmed destination',date:'2026-11-07',sources:[{title:'Test source',url:'https://example.com/source',date:'2026-11-07'}]};
          window.sendSnapshot(); return reply({answered:true});
        case 'camera': {
          const mode = ['streetView','earthView'].includes(command.payload.operation);
          state.camera={...state.camera,sequence:state.camera.sequence+1,
            operation:mode?'flyTo':command.payload.operation,
            viewMode:mode?(command.payload.operation==='earthView'?'earth':'street'):state.camera.viewMode};
          window.sendSnapshot(); return reply({moved:true});
        }
        case 'directions': return reply({ok:true,answer:'Review the full address and choose a maps app for directions.'});
        case 'savePlace':
          if(window.testFailSave)return reply(null,'Storage is unavailable. Your note has not been saved.');
          if(window.testSaveResponse==='null')return reply(null);
          if(window.testSaveResponse==='undefined')return reply(undefined);
          if(window.testSaveResponse==='missing')return reply({ok:true});
          if(window.testSaveResponse==='false')return reply({saved:false});
          return reply({saved:true});
        case 'startVoice':
          if(window.testHoldStart)return;
          state.voice={active:true,paused:false,phase:'listening',message:'Rici is listening'}; window.sendSnapshot(); return reply({active:true,paused:false});
        case 'pauseVoice':
          state.voice={active:true,paused:false,phase:'pausing',message:'Pausing conversation'}; window.sendSnapshot();
          if(window.testHoldPause)return;
          state.voice={active:false,paused:true,phase:'paused',message:'Conversation paused'}; window.sendSnapshot(); return reply({active:false,paused:true});
        case 'resumeVoice':
          state.voice={active:true,paused:false,phase:'connecting',message:'Connecting to Rici'}; window.sendSnapshot();
          if(window.testHoldResume)return;
          state.voice={active:true,paused:false,phase:'listening',message:'Rici is listening'}; window.sendSnapshot(); return reply({active:true,paused:false});
        case 'stopVoice':
          if(window.testHoldStop)return;
          state.voice={active:false,paused:false,phase:'complete',message:'Microphone off'}; window.sendSnapshot(); return reply({active:false,paused:false});
        default:return reply({ok:true});
      }
    }};
    document.addEventListener('DOMContentLoaded',()=>{
      if(connect)window.KorlixProjectionConnect({nonce:'test-session-nonce-123456789',snapshot:window.projectionState});
    });
  },{connect});
  await page.goto('file://' + path.join(app,'assets/web/projection.html'));
  if(connect)await page.waitForFunction(()=>document.querySelector('#connection-label').textContent==='Your KORLIX workspace');
}

async function settleLayout(page) {
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
}

async function routeProjectionRenderer(page) {
  await page.route('https://projection.test/brain-projection/earth.html',route=>route.fulfill({contentType:'text/html; charset=utf-8',body:`<!doctype html><html><head><meta charset="utf-8"><style>
    html,body{height:100%;margin:0;overflow:hidden;background:#142135;color:white;font:11px/1.5 system-ui}
    body{background:linear-gradient(140deg,#1b3245,#0c1729)}
    .provider-label{position:absolute;top:8px;left:8px;padding:6px;background:#031019}
    .provider-controls{position:absolute;top:8px;right:8px;display:flex;gap:4px}
    .provider-controls button{color:white;background:#273d50;border:1px solid #7191a3;padding:5px}
    #provider-attribution{position:absolute;left:0;right:0;bottom:0;padding:8px;background:#030b13;overflow-wrap:anywhere}a{color:#b3e1ff}
    </style></head><body><span class="provider-label">Provider surface fixture</span><div class="provider-controls"><button>Map control</button></div><div id="provider-attribution">Google Maps · Synthetic imagery supplied by Example City Survey Office; Example Regional Mapping Group; Example Geospatial Imagery Cooperative; Example Municipal Cartography Archive. Attribution fixture only; no real imagery is requested. <a id="provider-terms" href="https://provider-links.test/terms" target="_blank">Provider link fixture</a></div><script>
    window.received=[];window.addEventListener('message',e=>window.received.push(e.data));
    window.emitTransport=()=>parent.postMessage({type:'korlix-projection-transport-ready'},'*');
    window.emitStatus=(status,extra={})=>{document.body.dataset.phase=status;const camera=window.received.at(-1)?.camera;parent.postMessage({type:'korlix-projection-status',status,...(camera?{sequence:camera.sequence,viewMode:camera.viewMode}:{}),...extra},'*');};
    window.emitCreditHeight=height=>parent.postMessage({type:'korlix-projection-credits',height},'*');
    window.emitStatus('loading');
    </script></body></html>`}));
}

async function connectEntry(page,nonce,patch={}) {
  await page.evaluate(({nonce,patch})=>{
    Object.assign(window.projectionState,patch);
    window.KorlixProjectionConnect({nonce,snapshot:window.projectionState});
  },{nonce,patch});
}

async function assertEntryState(page,phase,active,motion='full') {
  assert.deepEqual(await page.evaluate(()=>({
    phase:document.body.dataset.entryState,active:document.body.dataset.entryActive,
    motion:document.body.dataset.entryMotion,skip:!document.getElementById('projection-entry-skip').hidden
  })),{phase,active:String(active),motion,skip:active&&motion==='full'});
}

async function entryControlPoint(page,selector) {
  const point=await page.locator(selector).evaluate(element=>{
    const box=element.getBoundingClientRect(),x=box.x+box.width/2,y=box.y+box.height/2;
    const hit=document.elementFromPoint(x,y);
    return {x,y,visible:box.width>0&&box.height>0&&box.top>=0&&box.bottom<=innerHeight,
      hittable:hit===element||element.contains(hit),disabled:element.disabled===true};
  });
  assert.ok(point.visible&&point.hittable&&!point.disabled,'Entrance leaves control usable: '+selector+' '+JSON.stringify(point));
  return {x:point.x,y:point.y};
}

async function changeEntryMotionPreference(page,preference) {
  // Media-query notifications come from the browser's real rendering cycle,
  // not the mocked JS clock. Observe that event before checking app cleanup.
  const wasReduced=await page.evaluate(()=>{
    const query=window.matchMedia('(prefers-reduced-motion: reduce)');
    window.entryMotionChanged=new Promise(resolve=>query.addEventListener('change',event=>resolve(event.matches),{once:true}));
    return query.matches;
  });
  assert.notEqual(wasReduced,preference==='reduce','This case must change the real media preference');
  await page.emulateMedia({reducedMotion:preference});
  let timer;
  try {
    const reduced=await Promise.race([
      page.evaluate(()=>window.entryMotionChanged),
      new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('Motion preference change event was not delivered')),2000);})
    ]);
    assert.equal(reduced,preference==='reduce');
  } finally {clearTimeout(timer);}
}

async function assertEntryLifecycle(browser,errors) {
  const page=await browser.newPage({viewport:{width:390,height:844},reducedMotion:'no-preference'});
  page.on('pageerror',error=>errors.push(error.message));
  // Only lifecycle assertions use a controlled clock. Visual evidence below
  // uses real time because CSS animation timelines are independent of this clock.
  await page.clock.install({time:new Date('2026-11-13T00:00:00Z')});
  await fixture(page,{connect:false});
  await page.clock.pauseAt(new Date('2026-11-13T00:01:00Z'));
  assert.equal(await page.locator('body').getAttribute('data-entry-active'),'false','No entrance before the native bridge connects');
  assert.equal(await page.locator('#projection-entry-skip').isVisible(),false);
  await connectEntry(page,'');
  assert.equal(await page.locator('body').getAttribute('data-entry-active'),'false','An invalid connection cannot start the entrance');
  await connectEntry(page,'entry-first-session');
  let elapsed=0;
  const advanceTo=async target=>{await page.clock.runFor(target-elapsed);elapsed=target;};
  await assertEntryState(page,'awaken',true);
  assert.equal(await page.evaluate(()=>window.projectionCommands.length),0,'Entrance does not start voice or issue camera commands');
  await advanceTo(32);
  await entryControlPoint(page,'#close-projection');
  const start=await entryControlPoint(page,'#talk-button');
  await page.mouse.click(start.x,start.y);
  assert.equal(await page.evaluate(()=>window.projectionCommands.at(-1).action),'startVoice','Voice starts before arrival');
  await advanceTo(33);
  await entryControlPoint(page,'#stop-button');

  const query='21 Oak Street, Apt 4B, Example City';
  await page.evaluate(query=>{
    const state=window.projectionState;
    state.destinationSearch={sequence:1,query,active:true,source:'voice'};
    window.sendSnapshot();
  },query);
  assert.equal(await page.locator('#destination-input').inputValue(),query);
  assert.equal(await page.locator('#search-button span').textContent(),'Finding…');
  assert.equal(await page.evaluate(()=>window.projectionCommands.some(command=>command.action==='search')),false,'Entrance does not duplicate the native voice search');
  await page.evaluate(query=>{
    const state=window.projectionState;
    state.destinationSearch.active=false;
    state.candidates=[{id:'entry-place',label:'Spoken entrance match',address:query,userQuery:query,latitude:40.71,longitude:-74,provider:'Test'}];
    window.sendSnapshot();
  },query);
  await advanceTo(65);
  assert.notEqual(await page.evaluate(()=>document.activeElement?.id),'destination-input','Voice results do not open the keyboard');
  const candidate=await entryControlPoint(page,'.candidate-button');
  assert.equal(await page.evaluate(()=>window.projectionCommands.some(command=>command.action==='select')),false,'Destination still requires confirmation');
  await page.mouse.click(candidate.x,candidate.y);
  await advanceTo(66);
  assert.equal(await page.locator('#place-label').textContent(),'Spoken entrance match');
  await page.evaluate(()=>{
    window.projectionState.destinationSearch={sequence:2,query:'32 Pine Avenue, Example City',active:true,source:'voice'};
    window.sendSnapshot();
  });
  assert.equal(await page.locator('#destination-input').inputValue(),'32 Pine Avenue, Example City','Next address arrives without replaying the entrance');
  const stop=await entryControlPoint(page,'#stop-button');
  await page.mouse.click(stop.x,stop.y);
  assert.equal(await page.evaluate(()=>window.projectionCommands.at(-1).action),'stopVoice','Stop dispatches during Awaken');
  await advanceTo(67);
  await assertEntryState(page,'awaken',true);
  await advanceTo(499);
  await assertEntryState(page,'awaken',true);
  await advanceTo(500);
  await assertEntryState(page,'enter',true);
  await connectEntry(page,'entry-first-session');
  await page.evaluate(()=>{
    window.projectionState.room='discovery';window.sendSnapshot();
    window.KorlixProjectionReceive({type:'voice',active:false,phase:'complete',message:'Microphone off'});
    window.KorlixProjectionReceive({type:'transcript',role:'user',text:'A continuing conversation'});
  });
  await page.locator('#destination-input').focus();
  await advanceTo(1499);
  await assertEntryState(page,'enter',true);
  await advanceTo(1500);
  await assertEntryState(page,'arrive',true);
  await advanceTo(2000);
  await assertEntryState(page,'complete',false);
  assert.equal(await page.evaluate(()=>document.activeElement?.id),'destination-input','Automatic arrival preserves input focus');
  await connectEntry(page,'entry-first-session');
  await assertEntryState(page,'complete',false);

  await page.evaluate(()=>document.querySelector('.projection-shell').scrollTop=0);
  await connectEntry(page,'entry-close-session');
  await page.clock.runFor(600);
  const close=await entryControlPoint(page,'#close-projection');
  await page.mouse.click(close.x,close.y);
  await assertEntryState(page,'complete',false);
  assert.equal(await page.evaluate(()=>window.projectionCommands.at(-1).action),'close','Close does not await arrival or its reply');
  assert.equal(await page.evaluate(()=>window.projectionCommands.filter(command=>command.action==='stopVoice').length),1,'Closing never stops the shared conversation');
  await page.clock.runFor(200);
  await connectEntry(page,'entry-reopened-session');
  await page.clock.runFor(700);
  await assertEntryState(page,'enter',true);
  await page.clock.runFor(500);
  await assertEntryState(page,'enter',true,'full');
  await page.clock.runFor(300);
  await assertEntryState(page,'arrive',true);
  await page.clock.runFor(500);
  await assertEntryState(page,'complete',false);

  await connectEntry(page,'entry-typed-search',{
    selectedPlace:null,candidates:[],destinationSearch:{sequence:0,query:'',active:false,source:'typed'}
  });
  await page.locator('#destination-input').fill('10 Downing Street, London');
  await page.locator('#search-form').evaluate(form=>form.scrollIntoView({block:'center'}));
  await page.clock.runFor(32);
  const searchButton=await entryControlPoint(page,'#search-button');
  await page.mouse.click(searchButton.x,searchButton.y);
  assert.equal(await page.evaluate(()=>window.projectionCommands.filter(command=>command.action==='search').at(-1)?.payload.query),'10 Downing Street, London','Typed search dispatches during the entrance');
  await page.clock.runFor(1);
  assert.equal(await page.locator('.candidate-button').count(),2);
  await assertEntryState(page,'awaken',true);

  for(const reason of ['foreground','closed','visibility','pagehide']) {
    const nonce='entry-cancel-'+reason;
    await connectEntry(page,nonce,{foreground:true,open:true});
    await page.evaluate(reason=>{
      if(reason==='foreground'||reason==='closed') {
        window.projectionState[reason==='foreground'?'foreground':'open']=false;window.sendSnapshot();
      } else if(reason==='visibility') {
        Object.defineProperty(document,'hidden',{configurable:true,value:true});
        document.dispatchEvent(new Event('visibilitychange'));
      } else window.dispatchEvent(new Event('pagehide'));
    },reason);
    await assertEntryState(page,'complete',false);
    await page.evaluate(()=>{delete document.hidden;document.dispatchEvent(new Event('visibilitychange'));});
    await connectEntry(page,nonce,{foreground:true,open:true});
    await page.clock.runFor(2100);
    await assertEntryState(page,'complete',false);
  }
  await connectEntry(page,'entry-keyboard-completion');
  await page.locator('#projection-entry-skip').focus();
  await page.clock.runFor(2000);
  await assertEntryState(page,'complete',false);
  assert.equal(await page.evaluate(()=>document.activeElement?.id),'projection-heading','Natural completion does not leave keyboard focus on hidden Skip');
  await connectEntry(page,'entry-skip-session');
  await page.locator('#projection-entry-skip').focus();
  const skip=await entryControlPoint(page,'#projection-entry-skip');
  await page.mouse.click(skip.x,skip.y);
  await assertEntryState(page,'complete',false);
  assert.equal(await page.evaluate(()=>document.activeElement?.id),'projection-heading','Skip returns its own focus to the Projection heading');

  await connectEntry(page,'entry-preference-change');
  await changeEntryMotionPreference(page,'reduce');
  await assertEntryState(page,'complete',false,'reduced');
  await connectEntry(page,'entry-reduced-session');
  await assertEntryState(page,'arrive',true,'reduced');
  assert.equal(await page.locator('#projection-entry-illustration').evaluate(element=>getComputedStyle(element).display),'none','Reduced motion has no portal geometry');
  const reducedProperties=await page.evaluate(()=>document.getAnimations().filter(animation=>{
    const target=animation.effect?.target;
    return target instanceof Element&&target.closest('#projection-entry-room,#projection-entry-illustration,.entry-scene-accent,.entry-scene-corner,.entry-scene-rail');
  }).flatMap(animation=>animation.effect.getKeyframes().flatMap(frame=>Object.keys(frame).filter(key=>!['offset','computedOffset','easing','composite'].includes(key)))));
  assert.ok(reducedProperties.every(property=>property==='opacity'),'Reduced entrance effects only change opacity: '+JSON.stringify(reducedProperties));
  await page.locator('#destination-input').focus();
  await page.clock.runFor(239);
  await assertEntryState(page,'arrive',true,'reduced');
  await page.clock.runFor(1);
  await assertEntryState(page,'complete',false,'reduced');
  assert.equal(await page.evaluate(()=>document.activeElement?.id),'destination-input');
  await connectEntry(page,'entry-return-to-full');
  await changeEntryMotionPreference(page,'no-preference');
  await assertEntryState(page,'complete',false);
  await connectEntry(page,'entry-return-to-full');
  await assertEntryState(page,'complete',false);
  await page.close();
}

async function assertEntryVisualStages(browser,errors,width,height) {
  const page=await browser.newPage({viewport:{width,height},reducedMotion:'no-preference'});
  page.on('pageerror',error=>errors.push(error.message));
  await fixture(page,{connect:false});
  assert.equal(await page.locator('#projection-entry-illustration .entry-portal').count(),5,'The entrance retains five decorative portals');
  for(const selector of ['#projection-entry-room','#projection-entry-illustration']) {
    assert.equal(await page.locator(selector).getAttribute('aria-hidden'),'true','Entrance artwork is decorative');
  }
  const captures=[];
  const phases=['awaken','enter','arrive','complete'];
  for(const phase of phases.slice(0,3)) {
    // Each real opening owns its own capture, so a slow PNG cannot skip the
    // next requested stage. Encoding may legitimately cross a phase boundary.
    const startedAt=await page.evaluate(()=>performance.now());
    await connectEntry(page,'entry-visual-'+width+'-'+phase);
    await page.waitForFunction(phase=>document.body.dataset.entryState===phase,phase,{timeout:3000,polling:10});
    const before=await page.evaluate(()=>({phase:document.body.dataset.entryState,at:performance.now()}));
    const pixels=screenDirectory?await page.screenshot({animations:'allow'}):null;
    const after=await page.evaluate(()=>({phase:document.body.dataset.entryState,at:performance.now()}));
    const interval=before.phase===after.phase?before.phase:before.phase+'-to-'+after.phase;
    const file=`projection-entrance-${interval}-${width}.png`;
    if(screenDirectory) {
      fs.mkdirSync(screenDirectory,{recursive:true});
      fs.writeFileSync(path.join(screenDirectory,file),pixels);
    }
    captures.push({requestedPhase:phase,startedAt,file:pixels?file:null,before,after});
    assert.equal(before.phase,phase);
    assert.ok(phases.indexOf(after.phase)>=phases.indexOf(phase),'The real entrance progresses monotonically during capture at '+width);
  }
  await page.waitForFunction(()=>document.body.dataset.entryState==='complete',{},{timeout:3000,polling:10});
  if(screenDirectory)fs.writeFileSync(path.join(screenDirectory,`projection-entrance-timing-${width}.json`),JSON.stringify({clock:'real',captureMode:'fresh opening per requested stage',captures},null,2));
  await assertEntryState(page,'complete',false);

  await routeProjectionRenderer(page);
  await connectEntry(page,'entry-provider-'+width,{
    selectedPlace:{id:'entry-provider',label:'Entrance provider fixture',address:'Synthetic attribution test',latitude:40.71,longitude:-74,provider:'Test'},
    camera:{sequence:1,operation:'flyTo',viewMode:'street',latitude:40.71,longitude:-74,height:650,heading:0,pitch:-45},
    config:{rendererUrl:'https://projection.test/brain-projection/earth.html',mapAvailable:true,geocodingAvailable:true,directionsAvailable:true,answersAvailable:true},
    voice:{active:true,phase:'listening',message:'Rici is listening'}
  });
  await page.locator('#map-container iframe').waitFor();
  const renderer=await (await page.locator('#map-container iframe').elementHandle()).contentFrame();
  await renderer.waitForFunction(()=>typeof window.emitTransport==='function');
  await settleRendererLayout(page,renderer,'entry-loading-'+width);
  await alignRendererInViewport(page);
  assert.equal(await page.locator('body').getAttribute('data-entry-active'),'true','Provider loads during the full entrance at '+width);
  assert.equal(await page.locator('#projection-entry-illustration').evaluate(element=>getComputedStyle(element).display),'none','Loading provider immediately hides the illustrative portal overlay');
  await assertClearRendererSurface(page,'entry-loading-'+width,{activeVoice:true});
  await renderer.evaluate(()=>window.emitTransport());
  await renderer.waitForFunction(()=>window.received.length===1);
  assert.equal(await renderer.evaluate(()=>window.received[0].camera.operation),'flyTo','Camera reaches the provider before arrival');
  assert.equal(await page.locator('body').getAttribute('data-entry-active'),'true');
  await renderer.evaluate(()=>window.emitStatus('ready'));
  await page.waitForFunction(()=>document.body.dataset.map==='ready');
  await assertClearRendererSurface(page,'entry-ready-'+width,{activeVoice:true});
  assert.equal(await page.evaluate(()=>window.projectionCommands.some(command=>['startVoice','resumeVoice','stopVoice','camera'].includes(command.action))),false,'Entrance preserves the active voice session and native camera intent');
  await page.waitForFunction(()=>document.body.dataset.entryState==='complete',{},{timeout:3000,polling:10});
  await assertClearRendererSurface(page,'entry-finished-'+width,{activeVoice:true,capture:true});
  await page.close();
}

async function assertSpokenAddressFeedback(browser, errors, width, height) {
  const page = await browser.newPage({viewport:{width,height},reducedMotion:'reduce'});
  page.on('pageerror',error=>errors.push(error.message));
  await fixture(page);
  const query = 'Twenty one Oak Street, Apt 4B, Example City, NY 10001';
  await page.evaluate(query=>{
    const state=window.projectionState;
    state.voice={active:true,phase:'listening',message:'Rici is listening'};
    state.loading=true;
    state.destinationSearch={sequence:1,query,active:true,source:'voice'};
    state.lastVoiceCommand={heard:query,action:'Find destination',status:'running',result:'Applying the view command.'};
    window.sendSnapshot();
  },query);
  assert.equal(await page.locator('#destination-input').inputValue(),query,'Voice query populates the original full address at '+width);
  assert.equal(await page.locator('#search-button span').textContent(),'Finding…','Native lookup shows progress without a form submission');
  assert.equal(await page.locator('#search-button').getAttribute('aria-busy'),'true');
  assert.equal(await page.locator('#search-button').isEnabled(),false);
  assert.equal(await page.evaluate(()=>window.projectionCommands.some(c=>c.action==='search')),false,'Rendering native search must not submit a duplicate request');
  await page.evaluate(query=>{
    const state=window.projectionState;
    state.loading=false;state.destinationSearch.active=false;
    state.candidates=[
      {id:'spoken-a',label:'First spoken match',address:'Example address fixture',userQuery:query,latitude:40.71,longitude:-74,provider:'Test'},
      {id:'spoken-b',label:'Second spoken match',address:'Alternate example fixture',userQuery:query,latitude:40.72,longitude:-73.98,provider:'Test'}
    ];
    state.lastVoiceCommand={...state.lastVoiceCommand,status:'completed',result:'Choose a matching destination.'};
    window.sendSnapshot();
  },query);
  await settleLayout(page);
  assert.match(await page.locator('#search-help').textContent(),/Choose the first result/);
  assert.equal(await page.locator('#search-button').getAttribute('aria-busy'),'false');
  const visibility=await page.evaluate(()=>{
    const candidate=document.querySelector('.candidate-button'),box=candidate.getBoundingClientRect();
    const dock=document.querySelector('.voice-dock').getBoundingClientRect();
    return {top:box.top,bottom:box.bottom,dockTop:dock.top,focused:document.activeElement?.id,
      hittable:document.elementFromPoint(box.x+box.width/2,box.y+box.height/2)?.closest('button')===candidate};
  });
  assert.ok(visibility.top>=0&&visibility.bottom<=visibility.dockTop&&visibility.hittable,'Spoken results are visible above the voice dock: '+JSON.stringify(visibility));
  assert.notEqual(visibility.focused,'destination-input','Spoken search must not raise the keyboard');
  assert.equal(await page.evaluate(()=>window.projectionCommands.some(c=>c.action==='select')),false,'Spoken search still requires destination confirmation');
  await page.locator('.candidate-button').first().click();
  await page.locator('#place-banner').waitFor();
  await page.locator('#destination-input').fill('An unfinished typed draft');
  await page.evaluate(()=>{window.projectionState.loading=true;window.sendSnapshot();});
  assert.equal(await page.locator('#destination-input').inputValue(),'An unfinished typed draft','Unrelated snapshots do not overwrite a new draft');
  assert.equal(await page.locator('#search-button span').textContent(),'Explore','A research request is not address-search progress');
  await page.evaluate(()=>{
    const state=window.projectionState;
    state.selectedPlace=null;state.candidates=[];
    state.destinationSearch={sequence:2,query:'32 Pine Avenue, Example City',active:true,source:'voice'};
    window.sendSnapshot();
  });
  assert.equal(await page.locator('#destination-input').inputValue(),'32 Pine Avenue, Example City','The next spoken address replaces the previous query');
  if(screenDirectory){fs.mkdirSync(screenDirectory,{recursive:true});await page.screenshot({path:path.join(screenDirectory,`projection-spoken-search-${width}.png`)});}
  await page.close();
}

async function assertVoiceControls(page,label) {
  await settleLayout(page);
  const controls=await page.evaluate(()=>['pause-button','resume-button','stop-button'].map(id=>{
    const button=document.getElementById(id),box=button.getBoundingClientRect();
    return {id,name:button.getAttribute('aria-label'),width:box.width,height:box.height,top:box.top,bottom:box.bottom,
      viewportHeight:innerHeight,hittable:document.elementFromPoint(box.x+box.width/2,box.y+box.height/2)?.closest('button')===button};
  }));
  for(const control of controls) {
    assert.ok(control.name&&control.width>=44&&control.height>=44,'Labeled 44px control at '+label+': '+JSON.stringify(control));
    assert.ok(control.top>=0&&control.bottom<=control.viewportHeight&&control.hittable,'Visible reachable control at '+label+': '+control.id);
  }
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1),false,'Voice controls fit '+label);
}

async function settleRendererLayout(page,renderer,label) {
  // Window size and the voice controls can resize the iframe. Wait for
  // both documents to agree without inspecting any provider-owned internals.
  let previous='',last;
  const deadline=Date.now()+5000;
  while(Date.now()<deadline) {
    await settleLayout(page);
    const child=await renderer.evaluate(()=>({width:innerWidth,height:innerHeight}));
    const parent=await page.evaluate(()=>{
      const frame=document.querySelector('#map-container iframe');
      return {width:frame.clientWidth,height:frame.clientHeight};
    });
    last={label,parent,child};
    const signature=JSON.stringify({parent,child});
    const agrees=parent.width>0&&parent.height>0&&Math.abs(parent.width-child.width)<=1&&Math.abs(parent.height-child.height)<=1;
    if(agrees&&signature===previous)return;
    previous=signature;
  }
  if(screenDirectory)await page.screenshot({path:path.join(screenDirectory,`projection-layout-failure-${label}.png`)});
  throw new Error('Renderer layout did not settle: '+JSON.stringify(last));
}

async function alignRendererInViewport(page) {
  await page.evaluate(()=>{
    const shell=document.querySelector('.projection-shell'),frame=document.querySelector('#map-container iframe');
    const clip=shell.getBoundingClientRect();
    const rect=frame.getBoundingClientRect();
    const change=rect.top-(clip.top+Math.max(8,(clip.height-rect.height)/2));
    shell.scrollTop+=change;
  });
  await settleLayout(page);
}

async function assertVoiceEntry(page,label) {
  await settleLayout(page);
  const geometry=await page.evaluate(()=>{
    const button=document.getElementById('talk-button'),status=document.getElementById('voice-phase');
    const dock=document.querySelector('.voice-dock'),shell=document.querySelector('.projection-shell');
    const box=button.getBoundingClientRect(),state=status.getBoundingClientRect();
    return {button:box.toJSON(),status:state.toJSON(),dock:dock.getBoundingClientRect().toJSON(),shell:shell.getBoundingClientRect().toJSON(),
      text:status.textContent,disabled:button.disabled,height:innerHeight,width:innerWidth,
      hittable:document.elementFromPoint(box.x+box.width/2,box.y+box.height/2)?.closest('button')===button};
  });
  assert.equal(geometry.text,'Microphone off','Inactive microphone is explicit at '+label);
  assert.equal(geometry.disabled,false,'Voice can be started at '+label);
  assert.ok(geometry.button.width>=44&&geometry.button.height>=44,'Voice start has a 44px touch target at '+label);
  assert.ok(geometry.button.top>=0&&geometry.button.bottom<=geometry.height&&geometry.hittable,'Voice start is reachable without auto-scrolling at '+label);
  assert.ok(geometry.status.top>=0&&geometry.status.bottom<=geometry.height,'Microphone state is visible at '+label);
  assert.ok(geometry.shell.bottom<=geometry.dock.top-10,'Inactive voice dock reserves its own space at '+label);
}

async function assertClearRendererSurface(page,label,{activeVoice=false,capture=false}={}) {
  const geometry=await page.evaluate(()=>{
    const frame=document.querySelector('#map-container iframe'),stage=document.getElementById('scene-stage');
    const shell=document.querySelector('.projection-shell'),dock=document.querySelector('.voice-dock'),stop=document.getElementById('stop-button');
    const rect=frame.getBoundingClientRect(),button=stop.getBoundingClientRect();
    const selectors=['.scene-topline','.scene-heading','.map-badge','.world-caption','.camera-controls','.place-banner','.room-architecture','.scene-crosshair','#world-canvas','.voice-dock','.view-toolbar','.voice-command-feedback','.voice-command-summary','#projection-entry-illustration','.entry-scene-accent','.entry-scene-corner','.entry-scene-rail','#projection-entry-skip'];
    const points=[[rect.left+2,rect.top+2],[rect.right-2,rect.top+2],[rect.left+2,rect.bottom-2],[rect.right-2,rect.bottom-2],[rect.left+rect.width/2,rect.top+rect.height/2]];
    return {frame:rect.toJSON(),shell:shell.getBoundingClientRect().toJSON(),dock:dock.getBoundingClientRect().toJSON(),stop:button.toJSON(),
      width:innerWidth,height:innerHeight,phase:document.body.dataset.map,renderer:document.body.dataset.renderer,
      before:getComputedStyle(stage,'::before').content,after:getComputedStyle(stage,'::after').content,
      dockShadow:getComputedStyle(dock).boxShadow,
      riciShadow:getComputedStyle(document.querySelector('.rici-panel')).boxShadow,
      overlays:Object.fromEntries(selectors.flatMap(selector=>Array.from(document.querySelectorAll(selector),(element,index)=>{
        const style=getComputedStyle(element),box=element.getBoundingClientRect();
        return [selector+'['+index+']',{visible:style.display!=='none'&&style.visibility!=='hidden'&&box.width>0&&box.height>0,rect:box.toJSON()}];
      }))),
      providerAncestors:Array.from((function*(){for(let element=frame;element;element=element.parentElement)yield element;})(),element=>{
        const style=getComputedStyle(element);
        return {tag:element.id||element.className||element.tagName,transform:style.transform,filter:style.filter,perspective:style.perspective,
          opacity:Number(style.opacity),translate:style.translate,scale:style.scale,rotate:style.rotate};
      }),
      entranceBackground:(()=>{
        const room=document.getElementById('projection-entry-room'),style=getComputedStyle(room);
        return {sibling:room.parentElement===shell.parentElement,hiddenFromAccessibility:room.getAttribute('aria-hidden')==='true',
          pointerEvents:style.pointerEvents,zIndex:Number(style.zIndex),shellZIndex:Number(getComputedStyle(shell).zIndex)};
      })(),
      hits:points.map(([x,y])=>{const hit=document.elementFromPoint(x,y);return {x,y,frame:hit===frame,hit:hit?.id||hit?.className||hit?.tagName};}),
      scrollTop:shell.scrollTop,windowScroll:scrollY,
      stopHittable:document.elementFromPoint(button.x+button.width/2,button.y+button.height/2)?.closest('#stop-button')===stop};
  });
  if(screenDirectory&&capture) {
    await page.screenshot({path:path.join(screenDirectory,`projection-surface-${label}.png`)});
    fs.writeFileSync(path.join(screenDirectory,`projection-surface-${label}.json`),JSON.stringify(geometry,null,2));
  }
  try {
    assert.equal(geometry.renderer,'active','Remote map has its unobstructed layout at '+label);
    assert.equal(geometry.before,'none','Discovery decoration stays outside the iframe at '+label);
    assert.equal(geometry.after,'none','App vignette cannot cover the iframe at '+label);
    assert.equal(geometry.dockShadow,'none','Voice dock decoration cannot shade the provider surface at '+label);
    assert.equal(geometry.riciShadow,'none','Rici panel decoration cannot shade the provider surface at '+label);
    for(const ancestor of geometry.providerAncestors) {
      assert.equal(ancestor.transform,'none','Entrance does not transform provider ancestor '+ancestor.tag+' at '+label);
      assert.equal(ancestor.filter,'none','Entrance does not filter provider ancestor '+ancestor.tag+' at '+label);
      assert.equal(ancestor.perspective,'none','Entrance does not add provider perspective at '+label);
      assert.equal(ancestor.opacity,1,'Entrance does not fade the provider at '+label);
      for(const property of ['translate','scale','rotate'])assert.equal(ancestor[property],'none','Entrance does not '+property+' provider ancestor '+ancestor.tag+' at '+label);
    }
    assert.ok(geometry.entranceBackground.sibling&&geometry.entranceBackground.hiddenFromAccessibility,'Entrance background is a decorative sibling at '+label);
    assert.equal(geometry.entranceBackground.pointerEvents,'none');
    assert.ok(Number.isFinite(geometry.entranceBackground.zIndex)&&Number.isFinite(geometry.entranceBackground.shellZIndex)
      &&geometry.entranceBackground.zIndex<geometry.entranceBackground.shellZIndex,'Entrance background is painted behind the workspace at '+label);
    const frame=geometry.frame;
    for(const [selector,overlay] of Object.entries(geometry.overlays)) {
      if(!overlay.visible)continue;
      const box=overlay.rect;
      const overlapWidth=Math.max(0,Math.min(frame.right,box.right)-Math.max(frame.left,box.left));
      const overlapHeight=Math.max(0,Math.min(frame.bottom,box.bottom)-Math.max(frame.top,box.top));
      assert.ok(overlapWidth*overlapHeight<.5,selector+' stays entirely outside the provider iframe at '+label);
    }
    const clip=geometry.shell;
    assert.ok(frame.top>=clip.top&&frame.bottom<=clip.bottom,'Complete iframe can scroll into view at '+label);
    assert.ok(geometry.hits.every(hit=>hit.frame),'All iframe corners and its center remain hittable at '+label);
    assert.ok(geometry.shell.bottom<=geometry.dock.top-10,'Scroll viewport ends above the voice dock at '+label);
    assert.ok(frame.bottom<geometry.dock.top,'Voice dock never covers the provider surface at '+label);
    if(activeVoice) {
      assert.ok(geometry.stop.y>=0&&geometry.stop.bottom<=geometry.height&&geometry.stopHittable,'Stop stays visible and hittable at '+label);
    }
  } catch(error) {
    console.error('Projection surface geometry:',JSON.stringify({label,geometry}));
    if(screenDirectory&&!capture)await page.screenshot({path:path.join(screenDirectory,`projection-surface-failure-${label}.png`)});
    throw error;
  }
}

(async()=>{
  const browser = await chromium.launch({headless:true,executablePath:process.env.BROWSER_EXECUTABLE_PATH||undefined,args:['--no-sandbox','--disable-dev-shm-usage']});
  const errors=[];
  try {
    await assertEntryLifecycle(browser,errors);
    for(const [width,height] of [[390,844],[768,1024]])await assertEntryVisualStages(browser,errors,width,height);
    for(const [width,height] of [[320,850],[390,844],[768,1024],[1024,768],[1440,1000]]) {
      const page = await browser.newPage({viewport:{width,height},reducedMotion:'reduce'});
      page.on('pageerror',error=>errors.push(error.message));
      await fixture(page);
      await assertVoiceEntry(page,'initial-'+width);
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1),false,'No horizontal overflow at '+width);
      assert.equal(await page.locator('#world-caption-text').textContent(),'Property imagery is not connected yet.');
      assert.equal(await page.locator('label[for="destination-input"]').textContent(),'Explore a property');
      assert.equal(await page.locator('label[for="destination-input"]').isVisible(),true,'Address exploration is visibly labeled at '+width);
      assert.equal(await page.locator('#search-button').isEnabled(),true,'Address lookup is available independently of 3D imagery');
      await page.evaluate(()=>{window.projectionState.config.checking=true;window.sendSnapshot();});
      assert.equal(await page.locator('#search-button').isEnabled(),false,'Address lookup waits for fresh capabilities');
      assert.equal(await page.locator('#search-help').first().textContent(),'Checking address search…Confirm a result to open Street View.');
      assert.equal(await page.locator('#world-caption-text').textContent(),'Checking property imagery…');
      await page.locator('#destination-input').fill('10 Downing Street, London SW1A 2AA');
      await page.locator('#search-form').evaluate(form=>form.requestSubmit());
      assert.equal(await page.evaluate(()=>window.projectionCommands.some(c=>c.action==='search')),false,'Submitting during refresh cannot use stale capabilities');
      await page.evaluate(()=>{window.projectionState.config.checking=false;window.projectionState.config.geocodingAvailable=false;window.sendSnapshot();});
      assert.equal(await page.locator('#search-button').isEnabled(),false);
      assert.match(await page.locator('#search-help').textContent(),/Address search is not connected yet/);
      assert.match(await page.locator('#world-caption-text').textContent(),/Property imagery is not connected yet/);
      await page.evaluate(()=>{window.projectionState.config.checkFailed=true;window.sendSnapshot();});
      assert.match(await page.locator('#search-help').textContent(),/Could not check address search\. Close and reopen Projection to try again\./);
      assert.match(await page.locator('#world-caption-text').textContent(),/Could not check property imagery/);
      await page.evaluate(()=>{window.projectionState.config.checkFailed=false;window.projectionState.config.geocodingAvailable=true;window.sendSnapshot();});
      assert.equal(await page.locator('#search-button').isEnabled(),true,'A refreshed address service re-enables search');
      await page.locator('#destination-input').fill('');
      assert.equal(await page.evaluate(()=>window.projectionCommands.some(c=>c.action==='startVoice')),false,'Opening must not start a second conversation');
      assert.equal(await page.locator('#talk-button').isEnabled(),true);
      assert.equal(await page.locator('#pause-button').isEnabled(),false);
      assert.equal(await page.locator('#resume-button').isEnabled(),false);
      assert.equal(await page.locator('#stop-button').isEnabled(),false);
      assert.equal(await page.locator('#directions-button').isEnabled(),false,'Directions require a confirmed destination');
      assert.equal(await page.locator('[data-camera="closer"]').isEnabled(),false,'Unconfigured illustration is not a working map');
      if(screenDirectory){fs.mkdirSync(screenDirectory,{recursive:true});await page.screenshot({path:path.join(screenDirectory,`projection-command-${width}.png`),fullPage:true});}
      await page.locator('#room-discovery').click();
      assert.equal(await page.locator('body').getAttribute('data-room'),'discovery');
      assert.equal(await page.locator('#room-discovery').getAttribute('aria-pressed'),'true');
      assert.equal(await page.evaluate(()=>window.projectionCommands.some(c=>['startVoice','stopVoice'].includes(c.action))),false,'Room switches leave voice untouched');
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1),false,'Discovery fits '+width);
      if(screenDirectory)await page.screenshot({path:path.join(screenDirectory,`projection-discovery-${width}.png`),fullPage:true});

      await page.evaluate(()=>{window.projectionState.config.answersAvailable=false;window.sendSnapshot();});
      const liveChip=page.locator('[data-question]').last();
      assert.equal(await liveChip.textContent(),'Live camera availability');
      assert.equal(await liveChip.isEnabled(),true,'Local live-view status is available without a research service or destination');
      assert.equal(await page.locator('[data-question]').first().isEnabled(),false,'Sourced questions still require research availability');
      await liveChip.click();
      await page.waitForFunction(()=>document.querySelector('#answer-text').textContent.includes('no connected, permitted live camera'));
      assert.equal(await page.evaluate(()=>window.testResearchCalls),0,'Live-view unavailability performs no sourced lookup');
      await page.evaluate(()=>{window.projectionState.config.answersAvailable=true;window.projectionState.answer=null;window.sendSnapshot();});

      await page.locator('#destination-input').fill('An ambiguous address');
      await page.locator('#search-button').click();
      await page.locator('.candidate-button').first().waitFor();
      assert.equal(await page.locator('.candidate-button').count(),2);
      assert.equal(await page.locator('.candidate-button .map-data-credit').count(),0,'Non-Google candidates do not carry Google attribution');
      assert.equal(await page.locator('.candidate-button').last().locator('.partial-match-warning').textContent(),'Check address — partial match','Partial geocoder matches must be disclosed before selection');
      assert.equal(await page.locator('#place-banner').isVisible(),false,'No automatic travel before explicit confirmation');
      assert.equal(await page.evaluate(()=>window.projectionCommands.some(c=>c.action==='select')),false);
      await page.locator('.candidate-button').last().click();
      await page.locator('#place-banner').waitFor();
      assert.equal(await page.locator('#place-label').textContent(),'Second destination candidate');
      assert.equal(await page.locator('#place-source').isVisible(),false,'Non-Google selected data does not carry Google attribution');
      assert.equal(await page.locator('#place-match').isVisible(),true,'The partial-match warning survives selection');
      assert.equal(await page.locator('#place-match').textContent(),'Check address — partial match');
      await page.locator('#destination-input').fill('An unconfirmed replacement query');
      const cameraBeforeDirections=await page.evaluate(()=>window.projectionState.camera);
      await page.locator('#directions-button').click();
      await page.waitForFunction(()=>document.querySelector('#projection-notice').textContent.includes('Review the full address'));
      assert.deepEqual(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='directions').at(-1).payload),{query:'An ambiguous address'},'Directions review uses the confirmed userQuery, not provider labels or unsent search input');
      assert.deepEqual(await page.evaluate(()=>window.projectionState.camera),cameraBeforeDirections,'Opening address review does not move or replace the map');
      assert.equal(await page.evaluate(()=>window.projectionCommands.some(c=>['startVoice','resumeVoice'].includes(c.action))),false,'Directions do not start or resume voice');
      const directionsBounds=await page.locator('#directions-button').boundingBox();
      assert.ok(directionsBounds&&directionsBounds.width>=44&&directionsBounds.height>=44,'Directions has a 44px touch target at '+width);
      await page.evaluate(()=>{window.projectionState.config.directionsAvailable=false;window.sendSnapshot();});
      assert.equal(await page.locator('#directions-button').isEnabled(),false,'Routing entitlement is required independently of the map');
      assert.equal(await page.locator('#directions-help').textContent(),'Address routing is not enabled for this account.');
      await page.evaluate(()=>{window.projectionState.config.directionsAvailable=true;delete window.projectionState.selectedPlace.userQuery;window.sendSnapshot();});
      await page.locator('#directions-button').click();
      await page.waitForFunction(()=>window.projectionCommands.filter(c=>c.action==='directions').length===2);
      assert.deepEqual(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='directions').at(-1).payload),{query:''},'Missing userQuery opens manual address review without substituting a provider address');
      assert.equal(await page.locator('#question-help').textContent(),'4 credits per successful sourced lookup.');
      await page.locator('[data-question]').first().click();
      await page.locator('.source-button').waitFor();
      assert.equal(await page.evaluate(()=>window.projectionTimeouts.filter(entry=>entry.action==='ask').at(-1).timeout),180000,'Sourced lookup deadline must cover the 175s native request budget');
      assert.match(await page.locator('#answer-text').textContent(),/\[1\]/);
      assert.match(await page.locator('.source-button').textContent(),/\[1\] Test source/);
      await page.locator('.source-button').click();
      assert.equal(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='openSource').at(-1).payload.url),'https://example.com/source');

      await page.locator('#save-details summary').click();
      await page.locator('#place-note').fill('Keep this draft if saving fails.');
      await page.evaluate(()=>window.testFailSave=true);
      await page.locator('#save-button').click();
      await page.waitForFunction(()=>document.querySelector('#save-status').textContent.includes('has not been saved'));
      assert.equal(await page.locator('#place-note').inputValue(),'Keep this draft if saving fails.');
      await page.evaluate(()=>window.testFailSave=false);
      for(const response of ['null','undefined','missing','false']){
        await page.evaluate(response=>window.testSaveResponse=response,response);
        await page.locator('#save-button').click();
        await page.waitForFunction(()=>document.querySelector('#save-status').textContent==='This place was not saved. Please try again.');
        assert.equal(await page.locator('#place-note').inputValue(),'Keep this draft if saving fails.','Unconfirmed save preserves the draft: '+response);
        assert.equal(await page.locator('#projection-notice').textContent(),'This place was not saved. Please try again.');
      }
      await page.evaluate(()=>window.testSaveResponse='success');
      await page.locator('#save-button').click();
      await page.waitForFunction(()=>document.querySelector('#save-status').textContent==='Place saved to My Brain.');
      assert.equal(await page.locator('#place-note').inputValue(),'');

      await page.evaluate(()=>window.testHoldStart=true);
      await page.locator('#talk-button').click();
      await page.evaluate(()=>{document.querySelector('#talk-button').click();document.querySelector('#talk-button').click();});
      assert.equal(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='startVoice').length),1,'Duplicate start is blocked while connecting');
      assert.equal(await page.locator('#stop-button').isEnabled(),true,'Connecting can be stopped');
      await page.evaluate(()=>{
        window.projectionState.voice={active:true,phase:'listening',message:'Rici is listening'};window.sendSnapshot();
        window.KorlixProjectionReceive({type:'transcript',role:'user',text:'Where are we going?'});
        window.KorlixProjectionReceive({type:'transcript',role:'assistant',text:'Choose a destination to explore.'});
      });
      assert.equal(await page.locator('#talk-button').isEnabled(),false,'Existing conversation cannot be started again');
      assert.equal(await page.locator('#transcript-count').textContent(),'2 messages');
      const stopBounds=await page.locator('#stop-button').boundingBox();
      assert.ok(stopBounds && stopBounds.y>=0 && stopBounds.y+stopBounds.height<=height,'Active Stop remains inside the viewport at '+width);
      if(screenDirectory&&width===390)await page.screenshot({path:path.join(screenDirectory,'projection-active-voice-390.png')});
      await page.evaluate(()=>{
        window.projectionState.transcript=[{role:'you',text:'Native snapshot question.'},{role:'rici',text:'Native snapshot response.'}];window.sendSnapshot();
      });
      assert.equal(await page.locator('.transcript-message strong').first().textContent(),'You','Native you/rici roles retain the correct speaker');
      assert.equal(await page.locator('.transcript-message p').last().textContent(),'Native snapshot response.');
      await assertVoiceControls(page,'listening-'+width);
      assert.equal(await page.locator('#pause-button').isEnabled(),true);
      assert.equal(await page.locator('#resume-button').isEnabled(),false);
      await page.evaluate(()=>window.testHoldPause=true);
      await page.locator('#pause-button').click();
      assert.equal(await page.locator('body').getAttribute('data-voice'),'pausing');
      assert.equal(await page.locator('#pause-button').isEnabled(),false,'Pause is guarded during shutdown');
      assert.equal(await page.locator('#resume-button').isEnabled(),false,'Resume waits for confirmed pause');
      assert.equal(await page.locator('#stop-button').isEnabled(),true,'Stop remains available while pausing');
      await page.evaluate(()=>{
        window.projectionState.voice={active:false,paused:true,phase:'paused',message:'Conversation paused'};
        window.KorlixProjectionReceive({type:'voice',...window.projectionState.voice});
        const command=window.projectionCommands.filter(c=>c.action==='pauseVoice').at(-1);
        window.KorlixProjectionReceive({type:'reply',id:command.id,data:{active:false,paused:true}});
      });
      assert.equal(await page.locator('body').getAttribute('data-voice'),'paused','Direct native paused events retain their phase');
      assert.equal(await page.locator('body').getAttribute('data-voice-active'),'false','Paused is not treated as an active microphone');
      assert.equal(await page.locator('#talk-button').isEnabled(),false,'A paused conversation uses Resume');
      assert.equal(await page.locator('#resume-button').isEnabled(),true);
      assert.equal(await page.locator('#stop-button').isEnabled(),true,'Stop works while paused');
      await assertVoiceControls(page,'paused-'+width);
      const voiceStartsBeforeNavigation=await page.evaluate(()=>window.projectionCommands.filter(c=>['startVoice','resumeVoice'].includes(c.action)).length);
      await page.locator('#room-command').click();
      assert.equal(await page.locator('body').getAttribute('data-voice'),'paused','Changing rooms preserves pause');
      await assertVoiceControls(page,'paused-command-'+width);
      await page.locator('#close-projection').click();
      assert.equal(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='close').length),1);
      assert.equal(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='stopVoice').length),0,'Closing projection does not stop the existing voice session');
      assert.equal(await page.evaluate(()=>window.projectionCommands.filter(c=>['startVoice','resumeVoice'].includes(c.action)).length),voiceStartsBeforeNavigation,'Room navigation and Close do not automatically resume voice');
      await page.locator('#stop-button').click();
      await page.waitForFunction(()=>document.querySelector('#voice-phase').textContent==='Microphone off');
      assert.equal(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='stopVoice').length),1);

      await page.evaluate(()=>{window.testHoldStart=false;window.testHoldPause=false;});
      await page.locator('#talk-button').click();
      await page.waitForFunction(()=>document.body.dataset.voice==='listening');
      await page.locator('#pause-button').click();
      await page.waitForFunction(()=>document.body.dataset.voice==='paused');
      await page.locator('#resume-button').click();
      await page.waitForFunction(()=>document.body.dataset.voice==='listening');
      assert.equal(await page.locator('#pause-button').isEnabled(),true,'A successful explicit Resume restores Pause');
      assert.equal(await page.locator('#resume-button').isEnabled(),false);
      assert.equal(await page.evaluate(()=>window.projectionTimeouts.filter(entry=>entry.action==='resumeVoice').at(-1).timeout),90000,'Resume receives the same connection budget as Start');
      await page.locator('#pause-button').click();
      await page.waitForFunction(()=>document.body.dataset.voice==='paused');
      await page.evaluate(()=>window.testHoldResume=true);
      await page.locator('#resume-button').click();
      await page.evaluate(()=>{document.querySelector('#resume-button').click();document.querySelector('#resume-button').click();});
      assert.equal(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='resumeVoice').length),2,'Duplicate Resume is blocked while connecting');
      assert.equal(await page.locator('body').getAttribute('data-voice'),'connecting');
      assert.equal(await page.locator('#stop-button').isEnabled(),true,'Stop cancels a pending Resume');
      await assertVoiceControls(page,'resuming-'+width);
      await page.evaluate(()=>window.testHoldStop=true);
      await page.locator('#stop-button').click();
      await page.evaluate(()=>window.KorlixProjectionReceive({type:'voice',active:true,paused:false,phase:'speaking',message:'A late audio update'}));
      assert.equal(await page.locator('body').getAttribute('data-voice'),'stopping','An in-flight voice event cannot undo Stop');
      assert.equal(await page.locator('#pause-button').isEnabled(),false);
      assert.equal(await page.locator('#resume-button').isEnabled(),false);
      await page.evaluate(()=>{
        window.projectionState.voice={active:false,paused:false,phase:'complete',message:'Microphone off'};window.sendSnapshot();
        for(const action of ['stopVoice','resumeVoice']) {
          const command=window.projectionCommands.filter(c=>c.action===action).at(-1);
          window.KorlixProjectionReceive({type:'reply',id:command.id,data:{active:action==='resumeVoice',paused:false}});
        }
      });
      await settleLayout(page);
      assert.equal(await page.locator('body').getAttribute('data-voice'),'complete','A late successful Resume reply cannot revive a stopped conversation');
      assert.equal(await page.locator('body').getAttribute('data-voice-active'),'false');
      assert.equal(await page.locator('#talk-button').isEnabled(),true);
      assert.equal(await page.locator('#resume-button').isEnabled(),false);
      assert.equal(await page.locator('#stop-button').isEnabled(),false);
      assert.equal(await page.evaluate(()=>window.projectionCommands.every(c=>/^\d+$/.test(c.id)&&c.nonce==='test-session-nonce-123456789')),true,'Every bridge command carries the session nonce and decimal ID');

      await page.evaluate(()=>{
        window.projectionState.answer={text:'<img src=x onerror=alert(1)>',sources:[{title:'Unsafe source',url:'javascript:alert(1)'}]};window.sendSnapshot();
      });
      assert.equal(await page.locator('#answer-text img').count(),0,'Research is text, never injected HTML');
      assert.equal(await page.locator('#answer-sources').isVisible(),false,'Non-HTTPS source links are rejected');
      await page.close();
    }

    // Geocoding remains available independently of the map. Its Google address
    // data needs a visible source credit attached to the candidate/selected card.
    for(const width of [320,390]) {
      for(const room of ['command','discovery']) {
        const offMap=await browser.newPage({viewport:{width,height:844},reducedMotion:'reduce'});
        offMap.on('pageerror',error=>errors.push(error.message));
        await fixture(offMap);
        await offMap.evaluate(room=>{
          window.testGeocodingProvider='google';window.projectionState.room=room;window.sendSnapshot();
        },room);
        assert.equal(await offMap.locator('#map-container iframe').count(),0,'Address attribution works with the map disabled');
        await offMap.locator('#destination-input').fill('Google address fixture');
        await offMap.locator('#search-button').click();
        await offMap.locator('.candidate-button').first().waitFor();
        const assertCredits=async(selector,count)=>{
          const credits=await offMap.locator(selector).evaluateAll(nodes=>nodes.map(node=>{
            const style=getComputedStyle(node),rect=node.getBoundingClientRect();
            const card=node.closest('.candidate-button,.place-banner').getBoundingClientRect();
            return {text:node.textContent,translate:node.getAttribute('translate'),fontSize:parseFloat(style.fontSize),
              weight:style.fontWeight,fontStyle:style.fontStyle,nowrap:style.whiteSpace,spacing:style.letterSpacing,color:style.color,
              width:rect.width,height:rect.height,inside:rect.left>=card.left&&rect.right<=card.right&&rect.top>=card.top&&rect.bottom<=card.bottom};
          }));
          assert.equal(credits.length,count,'Google source credit count at '+room+'/'+width);
          for(const credit of credits) {
            assert.equal(credit.text,'Google Maps');assert.equal(credit.translate,'no');
            assert.ok(credit.fontSize>=12&&credit.fontSize<=16,'Attribution is legible on the small card');
            assert.equal(credit.weight,'400');assert.equal(credit.fontStyle,'normal');
            assert.equal(credit.nowrap,'nowrap');assert.equal(credit.spacing,'normal');assert.equal(credit.color,'rgb(255, 255, 255)');
            assert.ok(credit.width>0&&credit.height>0&&credit.inside,'The complete credit fits inside its address card');
          }
        };
        await assertCredits('.candidate-button .map-data-credit',2);
        await offMap.locator('.candidate-button').first().click();
        await offMap.locator('#place-source').waitFor();
        await assertCredits('#place-source',1);
        assert.equal(await offMap.locator('#answer-text').textContent(),'Your destination is confirmed. What would you like to know?','Google labels stay in credited cards, separate from independent research');
        assert.equal(await offMap.locator('#answer-sources .map-data-credit').count(),0);
        assert.equal(await offMap.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1),false,'Google address credits fit '+room+'/'+width);
        if(screenDirectory)await offMap.screenshot({path:path.join(screenDirectory,`projection-geocoding-${room}-${width}.png`),fullPage:true});
        for(const provider of ['Google','google.com','not-google','']) {
          await offMap.evaluate(provider=>{window.projectionState.selectedPlace.provider=provider;window.sendSnapshot();},provider);
          assert.equal(await offMap.locator('#place-source').isVisible(),false,'Only the exact Google provider receives Google attribution: '+provider);
        }
        await offMap.close();
      }
    }

    for(const [width,height] of [[390,844],[768,1024]]) {
      await assertSpokenAddressFeedback(browser,errors,width,height);
    }

    const page = await browser.newPage({viewport:{width:1024,height:768},reducedMotion:'reduce'});
    page.on('pageerror',error=>errors.push(error.message));
    await page.context().route('https://provider-links.test/terms',route=>route.fulfill({contentType:'text/html; charset=utf-8',body:'<!doctype html><html><head><meta charset="utf-8"></head><body><h1>Provider link fixture</h1><form action="/accepted" method="get"><button type="submit">Continue fixture</button></form></body></html>'}));
    await page.context().route('https://provider-links.test/accepted**',route=>route.fulfill({contentType:'text/html; charset=utf-8',body:'<!doctype html><html><body><h1>Separate provider page accepted</h1></body></html>'}));
    await routeProjectionRenderer(page);
    await fixture(page);
    await page.evaluate(()=>{
      window.projectionState.selectedPlace={id:'renderer-fixture',label:'Camera fixture',address:'Not a real location claim',latitude:40.71,longitude:-74,provider:'Test'};
      window.projectionState.camera={sequence:1,operation:'flyTo',viewMode:'street',latitude:40.71,longitude:-74,height:650,heading:0,pitch:-45};
      window.projectionState.config={...window.projectionState.config,mapAvailable:true,rendererUrl:'https://projection.test/brain-projection/earth.html'};window.sendSnapshot();
    });
    await page.locator('#map-container iframe').waitFor();
    const renderer = await (await page.locator('#map-container iframe').elementHandle()).contentFrame();
    assert.ok(renderer,'Configured iframe has its own document');
    await renderer.waitForFunction(()=>typeof window.emitStatus==='function');
    await page.waitForFunction(()=>document.body.dataset.renderer==='active');
    assert.equal(await page.locator('#map-container').isVisible(),true,'The provider owns a visible unobstructed surface while loading');
    assert.equal(await page.locator('#world-canvas').isVisible(),false,'The illustrative globe cannot cover a loading provider');
    assert.equal(await page.locator('[data-camera="closer"]').isEnabled(),false,'Loading is not camera readiness');
    assert.equal(await renderer.evaluate(()=>window.received.length),0,'Camera commands wait for the verified frame transport');
    await page.evaluate(()=>window.dispatchEvent(new MessageEvent('message',{origin:'https://attacker.test',source:document.querySelector('iframe').contentWindow,data:{type:'korlix-projection-transport-ready'}})));
    assert.equal(await renderer.evaluate(()=>window.received.length),0,'A forged handshake cannot release camera commands');
    await renderer.evaluate(()=>window.emitTransport());
    await renderer.waitForFunction(()=>window.received.length===1);
    assert.equal(await renderer.evaluate(()=>window.received[0].camera.viewMode),'street','Street View is the default camera mode');
    assert.equal(await page.locator('[data-camera="closer"]').isEnabled(),false,'Transport does not claim loaded imagery');
    assert.equal(await page.locator('[data-camera="stopCamera"]').isEnabled(),true,'Stop stays available while imagery loads');
    await renderer.evaluate(()=>window.emitStatus('ready'));
    await page.waitForFunction(()=>document.body.dataset.map==='ready');
    await renderer.waitForFunction(()=>window.received.length>0);
    assert.equal(await renderer.evaluate(()=>typeof window.projectionState),'undefined','Workspace fixture state is not injected into the renderer');
    assert.equal(await renderer.evaluate(()=>JSON.stringify(window.received).includes('test-session-nonce')),false,'Native nonce never reaches iframe');
    assert.deepEqual(await renderer.evaluate(()=>Object.keys(window.received[0]).sort()),['camera','place','type']);
    assert.equal(await renderer.evaluate(()=>window.received[0].camera.operation),'flyTo','Native place selection reaches the map unchanged');
    assert.deepEqual(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='rendererReady').map(c=>c.payload.status)),['loading','ready'],'Native observes loading before actual renderer readiness');
    await page.evaluate(()=>{
      window.dispatchEvent(new MessageEvent('message',{origin:'https://projection.test',source:window,data:{type:'korlix-projection-status',status:'error',message:'Forged source'}}));
      window.dispatchEvent(new MessageEvent('message',{origin:'https://attacker.test',source:document.querySelector('iframe').contentWindow,data:{type:'korlix-projection-status',status:'error',message:'Forged origin'}}));
    });
    assert.equal(await page.locator('body').getAttribute('data-map'),'ready','Forged window or origin is ignored');
    await renderer.evaluate(()=>window.emitStatus('ready'));
    assert.equal(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='rendererReady'&&c.payload.status==='ready').length),1,'Duplicate renderer status does not duplicate ready action');

    await settleRendererLayout(page,renderer,'initial');
    const sandbox=(await page.locator('#map-container iframe').getAttribute('sandbox')).split(/\s+/).sort();
    assert.deepEqual(sandbox,['allow-popups','allow-popups-to-escape-sandbox','allow-same-origin','allow-scripts'],'Only the provider popup permissions are added to the isolated iframe');
    await alignRendererInViewport(page);
    const localUrl=page.url(),rendererUrl=renderer.url();
    const popupOpened=page.context().waitForEvent('page');
    await renderer.locator('#provider-terms').click();
    const popup=await popupOpened;
    await popup.waitForLoadState('domcontentloaded');
    assert.equal(popup.url(),'https://provider-links.test/terms','A user-clicked provider link opens its separate destination');
    assert.deepEqual(await popup.evaluate(()=>({opener:window.opener!==null,bridge:typeof window.Projection,workspace:typeof window.projectionState,connect:typeof window.KorlixProjectionConnect})),
      {opener:false,bridge:'undefined',workspace:'undefined',connect:'undefined'},'The provider popup has no local parent, native bridge or workspace/nonce fixture');
    await popup.getByRole('button',{name:'Continue fixture'}).click();
    await popup.waitForURL(url=>url.origin==='https://provider-links.test'&&url.pathname==='/accepted');
    assert.equal(await popup.locator('h1').textContent(),'Separate provider page accepted','The provider popup does not inherit the original iframe form restriction');
    assert.equal(page.url(),localUrl,'Provider popup cannot replace the local workspace');
    assert.equal(renderer.url(),rendererUrl,'Provider popup leaves the configured renderer in place');
    await popup.close();
    await settleRendererLayout(page,renderer,'after-provider-popup');
    const surfaceBefore=await page.evaluate(()=>{
      const frame=document.querySelector('#map-container iframe');
      return {width:frame.clientWidth,height:frame.clientHeight,stage:document.getElementById('scene-stage').clientHeight};
    });
    const nativeCommandsBefore=await page.evaluate(()=>window.projectionCommands.length);
    await renderer.evaluate(()=>{
      for(const height of [0,80,4096,-1,1.5,'80',NaN,Infinity,null,{},1000000])window.emitCreditHeight(height);
    });
    await settleRendererLayout(page,renderer,'ignored-legacy-geometry');
    assert.deepEqual(await page.evaluate(()=>{
      const frame=document.querySelector('#map-container iframe');
      return {width:frame.clientWidth,height:frame.clientHeight,stage:document.getElementById('scene-stage').clientHeight};
    }),surfaceBefore,'Remote credit geometry is retired and cannot resize the provider surface');
    assert.equal(await page.evaluate(()=>window.projectionCommands.length),nativeCommandsBefore,'Unknown geometry never becomes a native command or changes readiness');

    for(const width of [320,390,768,1024,1440]) {
      await page.setViewportSize({width,height:844});
      for(const room of ['command','discovery']) {
        await page.locator('#room-'+room).click();
        for(const phase of ['loading','ready']) {
          const label=`${room}-${phase}-${width}`;
          await renderer.evaluate(value=>window.emitStatus(value),phase);
          await page.waitForFunction(value=>document.body.dataset.map===(value==='ready'?'ready':'illustration'),phase);
          await settleRendererLayout(page,renderer,label);
          assert.equal(await page.locator('[data-camera="closer"]').isEnabled(),phase==='ready','App camera readiness remains accurate at '+label);
          assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1),false,'Remote map layout fits '+label);
          const startsBefore=await page.evaluate(()=>window.projectionCommands.filter(c=>['startVoice','resumeVoice'].includes(c.action)).length);
          for(const voicePhase of ['complete','error']) {
            await page.evaluate(voicePhase=>{
              window.projectionState.voice={active:false,paused:false,phase:voicePhase,message:voicePhase==='error'?'Voice connection failed. Tap Talk to Rici to reconnect.':'Microphone off'};
              window.sendSnapshot();
              document.querySelector('.projection-shell').scrollTop=0;
            },voicePhase);
            await assertVoiceEntry(page,`${voicePhase}-initial-${label}`);
            await alignRendererInViewport(page);
            await assertVoiceEntry(page,`${voicePhase}-map-${label}`);
            await assertClearRendererSurface(page,`${voicePhase}-${label}`);
          }
          assert.equal(await page.evaluate(()=>window.projectionCommands.filter(c=>['startVoice','resumeVoice'].includes(c.action)).length),startsBefore,'Visible microphone controls never start capture automatically at '+label);
          await alignRendererInViewport(page);
          await assertClearRendererSurface(page,label);
          if(screenDirectory&&width<500&&phase==='ready')await page.screenshot({path:path.join(screenDirectory,`projection-map-layout-${room}-${width}.png`),fullPage:true});

          await page.evaluate(()=>{
            window.scrollBeforeVoice=document.querySelector('.projection-shell').scrollTop;
            window.projectionState.voice={active:true,phase:'listening',message:'Rici is listening'};window.sendSnapshot();
          });
          assert.equal(await page.evaluate(()=>Math.abs(document.querySelector('.projection-shell').scrollTop-window.scrollBeforeVoice)<1),true,'Starting voice preserves the reading position at '+label);
          await settleRendererLayout(page,renderer,`active-${label}`);
          await alignRendererInViewport(page);
          await assertClearRendererSurface(page,`active-${label}`,{activeVoice:true,capture:true});
          await page.evaluate(()=>{
            window.projectionState.voice={active:false,paused:true,phase:'paused',message:'Conversation paused'};window.sendSnapshot();
          });
          await settleRendererLayout(page,renderer,`paused-${label}`);
          await alignRendererInViewport(page);
          await assertClearRendererSurface(page,`paused-${label}`,{activeVoice:true});
          await assertVoiceControls(page,`paused-map-${label}`);
          await page.evaluate(()=>{
            window.scrollBeforeStop=document.querySelector('.projection-shell').scrollTop;
            window.projectionState.voice={active:false,phase:'complete',message:'Microphone off'};window.sendSnapshot();
          });
          assert.equal(await page.evaluate(()=>Math.abs(document.querySelector('.projection-shell').scrollTop-window.scrollBeforeStop)<1),true,'Stopping voice preserves the view and keeps the voice entry visible at '+label);
          await assertVoiceEntry(page,'stopped-'+label);
        }
      }
    }
    await page.locator('[data-camera="closer"]').click();
    await renderer.waitForFunction(()=>window.received.at(-1).camera.operation==='closer');
    await page.evaluate(()=>{
      window.projectionState.camera={...window.projectionState.camera,sequence:window.projectionState.camera.sequence+1,operation:'zoomInContinuous'};
      window.sendSnapshot();
    });
    await renderer.waitForFunction(()=>window.received.at(-1).camera.operation==='zoomInContinuous');
    const cameraSequence=await page.evaluate(()=>window.projectionState.camera.sequence);
    await page.evaluate(sequence=>{
      const source=document.querySelector('iframe').contentWindow;
      for(const [origin,windowSource,record] of [
        ['https://attacker.test',source,{sequence,state:'limit',reason:'closest'}],
        ['https://projection.test',window,{sequence,state:'limit',reason:'closest'}],
        ['https://projection.test',source,{sequence:sequence-1,state:'limit',reason:'closest'}],
        ['https://projection.test',source,{sequence,state:'script',reason:'closest'}],
      ]) window.dispatchEvent(new MessageEvent('message',{origin,source:windowSource,data:{type:'korlix-projection-camera-status',...record}}));
    },cameraSequence);
    assert.equal(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='cameraStatus').length),0,'Untrusted/stale camera outcomes never reach native');
    await renderer.evaluate(sequence=>parent.postMessage({type:'korlix-projection-camera-status',sequence,state:'limit',reason:'closest'},'*'),cameraSequence);
    await page.waitForFunction(()=>window.projectionCommands.some(c=>c.action==='cameraStatus'));
    assert.deepEqual(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='cameraStatus').at(-1).payload),{sequence:cameraSequence,viewMode:'street',state:'limit',reason:'closest'});
    await page.locator('[data-camera="stopCamera"]').click();
    await renderer.waitForFunction(()=>window.received.at(-1).camera.operation==='stopCamera');
    assert.equal(await page.evaluate(()=>window.projectionCommands.at(-1).action),'camera','Camera stop is distinct from conversation Stop');
    await renderer.evaluate(()=>window.emitStatus('error'));
    await page.waitForFunction(()=>document.body.dataset.map==='illustration');
    assert.equal(await page.locator('#world-canvas').isVisible(),false,'Coverage errors keep the provider status visible without fabricated imagery');
    assert.equal(await page.locator('[data-camera="closer"]').isEnabled(),false,'Unavailable imagery cannot accept zoom');
    assert.equal(await page.locator('[data-view-mode="earth"]').isEnabled(),true,'Explicit Earth choice stays available after no coverage');
    assert.equal(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='rendererReady').at(-1).payload.status),'error','Renderer failure reaches native so voice cannot claim camera movement');
    const oldSequence=await page.evaluate(()=>window.projectionState.camera.sequence);
    await page.locator('[data-view-mode="earth"]').click();
    await renderer.waitForFunction(()=>window.received.at(-1).camera.viewMode==='earth');
    assert.equal(await renderer.evaluate(()=>window.received.at(-1).camera.operation),'flyTo','Mode selection uses the existing flyTo contract');
    assert.equal(await page.locator('[data-view-mode="earth"]').getAttribute('aria-pressed'),'true');
    await renderer.evaluate(sequence=>window.emitStatus('ready',{sequence,viewMode:'street'}),oldSequence);
    assert.equal(await page.locator('[data-camera="closer"]').isEnabled(),false,'Stale Street View readiness cannot enable Earth controls');
    await page.locator('[data-camera="stopCamera"]').click();
    await renderer.waitForFunction(()=>window.received.at(-1).camera.operation==='stopCamera');
    assert.equal(await page.locator('[data-camera="closer"]').isEnabled(),false,'Stop crosses the transport without claiming loaded imagery');
    await renderer.evaluate(()=>window.emitStatus('ready'));
    await page.waitForFunction(()=>document.body.dataset.map==='ready');
    assert.match(await page.locator('#map-badge').textContent(),/3D Earth/);
    await page.locator('[data-view-mode="street"]').click();
    await renderer.waitForFunction(()=>window.received.at(-1).camera.viewMode==='street');
    await renderer.evaluate(()=>window.emitStatus('error',{reason:'no-coverage',message:'No recorded Street View is available near this location.'}));
    await page.waitForFunction(()=>document.getElementById('world-caption-text').textContent.includes('No recorded Street View'));
    assert.equal(await page.locator('[data-view-mode="street"]').getAttribute('aria-pressed'),'true','No coverage never silently changes to Earth');
    await page.evaluate(()=>{
      window.projectionState.lastVoiceCommand={heard:'Reese, zoom in <img src=x onerror=alert(1)>',action:'Zoom in',result:'The property view is unavailable. Try another view.',status:'failed'};
      window.sendSnapshot();
    });
    assert.match(await page.locator('#voice-command-heard').textContent(),/Reese, zoom in <img/);
    assert.equal(await page.locator('#voice-command-feedback img').count(),0,'Recognized speech is rendered as text');
    assert.equal(await page.locator('#voice-command-action').textContent(),'Zoom in');
    assert.equal(await page.locator('#voice-command-feedback').getAttribute('data-status'),'failed');
    assert.match(await page.locator('#voice-command-result').textContent(),/unavailable/);
    assert.match(await page.locator('#voice-summary-heard').textContent(),/Reese, zoom in <img/);
    assert.equal(await page.locator('#voice-command-summary img').count(),0,'Compact voice feedback is text, never injected HTML');
    assert.match(await page.locator('#voice-summary-action').textContent(),/Zoom in.*unavailable/);
    for(const width of [320,390,768,1024]) {
      await page.setViewportSize({width,height:844});
      await settleRendererLayout(page,renderer,'voice-feedback-'+width);
      await alignRendererInViewport(page);
      await assertVoiceEntry(page,'voice-feedback-'+width);
      const bounds=await page.locator('#voice-command-summary').boundingBox();
      assert.ok(bounds&&bounds.y>=0&&bounds.y+bounds.height<=844,'Last heard/action feedback remains visible beside imagery at '+width);
      await assertClearRendererSurface(page,'voice-feedback-'+width);
    }
    for(const rendererUrl of ['http://projection.test/earth.html','javascript:alert(1)','https://name:password@projection.test/earth.html']){
      await page.evaluate(rendererUrl=>{window.projectionState.config.rendererUrl=rendererUrl;window.sendSnapshot();},rendererUrl);
      assert.equal(await page.locator('iframe').count(),0,'Unsafe renderer URL rejected: '+rendererUrl);
    }
    await page.close();
    assert.deepEqual(errors,[],'No uncaught browser errors');
    console.log('Projection UI passed: bounded one-shot full/reduced entrances, immediate voice and typed/spoken search, rapid close/reopen and lifecycle cleanup, real-time 390/768 stage evidence, clear loading/ready provider surfaces during full motion, five viewport sizes, both rooms, explicit place confirmation, reviewed userQuery directions with account entitlement, Google address attribution without a map, source safety, cost disclosure, save failure/success, visible idle/error microphone entry without auto-start, compact last-heard/action feedback, separate 44px Pause/Resume/Stop controls, explicit resume, cancellation of pending resume, stale reply protection, close/stop separation, renderer origin isolation, unobstructed provider surfaces while loading/ready and paused, separate provider popups, dock clearance with scroll preservation, and no credential transfer.');
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});
