// Runs the exported runtime with an in-memory DOM fixture. This is not a browser or visual test.
import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {template} from '../app_studio/model.mjs';
const source=readFileSync(new URL('../app_studio/runtime.js',import.meta.url),'utf8');
class Element {
 constructor(tag,text=''){this.tag=tag;this.textContent=text;this.children=[];this.events={};this.value='';this.checked=false;this.required=false;this.validation='';this.style={setProperty(){}};this.classList={toggle(){}};}
 append(...items){for(const x of items){this.children.push(x);x.parent=this;}}
 replaceChildren(...items){this.children=[];this.append(...items);}
 setAttribute(key,value){this[key]=value;}
 setCustomValidity(value){this.validation=value;}
 addEventListener(name,fn){(this.events[name]??=[]).push(fn);}
 async emit(name){for(const fn of this.events[name]||[])await fn({preventDefault(){}});}
 click(){for(const fn of this.events.click||[])fn({preventDefault(){}});return Promise.resolve();}
 remove(){if(this.parent)this.parent.children=this.parent.children.filter(x=>x!==this);}
 showModal(){this.open=true;}
 close(){this.open=false;this.emit('close');}
 reportValidity(){return flatten(this).filter(x=>['input','select'].includes(x.tag)).every(x=>!x.validation&&(!x.required||(x.type==='checkbox'?x.checked:!!x.value)));}
}
function flatten(e){return [e,...e.children.flatMap(flatten)];}
function fixture({preview=false,saved=null,storageError=false,starter='crm'}={}){
 const body=new Element('body'),root=new Element('div');body.append(root);const s=template(starter),specNode=new Element('script',JSON.stringify(s));let stored=saved;let writes=0;
 const document={body,documentElement:new Element('html'),getElementById:id=>id==='app'?root:specNode,createElement:t=>new Element(t)};
 vm.runInNewContext(source,{IS_PREVIEW:preview,STORAGE_KEY:'fixture',document,Option:function(text,value){const x=new Element('option',text);x.value=value;return x;},localStorage:{getItem(){if(storageError)throw Error('Unavailable');return stored;},setItem(k,v){if(storageError)throw Error('Unavailable');writes++;stored=v;}},URL:{createObjectURL:()=> 'blob:fixture',revokeObjectURL(){}},Blob:class{},setTimeout(){},alert(){}},{timeout:1000});
 const find=(tag,text)=>{const rows=flatten(body).filter(x=>x.tag===tag&&(text===undefined||x.textContent===text));assert(rows.length,`Missing ${tag}: ${text}`);return rows[0];};
 const input=label=>{const e=find('label',label);return e.children[0];};
 return {body,root,find,input,stored:()=>stored,writes:()=>writes,text:()=>flatten(body).map(x=>x.textContent).join('\n')};
}
test('exported app supports creating a contact and persists it locally',async()=>{const f=fixture();await f.find('button','Contacts').click();await f.find('button','Add Contact').click();for(const [label,value] of [['Name *','Avery Sample'],['Email','avery@example.com'],['Company','Sample Co'],['Notes','Follow up']])f.input(label).value=value;await f.find('form').emit('submit');assert(f.text().includes('Avery Sample'));assert.equal(f.writes(),1);assert(JSON.parse(f.stored()).contacts.some(r=>r.name==='Avery Sample'));});
test('required whitespace-only values do not save',async()=>{const f=fixture();await f.find('button','Contacts').click();await f.find('button','Add Contact').click();for(const label of ['Name *','Email','Company','Notes'])f.input(label).value=' ';await f.find('form').emit('submit');assert.equal(f.writes(),0);assert(f.input('Name *').validation);});
test('search filters cards and an empty result explains how to recover',async()=>{const f=fixture();await f.find('button','Contacts').click();const search=f.find('input');search.value='Taylor';await search.emit('input');assert(f.text().includes('Taylor Chen'));assert(!f.text().includes('Jordan Ellis'));search.value='nothing matches';await search.emit('input');assert(f.text().includes('No records here yet'));});
test('editing and confirmed removal update the real runtime data',async()=>{const f=fixture();await f.find('button','Contacts').click();await f.find('button','Edit').click();f.input('Name *').value='Updated Contact';await f.find('form').emit('submit');assert(f.text().includes('Updated Contact'));await f.find('button','Delete').click();assert(f.text().includes('Delete this contact?'));await f.find('button','Confirm').click();await Promise.resolve();assert(!f.text().includes('Updated Contact'));assert.equal(JSON.parse(f.stored()).contacts.length,1);});
test('status boards and choice filters show relevant opportunities',async()=>{const f=fixture();await f.find('button','Opportunities').click();assert(f.text().includes('New · 1'));assert(f.text().includes('In progress · 1'));const select=f.find('select');select.value='New';await select.emit('change');assert(f.text().includes('Website refresh'));assert(!f.text().includes('Monthly support'));});
test('sandbox preview has no browser storage or export-data side effects',async()=>{const f=fixture({preview:true,storageError:true});assert(!f.text().includes('Browser saving is unavailable'));assert(!f.text().includes('Export data'));await f.find('button','Contacts').click();await f.find('button','Edit').click();f.input('Name *').value='Temporary Preview';await f.find('form').emit('submit');assert(f.text().includes('Temporary Preview'));assert.equal(f.writes(),0);});
test('unavailable browser storage is disclosed and malformed saved state falls back to samples',()=>{const f=fixture({storageError:true});assert(f.text().includes('Browser saving is unavailable'));assert(f.text().includes('Your local workspace'));const g=fixture({saved:'{"contacts":"invalid"}'});assert(g.text().includes('Contacts'));});
test('all six starter schemas render through the same exported runtime',()=>{for(const starter of ['crm','bookings','inventory','projects','fieldwork','personal']){const f=fixture({starter});assert(f.text().includes(template(starter).name));assert(f.text().includes('Overview'));}});
