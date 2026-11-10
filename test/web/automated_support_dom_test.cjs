const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
let JSDOM;
try { ({JSDOM}=require(process.env.AUTOMATED_SUPPORT_JSDOM_PATH||'jsdom')); } catch { /* Optional browser-independent integration runner. */ }
const available={skip:!JSDOM};
const flush=()=>new Promise(resolve=>setImmediate(resolve));
async function setup({missing=false}={}) {
  const dom=new JSDOM('<html><body><nav class="navigation"></nav><header class="top-header"></header><section id="emailWorkspace"></section></body></html>',{url:'https://ui.example.test',runScripts:'outside-only'}),w=dom.window;
  w.APP={token:'fixture',apiBase:'https://api.example.test'};
  w.decodeJwtPayload=()=>({iss:'test',sub:'owner',session_id:'session',exp:4102444800});
  w.renderDashboard=()=>{};w.setConnectedState=()=>{};w.closeMobileSidebar=()=>{};
  w.matchMedia=()=>({matches:true});w.HTMLElement.prototype.scrollIntoView=()=>{};
  w.HTMLDialogElement.prototype.showModal=function(){this.setAttribute('open','');};
  w.HTMLDialogElement.prototype.close=function(){this.removeAttribute('open');this.dispatchEvent(new w.Event('close'));};
  w.confirm=()=>true;w.prompt=()=> 'Customer confirmed that the issue was resolved.';
  const calls=[],profiles=[{id:'a',displayName:'KORLIX AI',fromEmail:'support@example.test',replyTo:'reply@example.test',ready:true,mode:'draft',dailyCap:100},{id:'b',displayName:'Second business',fromEmail:'hello@business.example',replyTo:'reply@business.example',ready:false,mode:'paused'}];
  let row={id:'case-a',profileId:'a',subject:'Feature unavailable',details:'<img src=x onerror="bad()">',reporterEmail:'customer@example.test',reporterVerified:true,state:'new',automationPaused:false};
  const messages=[{id:'draft-a',kind:'acknowledgment',direction:'outbound',status:'pending',text:'Which feature were you using?'}];
  w.requestJson=async(url,options={})=>{
    const body=options.body?JSON.parse(options.body):null;calls.push({url,method:options.method||'GET',body});
    if(missing)throw Object.assign(new Error('Not found'),{status:404});
    if(url.endsWith('/profiles'))return{ok:true,profiles};
    if(url.endsWith('/profiles/a')){profiles[0].mode=body.mode;return{ok:true,profile:profiles[0]};}
    if(url.includes('/cases?'))return{ok:true,cases:new URL(url,w.location).searchParams.get('profileId')==='a'?[row]:[]};
    if(url.endsWith('/replies')){messages.push({id:'manual',kind:'owner_reply',direction:'outbound',status:'pending',text:body.text});return{ok:true,case:row,message:messages.at(-1)};}
    if(url.endsWith('/cases/case-a')){if(options.method==='PATCH')row={...row,...body};return{ok:true,case:row,messages};}
    throw Error('Unexpected path '+url);
  };
  w.eval(fs.readFileSync('website/nova-email/automated-support-model.js','utf8'));
  w.eval(fs.readFileSync('website/nova-email/automated-support.js','utf8'));
  w.document.dispatchEvent(new w.Event('DOMContentLoaded'));
  await flush();await flush();
  const change=async(selector,value)=>{const element=w.document.querySelector(selector);element.value=value;element.dispatchEvent(new w.Event('change',{bubbles:true}));await flush();await flush();};
  const click=async selector=>{w.document.querySelector(selector).click();await flush();await flush();};
  return{dom,w,calls,profiles,change,click};
}
test('DOM flow: separate addresses, draft review, pause, resolution and sign-out clearing',available,async()=>{
  const f=await setup(),d=f.w.document;
  try {
    assert.equal(d.querySelectorAll('[data-support-case]').length,1);
    await f.change('#supportProfile','b');
    assert.equal(d.querySelectorAll('[data-support-case]').length,0);
    assert.equal(d.querySelector('#supportMode option[value=automatic]').disabled,true);
    assert.match(d.querySelector('.support-address').textContent,/hello@business.example/);
    await f.change('#supportProfile','a');await f.click('[data-support-case]');
    assert.equal(d.querySelector('#supportCaseDialog').open,true);
    assert.equal(d.querySelectorAll('img[onerror]').length,0);
    await f.click('[data-support-action=draft]');assert.equal(d.querySelector('#supportReply').value,'Which feature were you using?');
    await f.click('[data-support-action=reply]');
    const reply=f.calls.find(call=>call.url.endsWith('/replies'));
    assert.deepEqual(reply.body,{text:'Which feature were you using?',confirmed:true});
    await f.click('[data-support-action=pause]');assert.match(d.querySelector('[data-support-action=pause]').textContent,/Resume/);
    await f.change('#supportCaseState','resolved');await f.click('[data-support-action=status]');
    assert.equal(f.calls.find(call=>call.body?.state==='resolved').body.resolutionNote,'Customer confirmed that the issue was resolved.');
    assert.equal(d.querySelector('[data-support-action=reply]').disabled,true);
    f.w.APP.token='';f.w.setConnectedState(false);await flush();
    assert.equal(d.querySelector('#supportCaseDialog').open,false);
    assert.equal(d.body.innerHTML.includes('customer@example.test'),false);
  }finally{f.dom.window.close();}
});
test('DOM flow: missing backend is shown as setup unavailable, without records',available,async()=>{
  const f=await setup({missing:true});
  try {assert.match(f.w.document.querySelector('#supportStatus').textContent,/awaiting setup/);assert.equal(f.w.document.querySelectorAll('[data-support-case]').length,0);}
  finally{f.dom.window.close();}
});
