/* Native commands are named, bounded operations. Credentials never enter JS. */
(() => {
  let sequence = 0;
  const requests = new Map(), listeners = new Set();
  const bridge = {
    call(command, args = {}) {
      if (!window.Korlix) return Promise.reject(new Error('Open this interface in the KORLIX Brain app to connect your account.'));
      return new Promise((resolve, reject) => {
        const id = ++sequence;
        const timer = setTimeout(() => {
          requests.delete(id);
          reject(new Error('The request is taking too long. Refresh My Brain before retrying a save.'));
        }, command === 'analyze' ? 660000 : 120000);
        requests.set(id, {resolve, reject, timer});
        let action=command,payload=args;
        if(command==='analyze')action='pickFile';
        if(command==='deleteMemory')payload={key:args.id,text:args.expected};
        if(command==='deleteBehavior')payload={key:args.index,expected:args.expected};
        window.Korlix.postMessage(JSON.stringify({id:String(id),action,payload}));
      });
    },
    receive(event) {
      if (Number.isInteger(event.id)) {
        const request = requests.get(event.id);
        if (!request) return;
        requests.delete(event.id); clearTimeout(request.timer);
        if (event.ok) request.resolve(event.value);
        else request.reject(new Error(event.error || 'The action could not finish.'));
      } else listeners.forEach(listener => listener(event));
    },
    subscribe(listener) { listeners.add(listener); return () => listeners.delete(listener); }
  };
  window.addEventListener('pagehide', () => {
    requests.forEach(request => { clearTimeout(request.timer); request.reject(new Error('The interface was closed.')); });
    requests.clear();
  });
  window.BrainBridge = bridge;
  window.KorlixBrainReceive = event => {
    if(event.type==='reply')bridge.receive({id:Number(event.id),ok:!event.error,value:event.data,error:event.error});
    else bridge.receive(event);
  };
})();
