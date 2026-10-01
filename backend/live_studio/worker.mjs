import 'dotenv/config';
import {randomUUID} from 'node:crypto';
import OpenAI from 'openai';
import {createClient} from '@supabase/supabase-js';
import {createLiveStore} from './store.mjs';
import {createLiveConnections} from './connections.mjs';
import {createLiveProviders} from './providers.mjs';
import {createLiveRuntime} from './runtime.mjs';
import {createYouTube} from './youtube.mjs';

const env=process.env;
if(!env.SUPABASE_URL||!env.SUPABASE_SERVICE_ROLE_KEY||!env.OPENAI_API_KEY){
  console.error('Live Studio worker requires its database and generation provider configuration.');process.exit(1);
}
const db=createClient(env.SUPABASE_URL,env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false},
  global:{fetch:(input,init={})=>fetch(input,{...init,signal:AbortSignal.any([init.signal,AbortSignal.timeout(15000)].filter(Boolean))})}});
const connections=createLiveConnections({database:db,env,publicRoot:env.LIVE_STUDIO_PUBLIC_ORIGIN||'https://chee-chai-chee-backend.onrender.com'});
if(!connections.configured){console.error('Live Studio worker requires application YouTube credentials and encrypted customer connection storage.');process.exit(1);}
// One encoder per worker instance. Additional approved instances get independent
// IDs and claim different customers without sharing grants or stream credentials.
const workerId=randomUUID(),store=createLiveStore(db);
const runtime=createLiveRuntime({store,storage:db.storage,workerId,
  providers:createLiveProviders(new OpenAI({apiKey:env.OPENAI_API_KEY,maxRetries:0})),mode:'youtube',
  youtubeFactory:async show=>createYouTube({channelId:show.channel_id,accessToken:await connections.forShow(show)})});
const announce=async()=>{try{await store.call(null,'announce',workerId,{mode:'youtube'});}catch{console.warn('Live Studio worker readiness unavailable.');}};
await announce();const heartbeat=setInterval(()=>void announce(),10000);runtime.start();
let shuttingDown=false;
const shutdown=async()=>{
  if(shuttingDown)return;shuttingDown=true;
  clearInterval(heartbeat);runtime.stop();
  await store.call(null,'retire',workerId).catch(()=>{});
  for(let n=0;n<40&&runtime.busy;n++)await new Promise(r=>setTimeout(r,500));
  process.exit(0);
};
process.once('SIGTERM',()=>void shutdown());process.once('SIGINT',()=>void shutdown());
