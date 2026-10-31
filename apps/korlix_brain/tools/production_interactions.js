  // The bundled view never receives an access token. Only this fixed command
  // vocabulary can cross the native bridge; all account requests stay native.
  let training='', memories=[], pending=null, deletion=null, canUndo=false;
  let memorySource='Typed entry',trainingSource='Typed instructions';
  let voiceActive=false, lastUserTranscript='', ready=false, writing=false;
  let requestNumber=0;
  const requests=new Map();
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
      const index=phases.findIndex(p=>p.key===message.phase);
      if(index>=0)setPhase(index);
      voiceActive=message.phase!=='complete';
      get('kb-voice-phase').textContent=message.message;
      get('kb-replay-demo').textContent=voiceActive?'Stop conversation':'Start conversation';
      root.dataset.voiceActive=String(voiceActive);refreshMusic();
    }else if(message.type==='transcript'&&message.text){
      const row=document.createElement('div');row.className='kb-bubble';
      const label=document.createElement('small');label.textContent=message.role==='you'?'YOU':'RICI';
      const text=document.createElement('p');text.textContent=message.text;row.append(label,text);
      if(message.role==='rici')row.append(makeButton('Report response',()=>native('report',{text:message.text}).then(result=>{if(result?.submitted)announce('Report received. Thank you.');}).catch(fail)));
      else {lastUserTranscript=message.text;get('kb-talk-review').disabled=false;}
      get('kb-transcript').append(row);
      while(get('kb-transcript').children.length>60)get('kb-transcript').firstChild.remove();
    }else if(message.type==='dictation'){
      const target=message.kind==='training'?'kb-training':'kb-memory';
      get(target).value=message.text;
      if(message.kind==='training')trainingSource='Voice';else memorySource='Voice';
      announce(message.final?'Dictation ready. Review before saving.':'Listening… tap Stop dictation when finished.');
    }else if(message.type==='dictationStatus'){
      announce(message.message);
    }
  };
  const fail=error=>announce(error.message||'Could not complete this action. Please try again.');
  function applySnapshot(snapshot){
    training=snapshot.training||'';
    memories=(snapshot.memories||[]).map(m=>({id:m.id,text:m.content,source:m.source||'Approved memory'}));
    canUndo=!!snapshot.canUndo;ready=true;
    get('kb-account-status').textContent='Account connected';
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
    if(name!=='home')finishIntro();
    if(name!=='transfer'){transferState=null;transferStage.dataset.transfer='ready';}
    if((currentScreen==='train'||currentScreen==='memory')&&name!==currentScreen)native('stopDictation').catch(()=>{});
    currentScreen=name;screens.forEach(screen=>{screen.hidden=screen.dataset.screen!==name;});announce('');
    root.dataset.screen=name;musicScreenChanged();
    if(name==='brain')renderBrain();
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
  function dictate(kind){native('dictate',{kind}).catch(fail);}
  function toggleVoice(){native(voiceActive?'stopVoice':'startVoice').catch(fail);}
  root.querySelectorAll('[data-go]').forEach(button=>button.addEventListener('click',()=>cinematicNavigate(button,()=>{
    if(writing){announce('Please wait for this change to finish.');return;}
    pending=null;deletion=null;show(button.dataset.go);
    if(button.dataset.go==='brain')refresh();
    if(button.dataset.go==='talk'&&!voiceActive)native('startVoice').catch(fail);
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
  get('kb-account').addEventListener('click',()=>native('account').catch(fail));get('kb-refresh').addEventListener('click',refresh);
  get('kb-return-voice').addEventListener('click',()=>show('talk'));
  get('kb-stop-voice').addEventListener('click',()=>native('stopVoice').catch(fail));
  setPhase(3);refresh();
