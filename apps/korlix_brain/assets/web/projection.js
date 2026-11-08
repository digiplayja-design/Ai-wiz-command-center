/* KORLIX Projection is a local presentation surface. Account and research
 * requests stay in the native workspace. The map frame receives camera data
 * only; it never receives the native bridge nonce or account credentials. */
(() => {
  'use strict';

  const $ = id => document.getElementById(id);
  const clip = (value, length = 2000) => typeof value === 'string' ? value.slice(0, length) : '';
  const isObject = value => value !== null && typeof value === 'object' && !Array.isArray(value);
  const finite = (value, min, max) => typeof value === 'number' && Number.isFinite(value) && value >= min && value <= max;
  const operations = new Set(['closer', 'farther', 'left', 'right', 'reset']);
  const isLocalLiveQuestion = question => /\b(live|real[ -]?time)\b.*\b(view|camera|feed|video|imagery)\b/i.test(question);
  const phases = new Set(['complete', 'connecting', 'listening', 'thinking', 'speaking', 'stopping', 'error']);
  const requests = new Map();
  const transcripts = [];
  const shell = document.querySelector('.projection-shell');
  const busy = {search:false, select:false, ask:false, save:false, close:false};
  let nonce = '', nextId = 0, connected = false, searchEpoch = 0, askEpoch = 0;
  let startPending = false, stopPending = false, startTimer = null, stopTimer = null;
  let voiceViewportActive = false;
  let frame = null, frameOrigin = '', frameUrl = '', mapStatus = 'illustration', lastCamera = '';
  let rendererCreditHeight = 30;
  let rendererTimer = null, canvasInvalidated = true;
  let localNotice = '', localNoticeKind = '', lastSavedPlace = '', pendingQuestionLocal = false;

  const emptyState = () => ({
    open:true, room:'command', loading:false, selectedPlace:null, candidates:[], answer:null,
    notice:'', camera:{sequence:0, operation:'reset'},
    config:{rendererUrl:null, mapAvailable:false, geocodingAvailable:false, answersAvailable:false, answerCredits:0, answerCostLabel:''},
    voice:{active:false, phase:'complete', message:''}
  });
  let state = emptyState();

  function safeUrl(value) {
    try {
      const url = new URL(value);
      return url.protocol === 'https:' && !url.username && !url.password ? url.href : null;
    } catch (_) { return null; }
  }

  function placeValue(raw) {
    if (!isObject(raw) || !clip(raw.id, 512) || !clip(raw.label, 600)) return null;
    if (!finite(raw.latitude, -90, 90) || !finite(raw.longitude, -180, 180)) return null;
    return {id:clip(raw.id,512), label:clip(raw.label,600), address:clip(raw.address,1000),
      latitude:raw.latitude, longitude:raw.longitude, provider:clip(raw.provider,100), partialMatch:raw.partialMatch === true};
  }

  function cameraValue(raw) {
    const camera = {sequence:0, operation:'reset'};
    if (!isObject(raw)) return camera;
    if (Number.isSafeInteger(raw.sequence) && raw.sequence >= 0) camera.sequence = raw.sequence;
    if (operations.has(raw.operation) || raw.operation === 'flyTo') camera.operation = raw.operation;
    for (const [key,min,max] of [['latitude',-90,90],['longitude',-180,180],['height',25,40000000],['heading',-360,360],['pitch',-90,0]]) {
      if (finite(raw[key],min,max)) camera[key] = raw[key];
    }
    return camera;
  }

  function voiceValue(raw) {
    const voice = isObject(raw) ? raw : {};
    const phase = phases.has(voice.phase) ? voice.phase : voice.active === true ? 'listening' : 'complete';
    return {active:voice.active === true && phase !== 'complete' && phase !== 'error', phase, message:clip(voice.message,300)};
  }

  function normalize(raw) {
    const base = emptyState();
    if (!isObject(raw)) return base;
    base.open = raw.open !== false;
    base.room = raw.room === 'discovery' ? 'discovery' : 'command';
    base.loading = raw.loading === true;
    base.selectedPlace = placeValue(raw.selectedPlace);
    base.candidates = (Array.isArray(raw.candidates) ? raw.candidates : []).slice(0,10).map(placeValue).filter(Boolean);
    base.notice = clip(raw.notice,1500);
    base.camera = cameraValue(raw.camera);
    base.voice = voiceValue(raw.voice);
    const config = isObject(raw.config) ? raw.config : {};
    base.config = {rendererUrl:safeUrl(config.rendererUrl), mapAvailable:config.mapAvailable === true,
      geocodingAvailable:config.geocodingAvailable === true, answersAvailable:config.answersAvailable === true,
      answerCredits:finite(config.answerCredits,0,1000000) ? config.answerCredits : 0, answerCostLabel:clip(config.answerCostLabel,300)};
    if (isObject(raw.answer) && clip(raw.answer.text,18000)) {
      base.answer = {text:clip(raw.answer.text,18000), scope:clip(raw.answer.scope,500), date:clip(raw.answer.date,100),
        sources:(Array.isArray(raw.answer.sources) ? raw.answer.sources : []).slice(0,15).filter(isObject).map(source => ({
          title:clip(source.title,300), url:safeUrl(source.url), date:clip(source.date,100)
        })).filter(source => source.url)};
    }
    return base;
  }

  function notice(message, kind = '') {
    localNotice = clip(message,1500); localNoticeKind = kind; renderNotice();
  }

  function renderNotice() {
    $('projection-notice').textContent = localNotice || state.notice || 'Your existing KORLIX conversation stays with you.';
    $('projection-notice').dataset.kind = localNoticeKind;
  }

  function send(action, payload = {}) {
    if (!connected || !nonce || !window.Projection || typeof window.Projection.postMessage !== 'function') {
      return Promise.reject(new Error('Open Projection inside the KORLIX app to connect to Rici.'));
    }
    const id = String(++nextId);
    return new Promise((resolve,reject) => {
      const timeout = action === 'ask' ? 180000 : action === 'startVoice' ? 90000 : 65000;
      const timer = setTimeout(() => {
        requests.delete(id);
        reject(new Error('The response was interrupted. Please try again.'));
      },timeout);
      requests.set(id,{resolve,reject,timer,action});
      try { window.Projection.postMessage(JSON.stringify({id,nonce,action,payload})); }
      catch (_) { clearTimeout(timer); requests.delete(id); reject(new Error('KORLIX could not receive this command. Please try again.')); }
    });
  }

  function fail(error) { notice(error instanceof Error ? error.message : 'This action could not be completed. Please try again.','error'); }

  function textNode(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    node.textContent = text;
    return node;
  }

  function icon(name) {
    const svg = document.createElementNS('http://www.w3.org/2000/svg','svg');
    svg.setAttribute('aria-hidden','true');
    const use = document.createElementNS('http://www.w3.org/2000/svg','use');
    use.setAttribute('href','#icon-' + name); svg.append(use); return svg;
  }

  function renderRoom() {
    const discovery = state.room === 'discovery';
    document.body.dataset.room = state.room;
    document.querySelectorAll('[data-room-choice]').forEach(button => button.setAttribute('aria-pressed',String(button.dataset.roomChoice === state.room)));
    $('room-overline').textContent = discovery ? 'DISCOVERY THEATER / 02' : 'COMMAND CENTER / 01';
    $('scene-title').textContent = discovery ? 'The world is your theater.' : 'A new perspective.';
    $('scene-subtitle').textContent = discovery ? 'Settle in. There’s a world to discover.' : 'Choose a place. Let Rici guide you.';
    canvasInvalidated = true;
  }

  function renderPlace() {
    const place = state.selectedPlace;
    $('place-banner').hidden = !place;
    $('place-label').textContent = place?.label || '';
    $('place-address').textContent = place?.address || '';
    $('place-match').hidden = !place?.partialMatch;
    $('place-banner').querySelector('.place-confirmed').textContent = place?.partialMatch ? 'Partial match' : 'Confirmed';
    $('provider-label').textContent = place?.provider ? clip(place.provider,60).toUpperCase() : 'PROJECTION / EARTH';
    $('save-button').disabled = !connected || !place || busy.save;
    $('save-button').textContent = busy.save ? 'Saving…' : 'Save place';
    $('place-note').disabled = !place || busy.save;
    if (!place) $('save-status').textContent = 'Choose and confirm a destination first.';
    else if ($('save-status').textContent === 'Choose and confirm a destination first.') $('save-status').textContent = '';
    document.querySelectorAll('[data-camera]').forEach(button => {
      button.disabled = !connected || !place || !state.config.mapAvailable || mapStatus !== 'ready';
    });
  }

  function renderCandidates() {
    const list = $('candidates-list'); list.replaceChildren();
    $('candidates-panel').hidden = state.candidates.length === 0;
    $('candidate-count').textContent = state.candidates.length + (state.candidates.length === 1 ? ' result' : ' results');
    state.candidates.forEach(place => {
      const button = document.createElement('button');
      button.type = 'button'; button.className = 'candidate-button'; button.disabled = busy.select;
      const labels = document.createElement('span');
      labels.append(textNode('strong','',place.label),textNode('small','',place.address || 'Confirm this destination'));
      if (place.partialMatch) labels.append(textNode('small','partial-match-warning','Check address — partial match'));
      button.append(icon('pin'),labels,icon('arrow'));
      button.addEventListener('click',async () => {
        if (busy.select) return;
        busy.select = true; notice('Confirming destination…'); renderCandidates();
        try { await send('select',{placeId:place.id}); notice(''); }
        catch (error) { fail(error); }
        finally { busy.select = false; renderCandidates(); }
      });
      list.append(button);
    });
  }

  function renderAnswer() {
    const answer = state.answer;
    $('answer-text').textContent = answer?.text || (state.selectedPlace
      ? `You’re exploring ${state.selectedPlace.label}. What would you like to know?`
      : `Your ${state.room === 'discovery' ? 'Discovery Theater' : 'Command Center'} is open. Where would you like to explore?`);
    const context = answer ? [answer.scope,answer.date ? 'As of ' + answer.date : ''].filter(Boolean).join(' · ') : '';
    $('answer-context').hidden = !context; $('answer-context').textContent = context;
    const sources = $('answer-sources'); sources.replaceChildren();
    sources.hidden = !answer?.sources.length;
    if (answer?.sources.length) {
      sources.append(textNode('span','eyebrow','SOURCES'));
      answer.sources.forEach((source,index) => {
        const button = document.createElement('button'); button.type = 'button'; button.className = 'source-button';
        const span = document.createElement('span');
        span.textContent = `[${index + 1}] ${source.title || new URL(source.url).hostname}`;
        if (source.date) span.append(textNode('small','',source.date));
        button.append(icon('link'),span);
        button.addEventListener('click',() => send('openSource',{url:source.url}).catch(fail));
        sources.append(button);
      });
    }
    const canAsk = connected && !!state.selectedPlace && state.config.answersAvailable && !busy.ask;
    document.querySelectorAll('[data-question]').forEach(button => {
      button.disabled = isLocalLiveQuestion(button.dataset.question) ? !connected || busy.ask : !canAsk;
    });
    $('question-input').disabled = !canAsk;
    $('question-button').disabled = !canAsk;
    $('question-help').textContent = busy.ask ? (pendingQuestionLocal ? 'Checking live-view availability…' : 'Rici is checking sources…') : !state.selectedPlace
      ? 'Select a destination to ask about its surroundings.' : !state.config.answersAvailable
      ? 'Location research will be available when its service is connected.'
      : (state.config.answerCostLabel || (state.config.answerCredits ? state.config.answerCredits + ' credits per sourced lookup.' : 'Answers use sources. Current facts include their available dates.'));
  }

  function renderSearch() {
    $('search-button').disabled = !connected || !state.config.geocodingAvailable || busy.search;
    $('search-button').querySelector('span').textContent = busy.search ? 'Finding…' : 'Explore';
    const help = $('search-help');
    help.firstElementChild.textContent = busy.search ? 'Finding matching destinations…' : connected && !state.config.geocodingAvailable
      ? 'Address search is waiting for a map connection.' : 'Say “Go to…” or enter an address.';
    help.lastElementChild.textContent = 'Confirm a result before traveling.';
  }

  function measureVoiceDock() {
    const height = document.querySelector('.voice-dock').getBoundingClientRect().height;
    if (!Number.isFinite(height)) return;
    document.documentElement.style.setProperty('--voice-dock-height',
      Math.max(0,Math.min(Math.ceil(height),Math.floor(window.innerHeight))) + 'px');
  }

  function renderVoice() {
    const voice = state.voice;
    const phase = stopPending ? 'stopping' : startPending && !voice.active ? 'connecting' : voice.phase;
    const active = voice.active || startPending || stopPending;
    const viewportActive = !['complete','error'].includes(phase);
    const transition = viewportActive !== voiceViewportActive;
    const scrollOffset = transition ? (voiceViewportActive ? shell.scrollTop : window.scrollY) : 0;
    document.body.dataset.voice = phase;
    $('voice-phase').textContent = phase === 'stopping' ? 'Stopping conversation…' : phase === 'connecting' ? 'Connecting to Rici…'
      : voice.message || (active ? 'Rici is with you' : 'Ready when you are');
    $('voice-hint').textContent = active ? 'Your KORLIX conversation continues in this room.' : 'Talk to Rici or type a destination.';
    $('talk-button').disabled = !connected || active;
    $('talk-label').textContent = active ? (phase === 'connecting' ? 'Connecting…' : phase === 'stopping' ? 'Finishing…' : 'Rici is with you') : 'Talk to Rici';
    $('talk-detail').textContent = active ? (phase === 'listening' ? 'Microphone on' : phase === 'speaking' ? 'Rici is speaking' : phase === 'thinking' ? 'Thinking with you' : 'Conversation active') : 'Start conversation';
    $('stop-button').disabled = !connected || !active || stopPending;
    $('stop-label').textContent = stopPending ? 'Stopping…' : 'Stop conversation';
    $('rici-presence').textContent = phase === 'listening' ? 'Listening' : phase === 'speaking' ? 'Speaking' : phase === 'thinking' ? 'Thinking' : active ? 'Connected' : 'Ready';
    measureVoiceDock();
    if (transition) {
      voiceViewportActive = viewportActive;
      if (viewportActive) {
        window.scrollTo(0,0);
        shell.scrollTop = scrollOffset;
      } else {
        shell.scrollTop = 0;
        window.scrollTo(0,scrollOffset);
      }
    }
  }

  function syncVoiceGuards() {
    if (state.voice.active || state.voice.phase === 'complete' || state.voice.phase === 'error') {
      startPending = false; clearTimeout(startTimer);
    }
    if (!state.voice.active && (state.voice.phase === 'complete' || state.voice.phase === 'error')) {
      stopPending = false; clearTimeout(stopTimer);
    }
  }

  function renderTranscripts() {
    $('transcript-count').textContent = transcripts.length + (transcripts.length === 1 ? ' message' : ' messages');
    const list = $('transcript-list'); list.replaceChildren();
    if (!transcripts.length) { list.append(textNode('p','section-help','Your conversation with Rici will appear here.')); return; }
    transcripts.forEach(message => {
      const row = document.createElement('div'); row.className = 'transcript-message';
      row.append(textNode('strong','',message.role === 'user' ? 'You' : 'Rici'),textNode('p','',message.text)); list.append(row);
    });
    if ($('conversation-details').open) list.scrollTop = list.scrollHeight;
  }

  function syncTranscripts(raw) {
    if (!Array.isArray(raw?.transcript)) return;
    transcripts.splice(0,transcripts.length,...raw.transcript.slice(-12).filter(isObject).filter(entry => clip(entry.text,6000)).map(entry => ({
      role:['user','you'].includes(entry.role) ? 'user' : 'assistant',text:clip(entry.text,6000)
    })));
    renderTranscripts();
  }

  function setMapStatus(status, message = '') {
    const previousStatus = mapStatus;
    mapStatus = status;
    const ready = status === 'ready';
    document.body.dataset.map = ready ? 'ready' : 'illustration';
    $('map-container').hidden = !frame;
    $('world-canvas').hidden = ready;
    $('map-badge').lastChild.textContent = ready ? '3D Earth imagery' : status === 'loading' ? 'Connecting map' : 'Illustrative globe';
    $('world-caption-text').textContent = ready ? 'Earth imagery · not a live camera feed' : status === 'loading'
      ? 'Illustrative globe · preparing your map' : 'Illustrative globe · map provider not connected';
    if (message && status === 'error') notice(message,'error');
    canvasInvalidated = true; renderPlace();
    if (connected && status !== previousStatus && ['ready','loading','error'].includes(status)) {
      send('rendererReady',{status}).catch(fail);
    }
  }

  function applyCreditHeight() {
    // A renderer can reserve at most one local viewport of presentation space.
    // The ready scene grows by that amount, keeping its map/control area intact.
    const height = Math.min(rendererCreditHeight, Math.max(0, Math.floor(window.innerHeight)), 4096);
    $('scene-stage').style.setProperty('--map-credit-height', height + 'px');
  }

  function disposeFrame() {
    clearTimeout(rendererTimer);
    frame?.remove(); frame = null; frameOrigin = ''; frameUrl = ''; lastCamera = '';
    rendererCreditHeight = 30; applyCreditHeight();
    $('map-container').replaceChildren(); setMapStatus('illustration');
  }

  function syncRenderer() {
    const url = state.config.mapAvailable ? state.config.rendererUrl : null;
    if (!url) { if (frame) disposeFrame(); return; }
    if (url === frameUrl) { sendCamera(); return; }
    disposeFrame();
    // The native controller additionally validates the API origin and exact
    // renderer path. This layer rejects non-HTTPS and credential-bearing URLs.
    frameOrigin = new URL(url).origin; frameUrl = url;
    frame = document.createElement('iframe'); frame.title = 'KORLIX 3D Earth map';
    frame.setAttribute('sandbox','allow-scripts allow-same-origin');
    frame.setAttribute('referrerpolicy','no-referrer');
    frame.setAttribute('allow',"camera 'none'; microphone 'none'; geolocation 'none'; payment 'none'; clipboard-read 'none'; clipboard-write 'none'");
    frame.src = url; $('map-container').append(frame); setMapStatus('loading');
    rendererTimer = setTimeout(() => { if (mapStatus === 'loading') setMapStatus('error','The map has not connected. You can keep talking to Rici.'); },45000);
  }

  function sendCamera() {
    if (!frame || mapStatus !== 'ready') return;
    const place = state.selectedPlace ? {id:state.selectedPlace.id,label:state.selectedPlace.label,
      latitude:state.selectedPlace.latitude,longitude:state.selectedPlace.longitude} : null;
    const data = {type:'korlix-projection-camera',camera:state.camera,place};
    const serialized = JSON.stringify(data);
    if (serialized === lastCamera) return;
    lastCamera = serialized;
    frame.contentWindow.postMessage(data,frameOrigin);
  }

  window.addEventListener('message',event => {
    if (!frame || event.source !== frame.contentWindow || event.origin !== frameOrigin) return;
    const data = event.data;
    if (!isObject(data)) return;
    if (data.type === 'korlix-projection-credits') {
      if (!Number.isInteger(data.height) || !finite(data.height,0,4096)) return;
      rendererCreditHeight = data.height; applyCreditHeight();
      return;
    }
    if (data.type !== 'korlix-projection-status' || !['loading','ready','error'].includes(data.status)) return;
    const wasReady = mapStatus === 'ready';
    if (data.status !== 'loading') clearTimeout(rendererTimer);
    setMapStatus(data.status,clip(data.message,500));
    if (data.status === 'ready') {
      if (!wasReady) lastCamera = '';
      sendCamera();
    }
  });
  window.addEventListener('resize',applyCreditHeight);

  function render() {
    $('connection-label').textContent = connected ? 'Your KORLIX workspace' : 'Preview · open inside KORLIX';
    $('close-projection').disabled = busy.close;
    renderRoom(); renderPlace(); renderCandidates(); renderAnswer(); renderSearch(); renderVoice(); renderNotice(); syncRenderer();
  }

  window.KorlixProjectionConnect = connection => {
    if (!isObject(connection) || !clip(connection.nonce,512)) return;
    if (nonce && nonce !== connection.nonce) {
      requests.forEach(request => { clearTimeout(request.timer); request.reject(new Error('The projection connection was renewed. Please try again.')); });
      requests.clear(); disposeFrame();
    }
    nonce = clip(connection.nonce,512); connected = true;
    state = normalize(connection.snapshot); localNotice = ''; localNoticeKind = '';
    syncTranscripts(connection.snapshot);
    syncVoiceGuards(); render();
  };

  window.KorlixProjectionReceive = message => {
    if (!connected || !isObject(message)) return;
    if (message.type === 'snapshot') {
      const previousId = state.selectedPlace?.id;
      state = normalize(message.state);
      syncTranscripts(message.state);
      if (previousId !== state.selectedPlace?.id) { lastSavedPlace = ''; $('save-status').textContent = ''; }
      localNotice = ''; localNoticeKind = ''; syncVoiceGuards(); render();
    } else if (message.type === 'reply') {
      const id = typeof message.id === 'string' ? message.id : '';
      const request = requests.get(id); if (!request) return;
      clearTimeout(request.timer); requests.delete(id);
      if (message.error) request.reject(new Error(clip(typeof message.error === 'string' ? message.error : message.error.message,1500) || 'This action could not be completed.'));
      else request.resolve(message.data);
    } else if (message.type === 'voice') {
      const phase = phases.has(message.phase) ? message.phase : 'complete';
      state.voice = voiceValue({active:!['complete','error'].includes(phase),phase,message:message.message});
      syncVoiceGuards(); renderVoice();
    } else if (message.type === 'transcript' && clip(message.text,6000)) {
      const entry = {role:['user','you'].includes(message.role) ? 'user' : 'assistant',text:clip(message.text,6000)};
      const last = transcripts.at(-1);
      if (!last || last.role !== entry.role || last.text !== entry.text) transcripts.push(entry);
      if (transcripts.length > 12) transcripts.splice(0,transcripts.length - 12);
      renderTranscripts();
    }
  };

  document.querySelectorAll('[data-room-choice]').forEach(button => button.addEventListener('click',async () => {
    const room = button.dataset.roomChoice;
    if (room === state.room) return;
    const previous = state.room; state.room = room; renderRoom(); renderAnswer();
    if (!connected) return;
    try { await send('room',{room}); }
    catch (error) { state.room = previous; renderRoom(); renderAnswer(); fail(error); }
  }));

  $('close-projection').addEventListener('click',async () => {
    if (busy.close) return;
    busy.close = true; $('close-projection').disabled = true;
    try { await send('close'); }
    catch (error) { fail(error); }
    finally { busy.close = false; $('close-projection').disabled = false; }
  });

  $('search-form').addEventListener('submit',async event => {
    event.preventDefault();
    const query = $('destination-input').value.trim();
    if (!query || busy.search || !connected || !state.config.geocodingAvailable) return;
    const epoch = ++searchEpoch; busy.search = true; notice(''); renderSearch();
    try { await send('search',{query:query.slice(0,300)}); }
    catch (error) { if (epoch === searchEpoch) fail(error); }
    finally { if (epoch === searchEpoch) { busy.search = false; renderSearch(); } }
  });

  async function ask(question) {
    const local = isLocalLiveQuestion(question);
    if (!question || busy.ask || !connected || (!local && (!state.selectedPlace || !state.config.answersAvailable))) return;
    const epoch = ++askEpoch; busy.ask = true; pendingQuestionLocal = local; notice(''); renderAnswer();
    try { await send('ask',{question:question.slice(0,1000)}); if (epoch === askEpoch) $('question-input').value = ''; }
    catch (error) { if (epoch === askEpoch) fail(error); }
    finally { if (epoch === askEpoch) { busy.ask = false; pendingQuestionLocal = false; renderAnswer(); } }
  }
  document.querySelectorAll('[data-question]').forEach(button => button.addEventListener('click',() => ask(button.dataset.question)));
  $('question-form').addEventListener('submit',event => { event.preventDefault(); ask($('question-input').value.trim()); });
  document.querySelectorAll('[data-camera]').forEach(button => button.addEventListener('click',() => send('camera',{operation:button.dataset.camera}).catch(fail)));

  $('save-form').addEventListener('submit',async event => {
    event.preventDefault();
    if (!state.selectedPlace || busy.save) return;
    const placeId = state.selectedPlace.id;
    busy.save = true; $('save-status').textContent = ''; renderPlace();
    try {
      const result = await send('savePlace',{note:$('place-note').value.trim().slice(0,1600)});
      if (result?.saved !== true) throw new Error(clip(result?.message,1000) || 'This place was not saved. Please try again.');
      if (state.selectedPlace?.id === placeId) {
        lastSavedPlace = placeId; $('save-status').textContent = 'Place saved to My Brain.'; $('place-note').value = '';
      }
      notice('Place saved to My Brain.');
    } catch (error) {
      $('save-status').textContent = error instanceof Error ? error.message : 'This place could not be saved.';
      fail(error);
    } finally { busy.save = false; renderPlace(); }
  });

  $('talk-button').addEventListener('click',async () => {
    if (state.voice.active || startPending || stopPending) return;
    startPending = true; notice(''); renderVoice();
    startTimer = setTimeout(() => {
      if (startPending) { startPending = false; renderVoice(); notice('Rici’s connection status was not received. Please try again.','error'); }
    },90000);
    try {
      const result = await send('startVoice');
      if (typeof result?.active === 'boolean' && startPending) {
        state.voice = {active:result.active,phase:result.active ? 'listening' : 'complete',message:result.active ? 'Rici is listening' : 'Microphone off'};
        syncVoiceGuards(); renderVoice();
      }
    } catch (error) { startPending = false; clearTimeout(startTimer); renderVoice(); fail(error); }
  });

  $('stop-button').addEventListener('click',async () => {
    if (stopPending || (!state.voice.active && !startPending)) return;
    stopPending = true; startPending = false; clearTimeout(startTimer); renderVoice();
    stopTimer = setTimeout(() => {
      if (stopPending) { stopPending = false; renderVoice(); notice('Stop has not been confirmed. Please tap Stop conversation again.','error'); }
    },65000);
    try {
      const result = await send('stopVoice');
      if (result?.active === false) {
        state.voice = {active:false,phase:'complete',message:'Microphone off'}; syncVoiceGuards(); renderVoice();
      }
    } catch (error) { stopPending = false; clearTimeout(stopTimer); renderVoice(); fail(error); }
  });

  // The globe is intentionally illustrative. No canvas shapes are represented
  // as geocoded locations, satellite imagery, street view, or a live feed.
  const canvas = $('world-canvas');
  const ctx = canvas.getContext('2d');
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let canvasWidth = 0, canvasHeight = 0, lastDraw = 0;
  const stars = Array.from({length:95},(_,i) => ({x:((i * 197 + 19) % 997) / 997,y:((i * 131 + 89) % 991) / 991,r:i % 5 === 0 ? 1 : .55}));
  const lands = [
    [[-165,65],[-145,72],[-128,68],[-110,72],[-95,65],[-81,56],[-59,49],[-72,44],[-81,25],[-98,19],[-107,30],[-123,39],[-129,53],[-150,56]],
    [[-78,10],[-64,11],[-50,2],[-35,-7],[-40,-22],[-52,-33],[-67,-54],[-74,-42],[-75,-23],[-81,-5]],
    [[-17,34],[4,37],[24,33],[33,24],[43,11],[50,9],[42,-4],[40,-17],[28,-34],[17,-35],[10,-20],[2,3],[-14,6],[-17,20]],
    [[-10,36],[-8,49],[5,57],[9,70],[30,70],[39,57],[58,55],[68,70],[110,73],[140,61],[170,65],[173,52],[145,45],[138,34],[121,23],[109,4],[99,8],[87,21],[79,8],[68,24],[49,29],[39,40],[28,41],[19,36]],
    [[113,-22],[124,-13],[138,-12],[146,-19],[153,-28],[147,-39],[131,-32],[116,-34]],
    [[-54,60],[-42,61],[-24,75],[-41,83],[-62,77]]
  ];

  function resizeCanvas() {
    const rect = canvas.parentElement.getBoundingClientRect();
    canvasWidth = rect.width; canvasHeight = rect.height;
    const dpr = Math.min(window.devicePixelRatio || 1,2);
    canvas.width = Math.round(rect.width * dpr); canvas.height = Math.round(rect.height * dpr);
    ctx?.setTransform(dpr,0,0,dpr,0,0); canvasInvalidated = true;
  }

  function drawGlobe(now) {
    if (!ctx || !canvasWidth || mapStatus === 'ready') return;
    const w = canvasWidth, h = canvasHeight, theater = state.room === 'discovery';
    ctx.clearRect(0,0,w,h);
    stars.forEach(star => { ctx.beginPath(); ctx.arc(star.x*w,star.y*h,star.r,0,Math.PI*2); ctx.fillStyle = star.r === 1 ? '#ddccea73' : '#9e98c84a'; ctx.fill(); });
    const mobile = w < 450, cx = w*.49, cy = h*(mobile ? .57 : .51), radius = Math.min(w*.32,h*.335);
    const rotation = -.55 + (reducedMotion.matches ? 0 : now*.000006);
    const tilt = -.12;
    const project = (longitude,latitude) => {
      const lon = longitude*Math.PI/180 + rotation, lat = latitude*Math.PI/180;
      const x = Math.cos(lat)*Math.sin(lon), y0 = Math.sin(lat), z0 = Math.cos(lat)*Math.cos(lon);
      const y = y0*Math.cos(tilt) - z0*Math.sin(tilt), z = y0*Math.sin(tilt) + z0*Math.cos(tilt);
      return [cx+x*radius,cy-y*radius,z];
    };
    const halo = ctx.createRadialGradient(cx,cy,radius*.75,cx,cy,radius*1.48);
    halo.addColorStop(0,'#8d91e914'); halo.addColorStop(.45,theater ? '#cf9ea926' : '#87b3d526'); halo.addColorStop(.68,'#9ab7c90b'); halo.addColorStop(1,'#5d8fad00');
    ctx.fillStyle = halo; ctx.fillRect(cx-radius*1.5,cy-radius*1.5,radius*3,radius*3);
    ctx.save(); ctx.beginPath(); ctx.arc(cx,cy,radius,0,Math.PI*2); ctx.clip();
    const globe = ctx.createRadialGradient(cx-radius*.35,cy-radius*.4,0,cx,cy,radius*1.15);
    globe.addColorStop(0,'#3d4d6b'); globe.addColorStop(.45,'#24334b'); globe.addColorStop(.82,'#101b2d'); globe.addColorStop(1,'#080e1c');
    ctx.fillStyle = globe; ctx.fillRect(cx-radius,cy-radius,radius*2,radius*2);
    function plot(points,stroke,fill) {
      ctx.beginPath(); let drawing = false;
      points.forEach(([lon,lat]) => { const [x,y,z] = project(lon,lat); if (z < 0) { drawing = false; return; } if (!drawing) ctx.moveTo(x,y); else ctx.lineTo(x,y); drawing = true; });
      if (fill) { ctx.closePath(); ctx.fillStyle=fill; ctx.fill(); }
      ctx.strokeStyle=stroke;ctx.stroke();
    }
    ctx.lineWidth=.65;
    for (let lat=-60;lat<=60;lat+=20) { const points=[]; for (let lon=-180;lon<=180;lon+=3) points.push([lon,lat]); plot(points,'#b6cce922'); }
    for (let lon=-180;lon<180;lon+=20) { const points=[]; for (let lat=-90;lat<=90;lat+=3) points.push([lon,lat]); plot(points,'#b6cce924'); }
    lands.forEach(land => plot(land,'#c2c5bb6b',theater ? '#b5ad8c34' : '#a0b9b43d'));
    for (let i=0;i<180;i++) {
      const longitude=(i*137.5)%360-180, latitude=((i*47)%126)-63;
      const [x,y,z] = project(longitude,latitude);
      if (z>.15 && i%3===0) { ctx.fillStyle=i%5===0?'#f0d4a7a6':'#adcaeb45'; ctx.fillRect(x,y,i%5===0?1.2:.7,i%5===0?1.2:.7); }
    }
    const shade=ctx.createLinearGradient(cx-radius,cy,cx+radius,cy);shade.addColorStop(0,'#07081100');shade.addColorStop(.5,'#0507110a');shade.addColorStop(1,'#03050ed6');ctx.fillStyle=shade;ctx.fillRect(cx-radius,cy-radius,radius*2,radius*2);
    ctx.restore();
    ctx.beginPath();ctx.arc(cx,cy,radius,0,Math.PI*2);ctx.lineWidth=1;ctx.strokeStyle='#c4d3ed65';ctx.stroke();
    ctx.beginPath();ctx.ellipse(cx,cy+radius*.13,radius*1.24,radius*.27,-.24,0,Math.PI*2);ctx.lineWidth=.6;ctx.strokeStyle=theater?'#dec19340':'#b4a7db38';ctx.stroke();
    ctx.beginPath();ctx.ellipse(cx,cy+radius*.09,radius*1.3,radius*.3,.25,Math.PI*.1,Math.PI*1.1);ctx.strokeStyle='#dec1933d';ctx.stroke();
    const floor=ctx.createRadialGradient(cx,h*.85,0,cx,h*.85,radius*.85);floor.addColorStop(0,'#caac7730');floor.addColorStop(1,'#caac7700');ctx.save();ctx.translate(0,h*.85*.85);ctx.scale(1,.15);ctx.fillStyle=floor;ctx.fillRect(cx-radius,h*.85-radius,radius*2,radius*2);ctx.restore();
  }
  function animate(now) {
    if (!document.hidden && (canvasInvalidated || (!reducedMotion.matches && now-lastDraw>80))) {
      drawGlobe(now); lastDraw=now; canvasInvalidated=false;
    }
    requestAnimationFrame(animate);
  }
  new ResizeObserver(resizeCanvas).observe($('scene-stage'));
  new ResizeObserver(measureVoiceDock).observe(document.querySelector('.voice-dock'));
  reducedMotion.addEventListener('change',() => { canvasInvalidated=true; });
  document.addEventListener('visibilitychange',() => { canvasInvalidated=true; });
  render(); resizeCanvas(); requestAnimationFrame(animate);
})();
