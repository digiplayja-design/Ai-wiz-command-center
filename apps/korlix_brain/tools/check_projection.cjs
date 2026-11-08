const assert = require('node:assert/strict');
const path = require('node:path');
const fs = require('node:fs');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const app = path.resolve(__dirname,'..');
const screenDirectory = process.env.PROJECTION_SCREENSHOTS;

async function fixture(page) {
  await page.addInitScript(() => {
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
    window.testHoldStop = false;
    window.projectionState = {
      open:true,room:'command',loading:false,selectedPlace:null,candidates:[],answer:null,notice:'',
      camera:{sequence:0,operation:'reset'},
      config:{rendererUrl:null,mapAvailable:false,geocodingAvailable:true,answersAvailable:true,answerCredits:4,answerCostLabel:'4 credits per successful sourced lookup.'},
      voice:{active:false,phase:'complete',message:'Ready when you are'}
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
            {id:'fixture-a',label:'First destination candidate',address:'A location fixture for UI testing',latitude:40.71,longitude:-74,provider:'Test geocoder'},
            {id:'fixture-b',label:'Second destination candidate',address:'A different location fixture for UI testing',latitude:40.72,longitude:-73.98,provider:'Test geocoder',partialMatch:true}
          ];
          state.notice='Choose a matching destination to confirm.'; window.sendSnapshot(); return reply({requiresConfirmation:true});
        case 'select':
          state.selectedPlace=state.candidates.find(place=>place.id===command.payload.placeId); state.candidates=[]; state.answer=null;
          state.camera={sequence:state.camera.sequence+1,operation:'flyTo',latitude:state.selectedPlace.latitude,longitude:state.selectedPlace.longitude,height:800};
          state.notice='Destination confirmed.'; window.sendSnapshot(); return reply({selected:true});
        case 'ask':
          if(/\b(live|real[ -]?time)\b.*\b(view|camera|feed|video|imagery)\b/i.test(command.payload.question)){
            state.answer={text:'There is no connected, permitted live camera for this place. Earth imagery is recorded, not a live feed.',sources:[],isLive:false};
            window.sendSnapshot();return reply({isLive:false,local:true});
          }
          window.testResearchCalls++;
          state.answer={text:'This is a sourced response fixture, not a claim about a real place. [1]',scope:'Confirmed destination',date:'2026-11-07',sources:[{title:'Test source',url:'https://example.com/source',date:'2026-11-07'}]};
          window.sendSnapshot(); return reply({answered:true});
        case 'camera': state.camera={...state.camera,sequence:state.camera.sequence+1,operation:command.payload.operation}; window.sendSnapshot(); return reply({moved:true});
        case 'savePlace':
          if(window.testFailSave)return reply(null,'Storage is unavailable. Your note has not been saved.');
          if(window.testSaveResponse==='null')return reply(null);
          if(window.testSaveResponse==='undefined')return reply(undefined);
          if(window.testSaveResponse==='missing')return reply({ok:true});
          if(window.testSaveResponse==='false')return reply({saved:false});
          return reply({saved:true});
        case 'startVoice':
          if(window.testHoldStart)return;
          state.voice={active:true,phase:'listening',message:'Rici is listening'}; window.sendSnapshot(); return reply({active:true});
        case 'stopVoice':
          if(window.testHoldStop)return;
          state.voice={active:false,phase:'complete',message:'Microphone off'}; window.sendSnapshot(); return reply({active:false});
        default:return reply({ok:true});
      }
    }};
    document.addEventListener('DOMContentLoaded',()=>{
      window.KorlixProjectionConnect({nonce:'test-session-nonce-123456789',snapshot:window.projectionState});
    });
  });
  await page.goto('file://' + path.join(app,'assets/web/projection.html'));
  await page.waitForFunction(()=>document.querySelector('#connection-label').textContent==='Your KORLIX workspace');
}

async function settleLayout(page) {
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
}

async function settleRendererLayout(page,renderer,label) {
  // A credit resize crosses two documents: iframe ResizeObserver -> postMessage
  // -> scene height -> iframe viewport. Parent animation frames alone do not
  // establish that the child has received its new viewport size.
  let previous='',last;
  const deadline=Date.now()+5000;
  while(Date.now()<deadline) {
    await settleLayout(page);
    const child=await renderer.evaluate(()=>({width:innerWidth,height:innerHeight,
      footer:document.getElementById('map-credits').getBoundingClientRect().toJSON()}));
    const parent=await page.evaluate(()=>{
      const frame=document.querySelector('#map-container iframe'),stage=document.getElementById('scene-stage');
      return {width:frame.clientWidth,height:frame.clientHeight,
        reserved:parseFloat(getComputedStyle(stage).getPropertyValue('--map-credit-height'))};
    });
    last={label,parent,child};
    const signature=JSON.stringify({parent,width:child.width,height:child.height,footer:child.footer});
    const agrees=Math.abs(parent.width-child.width)<=1&&Math.abs(parent.height-child.height)<=1&&
      parent.reserved===Math.ceil(child.footer.height)&&child.footer.top>=0&&child.footer.bottom<=child.height+1;
    if(agrees&&signature===previous)return;
    previous=signature;
  }
  if(screenDirectory)await page.screenshot({path:path.join(screenDirectory,`projection-layout-failure-${label}.png`)});
  throw new Error('Renderer layout did not settle: '+JSON.stringify(last));
}

(async()=>{
  const browser = await chromium.launch({headless:true,executablePath:process.env.BROWSER_EXECUTABLE_PATH||undefined,args:['--no-sandbox','--disable-dev-shm-usage']});
  const errors=[];
  try {
    for(const [width,height] of [[320,850],[390,844],[768,1024],[1024,768],[1440,1000]]) {
      const page = await browser.newPage({viewport:{width,height},reducedMotion:'reduce'});
      page.on('pageerror',error=>errors.push(error.message));
      await fixture(page);
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1),false,'No horizontal overflow at '+width);
      assert.equal(await page.locator('#world-caption-text').textContent(),'Illustrative globe · connect a map provider to explore');
      assert.equal(await page.evaluate(()=>window.projectionCommands.some(c=>c.action==='startVoice')),false,'Opening must not start a second conversation');
      assert.equal(await page.locator('#talk-button').isEnabled(),true);
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
      assert.equal(await page.locator('.candidate-button').last().locator('.partial-match-warning').textContent(),'Check address — partial match','Partial geocoder matches must be disclosed before selection');
      assert.equal(await page.locator('#place-banner').isVisible(),false,'No automatic travel before explicit confirmation');
      assert.equal(await page.evaluate(()=>window.projectionCommands.some(c=>c.action==='select')),false);
      await page.locator('.candidate-button').last().click();
      await page.locator('#place-banner').waitFor();
      assert.equal(await page.locator('#place-label').textContent(),'Second destination candidate');
      assert.equal(await page.locator('#place-match').isVisible(),true,'The partial-match warning survives selection');
      assert.equal(await page.locator('#place-match').textContent(),'Check address — partial match');
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
      await page.locator('#close-projection').click();
      assert.equal(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='close').length),1);
      assert.equal(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='stopVoice').length),0,'Closing projection does not stop the existing voice session');
      await page.locator('#stop-button').click();
      await page.waitForFunction(()=>document.querySelector('#voice-phase').textContent==='Microphone off');
      assert.equal(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='stopVoice').length),1);
      assert.equal(await page.evaluate(()=>window.projectionCommands.every(c=>/^\d+$/.test(c.id)&&c.nonce==='test-session-nonce-123456789')),true,'Every bridge command carries the session nonce and decimal ID');

      await page.evaluate(()=>{
        window.projectionState.answer={text:'<img src=x onerror=alert(1)>',sources:[{title:'Unsafe source',url:'javascript:alert(1)'}]};window.sendSnapshot();
      });
      assert.equal(await page.locator('#answer-text img').count(),0,'Research is text, never injected HTML');
      assert.equal(await page.locator('#answer-sources').isVisible(),false,'Non-HTTPS source links are rejected');
      await page.close();
    }

    const page = await browser.newPage({viewport:{width:1024,height:768},reducedMotion:'reduce'});
    page.on('pageerror',error=>errors.push(error.message));
    await page.route('https://projection.test/brain-projection/earth.html',route=>route.fulfill({contentType:'text/html',body:`<!doctype html><html><head><style>
      html,body{height:100%;margin:0;overflow:hidden;background:#142135;color:white;font:11px/1.5 system-ui}
      #map-credits{position:absolute;left:0;right:0;bottom:0;padding:8px;background:#030b13;overflow-wrap:anywhere}
      </style></head><body>Map renderer fixture<div id="map-credits">Google Maps · Synthetic imagery supplied by Example City Survey Office; Example Regional Mapping Group; Example Geospatial Imagery Cooperative; Example Municipal Cartography Archive; Example Terrain Survey Partnership; Example Geographic Data Consortium. Attribution fixture only; no real imagery is requested.</div><script>
      window.received=[];window.addEventListener('message',e=>window.received.push(e.data));
      window.emitStatus=status=>parent.postMessage({type:'korlix-projection-status',status},'*');
      window.emitCreditHeight=height=>parent.postMessage({type:'korlix-projection-credits',height},'*');
      window.publishCredits=()=>{if(!window.pauseCreditReports)window.emitCreditHeight(Math.ceil(document.getElementById('map-credits').getBoundingClientRect().height));};
      new ResizeObserver(window.publishCredits).observe(document.getElementById('map-credits'));
      window.addEventListener('resize',window.publishCredits);window.emitStatus('ready');window.publishCredits();
      </script></body></html>`}));
    await fixture(page);
    await page.evaluate(()=>{
      window.projectionState.selectedPlace={id:'renderer-fixture',label:'Camera fixture',address:'Not a real location claim',latitude:40.71,longitude:-74,provider:'Test'};
      window.projectionState.camera={sequence:1,operation:'flyTo',latitude:40.71,longitude:-74,height:650,heading:0,pitch:-45};
      window.projectionState.config={...window.projectionState.config,mapAvailable:true,rendererUrl:'https://projection.test/brain-projection/earth.html'};window.sendSnapshot();
    });
    await page.waitForFunction(()=>document.body.dataset.map==='ready');
    assert.equal(await page.locator('#map-container').isVisible(),true);
    assert.equal(await page.locator('#world-canvas').isVisible(),false);
    const renderer = page.frames().find(frame=>frame.url().startsWith('https://projection.test/'));
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

    await settleLayout(page);
    const creditHeightBefore=await page.evaluate(()=>document.getElementById('scene-stage').style.getPropertyValue('--map-credit-height'));
    const nativeCommandsBefore=await page.evaluate(()=>window.projectionCommands.length);
    await page.evaluate(()=>{
      window.dispatchEvent(new MessageEvent('message',{origin:'https://projection.test',source:window,data:{type:'korlix-projection-credits',height:250}}));
      window.dispatchEvent(new MessageEvent('message',{origin:'https://attacker.test',source:document.querySelector('iframe').contentWindow,data:{type:'korlix-projection-credits',height:250}}));
    });
    await renderer.evaluate(()=>{
      window.pauseCreditReports=true;
      for(const height of [-1,1.5,'80',NaN,Infinity,null,{},4097,1000000])window.emitCreditHeight(height);
    });
    await settleLayout(page);
    assert.equal(await page.evaluate(()=>document.getElementById('scene-stage').style.getPropertyValue('--map-credit-height')),creditHeightBefore,'Forged source/origin or malformed/unbounded credit geometry cannot move shell controls');
    await renderer.evaluate(()=>window.emitCreditHeight(4096));
    await page.waitForFunction(()=>parseFloat(document.getElementById('scene-stage').style.getPropertyValue('--map-credit-height'))===innerHeight);
    assert.equal(await page.evaluate(()=>window.projectionCommands.length),nativeCommandsBefore,'Public geometry never becomes a native command or changes readiness');
    await renderer.evaluate(()=>{window.pauseCreditReports=false;window.publishCredits();});
    await settleLayout(page);

    for(const width of [320,390,1024]) {
      await page.setViewportSize({width,height:844});
      for(const room of ['command','discovery']) {
        await page.locator('#room-'+room).click();
        await settleRendererLayout(page,renderer,`${room}-${width}`);
        const footer=await renderer.evaluate(()=>document.getElementById('map-credits').getBoundingClientRect().toJSON());
        const iframe=await page.locator('#map-container iframe').boundingBox();
        const geometry=await page.evaluate(()=>{
          const stage=document.getElementById('scene-stage');
          const selectors=['.world-caption','.camera-controls','.place-banner','.room-architecture','.scene-crosshair','.scene-topline'];
          return {reserved:parseFloat(getComputedStyle(stage).getPropertyValue('--map-credit-height')),
            base:parseFloat(getComputedStyle(stage).getPropertyValue('--scene-height')),stage:stage.getBoundingClientRect().toJSON(),
            afterBottom:parseFloat(getComputedStyle(stage,'::after').bottom),beforeBottom:parseFloat(getComputedStyle(stage,'::before').bottom),
            overlays:Object.fromEntries(selectors.map(selector=>[selector,document.querySelector(selector).getBoundingClientRect().toJSON()]))};
        });
        assert.ok(footer.height>30,'Fixture uses genuinely wrapped attribution at '+width);
        assert.equal(geometry.reserved,Math.ceil(footer.height),'Entire measured attribution receives room at '+width+' / '+room);
        assert.ok(geometry.stage.height>=geometry.base+geometry.reserved-1,'Footer space does not shrink the map/control area');
        const footerTop=iframe.y+footer.top;
        for(const [name,box] of Object.entries(geometry.overlays)) {
          assert.ok(box.bottom<=footerTop+1,name+' stays out of provider credits at '+width+' / '+room);
        }
        assert.ok(geometry.afterBottom>=geometry.reserved,'Vignette excludes provider footer');
        if(room==='discovery')assert.ok(geometry.beforeBottom>=geometry.reserved,'Discovery frame excludes provider footer');
        if(screenDirectory&&width<500)await page.screenshot({path:path.join(screenDirectory,`projection-attribution-${room}-${width}.png`),fullPage:true});

        await page.evaluate(()=>{
          const stage=document.getElementById('scene-stage');
          window.scrollTo(0,Math.max(0,stage.getBoundingClientRect().bottom+scrollY-innerHeight+40));
          window.scrollBeforeVoice=scrollY;
          window.projectionState.voice={active:true,phase:'listening',message:'Rici is listening'};window.sendSnapshot();
        });
        assert.equal(await page.evaluate(()=>Math.abs(document.querySelector('.projection-shell').scrollTop-window.scrollBeforeVoice)<1),true,'Starting voice preserves the reading position in the reserved scroll viewport');
        // Activating the bounded scroll viewport can add a scrollbar and wrap
        // credits again. Align only after both documents agree on that layout.
        await settleRendererLayout(page,renderer,`active-${room}-${width}`);
        await page.evaluate(()=>{
          const shell=document.querySelector('.projection-shell');
          shell.scrollTop+=document.getElementById('scene-stage').getBoundingClientRect().bottom-shell.getBoundingClientRect().bottom+12;
        });
        await settleRendererLayout(page,renderer,`aligned-${room}-${width}`);
        const active=await page.evaluate(()=>{
          const shell=document.querySelector('.projection-shell'),dock=document.querySelector('.voice-dock'),stop=document.getElementById('stop-button');
          const button=stop.getBoundingClientRect();
          return {shell:shell.getBoundingClientRect().toJSON(),dock:dock.getBoundingClientRect().toJSON(),stop:button.toJSON(),
            scrollTop:shell.scrollTop,scrollHeight:shell.scrollHeight,clientHeight:shell.clientHeight,windowScroll:scrollY,
            reservedCredits:parseFloat(getComputedStyle(document.getElementById('scene-stage')).getPropertyValue('--map-credit-height')),
            stopHittable:document.elementFromPoint(button.x+button.width/2,button.y+button.height/2)?.closest('#stop-button')===stop};
        });
        const activeFrame=await page.locator('#map-container iframe').boundingBox();
        const activeFooter=await renderer.evaluate(()=>document.getElementById('map-credits').getBoundingClientRect().toJSON());
        const diagnostic={width,room,active,activeFrame,activeFooter,
          absoluteFooter:{top:activeFrame.y+activeFooter.top,bottom:activeFrame.y+activeFooter.bottom}};
        if(screenDirectory) {
          await page.screenshot({path:path.join(screenDirectory,`projection-attribution-active-${room}-${width}.png`)});
          fs.writeFileSync(path.join(screenDirectory,`projection-attribution-geometry-${room}-${width}.json`),JSON.stringify(diagnostic,null,2));
        }
        try {
          assert.ok(active.shell.bottom<=active.dock.top-10,'Scroll viewport ends above the active voice dock at '+width+' / '+room);
          assert.ok(activeFrame.y+activeFooter.top>=active.shell.top&&activeFrame.y+activeFooter.bottom<=active.shell.bottom,'Full attribution can scroll into view without going behind the dock at '+width+' / '+room);
          assert.ok(activeFrame.y+activeFooter.bottom<active.dock.top,'Active voice dock never covers visible provider attribution at '+width+' / '+room);
          assert.ok(active.stop.y>=0&&active.stop.bottom<=844&&active.stopHittable,'Stop stays visible and hittable with wrapped credits at '+width+' / '+room);
        } catch(error) {
          console.error('Active attribution geometry:',JSON.stringify(diagnostic));
          throw error;
        }
        await page.evaluate(()=>{
          window.scrollBeforeStop=document.querySelector('.projection-shell').scrollTop;
          window.projectionState.voice={active:false,phase:'complete',message:'Microphone off'};window.sendSnapshot();
        });
        assert.equal(await page.evaluate(()=>Math.abs(scrollY-window.scrollBeforeStop)<1),true,'Stopping voice restores the same reading position to normal page scrolling');
      }
    }
    await page.locator('[data-camera="closer"]').click();
    await renderer.waitForFunction(()=>window.received.at(-1).camera.operation==='closer');
    await renderer.evaluate(()=>window.emitStatus('error'));
    await page.waitForFunction(()=>document.body.dataset.map==='illustration');
    assert.equal(await page.locator('#world-canvas').isVisible(),true,'Renderer failure returns to honest illustration');
    assert.equal(await page.evaluate(()=>window.projectionCommands.filter(c=>c.action==='rendererReady').at(-1).payload.status),'error','Renderer failure reaches native so voice cannot claim camera movement');
    for(const rendererUrl of ['http://projection.test/earth.html','javascript:alert(1)','https://name:password@projection.test/earth.html']){
      await page.evaluate(rendererUrl=>{window.projectionState.config.rendererUrl=rendererUrl;window.sendSnapshot();},rendererUrl);
      assert.equal(await page.locator('iframe').count(),0,'Unsafe renderer URL rejected: '+rendererUrl);
    }
    await page.close();
    assert.deepEqual(errors,[],'No uncaught browser errors');
    console.log('Projection UI passed: five viewport sizes, both rooms, explicit place confirmation, source safety, cost disclosure, save failure/success, voice continuity, duplicate-start prevention, close/stop separation, renderer origin isolation, bounded wrapping attribution, active-dock clearance with scroll preservation, and no credential transfer.');
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});
