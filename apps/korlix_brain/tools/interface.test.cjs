const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const {JSDOM}=require('jsdom');
const assets=path.join(__dirname,'../assets/web');
const tick=()=>new Promise(resolve=>setImmediate(resolve));
async function setup({failSave=false,deferSave=false,reduced=true}={}){
  const dom=new JSDOM(fs.readFileSync(path.join(assets,'index.html'),'utf8'),{url:'file:///android_asset/flutter_assets/assets/web/index.html',runScripts:'outside-only'});
  const w=dom.window,d=w.document,calls=[],pending=[];
  let training='Keep replies concise.',memories=[],sequence=0,time=0,rafId=0;
  const frames=new Map();
  Object.defineProperty(w,'devicePixelRatio',{value:1});
  Object.defineProperty(w.performance,'now',{value:()=>time});
  Object.defineProperty(w.HTMLElement.prototype,'clientWidth',{get(){return 430;}});
  Object.defineProperty(w.HTMLElement.prototype,'clientHeight',{get(){return this.classList.contains('kb-app')?1400:this.tagName==='CANVAS'?360:72;}});
  w.HTMLElement.prototype.getBoundingClientRect=function(){return {left:0,top:0,width:430,height:this.clientHeight,right:430,bottom:this.clientHeight};};
  w.HTMLCanvasElement.prototype.getContext=()=>new Proxy({createLinearGradient:()=>({addColorStop(){}}),createRadialGradient:()=>({addColorStop(){}})}, {get(o,k){return o[k]??(()=>{});},set(o,k,v){o[k]=v;return true;}});
  w.getComputedStyle=()=>({color:'rgb(80, 225, 255)'});
  w.matchMedia=()=>({matches:reduced,addEventListener(){}});
  w.scrollTo=()=>{};
  w.requestAnimationFrame=fn=>{const id=++rafId;frames.set(id,fn);return id;};w.cancelAnimationFrame=id=>frames.delete(id);
  w.ResizeObserver=class {observe(){} disconnect(){}};
  w.IntersectionObserver=class {constructor(fn){this.fn=fn;}observe(target){this.fn([{isIntersecting:true,target}]);}disconnect(){}};
  const snapshot=()=>({training,memories:structuredClone(memories),canUndo:false});
  function reply(request,data,error){w.KorlixBrainReceive({type:'reply',id:request.id,data,error});}
  w.Korlix={postMessage(raw){const request=JSON.parse(raw);calls.push(request);let data=null;
    if(request.action==='load')data=snapshot();
    if(request.action==='saveMemory'){
      if(deferSave){pending.push(request);return;}
      if(failSave){queueMicrotask(()=>reply(request,null,'Could not save.'));return;}
      memories.push({id:String(++sequence),content:request.payload.text});data=snapshot();
    }
    if(request.action==='saveTraining'){training=request.payload.text;data=snapshot();}
    if(request.action==='deleteMemory'){memories=memories.filter(m=>m.id!==request.payload.key);data=snapshot();}
    if(request.action==='startVoice')data={canceled:true};
    queueMicrotask(()=>reply(request,data));
  }};
  w.eval(fs.readFileSync(path.join(assets,'bridge.js'),'utf8'));
  w.eval(fs.readFileSync(path.join(assets,'app.js'),'utf8'));
  await tick();
  const get=id=>d.getElementById('cinema-'+id);
  const screen=()=>[...d.querySelectorAll('[data-screen]')].find(e=>!e.hidden).dataset.screen;
  async function go(name){d.querySelector('[data-go="'+name+'"]').click();await tick();}
  function advance(ms){for(let t=0;t<ms;t+=33){time+=33;const callbacks=[...frames.values()];frames.clear();callbacks.forEach(fn=>fn(time));assert(frames.size<=1);}}
  return {dom,w,d,get,calls,pending,reply,snapshot,screen,go,advance,frames};
}
test('approved controls and real app entry load together',async()=>{
  const app=await setup();try{
    assert.equal(app.screen(),'home');assert.equal(app.calls.filter(r=>r.action==='load').length,1);
    assert.equal(app.d.querySelectorAll('.kb-halo-talk').length,1);
    assert.equal(app.d.querySelectorAll('.kb-magnetic-key').length,2);
    assert.equal(app.d.querySelectorAll('.kb-memory-chip').length,1);
    assert.equal(app.d.querySelectorAll('[data-entry]').length,6);
    assert(!app.d.body.textContent.includes('animation demo'));
    assert(!app.d.body.textContent.includes('Approve in preview'));
  }finally{app.dom.window.close();}
});
test('typing and review never save until approval; confirmed memory survives refresh',async()=>{
  const app=await setup();try{
    await app.go('memory');app.get('kb-memory').value='My approved fact';
    app.get('kb-memory-form').dispatchEvent(new app.w.Event('submit',{cancelable:true}));await tick();
    assert.equal(app.screen(),'review');assert.equal(app.calls.filter(r=>r.action==='saveMemory').length,0);
    app.get('kb-approve').click();await tick();assert.equal(app.screen(),'transfer');
    assert.equal(app.calls.filter(r=>r.action==='saveMemory').length,1);
    await app.go('brain');assert(app.get('kb-memory-list').textContent.includes('My approved fact'));
  }finally{app.dom.window.close();}
});
test('failed save keeps review and never shows a successful transfer',async()=>{
  const app=await setup({failSave:true});try{
    await app.go('memory');app.get('kb-memory').value='Unsaved';app.get('kb-memory-form').dispatchEvent(new app.w.Event('submit',{cancelable:true}));
    app.get('kb-approve').click();await tick();assert.equal(app.screen(),'review');assert.match(app.get('kb-status').textContent,/Could not save/);
    assert.equal(app.get('kb-approve').disabled,false);
  }finally{app.dom.window.close();}
});
test('repeated approval taps produce one request while saving',async()=>{
  const app=await setup({deferSave:true});try{
    await app.go('memory');app.get('kb-memory').value='One save';app.get('kb-memory-form').dispatchEvent(new app.w.Event('submit',{cancelable:true}));
    app.get('kb-approve').click();app.get('kb-approve').click();await tick();
    assert.equal(app.pending.length,1);app.reply(app.pending[0],app.snapshot());await tick();
  }finally{app.dom.window.close();}
});
test('deletion maps the selected memory ID and text to native confirmation',async()=>{
  const app=await setup();try{
    await app.go('memory');app.get('kb-memory').value='Remove me';app.get('kb-memory-form').dispatchEvent(new app.w.Event('submit',{cancelable:true}));
    app.get('kb-approve').click();await tick();await app.go('brain');
    app.get('kb-memory-list').querySelector('button').click();await tick();assert.equal(app.screen(),'delete');
    assert.equal(app.calls.filter(r=>r.action==='deleteMemory').length,0);
    app.get('kb-confirm-delete').click();await tick();
    assert.deepEqual(app.calls.find(r=>r.action==='deleteMemory').payload,{key:'1',text:'Remove me'});
  }finally{app.dom.window.close();}
});
test('voice leaves microphone control with native events, and text is never executable markup',async()=>{
  const app=await setup();try{
    await app.go('talk');assert.equal(app.get('kb-replay-demo').textContent,'Connect to Rici');
    app.w.KorlixBrainReceive({type:'transcript',role:'rici',text:'<img src=x onerror=alert(1)>'});
    assert.equal(app.d.querySelector('#brain-transcript img'),null);
    await app.go('home');assert(app.calls.some(r=>r.action==='stopVoice'));
  }finally{app.dom.window.close();}
});
test('silent storm runs in one visual loop and obeys pause',async()=>{
  const app=await setup({reduced:false});try{
    app.advance(4500);const root=app.d.querySelector('.kb-product');assert.equal(root.dataset.boot,'ready');
    app.advance(4000);assert.equal(app.calls.filter(r=>/audio|sound|thunder/i.test(r.action)).length,0);
    app.get('kb-motion-toggle').click();app.advance(1000);assert.equal(app.frames.size,0);
    assert.equal(root.dataset.lightning,'idle');
  }finally{app.dom.window.close();}
});
