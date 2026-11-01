
    (() => {
  const stage = document.getElementById('korlix-silent-storm');
  const root = stage.querySelector('.kb-product');
  const idPrefix = root.dataset.prefix;
  const get = (id) => root.querySelector('#' + idPrefix + id);
  const screens = [...root.querySelectorAll('[data-screen]')];
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let userPaused = reducedMotion.matches, motionOverride = false, currentScreen = 'home';
  let animationFrame = null, lastFrame = 0, energyClock = 0, lastPaletteRead = 0;
  let demoIndex = 3;
  const phases = [
    {key:'listening',label:'Rici is listening',duration:2800,speed:1.25},
    {key:'thinking',label:'Rici is thinking',duration:2200,speed:1.95},
    {key:'speaking',label:'Rici is speaking',duration:3800,speed:1.5},
    {key:'complete',label:'Microphone off',duration:0,speed:1}
  ];
  const menus = [...root.querySelectorAll('[data-orbit-target]')].map((element,index) => ({element,buttons:[...element.querySelectorAll('[data-entry]')],angle:-Math.PI/2+index*.35,radius:112,hover:false,focus:false,touch:false}));
  const scenes = [...root.querySelectorAll('[data-brain-canvas]')].map(canvas => ({canvas,context:canvas.getContext('2d'),screen:canvas.dataset.brainCanvas,width:0,height:0,dpr:1}));
  const palette = {flow:'',accent:'',core:'',gold:''};
    const app = root.querySelector('.kb-app');
  const voiceScene = get('kb-voice-scene');
  const voiceBars = [...voiceScene.querySelectorAll('.kb-voice-waves span')];
  const transferStage = get('kb-transfer-stage');
  const transferCanvas = get('kb-transfer-canvas');
  const transferContext = transferCanvas.getContext('2d');
  const transferGeometry = {width:0,height:0,dpr:1,start:[0,0],end:[0,0]};
  let inViewport = true, introQueued = !reducedMotion.matches;
  let introActive = false, introElapsed = 0, focusRequest = null, transferState = null;
  let voicePower = .15;
  const clamp = (x,min=0,max=1) => Math.max(min,Math.min(max,x));
  const smooth = x => {const t=clamp(x);return t*t*(3-2*t);};
  let appVisible = true;
  const welcome = {active:false, attempted:false, sequence:0, timer:null};
  const welcomeAudio = get('kb-welcome-audio');
  const welcomeKey = 'korlix-brain-welcome-v1-seen';
  function welcomeSeen(){try{return localStorage.getItem(welcomeKey)==='true';}catch(error){return false;}}
  function rememberWelcome(){try{localStorage.setItem(welcomeKey,'true');}catch(error){}}
  function welcomeUi(message){
    root.dataset.welcome=welcome.active?'playing':'idle';
    get('kb-welcome-controls').hidden=currentScreen!=='home';
    get('kb-welcome-status').textContent=message||'AI welcome from Rici';
    get('kb-welcome-play').hidden=welcome.active;
    get('kb-welcome-play').textContent=welcomeSeen()?'Replay welcome':'Play welcome';
    get('kb-welcome-play').disabled=musicCaptureActive();
    get('kb-welcome-skip').hidden=!welcome.active;
  }
  function stopWelcome(markSeen=true){
    const wasActive=welcome.active;
    welcome.sequence++;welcome.active=false;clearTimeout(welcome.timer);
    welcomeAudio.pause();welcomeAudio.currentTime=0;
    if(markSeen)rememberWelcome();
    welcomeUi();
    if(wasActive){music.idleUntil=performance.now()+3000;musicSession(false);refreshMusic();}
  }
  async function playWelcome(){
    if(musicCaptureActive()||currentScreen!=='home'||!musicVisible()||music.disposed)return;
    const sequence=++welcome.sequence;welcome.active=true;
    welcomeAudio.currentTime=0;welcomeAudio.volume=.9;
    welcomeUi('Rici is welcoming you…');musicSession(true);refreshMusic(.12);
    clearTimeout(welcome.timer);
    welcome.timer=setTimeout(()=>stopWelcome(),30000);
    try{
      await welcomeAudio.play();
      if(sequence!==welcome.sequence||musicCaptureActive()||!musicVisible()){
        if(!welcome.active)welcomeAudio.pause();
        return;
      }
      rememberWelcome();
    }catch(error){
      if(sequence!==welcome.sequence)return;
      stopWelcome(false);welcomeUi('Tap Play welcome to listen.');
    }
  }
  function maybeWelcome(){
    if(welcome.attempted)return;
    welcome.attempted=true;welcomeUi();
    if(!welcomeSeen())playWelcome();
  }
  welcomeAudio.addEventListener('ended',()=>stopWelcome());
  welcomeAudio.addEventListener('error',()=>{
    if(welcome.active){stopWelcome(false);welcomeUi('Welcome unavailable. You can keep using the app.');}
  });
  get('kb-welcome-play').addEventListener('click',playWelcome);
  get('kb-welcome-skip').addEventListener('click',()=>stopWelcome());

  const musicToggle = get('kb-music-toggle');
  const musicVolume = get('kb-music-volume');
  const musicStatus = get('kb-music-status');
  const music = {
    wanted:false, loading:false, needsTap:false, disposed:false,
    context:null, gain:null, analyser:null, source:null, buffer:null, decoding:null,
    volume:1, sequence:0, idleUntil:0, idleTimer:null, statusTimer:null,
    suspendTimer:null, removalTimer:null, hidden:false, autoSuspended:false,
    dictating:false, ownsPlaybackSession:false,
    ramp:{from:0,to:0,start:0,end:0}, samples:new Uint8Array(256), glow:0
  };

  function musicVisible(){return appVisible && !document.hidden && inViewport && root.isConnected;}
  function musicCaptureActive(){return root.dataset.voiceActive==='true'||music.dictating;}
  function musicSession(playback){
    // Web Audio otherwise uses iOS's ringer-muted ambient category. Release
    // our playback override before native voice/dictation takes the microphone.
    try{
      if(!navigator.audioSession)return;
      if(playback||(welcome.active&&!musicCaptureActive()&&musicVisible())){
        if(navigator.audioSession.type!=='playback')navigator.audioSession.type='playback';
        music.ownsPlaybackSession=true;
      }else if(music.ownsPlaybackSession){
        navigator.audioSession.type='auto';music.ownsPlaybackSession=false;
      }
    }catch(error){/* Older WebViews keep their normal audio behavior. */}
  }
  function pauseMusicForCapture(){
    clearTimeout(music.suspendTimer);
    music.loading=false;music.autoSuspended=true;
    rampMusic(0,0);musicSession(false);
    if(music.context&&music.context.state==='running')music.context.suspend().catch(()=>{});
  }
  function musicText(state,text){
    root.dataset.music=state;
    if(musicStatus.textContent!==text)musicStatus.textContent=text;
    musicToggle.setAttribute('aria-pressed',String(music.wanted));
    get('kb-music-label').textContent=music.wanted?(music.needsTap?'Resume ambience':music.loading?'Starting…':state==='quiet'?'Ambience · quiet':'Ambience on'):'Play ambience';
    musicToggle.setAttribute('aria-label',music.wanted?(music.needsTap?'Resume ambient music':'Pause ambient music'):'Play ambient music');
    get('kb-music-play-icon').hidden=music.wanted&&!music.needsTap;
    get('kb-music-stop-icon').hidden=!music.wanted||music.needsTap;
  }
  function musicGainNow(){
    if(!music.context)return 0;
    const r=music.ramp,t=music.context.currentTime;
    return r.end<=r.start||t>=r.end?r.to:r.from+(r.to-r.from)*clamp((t-r.start)/(r.end-r.start));
  }
  function rampMusic(to,seconds){
    if(!music.gain||!music.context||music.context.state==='closed')return;
    if(to===music.ramp.to)return;
    const now=music.context.currentTime,from=musicGainNow();
    music.gain.gain.cancelScheduledValues(now);
    music.gain.gain.setValueAtTime(from,now);
    music.gain.gain.linearRampToValueAtTime(to,now+seconds);
    music.ramp={from,to,start:now,end:now+seconds};
  }
  function clearMusicWait(){
    clearTimeout(music.idleTimer);clearTimeout(music.statusTimer);
    music.idleTimer=null;music.statusTimer=null;
  }
  function refreshMusic(fade=1.6){
    clearMusicWait();
    if(music.disposed)return;
    if(!music.wanted){musicText('off','Off · tap to listen');return;}
    if(!musicVisible()){musicText('paused','Paused in background');return;}
    if(musicCaptureActive()){
      pauseMusicForCapture();musicText('quiet','Paused while the microphone is in use');return;
    }
    if(welcome.active){rampMusic(0,.12);musicText('quiet','Quiet for Rici’s welcome');return;}
    if(music.loading){musicText('loading','Preparing the ambient bed…');return;}
    if(music.autoSuspended&&currentScreen==='home'&&music.context&&music.source){
      music.autoSuspended=false;playMusic();return;
    }
    if(music.needsTap||!music.context||music.context.state!=='running'){
      music.needsTap=true;musicText('paused','Tap to resume music');return;
    }
    if(!music.source)return;
    if(currentScreen!=='home'||performance.now()<music.idleUntil){
      rampMusic(0,.48);
      if(currentScreen!=='home')musicSession(false);
      const fading=musicGainNow()>.002;
      musicText('quiet',fading?'Fading for your action':currentScreen==='home'?'Returns after 3 seconds':'Quiet while you work');
      if(fading)music.statusTimer=setTimeout(()=>refreshMusic(),500);
      else if(currentScreen==='home')music.idleTimer=setTimeout(()=>refreshMusic(),Math.max(0,music.idleUntil-performance.now()));
      return;
    }
    musicSession(music.volume>0);rampMusic(music.volume/100,fade);
    musicText(music.volume?'playing':'quiet',music.volume?'Playing softly':'Muted · volume is at 0%');
  }
  function seamlessMusicBuffer(decoded){
    const context=music.context,overlap=Math.round(decoded.sampleRate*.45);
    if(decoded.length<overlap*4)return decoded;
    const length=decoded.length-overlap;
    const buffer=context.createBuffer(decoded.numberOfChannels,length,decoded.sampleRate);
    for(let channel=0;channel<decoded.numberOfChannels;channel++){
      const input=decoded.getChannelData(channel),output=buffer.getChannelData(channel);
      output.set(input.subarray(overlap));
      for(let i=0;i<overlap;i++){
        const mix=.5-.5*Math.cos(Math.PI*i/(overlap-1));
        output[length-overlap+i]=input[decoded.length-overlap+i]*(1-mix)+input[i]*mix;
      }
    }
    return buffer;
  }
  function decodeMusic(){
    if(music.buffer)return Promise.resolve(music.buffer);
    if(!music.decoding){
      const binary=atob(stage.querySelector('#kb-ambient-audio-data').textContent.trim());
      const bytes=new Uint8Array(binary.length);
      for(let i=0;i<binary.length;i++)bytes[i]=binary.charCodeAt(i);
      music.decoding=music.context.decodeAudioData(bytes.buffer).then(decoded=>{
        music.buffer=seamlessMusicBuffer(decoded);return music.buffer;
      }).catch(error=>{music.decoding=null;throw error;});
    }
    return music.decoding;
  }
  function watchMusicConnection(){
    clearTimeout(music.removalTimer);
    if(!music.wanted||music.disposed)return;
    music.removalTimer=setTimeout(()=>{
      if(!root.isConnected)disposeMusic();else watchMusicConnection();
    },1500);
  }
  async function playMusic(){
    const AudioEngine=window.AudioContext||window.webkitAudioContext;
    if(!AudioEngine){musicText('off','Audio is unavailable in this browser');return;}
    const request=++music.sequence;
    music.wanted=true;music.loading=true;music.needsTap=false;
    clearTimeout(music.suspendTimer);
    if(musicCaptureActive()){refreshMusic();return;}
    try{
      musicSession(currentScreen==='home'&&musicVisible());
      if(!music.context){
        music.context=new AudioEngine();music.gain=music.context.createGain();
        music.gain.gain.value=0;music.analyser=music.context.createAnalyser();
        music.analyser.fftSize=256;music.gain.connect(music.analyser);music.analyser.connect(music.context.destination);
        music.context.addEventListener('statechange',()=>{
          if(!music.loading&&music.wanted&&!music.disposed){
            if(music.context.state==='running')music.needsTap=false;
            refreshMusic();
          }
        });
      }
      // Resume inside the tap gesture; decode is local and never requests a microphone.
      const resume=music.context.resume();
      refreshMusic();watchMusicConnection();
      const results=await Promise.all([resume,decodeMusic()]);
      if(request!==music.sequence||!music.wanted||music.disposed)return;
      if(musicCaptureActive()){pauseMusicForCapture();refreshMusic();return;}
      if(!music.source){
        music.source=music.context.createBufferSource();music.source.buffer=results[1];
        music.source.loop=true;music.source.connect(music.gain);music.source.start();
      }
      music.loading=false;music.autoSuspended=false;
      music.needsTap=music.context.state!=='running';
      refreshMusic();
      if(!musicVisible())silenceMusicInBackground();
    }catch(error){
      if(request!==music.sequence||music.disposed)return;
      music.loading=false;music.wanted=false;rampMusic(0,.1);
      musicSession(false);
      musicText('off','Couldn’t start audio · tap to retry');
    }
  }
  function stopMusic(){
    music.sequence++;music.wanted=false;music.loading=false;music.needsTap=false;
    clearMusicWait();clearTimeout(music.suspendTimer);clearTimeout(music.removalTimer);
    rampMusic(0,.6);refreshMusic();
    musicSession(false);
    music.suspendTimer=setTimeout(()=>{
      if(!music.wanted&&music.context&&music.context.state==='running')music.context.suspend().catch(()=>{});
    },650);
    root.style.setProperty('--kb-music-glow','0');
  }
  function duckMusic(){
    if(!music.wanted)return;
    music.idleUntil=performance.now()+3000;refreshMusic();
  }
  function musicScreenChanged(){
    if(!music.wanted)return;
    if(currentScreen==='home')music.idleUntil=performance.now()+3000;
    refreshMusic();
  }
  function silenceMusicInBackground(){
    clearMusicWait();clearTimeout(music.suspendTimer);
    music.autoSuspended=true;rampMusic(0,.08);musicSession(false);
    if(music.wanted)musicText('paused','Paused in background');
    music.suspendTimer=setTimeout(()=>{
      if(!musicVisible()&&music.context&&music.context.state==='running')music.context.suspend().catch(()=>{});
    },110);
  }
  function musicEnvironmentChanged(){
    const hidden=!musicVisible();
    if(hidden===music.hidden)return;
    music.hidden=hidden;
    if(hidden){stopWelcome();silenceMusicInBackground();return;}
    clearTimeout(music.suspendTimer);
    if(!music.wanted)return;
    music.idleUntil=performance.now()+3000;
    if(musicCaptureActive()){refreshMusic();return;}
    if(currentScreen==='home'&&music.context&&music.autoSuspended&&!music.loading){
      music.autoSuspended=false;
      musicSession(true);
      music.context.resume().then(()=>{
        if(music.wanted&&!music.disposed){music.needsTap=music.context.state!=='running';refreshMusic();}
      }).catch(()=>{if(music.wanted){music.needsTap=true;refreshMusic();}});
    }else refreshMusic();
  }
  function tickMusicGlow(dt){
    let target=0;
    if(music.wanted&&music.analyser&&music.context.state==='running'&&currentScreen==='home'){
      music.analyser.getByteTimeDomainData(music.samples);
      let power=0;for(const sample of music.samples)power+=Math.pow((sample-128)/128,2);
      target=clamp(Math.sqrt(power/music.samples.length)*7,0,.65);
    }
    music.glow+=(target-music.glow)*Math.min(1,dt*4);
    root.style.setProperty('--kb-music-glow',music.glow.toFixed(3));
  }
  function disposeMusic(){
    if(music.disposed)return;
    music.disposed=true;music.wanted=false;music.sequence++;stopWelcome();
    musicSession(false);
    clearMusicWait();clearTimeout(music.suspendTimer);clearTimeout(music.removalTimer);
    if(music.source){try{music.source.stop();}catch(error){}}
    if(music.context&&music.context.state!=='closed')music.context.close().catch(()=>{});
  }
  function mountMusic(){
    const settings=get('kb-music-settings');
    const details=get('kb-music-details');
    try{
      const saved=localStorage.getItem('korlix-brain-ambience-volume');
      if(saved!==null&&/^\d{1,3}$/.test(saved))music.volume=clamp(Number(saved),0,100);
    }catch(error){}
    const showVolume=()=>{
      musicVolume.value=String(music.volume);
      get('kb-music-volume-value').textContent=music.volume+'%';
      get('kb-music-level').textContent=music.volume+'%';
      settings.setAttribute('aria-label','Volume controls, '+music.volume+' percent');
      musicVolume.setAttribute('aria-valuetext',music.volume+' percent');
    };
    showVolume();
    settings.addEventListener('click',()=>{
      details.hidden=!details.hidden;
      settings.setAttribute('aria-expanded',String(!details.hidden));
      settings.closest('.kb-audio-controls').dataset.expanded=String(!details.hidden);
    });
    settings.closest('.kb-audio-controls').addEventListener('keydown',event=>{
      if(event.key==='Escape'&&!details.hidden){
        details.hidden=true;settings.setAttribute('aria-expanded','false');
        settings.closest('.kb-audio-controls').dataset.expanded='false';settings.focus();
      }
    });
    musicToggle.addEventListener('click',()=>{
      if(music.wanted&&!music.needsTap)stopMusic();else playMusic();
    });
    musicVolume.addEventListener('input',()=>{
      music.volume=clamp(Number(musicVolume.value),0,100);
      try{localStorage.setItem('korlix-brain-ambience-volume',String(music.volume));}catch(error){}
      showVolume();refreshMusic(.18);
    });
    stage.addEventListener('click',event=>{
      const button=event.target.closest('button');
      if(button&&!button.closest('.kb-audio-controls'))duckMusic();
    },true);
    window.addEventListener('pagehide',disposeMusic);
  }

  // Silent, sustained lightning across the full app; one existing animation loop.
  const lightningCanvas = get('kb-storm-canvas');
  const lightningContext = lightningCanvas.getContext('2d');
  const lightningPreview = document.createElement('button');
  const lightning = {
    wait:2.2+Math.random()*1.5, age:0, duration:0, paths:null, cooldown:0,
    width:0, height:0, dpr:1, drawn:false
  };
  function measureLightning(){
    const width=app.clientWidth,height=app.clientHeight;
    if(!width||!height)return;
    const dpr=Math.min(window.devicePixelRatio||1,1.5);
    if(width!==lightning.width||height!==lightning.height||dpr!==lightning.dpr){
      lightning.width=width;lightning.height=height;lightning.dpr=dpr;
      lightningCanvas.width=Math.round(width*dpr);
      lightningCanvas.height=Math.round(height*dpr);
      lightning.drawn=false;
      if(lightning.paths)drawLightning();
    }
  }
  function stormFracture(anchors,roughness){
    const width=lightning.width,height=lightning.height,result=[];
    for(let segment=1;segment<anchors.length;segment++){
      let points=[anchors[segment-1],anchors[segment]];
      for(let level=0;level<4;level++){
        const next=[points[0]];
        for(let i=1;i<points.length;i++){
          const a=points[i-1],b=points[i],dx=(b[0]-a[0])*width,dy=(b[1]-a[1])*height;
          const length=Math.hypot(dx,dy)||1;
          const offset=(Math.random()-.5)*roughness*width*Math.pow(.53,level);
          next.push([
            clamp((a[0]+b[0])/2-dy/length*offset/width,-.02,1.02),
            clamp((a[1]+b[1])/2+dx/length*offset/height,-.02,1.02)
          ],b);
        }
        points=next;
      }
      result.push(...points.slice(segment===1?0:1));
    }
    return result;
  }
  function startLightning(){
    if(paused()||currentScreen!=='home'||lightning.paths||lightning.cooldown>0||!lightningContext)return false;
    measureLightning();
    if(!lightning.width||!lightning.height)return false;
    const mirror=Math.random()<.5;
    const flip=p=>[mirror?1-p[0]:p[0],p[1]];
    const primary=stormFracture([
      [.14+Math.random()*.18,-.015], [.69,.17], [.33,.34],
      [.73,.52], [.28,.73], [.78+Math.random()*.14,1.015]
    ].map(flip),.26);
    const secondary=stormFracture([
      [.97,.035],[.77,.21],[.91,.43],[.65,.69],[.94,.98]
    ].map(flip),.14);
    const paths=[
      {points:primary,weight:1,delay:0,travel:.2},
      {points:secondary,weight:.58,delay:.12,travel:.25}
    ];
    for(let i=0;i<8;i++){
      const index=Math.round((.12+i*.095)*(primary.length-1));
      const origin=primary[index],right=i%2===0;
      const tip=[right?1.025:-.025,clamp(origin[1]+.08+Math.random()*.11,.04,.98)];
      const branch=stormFracture([origin,[(origin[0]+tip[0])*.5,origin[1]+.035],tip],.15);
      const delay=.1+i*.025;
      paths.push({points:branch,weight:.34+Math.random()*.14,delay,travel:.2});
      const fork=branch[Math.floor(branch.length*.52)];
      const twigEnd=[clamp(fork[0]+(right?.17:-.17),.015,.985),clamp(fork[1]-.08,.02,.96)];
      paths.push({points:stormFracture([fork,twigEnd],.065),weight:.18,delay:delay+.09,travel:.18});
    }
    lightning.paths=paths;lightning.age=0;lightning.duration=3.1+Math.random()*.5;
    lightning.cooldown=lightning.duration+.7;lightning.wait=8+Math.random()*8;
    root.dataset.lightning='strike';drawLightning();return true;
  }
  function wipeLightning(){
    if(lightningContext&&lightning.drawn){
      lightningContext.setTransform(lightning.dpr,0,0,lightning.dpr,0,0);
      lightningContext.clearRect(0,0,lightning.width,lightning.height);
    }
    lightning.drawn=false;root.style.setProperty('--kb-storm-power','0');
  }
  function clearLightning(){
    lightning.paths=null;lightning.age=0;root.dataset.lightning='idle';
    lightningPreview.disabled=paused();wipeLightning();
  }
  function traceLightning(points,progress){
    const ctx=lightningContext,limit=Math.max(1,Math.ceil((points.length-1)*clamp(progress)));
    ctx.beginPath();
    for(let i=0;i<=limit;i++){
      const p=points[Math.min(i,points.length-1)],x=p[0]*lightning.width,y=p[1]*lightning.height;
      if(i)ctx.lineTo(x,y);else ctx.moveTo(x,y);
    }
  }
  function drawLightning(){
    if(!lightningContext||!lightning.paths||paused()||currentScreen!=='home')return;
    const ctx=lightningContext,age=lightning.age;
    const attack=smooth(age/.12),fade=1-smooth((age-1.35)/(lightning.duration-1.35));
    const envelope=attack*fade,scale=clamp(lightning.width/430,.72,1.15);
    ctx.setTransform(lightning.dpr,0,0,lightning.dpr,0,0);
    ctx.clearRect(0,0,lightning.width,lightning.height);lightning.drawn=true;
    ctx.save();ctx.lineCap='round';ctx.lineJoin='round';
    for(const path of lightning.paths){
      const local=age-path.delay;if(local<=0)continue;
      const reach=smooth(local/path.travel),strength=envelope*smooth(local/.1);
      traceLightning(path.points,reach);
      ctx.strokeStyle=palette.flow;ctx.shadowColor=palette.flow;
      ctx.lineWidth=19*scale*path.weight;ctx.shadowBlur=28*scale;
      ctx.globalAlpha=.11*strength;ctx.stroke();
      ctx.strokeStyle=palette.lightning;ctx.shadowColor=palette.lightning;
      ctx.lineWidth=7*scale*path.weight;ctx.shadowBlur=15*scale;
      ctx.globalAlpha=.45*strength;ctx.stroke();
      ctx.lineWidth=3.7*scale*path.weight;ctx.shadowBlur=4*scale;
      ctx.globalAlpha=.95*strength;ctx.stroke();
      ctx.strokeStyle=palette.core;ctx.lineWidth=Math.max(.45,1.65*scale*path.weight);
      ctx.shadowBlur=0;ctx.globalAlpha=.96*strength;ctx.stroke();
    }
    // Two bright currents travel down the main bolt while its branches hold.
    if(age>.2&&age<2.6){
      const points=lightning.paths[0].points;
      for(const offset of [0,.42]){
        const progress=((age-.2)*.48+offset)%1;
        const index=Math.floor(progress*(points.length-1));
        const tail=Math.max(0,index-6),strand=points.slice(tail,index+1);
        if(strand.length<2)continue;
        traceLightning(strand,1);ctx.strokeStyle=palette.core;
        ctx.lineWidth=2.2*scale;ctx.shadowColor=palette.lightning;ctx.shadowBlur=10*scale;
        ctx.globalAlpha=.82*envelope;ctx.stroke();
      }
    }
    ctx.restore();root.style.setProperty('--kb-storm-power',(envelope*.65).toFixed(3));
  }
  function tickLightning(dt){
    if(currentScreen!=='home')return;
    lightning.cooldown=Math.max(0,lightning.cooldown-dt);
    if(lightning.paths){
      lightning.age+=dt;
      if(lightning.age>=lightning.duration){lightning.paths=null;root.dataset.lightning='idle';wipeLightning();}
      else drawLightning();
    }else if(!introActive&&!focusRequest){
      lightning.wait-=dt;if(lightning.wait<=0)startLightning();
    }
  }
  lightningPreview.addEventListener('click',()=>{
    if(paused())return;
    if(currentScreen!=='home')show('home');
    finishIntro();startLightning();syncAnimation();
  });

  function bootStep(name,value){root.style.setProperty('--kb-boot-'+name,String(value));}
  function drawIntro(){
    const t=introElapsed;
    bootStep('brain',.12+.88*smooth(t/.65));
    bootStep('reveal',((1-smooth((t-.12)/.95))*100).toFixed(2)+'%');
    bootStep('flow',smooth((t-.3)/.65));
    bootStep('halo',Math.sin(clamp((t-.2)/1.8)*Math.PI)*.85);
    for(const [name,start] of [['talk',1.05],['train',1.28],['memory',1.5],['vault',1.72]])bootStep(name,.12+.88*smooth((t-start)/.34));
  }
  function finishIntro(){
    introActive=false;introQueued=false;root.dataset.boot='ready';
    get('kb-startup-status').textContent='Your brain is ready';
  }
  function startIntro(explicit=false){
    clearFocus(false);
    if(currentScreen!=='home')show('home');
    introQueued=false;
    if(explicit){userPaused=false;motionOverride=true;}
    if(paused()||(reducedMotion.matches&&!motionOverride)){finishIntro();syncMotion();return;}
    introElapsed=0;introActive=true;root.dataset.boot='running';
    get('kb-startup-status').textContent='Activating your brain';
    drawIntro();syncMotion();
  }
  function clearFocus(run){
    const request=focusRequest;focusRequest=null;root.dataset.focus='off';
    root.querySelectorAll('.kb-focused-chip').forEach(el=>el.classList.remove('kb-focused-chip'));
    root.querySelectorAll('.kb-focus-group').forEach(el=>el.classList.remove('kb-focus-group'));
    if(run&&request)request.callback();
  }
  function cinematicNavigate(button,callback){
    finishIntro();clearFocus(false);
    if(paused()||currentScreen!=='home'){callback();return;}
    focusRequest={elapsed:0,callback};root.dataset.focus='on';
    button.classList.add('kb-focused-chip');
    const group=button.closest('[data-orbit-target]');if(group)group.classList.add('kb-focus-group');
    syncAnimation();
  }
  function resetDepth(){
    app.style.setProperty('--kb-tilt-x','0deg');app.style.setProperty('--kb-tilt-y','0deg');
    app.style.setProperty('--kb-chip-drift-x','0px');app.style.setProperty('--kb-chip-drift-y','0px');
  }
  function moveDepth(event){
    if(paused()||currentScreen==='transfer'||introActive||focusRequest)return;
    if(event.pointerType==='touch'&&!event.buttons)return;
    const box=app.getBoundingClientRect();if(!box.width||!box.height)return;
    const x=clamp((event.clientX-box.left)/box.width*2-1,-1,1);
    const y=clamp((event.clientY-box.top)/Math.min(box.height,700)*2-1,-1,1);
    app.style.setProperty('--kb-tilt-x',(-y*2.7).toFixed(2)+'deg');
    app.style.setProperty('--kb-tilt-y',(x*3.4).toFixed(2)+'deg');
    app.style.setProperty('--kb-chip-drift-x',(x*1.4).toFixed(2)+'px');
    app.style.setProperty('--kb-chip-drift-y',(y*.8).toFixed(2)+'px');
  }
  function updateVoiceLight(dt){
    if(currentScreen!=='talk')return;
    const phase=phases[demoIndex].key;
    let target=.15;
    if(phase==='listening')target=.22+.1*(.5+.5*Math.sin(energyClock*3));
    if(phase==='thinking')target=.35+.12*(.5+.5*Math.sin(energyClock*2));
    if(phase==='speaking')target=.3+.55*Math.abs(Math.sin(energyClock*7.4)*Math.cos(energyClock*2.7));
    voicePower+= (target-voicePower)*Math.min(1,dt?dt*12:1);
    voiceScene.style.setProperty('--kb-voice-power',voicePower.toFixed(3));
    voiceBars.forEach((bar,index)=>{
      const wave=phase==='complete'?.18:clamp(voicePower*(.55+.65*Math.abs(Math.sin(energyClock*5+index*.8))),.15,1);
      bar.style.transform='scaleY('+wave.toFixed(3)+')';
    });
  }
  function measureTransfer(){
    if(currentScreen!=='transfer')return;
    const box=transferStage.getBoundingClientRect();if(!box.width||!box.height)return;
    const chip=get('kb-transfer-chip').getBoundingClientRect();
    const brain=transferStage.querySelector('.kb-grand-brain').getBoundingClientRect();
    transferGeometry.width=box.width;transferGeometry.height=box.height;
    transferGeometry.dpr=Math.min(window.devicePixelRatio||1,2);
    transferGeometry.start=[chip.left-box.left+chip.width/2,chip.top-box.top+10];
    transferGeometry.end=[brain.left-box.left+brain.width*.53,brain.top-box.top+brain.height*.46];
    transferCanvas.width=Math.round(box.width*transferGeometry.dpr);
    transferCanvas.height=Math.round(box.height*transferGeometry.dpr);
    drawTransfer();
  }
  function transferPoint(t,lane){
    const [x0,y0]=transferGeometry.start,[x3,y3]=transferGeometry.end;
    const spread=48+lane*13,sign=lane%2?-1:1;
    const x1=x0+sign*spread,y1=y0-(y0-y3)*.25;
    const x2=x3-sign*spread*.7,y2=y3+(y0-y3)*.25;
    const u=1-t;
    return [u*u*u*x0+3*u*u*t*x1+3*u*t*t*x2+t*t*t*x3,u*u*u*y0+3*u*u*t*y1+3*u*t*t*y2+t*t*t*y3];
  }
  function drawTransfer(){
    const ctx=transferContext,g=transferGeometry;if(!ctx||!g.width||!g.height)return;
    ctx.setTransform(g.dpr,0,0,g.dpr,0,0);ctx.clearRect(0,0,g.width,g.height);
    if(!transferState)return;
    const time=transferState.elapsed;
    ctx.save();ctx.lineCap='round';
    if(time<1.9){
      for(let lane=0;lane<3;lane++){
        ctx.globalAlpha=.12*(1-smooth((time-1.3)/.6));ctx.strokeStyle=lane===1?palette.flow:palette.gold;ctx.lineWidth=.65;ctx.beginPath();
        for(let i=0;i<=40;i++){const p=transferPoint(i/40,lane);if(i)ctx.lineTo(p[0],p[1]);else ctx.moveTo(p[0],p[1]);}ctx.stroke();
      }
      for(let index=0;index<14;index++){
        const progress=(time-.08-index*.034)/1.12;if(progress<0||progress>1)continue;
        const lane=index%3,t=smooth(progress),head=transferPoint(t,lane),tail=transferPoint(Math.max(0,t-.065),lane);
        const color=index%4===0?palette.flow:palette.gold;
        const gradient=ctx.createLinearGradient(tail[0],tail[1],head[0],head[1]);gradient.addColorStop(0,'transparent');gradient.addColorStop(1,color);
        ctx.globalAlpha=.92;ctx.strokeStyle=gradient;ctx.lineWidth=index%3===0?2.2:1.3;ctx.beginPath();
        for(let j=0;j<=8;j++){const p=transferPoint(Math.max(0,t-.065*(1-j/8)),lane);if(j)ctx.lineTo(p[0],p[1]);else ctx.moveTo(p[0],p[1]);}ctx.stroke();
        const glow=ctx.createRadialGradient(head[0],head[1],0,head[0],head[1],8);glow.addColorStop(0,color);glow.addColorStop(1,'transparent');
        ctx.globalAlpha=.55;ctx.fillStyle=glow;ctx.beginPath();ctx.arc(head[0],head[1],8,0,Math.PI*2);ctx.fill();
        ctx.globalAlpha=1;ctx.fillStyle=palette.core;ctx.beginPath();ctx.arc(head[0],head[1],1.5,0,Math.PI*2);ctx.fill();
      }
    }
    const pulse=clamp((time-1.15)/.95);
    const glow=pulse>0&&pulse<1?Math.sin(pulse*Math.PI)*.85:transferState.complete?.16:0;
    transferStage.style.setProperty('--kb-arrival-glow',glow.toFixed(3));
    if(pulse>0&&pulse<1){
      ctx.globalAlpha=(1-pulse)*.6;ctx.strokeStyle=palette.gold;ctx.lineWidth=1.1;
      ctx.beginPath();ctx.arc(g.end[0],g.end[1],5+pulse*40,0,Math.PI*2);ctx.stroke();
    }
    ctx.restore();
  }
  function finishTransfer(){
    if(!transferState||transferState.complete)return;
    transferState.complete=true;transferState.elapsed=2.2;transferStage.dataset.transfer='complete';
    const title=transferState.kind==='training'?'Behaviors updated':'Memory saved';
    get('kb-transfer-title').textContent=title;get('kb-transfer-status').textContent='Saved to your account';
    announce(title+' to your account.');drawTransfer();
  }
  function beginTransfer(change){
    transferState={elapsed:0,complete:false,kind:change.kind};
    get('kb-transfer-title').textContent=change.kind==='training'?'Teaching your brain':'Adding your memory';
    get('kb-transfer-status').textContent='Approved · showing the transfer';
    get('kb-transfer-kind').textContent=change.kind==='training'?'BEHAVIOR':'MEMORY';
    get('kb-transfer-value').textContent=change.text;
    transferStage.dataset.transfer='running';show('transfer');
    if(paused())finishTransfer();else syncAnimation();
  }
  function tickCinema(dt){
    if(introActive){introElapsed+=dt;drawIntro();if(introElapsed>=2.15)finishIntro();}
    if(focusRequest){focusRequest.elapsed+=dt;if(focusRequest.elapsed>=.17)clearFocus(true);}
    if(currentScreen==='transfer'&&transferState&&!transferState.complete){
      transferState.elapsed+=dt;if(transferState.elapsed>=2.2)finishTransfer();else drawTransfer();
    }
    updateVoiceLight(dt);tickMusicGlow(dt);tickLightning(dt);
  }
  function cinemaMotionChanged(){
    lightningPreview.disabled=paused();
    if(paused())clearLightning();
    if(paused()){resetDepth();if(focusRequest)clearFocus(true);}
    if(reducedMotion.matches&&!motionOverride){if(introActive)finishIntro();if(transferState&&!transferState.complete)finishTransfer();}
  }
  function mountCinema(){
    app.addEventListener('pointermove',moveDepth,{passive:true});
    app.addEventListener('pointerleave',resetDepth,{passive:true});
    app.addEventListener('pointerup',event=>{if(event.pointerType==='touch')resetDepth();},{passive:true});
    app.addEventListener('pointercancel',resetDepth,{passive:true});
    if(typeof IntersectionObserver!=='undefined'){
      const viewportObserver=new IntersectionObserver(entries=>{
        inViewport=entries[0].isIntersecting;syncMotion();
      },{threshold:0});viewportObserver.observe(app);
      const introObserver=new IntersectionObserver(entries=>{
        if(entries[0].isIntersecting&&introQueued&&!document.hidden&&!userPaused){startIntro(false);introObserver.disconnect();}
      },{threshold:.15});introObserver.observe(root.querySelector('[data-screen="home"] .kb-grand-brain'));
    }else if(introQueued)startIntro(false);
  }

  // Decorative energy routes in the coordinate system of the existing brain artwork.
  const knots = [
    [[.14,.48],[.17,.37],[.24,.32],[.31,.31],[.33,.25],[.39,.28],[.43,.37],[.42,.48],[.37,.57],[.30,.55],[.25,.45],[.21,.43],[.18,.53]],
    [[.32,.17],[.39,.09],[.48,.08],[.54,.14],[.61,.12],[.67,.18],[.63,.26],[.56,.29],[.52,.37],[.47,.39],[.44,.31],[.45,.22],[.39,.20]],
    [[.61,.33],[.68,.27],[.74,.21],[.80,.29],[.83,.38],[.80,.45],[.83,.52],[.78,.62],[.70,.66],[.64,.56],[.61,.47]],
    [[.40,.46],[.48,.43],[.55,.36],[.61,.38],[.63,.47],[.59,.55],[.56,.61],[.52,.69],[.45,.71],[.40,.62]],
    [[.19,.57],[.26,.63],[.36,.66],[.42,.74],[.49,.77],[.56,.75],[.62,.70],[.65,.64],[.58,.61],[.52,.65],[.45,.59],[.38,.57],[.29,.60]],
    [[.59,.79],[.65,.77],[.73,.77],[.80,.80],[.77,.86],[.71,.89],[.65,.86],[.61,.83]],
    [[.55,.82],[.57,.87],[.61,.96],[.59,.94],[.54,.87]]
  ];
  const outline = [[.104,.57],[.105,.43],[.14,.32],[.22,.22],[.31,.13],[.40,.06],[.46,.03],[.51,.05],[.60,.055],[.67,.065],[.73,.10],[.78,.15],[.83,.22],[.85,.32],[.88,.42],[.89,.56],[.875,.67],[.85,.73],[.80,.745],[.825,.78],[.825,.83],[.79,.88],[.72,.92],[.67,.925],[.62,.89],[.595,.90],[.625,.97],[.605,.995],[.58,.98],[.53,.90],[.51,.85],[.44,.84],[.38,.80],[.33,.74],[.30,.69],[.22,.68],[.16,.64]];
  function smoothPoint(points,t) {
    const n=points.length, f=((t%1)+1)%1*n, i=Math.floor(f), u=f-i, u2=u*u, u3=u2*u;
    const a=points[(i+n-1)%n],b=points[i%n],c=points[(i+1)%n],d=points[(i+2)%n];
    return [0,1].map(k=>.5*((2*b[k])+(-a[k]+c[k])*u+(2*a[k]-5*b[k]+4*c[k]-d[k])*u2+(-a[k]+3*b[k]-3*c[k]+d[k])*u3));
  }
  const routes=knots.map(points=>Array.from({length:240},(_,i)=>smoothPoint(points,i/240)));
  const particles=routes.flatMap((_,route)=>Array.from({length:route===6?2:3},(_,index)=>({route,phase:index/3+route*.137,rate:(route===6?.065:.06+route*.006)*(index===2?.74:1),direction:route%2?-1:1,accent:index===2,radius:index===2?2.7:1.8,trail:index===2?.055:.04})));
  const junctions=[[.42,.46],[.63,.47],[.56,.69],[.70,.82]];
  function routePoint(route,t) {
    const points=routes[route], f=((t%1)+1)%1*points.length, i=Math.floor(f), u=f-i, a=points[i], b=points[(i+1)%points.length];
    return [a[0]+(b[0]-a[0])*u,a[1]+(b[1]-a[1])*u];
  }
  function mapPoint(scene,p) {
    const imageWidth=scene.width*1.22, imageHeight=imageWidth/1.5;
    return [(scene.width-imageWidth)/2+p[0]*imageWidth,(scene.height-imageHeight)/2+p[1]*imageHeight];
  }
  function readPalette() {
    palette.flow=getComputedStyle(get('kb-flow-color')).color;
    palette.accent=getComputedStyle(get('kb-accent-color')).color;
    palette.core=getComputedStyle(get('kb-core-color')).color;
    palette.gold=getComputedStyle(get('kb-gold-color')).color;
    palette.lightning=getComputedStyle(get('kb-lightning-color')).color;
  }
  function drawSignals(scene) {
    const ctx=scene.context;
    if(!ctx||!scene.width||!scene.height)return;
    ctx.setTransform(scene.dpr,0,0,scene.dpr,0,0);
    ctx.clearRect(0,0,scene.width,scene.height);
    ctx.save();ctx.beginPath();
    outline.forEach((p,i)=>{const q=mapPoint(scene,p);if(i)ctx.lineTo(q[0],q[1]);else ctx.moveTo(q[0],q[1]);});ctx.closePath();ctx.clip();
    const scale=Math.max(.85,Math.min(1.25,scene.width/390));
    routes.forEach((points,index)=>{
      ctx.beginPath();points.forEach((p,i)=>{const q=mapPoint(scene,p);if(i)ctx.lineTo(q[0],q[1]);else ctx.moveTo(q[0],q[1]);});ctx.closePath();
      ctx.globalAlpha=.075;ctx.strokeStyle=index%2?palette.accent:palette.flow;ctx.lineWidth=.65*scale;ctx.stroke();
    });
    particles.forEach(particle=>{
      const cinematicGold=introActive||currentScreen==='transfer'||(currentScreen==='talk'&&demoIndex===2);
      const t=particle.phase+energyClock*particle.rate*particle.direction, color=particle.accent?(cinematicGold?palette.gold:palette.accent):palette.flow;
      const head=mapPoint(scene,routePoint(particle.route,t)),tail=mapPoint(scene,routePoint(particle.route,t-particle.trail*particle.direction));
      const trail=ctx.createLinearGradient(tail[0],tail[1],head[0],head[1]);trail.addColorStop(0,'transparent');trail.addColorStop(.65,color);trail.addColorStop(1,color);
      ctx.globalAlpha=.8;ctx.strokeStyle=trail;ctx.lineWidth=(particle.accent?2:1.4)*scale;ctx.lineCap='round';ctx.beginPath();
      for(let i=0;i<=14;i++){const q=mapPoint(scene,routePoint(particle.route,t-particle.trail*particle.direction*(1-i/14)));if(i)ctx.lineTo(q[0],q[1]);else ctx.moveTo(q[0],q[1]);}ctx.stroke();
      const radius=particle.radius*scale,glow=ctx.createRadialGradient(head[0],head[1],0,head[0],head[1],radius*4.2);
      glow.addColorStop(0,color);glow.addColorStop(.2,color);glow.addColorStop(1,'transparent');
      ctx.globalAlpha=.5;ctx.fillStyle=glow;ctx.beginPath();ctx.arc(head[0],head[1],radius*4.2,0,Math.PI*2);ctx.fill();
      ctx.globalAlpha=1;ctx.fillStyle=color;ctx.beginPath();ctx.arc(head[0],head[1],radius,0,Math.PI*2);ctx.fill();
      ctx.fillStyle=palette.core;ctx.beginPath();ctx.arc(head[0],head[1],radius*.48,0,Math.PI*2);ctx.fill();
    });
    junctions.forEach((p,index)=>{
      const center=mapPoint(scene,p),phase=(energyClock/3.8+index*.27)%1;
      ctx.globalAlpha=(1-phase)*.3;ctx.lineWidth=.8*scale;ctx.strokeStyle=index%2?palette.accent:palette.flow;
      ctx.beginPath();ctx.arc(center[0],center[1],(2+phase*11)*scale,0,Math.PI*2);ctx.stroke();
      if(index<2){
        const a=energyClock*(index?-1.1:1.1)+index;
        for(let j=0;j<2;j++){const theta=a+j*Math.PI;ctx.globalAlpha=.8;ctx.fillStyle=index?palette.accent:palette.flow;ctx.beginPath();ctx.arc(center[0]+Math.cos(theta)*10*scale,center[1]+Math.sin(theta)*6*scale,1.3*scale,0,Math.PI*2);ctx.fill();}
      }
    });
    ctx.restore();
  }
  function paused(){return userPaused||document.hidden||!inViewport;}
  function activeScene(){return currentScreen==='home'||currentScreen==='talk'||currentScreen==='transfer';}
  function placeMenu(menu){menu.buttons.forEach((button,index)=>{const a=menu.angle+index*Math.PI*2/menu.buttons.length;button.style.transform=`translate3d(${(Math.cos(a)*menu.radius).toFixed(2)}px,${(Math.sin(a)*96).toFixed(2)}px,0)`;});}
  function measure(){
    menus.forEach(menu=>{if(menu.element.clientWidth)menu.radius=Math.max(100,menu.element.clientWidth/2-16);placeMenu(menu);});
    scenes.forEach(scene=>{const w=scene.canvas.clientWidth,h=scene.canvas.clientHeight;if(!w||!h)return;const dpr=Math.min(window.devicePixelRatio||1,2);if(scene.width!==w||scene.height!==h||scene.dpr!==dpr){scene.width=w;scene.height=h;scene.dpr=dpr;scene.canvas.width=Math.round(w*dpr);scene.canvas.height=Math.round(h*dpr);}drawSignals(scene);});
    measureTransfer();measureLightning();
  }
  function tick(time){
    animationFrame=null;
    if(!root.isConnected){disposeMusic();lastFrame=0;return;}
    if(paused()||!activeScene()){lastFrame=0;return;}
    if(lastFrame&&time-lastFrame<31){animationFrame=requestAnimationFrame(tick);return;}
    const dt=lastFrame?Math.min((time-lastFrame)/1000,.08):0;lastFrame=time;
    energyClock+=dt*(currentScreen==='talk'?phases[demoIndex].speed:1);
    tickCinema(dt);
    if(time-lastPaletteRead>1000){readPalette();lastPaletteRead=time;}
    if(currentScreen==='home')menus.forEach((menu,index)=>{if(!menu.hover&&!menu.focus&&!menu.touch&&!focusRequest)menu.angle+=dt*Math.PI*2/48*(index?-1:1);placeMenu(menu);});
    scenes.forEach(scene=>{if(scene.screen===currentScreen)drawSignals(scene);});
    if(activeScene()&&!paused()&&animationFrame===null)animationFrame=requestAnimationFrame(tick);
  }
  function syncAnimation(){
    if(paused()||!activeScene()){if(animationFrame!==null)cancelAnimationFrame(animationFrame);animationFrame=null;lastFrame=0;}
    else if(animationFrame===null)animationFrame=requestAnimationFrame(tick);
  }
  function pauseDemo(){}
  function scheduleDemo(){}
  function setPhase(index){demoIndex=index;const phase=phases[index];get('kb-voice-scene').dataset.phase=phase.key;get('kb-voice-phase').textContent=phase.label;updateVoiceLight(0);}
  function syncMotion(){root.dataset.motion=paused()?'paused':'playing';root.dataset.motionOverride=motionOverride?'on':'off';get('kb-motion-toggle').setAttribute('aria-pressed',String(userPaused));get('kb-motion-toggle').setAttribute('aria-label',userPaused?'Play animations':'Pause animations');get('kb-motion-label').textContent=userPaused?'Play animations':'Pause animations';get('kb-motion-pause').hidden=userPaused;get('kb-motion-play').hidden=!userPaused;if(paused())pauseDemo();else scheduleDemo();cinemaMotionChanged();musicEnvironmentChanged();syncAnimation();}

  // The bundled view never receives an access token. Only this fixed command
  // vocabulary can cross the native bridge; all account requests stay native.
  let training='', memories=[], pending=null, deletion=null, canUndo=false;
  let memorySource='Typed entry',trainingSource='Typed instructions';
  let voiceActive=false, voiceStopping=false, voiceStarting=false, lastUserTranscript='', ready=false, writing=false;
  let requestNumber=0, voiceRequestEpoch=0;
  const requests=new Map();
  const transcriptMessages=new Map(), savedMessages=new Map(), transcriptBusy=new Set();
  let savedRevision=0;
  const announce=text=>{get('kb-status').textContent=text;};
  const behaviors=()=>training.split(/\r?\n/).map(line=>line.trim()).filter(Boolean);
  function native(action,payload={}){
    if(!window.Korlix?.postMessage)return Promise.reject(new Error('Open the installed KORLIX Brain+Voice app to connect your account.'));
    const id=String(++requestNumber);
    return new Promise((resolve,reject)=>{
      const timeout=action==='pickFile'?660000:action==='startVoice'?90000:65000;
      const timer=setTimeout(()=>{requests.delete(id);reject(new Error('The response was interrupted. Refresh My Brain before trying a change again.'));},timeout);
      requests.set(id,{resolve,reject,timer});
      window.Korlix.postMessage(JSON.stringify({id,action,payload}));
    });
  }
  window.KorlixBrainReceive=message=>{
    if(message.type==='reply'){
      const request=requests.get(message.id);if(!request)return;
      clearTimeout(request.timer);requests.delete(message.id);
      message.error?request.reject(new Error(message.error)):request.resolve(message.data);
    }else if(message.type==='voice'){
      if(message.phase!=='complete')stopWelcome();
      if(message.phase==='complete'){voiceStarting=false;voiceStopping=false;}
      if(voiceStopping&&message.phase!=='complete')message={...message,phase:'stopping',message:'Stopping conversation…'};
      const index=phases.findIndex(p=>p.key===message.phase);
      if(index>=0)setPhase(index);
      voiceActive=message.phase!=='complete';
      voiceStopping=message.phase==='stopping';
      get('kb-voice-modes').disabled=voiceActive;
      get('kb-voice-phase').textContent=message.message;
      get('kb-live-phase').textContent=message.message;
      get('kb-stop-voice').disabled=voiceStopping;
      get('kb-stop-label').textContent=voiceStopping?'Stopping…':'Stop conversation';
      get('kb-replay-demo').textContent='Start conversation';
      root.dataset.voiceActive=String(voiceActive);refreshMusic();welcomeUi();
    }else if(message.type==='transcript'&&message.text){
      transcriptMessages.set(message.id||'unavailable-'+Date.now(),message);
      while(transcriptMessages.size>60)transcriptMessages.delete(transcriptMessages.keys().next().value);
      renderTranscripts();
    }else if(message.type==='brainSnapshot'){
      applySnapshot(message.snapshot);
    }else if(message.type==='voiceSaved'||message.type==='voiceNotice'){
      announce(message.message);
    }else if(message.type==='dictation'){
      const target=message.kind==='training'?'kb-training':'kb-memory';
      get(target).value=message.text;
      if(message.kind==='training')trainingSource='Voice';else memorySource='Voice';
      announce(message.final?'Dictation ready. Review before saving.':'Listening… tap Stop dictation when finished.');
    }else if(message.type==='dictationStatus'){
      music.dictating=message.active===true;if(music.dictating)stopWelcome();refreshMusic();welcomeUi();
      announce(message.message);
    }else if(message.type==='appLifecycle'){
      appVisible=message.active===true;musicEnvironmentChanged();
    }
  };
  const fail=error=>announce(error.message||'Could not complete this action. Please try again.');
  function applySnapshot(snapshot){
    training=snapshot.training||'';
    memories=(snapshot.memories||[]).map(m=>({id:m.id,text:m.content,source:m.source==='voice_confirmed'?((m.tags||[]).includes('instruction')?'Voice instruction':'Voice memory'):(m.source||'Approved memory')}));
    canUndo=!!snapshot.canUndo;ready=true;
    get('kb-account-status').textContent='Account connected';
    maybeWelcome();
    if(currentScreen==='brain')renderBrain();
  }
  async function refresh(){
    if(writing)return;
    get('kb-account-status').textContent='Syncing…';
    try{applySnapshot(await native('load'));announce('Your brain is up to date.');}
    catch(error){get('kb-account-status').textContent='Sync unavailable';fail(error);}
  }
  async function mutate(action,payload,complete){
    if(writing)return;
    if(!ready){announce('Refresh your account before making changes.');return;}
    writing=true;get('kb-approve').disabled=true;get('kb-confirm-delete').disabled=true;
    announce('Saving your approved change…');
    try{applySnapshot(await native(action,payload));complete();}
    catch(error){fail(error);}
    finally{writing=false;get('kb-approve').disabled=false;get('kb-confirm-delete').disabled=false;}
  }
  function makeButton(label,fn,classes='kb-link cursor-interaction'){
    const button=document.createElement('button');button.type='button';button.className=classes;button.textContent=label;button.addEventListener('click',fn);return button;
  }
  function transcriptRow(message){
    const row=document.createElement('article');row.className='kb-bubble';row.dataset.messageId=message.id||'';
    const label=document.createElement('small');label.textContent=message.role==='you'?'YOU':'RICI';
    const text=document.createElement('p');text.textContent=message.text;row.append(label,text);
    if(message.createdAt){const time=document.createElement('time');time.dateTime=message.createdAt;time.textContent=new Date(message.createdAt).toLocaleString();row.append(time);}
    const actions=document.createElement('div');actions.className='kb-transcript-actions';
    for(const [action,label] of [['save',savedMessages.has(message.id)?'Saved':'Save'],['share','Share'],['delete','Delete']]){
      const button=makeButton(label,()=>transcriptAction(action,message),action==='delete'?'kb-link kb-danger cursor-interaction':'kb-link cursor-interaction');
      button.dataset.transcriptAction=action;
      button.disabled=!message.id||transcriptBusy.has(message.id)||(action==='save'&&savedMessages.has(message.id));
      actions.append(button);
    }
    if(message.role==='rici')actions.append(makeButton('Report response',()=>native('report',{text:message.text}).then(result=>{if(result?.submitted)announce('Report received. Thank you.');}).catch(fail)));
    row.append(actions);return row;
  }
  function renderTranscripts(){
    get('kb-transcript').replaceChildren(...Array.from(transcriptMessages.values(),transcriptRow));
    lastUserTranscript=Array.from(transcriptMessages.values()).reverse().find(m=>m.role==='you')?.text||'';
    get('kb-talk-review').disabled=!lastUserTranscript;
    const list=get('kb-saved-transcripts');list.replaceChildren(...Array.from(savedMessages.values(),transcriptRow));
    get('kb-saved-empty').hidden=savedMessages.size>0;
    get('kb-saved-count').textContent=savedMessages.size+' saved '+(savedMessages.size===1?'message':'messages');
  }
  async function loadSavedTranscripts(){
    const revision=savedRevision;
    try{
      const items=await native('listSavedTranscripts');
      if(revision!==savedRevision)return;
      savedMessages.clear();(items||[]).forEach(item=>savedMessages.set(item.id,item));renderTranscripts();
    }catch(error){if(currentScreen==='saved')fail(error);}
  }
  async function transcriptAction(action,message){
    if(transcriptBusy.has(message.id))return;
    transcriptBusy.add(message.id);++savedRevision;renderTranscripts();
    try{
      const result=await native(action+'Transcript',{messageId:message.id});
      if(action==='save'){
        const previous=Array.from(savedMessages.entries());savedMessages.clear();savedMessages.set(result.id,result);previous.forEach(([id,item])=>savedMessages.set(id,item));
        announce('Message saved on this device. Find it in Saved messages.');
      }else if(action==='delete'&&result?.deleted){
        transcriptMessages.delete(message.id);savedMessages.delete(message.id);announce('Transcript message deleted from this device.');
      }else if(action==='share'&&result?.shared)announce('Message shared.');
    }catch(error){fail(error);}
    finally{transcriptBusy.delete(message.id);++savedRevision;renderTranscripts();}
  }
  function confirmDeletion(kind,key,text){
    deletion={kind,key,text,expected:training};
    get('kb-delete-title').textContent=kind==='behavior'?'Delete this behavior?':'Delete this memory?';
    get('kb-delete-value').textContent=text;get('kb-confirm-delete').textContent=kind==='behavior'?'Delete behavior':'Delete memory';show('delete');
  }
  function renderBrain(){
    get('kb-saved-training').textContent=training||'No behaviors added yet.';
    get('kb-behavior-count').textContent='BEHAVIORS · '+behaviors().length;
    get('kb-undo-training').hidden=true;get('kb-undo-deletion').hidden=!canUndo;
    get('kb-memory-count').textContent='MEMORIES · '+memories.length;
    const list=get('kb-memory-list');list.replaceChildren();
    if(!memories.length){const p=document.createElement('p');p.className='kb-caption';p.textContent='Your approved memories will appear here.';list.append(p);}
    memories.forEach(memory=>{
      const item=document.createElement('div');item.className='kb-memory-item';
      const label=document.createElement('span');label.className='kb-caption';label.textContent=memory.source;
      const value=document.createElement('p');value.textContent=memory.text;
      item.append(label,value,makeButton('Delete memory',()=>confirmDeletion('memory',memory.id,memory.text),'kb-link kb-danger cursor-interaction'));list.append(item);
    });
  }
  function renderDeleteList(kind){
    const list=get(kind==='behavior'?'kb-behavior-delete-list':'kb-memory-delete-list');list.replaceChildren();
    const items=kind==='behavior'?behaviors().map((text,key)=>({text,key})):memories.map(m=>({text:m.text,key:m.id}));
    if(!items.length){const p=document.createElement('p');p.className='kb-caption';p.textContent='There are no saved items to delete.';list.append(p);}
    items.forEach(item=>{const row=document.createElement('div');row.className='kb-memory-item';const p=document.createElement('p');p.textContent=item.text;row.append(p,makeButton('Delete',()=>confirmDeletion(kind,item.key,item.text),'kb-link kb-danger cursor-interaction'));list.append(row);});
  }
  function show(name,preserveDraft=false){
    clearFocus(false);resetDepth();clearLightning();
    if(name!=='home'){finishIntro();stopWelcome();}
    if(name!=='transfer'){transferState=null;transferStage.dataset.transfer='ready';}
    if((currentScreen==='train'||currentScreen==='memory')&&name!==currentScreen)native('stopDictation').catch(()=>{});
    currentScreen=name;screens.forEach(screen=>{screen.hidden=screen.dataset.screen!==name;});announce('');
    root.dataset.screen=name;musicScreenChanged();welcomeUi();
    if(name==='brain')renderBrain();
    if(name==='saved'){renderTranscripts();loadSavedTranscripts();}
    if(name==='manage-behaviors')renderDeleteList('behavior');if(name==='manage-memories')renderDeleteList('memory');
    if(name==='train'&&!preserveDraft){get('kb-training').value=training;trainingSource='Typed instructions';}
    if(name==='memory'&&!preserveDraft){get('kb-memory').value='';memorySource='Typed entry';}
    if(name==='home')menus.forEach(menu=>{menu.touch=false;menu.focus=false;menu.hover=false;});
    measure();syncAnimation();
  }
  function review(kind,text,source){
    if(writing)return;
    if(!text.trim()){announce('Add some text first.');return;}
    const max=kind==='training'?12000:4000;
    if(text.trim().length>max){announce('Please shorten this to '+max+' characters.');return;}
    pending={kind,text:text.trim(),source,expected:training};
    get('kb-review-title').textContent=kind==='training'?'Review behaviors':'Review memory';
    get('kb-review-kind').textContent=kind==='training'?'Replace behaviors with':'Memory to add';
    get('kb-review-value').textContent=pending.text;get('kb-review-old').textContent=kind==='training'?training:'';
    get('kb-review-old-block').hidden=kind!=='training'||!training;
    get('kb-review-source').textContent='Source: '+source+'. Saves to your shared KORLIX account only after approval.';show('review');
  }
  async function pickFile(kind){
    announce('Choose a document to analyze…');
    try{
      const result=await native('pickFile',{kind});if(result?.canceled)return;
      show(kind==='training'?'train':'memory',true);
      get(kind==='training'?'kb-training':'kb-memory').value=result.text;
      if(kind==='training')trainingSource='File: '+result.filename;else memorySource='File: '+result.filename;
      announce('Draft ready. Edit and review before approving.');
    }catch(error){fail(error);}
  }
  function dictate(kind){
    stopWelcome();music.dictating=true;refreshMusic();welcomeUi();
    native('dictate',{kind}).catch(error=>{music.dictating=false;refreshMusic();fail(error);});
  }
  function stopVoice(){
    if(voiceStopping)return;
    const epoch=++voiceRequestEpoch;
    voiceStopping=true;
    window.KorlixBrainReceive({type:'voice',phase:'stopping',message:'Stopping conversation…'});
    native('stopVoice').catch(error=>{
      if(epoch!==voiceRequestEpoch)return;
      voiceStopping=false;get('kb-stop-voice').disabled=false;
      get('kb-stop-label').textContent='Retry stop';fail(error);
    });
  }
  function startVoice(){
    if(voiceActive||voiceStarting)return;
    stopWelcome();
    const epoch=++voiceRequestEpoch;
    voiceStarting=true;
    window.KorlixBrainReceive({type:'voice',phase:'connecting',message:'Connecting to Rici…'});
    native('startVoice',{mode:root.querySelector('input[name="brain-voice-mode"]:checked')?.value||'live'}).then(result=>{
      // Consent can be declined without creating a voice session.
      if(epoch===voiceRequestEpoch&&result?.active===false)
        window.KorlixBrainReceive({type:'voice',phase:'complete',message:'Microphone off'});
    }).catch(error=>{
      if(epoch!==voiceRequestEpoch)return;
      window.KorlixBrainReceive({type:'voice',phase:'complete',message:'Microphone off'});fail(error);
    }).finally(()=>{if(epoch===voiceRequestEpoch)voiceStarting=false;});
  }
  function toggleVoice(){voiceActive?stopVoice():startVoice();}
  root.querySelectorAll('[data-go]').forEach(button=>button.addEventListener('click',()=>cinematicNavigate(button,()=>{
    if(writing){announce('Please wait for this change to finish.');return;}
    pending=null;deletion=null;show(button.dataset.go);
    if(button.dataset.go==='brain')refresh();
    if(button.dataset.go==='talk'&&!voiceActive)startVoice();
  })));
  menus.forEach(menu=>{
    menu.element.addEventListener('pointerenter',event=>{if(event.pointerType!=='touch')menu.hover=true;});menu.element.addEventListener('pointerleave',()=>{menu.hover=false;});
    menu.element.addEventListener('focusin',()=>{menu.focus=true;});menu.element.addEventListener('focusout',event=>{menu.focus=menu.element.contains(event.relatedTarget);});
    menu.element.addEventListener('pointerdown',()=>{menu.touch=true;},{passive:true});menu.element.addEventListener('pointerup',()=>{menu.touch=false;},{passive:true});menu.element.addEventListener('pointercancel',()=>{menu.touch=false;},{passive:true});
    menu.buttons.forEach(button=>button.addEventListener('click',()=>cinematicNavigate(button,()=>{
      if(writing)return;pending=null;const target=menu.element.dataset.orbitTarget;const kind=target==='train'?'training':'memory';show(target);
      if(button.dataset.entry==='type')get(target==='train'?'kb-training':'kb-memory').focus({preventScroll:true});
      if(button.dataset.entry==='file')pickFile(kind);if(button.dataset.entry==='voice')dictate(kind);
    })));
  });
  get('kb-motion-toggle').addEventListener('click',()=>{userPaused=!userPaused;motionOverride=!userPaused;syncMotion();});
  get('kb-replay-demo').addEventListener('click',toggleVoice);
  get('kb-voice-modes').addEventListener('change',()=>{
    const deep=root.querySelector('input[name="brain-voice-mode"]:checked')?.value==='deep';
    get('kb-mode-hint').textContent=deep?'Deep Think uses Sol Max for every answer and takes longer.':'Live Conversation is ready. Stop the conversation to switch modes.';
  });
  document.addEventListener('visibilitychange',syncMotion);reducedMotion.addEventListener('change',event=>{userPaused=event.matches;motionOverride=false;syncMotion();});
  get('kb-training-form').addEventListener('submit',event=>{event.preventDefault();review('training',get('kb-training').value,trainingSource);});
  get('kb-memory-form').addEventListener('submit',event=>{event.preventDefault();review('memory',get('kb-memory').value,memorySource);});
  get('kb-training').addEventListener('input',()=>{trainingSource='Typed instructions';});get('kb-memory').addEventListener('input',()=>{memorySource='Typed entry';});
  get('kb-training-example').addEventListener('click',()=>dictate('training'));
  get('kb-training-file-example').addEventListener('click',()=>pickFile('training'));
  get('kb-memory-voice-example').addEventListener('click',()=>dictate('memory'));
  get('kb-memory-file-example').addEventListener('click',()=>pickFile('memory'));
  root.querySelectorAll('[data-stop-dictation]').forEach(button=>button.addEventListener('click',()=>native('stopDictation').catch(fail)));
  get('kb-talk-review').addEventListener('click',()=>{if(lastUserTranscript)review('memory',lastUserTranscript,'Voice');});
  get('kb-review-back').addEventListener('click',()=>{if(pending&&!writing)show(pending.kind==='training'?'train':'memory',true);});
  get('kb-cancel').addEventListener('click',()=>{if(writing)return;pending=null;show('home');announce('Canceled. Nothing was added.');});
  get('kb-approve').addEventListener('click',()=>{
    if(!pending)return;const change={...pending};
    mutate(change.kind==='training'?'saveTraining':'saveMemory',change,()=>{pending=null;beginTransfer(change);});
  });
  get('kb-open-delete-behavior').addEventListener('click',()=>show('manage-behaviors'));get('kb-open-delete-memory').addEventListener('click',()=>show('manage-memories'));
  get('kb-confirm-delete').addEventListener('click',()=>{if(!deletion)return;const selected={...deletion};mutate(selected.kind==='behavior'?'deleteBehavior':'deleteMemory',selected,()=>{deletion=null;show('brain');announce('Selected item deleted from your account.');});});
  get('kb-undo-deletion').addEventListener('click',()=>mutate('undo',{},()=>{show('brain');announce('Previous change restored.');}));
  get('kb-account').addEventListener('click',()=>{stopWelcome();native('account').catch(fail);});get('kb-refresh').addEventListener('click',refresh);
  get('kb-return-voice').addEventListener('click',()=>show('talk'));
  get('kb-saved-back').addEventListener('click',()=>show('talk'));
  get('kb-saved-refresh').addEventListener('click',loadSavedTranscripts);
  get('kb-stop-voice').addEventListener('click',stopVoice);
  setPhase(3);refresh();loadSavedTranscripts();

  const resize=new ResizeObserver(measure);menus.forEach(menu=>resize.observe(menu.element));scenes.forEach(scene=>resize.observe(scene.canvas));
  resize.observe(transferStage);resize.observe(app);
  mountMusic();readPalette();measure();syncMotion();mountCinema();


})();
