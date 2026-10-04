// Executes the trusted hosted runtime with a DOM/network fixture; not a browser layout test.
import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
const source=readFileSync(new URL('../app_studio/portal_runtime.js',import.meta.url),'utf8');
class Element{
 constructor(tag,text=''){this.tag=tag;this.textContent=text;this.children=[];this.events={};this.value='';this.style={setProperty(){}};this.disabled=false;}
 append(...items){for(const item of items){this.children.push(item);item.parent=this;}}
 prepend(...items){for(const item of [...items].reverse()){this.children.unshift(item);item.parent=this;}}
 replaceChildren(...items){this.children=[];this.append(...items);}
 setAttribute(k,v){this[k]=v;}addEventListener(k,fn){(this.events[k]??=[]).push(fn);}
 async emit(k){for(const fn of this.events[k]||[])await fn({preventDefault(){}});}
 async click(){await this.emit('click');}focus(){}scrollIntoView(){}remove(){if(this.parent)this.parent.children=this.parent.children.filter(x=>x!==this);}
 reportValidity(){return flatten(this).every(x=>!x.required||String(x.value).trim());}
}
const flatten=e=>[e,...e.children.flatMap(flatten)];
async function fixture({role='customer',launch=true,failExchange=false,requestFailure=false,theme='light'}={}){
 const id=randomUUID(),rid=randomUUID(),customerId=randomUUID(),body=new Element('body'),root=new Element('main');root.id='app';body.append(root);
 const portal={id,name:'<img src=x onerror=alert(1)> Example team',description:'<script>bad()</script> Welcome',theme,accent:'#872ed1',role,payment_url:'https://pay.example.test/customer'};
 const calls=[],replaced=[],requests=[{id:rid,customer_id:customerId,customer_email:'customer@example.test',title:'Leaking tap',description:'Please check the kitchen tap',status:'open',version:1,created_at:'2026-10-01T12:00:00Z',updated_at:'2026-10-01T12:00:00Z'}],messages=[],files=[];
 const config=new Element('script',JSON.stringify({id,signInUrl:'https://www.korlixdeveloper.com/app/?app_portal='+id}));config.id='portal-config';body.append(config);
 const document={body,documentElement:new Element('html'),getElementById:key=>flatten(body).find(x=>x.id===key)||null,createElement:t=>new Element(t)};
 let failCreate=requestFailure;
 class Form{append(){}}
 const fetch=async(url,opts)=>{calls.push({url,opts});const path=url.replace('/api/app-studio/portals/'+id+'/runtime',''),data=opts.body&&! (opts.body instanceof Form)?JSON.parse(opts.body):null;let status=200,result={};
  if(path==='/exchange'){if(failExchange){status=403;result={error:'This launch link expired.'};}else result={portal,token:'t'.repeat(43)};}
  else if(path==='')result={portal,requests};
  else if(path==='/requests'&&opts.method==='POST'){if(failCreate){failCreate=false;status=503;result={error:'Connection interrupted. Retry this request.'};}else{const r={...requests[0],id:data.request_key,title:data.title,description:data.description};requests.push(r);result={request:r};}}
  else if(path.endsWith('/messages'))messages.push({id:data.request_key,body:data.body,author_role:role,created_at:'2026-10-01T13:00:00Z'});
  else if(path.endsWith('/status')){Object.assign(requests.find(r=>path.includes(r.id)),{status:data.status,version:2});}
  else if(path.startsWith('/requests/')){const r=requests.find(r=>path.includes(r.id));if(opts.method==='DELETE')requests.splice(requests.indexOf(r),1);else result={request:r,messages,files};}
  return {ok:status<300,status,json:async()=>result,blob:async()=>new Blob(['fixture'])};
 };
 vm.runInNewContext(source,{document,fetch,FormData:Form,URLSearchParams,location:{hash:launch?'#launch='+'l'.repeat(43):'',pathname:'/portals/'+id+'/'},history:{replaceState:(...args)=>replaced.push(args)},crypto:{randomUUID},URL:{createObjectURL:()=> 'blob:fixture',revokeObjectURL(){}},setTimeout,console},{timeout:2000});
 const settle=async()=>{for(let i=0;i<8;i++)await new Promise(r=>setImmediate(r));};await settle();
 const nodes=()=>flatten(root),text=()=>nodes().map(n=>n.textContent).join('\n'),find=(tag,t)=>{const found=nodes().find(x=>x.tag===tag&&(t===undefined||x.textContent===t));assert(found,'Missing '+tag+': '+t+'\n'+text());return found;};
 return {id,portal,root,calls,replaced,requests,messages,nodes,text,find,settle,field:label=>find('label',label).children[0],click:async label=>{await find('button',label).click();await settle();},submit:async()=>{await find('form').emit('submit');await settle();}};
}
test('private landing without launch presents Korlix sign-in and performs no data request',async()=>{const f=await fixture({launch:false});assert(f.text().includes('Your work, in one place.'));assert.match(f.find('a','Continue with KORLIX').href,/app_portal=/);assert.equal(f.calls.length,0);});
test('launch credentials are removed from history, exchanged once and kept out of links',async()=>{const f=await fixture();assert.equal(f.replaced[0][2],'/portals/'+f.id+'/');assert.equal(f.calls[0].opts.headers.Authorization,undefined);assert.equal(JSON.parse(f.calls[0].opts.body).code,'l'.repeat(43));assert.equal(f.calls[1].opts.headers.Authorization,'Portal '+'t'.repeat(43));for(const a of f.nodes().filter(x=>x.tag==='a'))assert(!a.href.includes('launch='));assert(!f.text().includes('t'.repeat(43)));});
test('expired launch offers a working sign-in recovery instead of leaving a loading screen',async()=>{const f=await fixture({failExchange:true});assert(f.text().includes('This launch link expired.'));assert(f.find('a','Continue with KORLIX'));assert.equal(f.calls.length,1);});
test('project labels and conversation strings render as literal text with no executable markup',async()=>{const f=await fixture();assert(f.text().includes('<img src=x onerror=alert(1)>'));assert(f.text().includes('<script>bad()</script>'));assert.equal(f.nodes().filter(x=>['img','script'].includes(x.tag)).length,0);await f.click('Open request');f.field('Reply').value='<svg onload=alert(1)>';await f.submit();assert.equal(f.messages[0].body,'<svg onload=alert(1)>');assert(f.text().includes('<svg onload=alert(1)>'));assert.equal(f.nodes().filter(x=>x.tag==='svg').length,0);});
test('failed request retains entered values and retry reuses the same operation key',async()=>{const f=await fixture({requestFailure:true});await f.click('＋ New request');f.field('Request title').value='New service call';f.field('Details').value='Please call before arrival.';await f.submit();assert(f.text().includes('Connection interrupted'));assert.equal(f.field('Details').value,'Please call before arrival.');await f.submit();const creates=f.calls.filter(x=>x.url.endsWith('/requests')&&x.opts.method==='POST');assert.equal(creates.length,2);assert.equal(JSON.parse(creates[0].opts.body).request_key,JSON.parse(creates[1].opts.body).request_key);assert(f.text().includes('New service call'));});
test('staff can change status and customer runtime has no staff controls',async()=>{const c=await fixture();await c.click('Open request');assert(!c.text().includes('Save status'));assert(!c.text().includes('Delete request'));const s=await fixture({role:'staff'});await s.click('Open request');s.find('select').value='completed';await s.click('Save status');assert.equal(s.requests[0].status,'completed');assert(s.text().includes('Completed'));});
test('request deletion requires explicit confirmation and uses current version',async()=>{const f=await fixture({role:'owner'});await f.click('Open request');await f.click('Delete request');assert(f.text().includes('This cannot be undone'));assert.equal(f.calls.filter(x=>x.opts.method==='DELETE').length,0);await f.click('Confirm');assert.equal(f.requests.length,0);const d=f.calls.find(x=>x.opts.method==='DELETE');assert.deepEqual(JSON.parse(d.opts.body),{version:1,confirmed:true});});
test('search and external checkout explain the supported workflow; logout revokes the scoped session',async()=>{const f=await fixture({theme:'dark'});const pay=f.find('a','Open external checkout');assert.equal(pay.rel,'noopener noreferrer');assert(f.text().includes('payment status is not tracked here'));const search=f.find('input');search.value='not present';await search.emit('input');assert(f.text().includes('No matching requests'));await f.click('Sign out of portal');assert(f.calls.some(x=>x.url.endsWith('/logout')));assert(f.text().includes('You have signed out'));assert(!f.text().includes('Leaking tap'));});
