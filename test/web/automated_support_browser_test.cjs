const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const path=require('node:path');
const fs=require('node:fs/promises');
const {chromium}=require('playwright');
let browser;
const artifacts=path.resolve('build/automated_support_browser');
before(async()=>{await fs.mkdir(artifacts,{recursive:true});browser=await chromium.launch({headless:true,executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH||undefined,args:['--no-sandbox','--disable-dev-shm-usage']});});
after(async()=>browser?.close());

async function setup(width,{missing=false}={}) {
  const page=await browser.newPage({viewport:{width,height:1000}});
  await page.setContent('<html lang="en"><head><title>Support test</title></head><body><div class="app-shell"><aside class="sidebar"><nav class="navigation"></nav></aside><main class="main-content"><header class="top-header"><h1>KORLIX Email Center</h1></header><div id="emailWorkspace"></div></main></div></body></html>');
  for(const name of ['styles.css','email-workspace.css','automated-support.css'])await page.addStyleTag({path:path.resolve('website/nova-email',name)});
  await page.evaluate(({missing})=>{
    window.APP={token:'fixture',apiBase:'https://api.example.test'};
    window.decodeJwtPayload=()=>({iss:'test',sub:'owner-a',session_id:'session',exp:4102444800});
    window.setConnectedState=()=>{};window.renderDashboard=()=>{};window.closeMobileSidebar=()=>{};
    window.supportCalls=[];
    const profiles=[{id:'a',displayName:'KORLIX AI',fromEmail:'support@example.test',replyTo:'replies@example.test',mode:'draft',ready:true,dailyCap:100},
      {id:'b',displayName:'Receipt Wiz',fromEmail:'receipts@example.test',replyTo:'receipt-replies@example.test',mode:'paused',ready:false,dailyCap:40}];
    let record={id:'case-a',profileId:'a',subject:'A feature will not load',reporterEmail:'customer@example.test',reporterVerified:true,details:'The feature is not loading. <img src=x onerror="bad()">',appVersion:'12.0.5+145',platform:'android',appArea:'app_wide_ai_reporting',state:'new',automationPaused:false,createdAt:'2026-11-10T02:04:25Z',updatedAt:'2026-11-10T02:04:25Z'};
    const messages=[{id:'m1',direction:'outbound',kind:'acknowledgment',text:'Thanks for your report. Which feature were you trying to open?',status:'sent',createdAt:record.createdAt}];
    window.requestJson=async(url,options={})=>{
      const method=options.method||'GET',body=options.body?JSON.parse(options.body):null;
      window.supportCalls.push({url,method,body});
      if(missing)throw Object.assign(new Error('Not found'),{status:404});
      if(url.endsWith('/profiles'))return{ok:true,profiles};
      if(url.endsWith('/profiles/a')){profiles[0].mode=body.mode;return{ok:true,profile:profiles[0]};}
      if(url.includes('/cases?')){const query=new URL(url,'https://api.example.test').searchParams;return{ok:true,cases:query.get('profileId')==='a'&&(!query.get('state')||query.get('state')===record.state)?[record]:[]};}
      if(url.endsWith('/cases/case-a/replies')){messages.push({id:'m2',direction:'outbound',text:body.text,status:'pending',createdAt:record.createdAt});return{ok:true,case:record,message:messages.at(-1)};}
      if(url.endsWith('/cases/case-a')){if(method==='PATCH')record={...record,...body};return{ok:true,case:record,messages};}
      throw Error('Unexpected fixture route '+url);
    };
  },{missing});
  await page.addScriptTag({path:path.resolve('website/nova-email/automated-support-model.js')});
  await page.addScriptTag({path:path.resolve('website/nova-email/automated-support.js')});
  return page;
}
for(const width of [390,1440])test(`support at ${width}px selects profiles, reviews replies, pauses and resolves`,async()=>{
  const page=await setup(width),errors=[];page.on('pageerror',e=>errors.push(e.message));
  try {
    await page.getByRole('button',{name:/A feature will not load/}).waitFor();
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'No horizontal overflow');
    await page.screenshot({path:path.join(artifacts,`support-${width}.png`),fullPage:true});
    await page.locator('#supportProfile').selectOption('b');
    await page.getByText('This address needs setup before automatic replies can be enabled.').waitFor();
    assert.equal(await page.locator('#supportMode option[value="automatic"]').isDisabled(),true);
    assert.equal(await page.getByRole('button',{name:/A feature will not load/}).count(),0);
    await page.locator('#supportProfile').selectOption('a');
    await page.getByRole('button',{name:/A feature will not load/}).click();
    await page.getByRole('dialog').waitFor();
    assert.equal(await page.locator('img[onerror]').count(),0);
    await page.getByRole('button',{name:'Take over · pause automation'}).click();
    await page.getByRole('button',{name:'Resume case automation'}).waitFor();
    await page.locator('#supportReply').fill('Which feature were you trying to open?');
    page.once('dialog',dialog=>dialog.accept());
    await page.getByRole('button',{name:'Review reply',exact:true}).click();
    await page.getByText('Reply recorded. Check its message status for sending progress.').waitFor();
    const reply=(await page.evaluate(()=>supportCalls)).find(c=>c.url.endsWith('/replies'));
    assert.deepEqual(reply.body,{text:'Which feature were you trying to open?',confirmed:true});
    await page.locator('#supportCaseState').selectOption('resolved');
    page.once('dialog',dialog=>dialog.accept('The customer confirmed that the feature opened.'));
    await page.getByRole('button',{name:'Update status'}).click();
    await page.getByText('Case status updated.').waitFor();
    const resolved=(await page.evaluate(()=>supportCalls)).find(c=>c.body?.state==='resolved');
    assert.equal(resolved.body.resolutionNote,'The customer confirmed that the feature opened.');
    await page.screenshot({path:path.join(artifacts,`conversation-${width}.png`),fullPage:true});
    await page.evaluate(()=>{APP.token='';setConnectedState(false);});
    await page.getByText('Sign in to view your support workspace.').waitFor();
    assert.equal(await page.locator('#supportCaseDialog').evaluate(d=>d.open),false);
    assert.equal(await page.locator('#supportCaseList').textContent().then(t=>t.includes('customer@example.test')),false);
    assert.deepEqual(errors,[]);
  }finally{await page.close();}
});
test('unavailable backend gives setup state and no invented cases',async()=>{
  const page=await setup(390,{missing:true});
  try {await page.getByText('Automated support is awaiting setup for this workspace.').waitFor();assert.equal(await page.locator('[data-support-case]').count(),0);assert.equal(await page.locator('#supportProfile').count(),0);}
  finally{await page.close();}
});
