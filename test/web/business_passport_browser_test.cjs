const {test,before,after}=require('node:test');
const assert=require('node:assert/strict');
const http=require('node:http');
const fs=require('node:fs/promises');
const path=require('node:path');
const {chromium}=require('playwright');
let server,browser,base;
const root=path.resolve('website'),artifacts=path.resolve('build/passport_browser_checks');
const business={id:'11111111-1111-4111-8111-111111111111',slug:'fixture-home-services',verified:false,
  details:{name:'Harbour Home Services',category:'Home & Property',tagline:'Thoughtful care for the place you call home.',description:'Synthetic browser-test business. Reliable property maintenance, repairs and friendly advice for your next project.',city:'Kingston',country:'Jamaica',service_area:'Kingston and St Andrew',phone:'+15550102030',email:'hello@example.test',hours:'Monday–Friday · 8:00 AM–5:00 PM\nSaturday · By appointment',services:'Home maintenance | Request a quote\nProperty inspections | From $75\nRepair consultations | 30 minutes',photos:[],languages:'English'},
  booking:{title:'Project consultation',durationMinutes:30,url:'https://chee-chai-chee-backend.onrender.com/book/fixture-consultation'},
};
before(async()=>{
 await fs.mkdir(artifacts,{recursive:true});
 server=http.createServer(async(q,r)=>{try{const name=path.resolve(root,'.'+new URL(q.url,'http://local').pathname);if(!name.startsWith(root+path.sep))throw Error();r.writeHead(200,{'Content-Type':{'.html':'text/html','.css':'text/css','.js':'text/javascript','.png':'image/png'}[path.extname(name)]||'application/octet-stream'}).end(await fs.readFile(name));}catch{r.writeHead(404).end();}});
 await new Promise(r=>server.listen(0,'127.0.0.1',r));base='http://127.0.0.1:'+server.address().port;
 browser=await chromium.launch({headless:true,executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH||undefined,args:['--no-sandbox','--disable-dev-shm-usage']});
});
after(async()=>{await browser?.close();await new Promise(r=>server?server.close(r):r());});
async function setup(width){const page=await browser.newPage({viewport:{width,height:1000},acceptDownloads:true});
 await page.route('https://chee-chai-chee-backend.onrender.com/api/directory/**',async route=>{
  const url=route.request().url();
  if(url.endsWith('/passport-qr'))return route.fulfill({contentType:'image/svg+xml',body:'<svg xmlns="http://www.w3.org/2000/svg" width="104" height="104" viewBox="0 0 104 104"><rect width="104" height="104" fill="white"/><path d="M10 10h28v28H10zM66 10h28v28H66zM10 66h28v28H10zM46 10h10v10H46zM46 30h10v26H46zM10 46h28v10H10zM66 46h28v10H66zM46 66h10v28H46zM66 66h10v10H66zM84 84h10v10H84z" fill="#102b4d"/></svg>'});
  return route.fulfill({contentType:'application/json',body:JSON.stringify(url.includes('/metrics')?{ok:true}:business)});
 });return page;}
for(const width of [360,1440])test(`Passport at ${width}px: booking, contact, QR and sharing are usable`,async()=>{
 const page=await setup(width),errors=[];page.on('pageerror',e=>errors.push(e.message));
 try{
  await page.goto(base+'/business-directory/passport.html?business='+business.slug);
  await page.getByRole('heading',{name:business.details.name,exact:true}).waitFor();
  assert.equal(await page.getByRole('link',{name:'Book an appointment'}).getAttribute('href'),business.booking.url);
  assert.equal(await page.getByRole('link',{name:'Call business'}).getAttribute('href'),'tel:'+business.details.phone);
  assert(await page.getByText('Home maintenance',{exact:true}).isVisible());
  assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),'No horizontal scrolling');
  const save=page.getByRole('button',{name:'Save contact',exact:true}).filter({visible:true});
  const pending=page.waitForEvent('download');await save.click();const download=await pending;const data=await fs.readFile(await download.path(),'utf8');assert.match(data,/BEGIN:VCARD/);assert.match(data,/Harbour Home Services/);assert.match(data,/TEL;TYPE=WORK:\+15550102030/);
  await page.screenshot({path:path.join(artifacts,`passport-${width}.png`),fullPage:true});assert.deepEqual(errors,[]);
 }finally{await page.close();}
});
test('owner text renders as text and hidden Passports never show stale contact actions',async()=>{
 const page=await setup(390);
 try{
  await page.unroute('https://chee-chai-chee-backend.onrender.com/api/directory/**');
  await page.route('https://chee-chai-chee-backend.onrender.com/api/directory/**',r=>r.fulfill({status:404,contentType:'application/json',body:'{"error":"Business not found."}'}));
  await page.goto(base+'/business-directory/passport.html?business=hidden-fixture');await page.getByText('Business not found.').waitFor();assert.equal(await page.getByRole('link',{name:'Book an appointment'}).count(),0);
  await page.unroute('https://chee-chai-chee-backend.onrender.com/api/directory/**');
  await page.route('https://chee-chai-chee-backend.onrender.com/api/directory/**',r=>r.fulfill({contentType:'application/json',body:JSON.stringify({...business,details:{...business.details,name:'<img src=x onerror="alert(1)">',website:'javascript:alert(1)'}})}));
  await page.goto(base+'/business-directory/passport.html?business=fixture');await page.getByRole('heading',{name:'<img src=x onerror="alert(1)">',exact:true}).waitFor();assert.equal(await page.locator('img[onerror]').count(),0);assert.equal(await page.getByRole('link',{name:'Visit website'}).count(),0);
 }finally{await page.close();}
});
