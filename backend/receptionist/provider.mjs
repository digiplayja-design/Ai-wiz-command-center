import {fail,uuid,sessionSecret} from './core.mjs';

export function receptionistProvider(environment=process.env,fetcher=fetch){
  const key=environment.KORLIX_RECEPTIONIST_VAPI_KEY||environment.VAPI_PRIVATE_KEY||environment.VAPI_API_KEY;
  const secret=environment.KORLIX_RECEPTIONIST_SERVER_SECRET||environment.KORLIX_VAPI_SERVER_SECRET||'';
  const root=(environment.KORLIX_RECEPTIONIST_PUBLIC_URL||'https://chee-chai-chee-backend.onrender.com').replace(/\/$/,'');
  async function request(path,method='GET',body){
    if(!key)fail('Phone connection is awaiting platform setup. You can save settings and preview your receptionist now.',503);
    const r=await fetcher('https://api.vapi.ai'+path,{method,headers:{Authorization:`Bearer ${key}`,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{}),signal:AbortSignal.timeout(12000)});
    if(!r.ok)fail('The phone provider could not confirm this connection. Please retry or contact support.',503);
    return r.json();
  }
  const hook=root+'/api/receptionist/provider/events';
  function unused(line){return !line.assistantId&&!line.squadId&&!line.workflowId&&!line.server?.url&&!line.serverUrl;}
  async function lines(){const data=await request('/phone-number');return (Array.isArray(data)?data:[]).filter(unused).map(l=>({id:l.id,number:l.number})).filter(l=>/^\+[1-9]\d{7,14}$/.test(l.number||''));}
  async function connect(id,commit){
    if(!secret)fail('Phone authentication needs platform setup.',503);
    const line=await request('/phone-number/'+uuid(id));
    if(!unused(line))fail('Choose an unused phone line. This number already has call routing.',409);
    if(!/^\+[1-9]\d{7,14}$/.test(line.number||''))fail('Choose a valid telephone number.',409);
    await request('/phone-number/'+id,'PATCH',{server:{url:hook,headers:{'x-vapi-secret':secret},timeoutSeconds:7}});
    try{return await commit({provider_id:line.id,number:line.number});}
    catch(error){
      // Restore only the unassigned routing state we just observed; never remove
      // an existing assistant or transfer a number from another service.
      await request('/phone-number/'+id,'PATCH',{server:null}).catch(()=>{});
      throw error;
    }
  }
  function assistant(call){
    const s=call.snapshot.settings,b=call.snapshot.business;
    return {name:('K-Nova · '+b.name).slice(0,40),
      firstMessage:`Hello, I'm K-Nova, the AI receptionist for ${b.name}. This call is processed by AI. I can save your request for the business. ${s.greeting||'How can I help you today?'}`,
      firstMessageMode:'assistant-speaks-first',maxDurationSeconds:call.max_seconds,
      model:{provider:'custom-llm',url:root+'/api/receptionist/model',model:'gpt-6-astra',metadataSendMode:'variable',numFastTurns:0,
        headers:{'x-korlix-call-key':sessionSecret(secret,call.id)},timeoutSeconds:120,messages:[]},
      voice:{provider:'openai',voiceId:s.voice||'coral',model:'gpt-4o-mini-tts'},
      transcriber:{provider:'openai',model:'gpt-4o-transcribe'},
      server:{url:hook,headers:{'x-vapi-secret':secret}},serverMessages:['end-of-call-report','status-update'],
      artifactPlan:{recordingEnabled:false,videoRecordingEnabled:false,loggingEnabled:false,pcapEnabled:false,transcriptPlan:{enabled:false}},
      analysisPlan:{summaryPlan:{enabled:false},successEvaluationPlan:{enabled:false},structuredDataPlan:{enabled:false}},
    };
  }
  return {secret,ready:!!secret,connectionReady:!!key&&!!secret,lines,connect,assistant};
}
