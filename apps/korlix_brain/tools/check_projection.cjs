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
    window.testHoldPause = false;
    window.testHoldResume = false;
    window.testHoldStop = false;
    window.testGeocodingProvider = 'Test geocoder';
    window.projectionState = {
      open:true,room:'command',loading:false,selectedPlace:null,candidates:[],answer:null,notice:'',
      camera:{sequence:0,operation:'reset'},
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
      window.KorlixProjectionConnect({nonce:'test-session-nonce-123456789',snapshot:window.projectionState});
    });
  });
  await page.goto('file://' + path.join(app,'assets/web/projection.html'));
  await page.waitForFunction(()=>document.querySelector('#connection-label').textContent==='Your KORLIX workspace');
}

async function settleLayout(page) {
  await page.evaluate(()=>new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve))));
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
  // Window size and the active voice scrollport can resize the iframe. Wait for
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
    const active=!['complete','error'].includes(document.body.dataset.voice);
    const clip=active?shell.getBoundingClientRect():{top:0,height:innerHeight};
    const rect=frame.getBoundingClientRect();
    const change=rect.top-(clip.top+Math.max(8,(clip.height-rect.height)/2));
    if(active)shell.scrollTop+=change;
    else window.scrollBy(0,change);
  });
  await settleLayout(page);
}

async function assertClearRendererSurface(page,label,{activeVoice=false,capture=false}={}) {
  const geometry=await page.evaluate(()=>{
    const frame=document.querySelector('#map-container iframe'),stage=document.getElementById('scene-stage');
    const shell=document.querySelector('.projection-shell'),dock=document.querySelector('.voice-dock'),stop=document.getElementById('stop-button');
    const rect=frame.getBoundingClientRect(),button=stop.getBoundingClientRect();
    const selectors=['.scene-topline','.scene-heading','.map-badge','.world-caption','.camera-controls','.place-banner','.room-architecture','.scene-crosshair','#world-canvas','.voice-dock'];
    const points=[[rect.left+2,rect.top+2],[rect.right-2,rect.top+2],[rect.left+2,rect.bottom-2],[rect.right-2,rect.bottom-2],[rect.left+rect.width/2,rect.top+rect.height/2]];
    return {frame:rect.toJSON(),shell:shell.getBoundingClientRect().toJSON(),dock:dock.getBoundingClientRect().toJSON(),stop:button.toJSON(),
      width:innerWidth,height:innerHeight,phase:document.body.dataset.map,renderer:document.body.dataset.renderer,
      before:getComputedStyle(stage,'::before').content,after:getComputedStyle(stage,'::after').content,
      dockShadow:getComputedStyle(dock).boxShadow,
      riciShadow:getComputedStyle(document.querySelector('.rici-panel')).boxShadow,
      overlays:Object.fromEntries(selectors.map(selector=>{
        const element=document.querySelector(selector),style=getComputedStyle(element),box=element.getBoundingClientRect();
        return [selector,{visible:style.display!=='none'&&style.visibility!=='hidden'&&box.width>0&&box.height>0,rect:box.toJSON()}];
      })),
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
    const frame=geometry.frame;
    for(const [selector,overlay] of Object.entries(geometry.overlays)) {
      if(!overlay.visible)continue;
      const box=overlay.rect;
      const overlapWidth=Math.max(0,Math.min(frame.right,box.right)-Math.max(frame.left,box.left));
      const overlapHeight=Math.max(0,Math.min(frame.bottom,box.bottom)-Math.max(frame.top,box.top));
      assert.ok(overlapWidth*overlapHeight<.5,selector+' stays entirely outside the provider iframe at '+label);
    }
    const clip=activeVoice?geometry.shell:{top:0,bottom:geometry.height};
    assert.ok(frame.top>=clip.top&&frame.bottom<=clip.bottom,'Complete iframe can scroll into view at '+label);
    assert.ok(geometry.hits.every(hit=>hit.frame),'All iframe corners and its center remain hittable at '+label);
    if(activeVoice) {
      assert.ok(geometry.shell.bottom<=geometry.dock.top-10,'Scroll viewport ends above the active voice dock at '+label);
      assert.ok(frame.bottom<geometry.dock.top,'Voice dock never covers the provider surface at '+label);
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
    for(const [width,height] of [[320,850],[390,844],[768,1024],[1024,768],[1440,1000]]) {
      const page = await browser.newPage({viewport:{width,height},reducedMotion:'reduce'});
      page.on('pageerror',error=>errors.push(error.message));
      await fixture(page);
      assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1),false,'No horizontal overflow at '+width);
      assert.equal(await page.locator('#world-caption-text').textContent(),'Illustrative globe · connect a map provider to explore');
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

    const page = await browser.newPage({viewport:{width:1024,height:768},reducedMotion:'reduce'});
    page.on('pageerror',error=>errors.push(error.message));
    await page.context().route('https://provider-links.test/terms',route=>route.fulfill({contentType:'text/html; charset=utf-8',body:'<!doctype html><html><head><meta charset="utf-8"></head><body><h1>Provider link fixture</h1><form action="/accepted" method="get"><button type="submit">Continue fixture</button></form></body></html>'}));
    await page.context().route('https://provider-links.test/accepted**',route=>route.fulfill({contentType:'text/html; charset=utf-8',body:'<!doctype html><html><body><h1>Separate provider page accepted</h1></body></html>'}));
    await page.route('https://projection.test/brain-projection/earth.html',route=>route.fulfill({contentType:'text/html; charset=utf-8',body:`<!doctype html><html><head><meta charset="utf-8"><style>
      html,body{height:100%;margin:0;overflow:hidden;background:#142135;color:white;font:11px/1.5 system-ui}
      body{background:linear-gradient(140deg,#1b3245,#0c1729)}
      .provider-label{position:absolute;top:8px;left:8px;padding:6px;background:#031019}
      .provider-controls{position:absolute;top:8px;right:8px;display:flex;gap:4px}
      .provider-controls button{color:white;background:#273d50;border:1px solid #7191a3;padding:5px}
      #provider-attribution{position:absolute;left:0;right:0;bottom:0;padding:8px;background:#030b13;overflow-wrap:anywhere}a{color:#b3e1ff}
      </style></head><body><span class="provider-label">Provider surface fixture</span><div class="provider-controls"><button>Map control</button></div><div id="provider-attribution">Google Maps · Synthetic imagery supplied by Example City Survey Office; Example Regional Mapping Group; Example Geospatial Imagery Cooperative; Example Municipal Cartography Archive. Attribution fixture only; no real imagery is requested. <a id="provider-terms" href="https://provider-links.test/terms" target="_blank">Provider link fixture</a></div><script>
      window.received=[];window.addEventListener('message',e=>window.received.push(e.data));
      window.emitStatus=status=>{document.body.dataset.phase=status;parent.postMessage({type:'korlix-projection-status',status},'*');};
      window.emitCreditHeight=height=>parent.postMessage({type:'korlix-projection-credits',height},'*');
      window.emitStatus('loading');
      </script></body></html>`}));
    await fixture(page);
    await page.evaluate(()=>{
      window.projectionState.selectedPlace={id:'renderer-fixture',label:'Camera fixture',address:'Not a real location claim',latitude:40.71,longitude:-74,provider:'Test'};
      window.projectionState.camera={sequence:1,operation:'flyTo',latitude:40.71,longitude:-74,height:650,heading:0,pitch:-45};
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
    assert.equal(await renderer.evaluate(()=>window.received.length),0,'Camera commands wait for actual renderer readiness');
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
          await alignRendererInViewport(page);
          await assertClearRendererSurface(page,label);
          if(screenDirectory&&width<500&&phase==='ready')await page.screenshot({path:path.join(screenDirectory,`projection-map-layout-${room}-${width}.png`),fullPage:true});

          await page.evaluate(()=>{
            window.scrollBeforeVoice=scrollY;
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
          assert.equal(await page.evaluate(()=>Math.abs(scrollY-window.scrollBeforeStop)<1),true,'Stopping voice restores normal page scrolling at '+label);
        }
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
    console.log('Projection UI passed: five viewport sizes, both rooms, explicit place confirmation, reviewed userQuery directions with account entitlement, Google address attribution without a map, source safety, cost disclosure, save failure/success, separate 44px Pause/Resume/Stop controls, explicit resume, cancellation of pending resume, stale reply protection, close/stop separation, renderer origin isolation, unobstructed provider surfaces while loading/ready and paused, separate provider popups, dock clearance with scroll preservation, and no credential transfer.');
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});
