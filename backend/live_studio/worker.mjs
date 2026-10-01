import 'dotenv/config';
import OpenAI from 'openai';
import {createClient} from '@supabase/supabase-js';
import {channelConfig,channelConfigured} from './core.mjs';
import {createLiveStore} from './store.mjs';
import {createLiveProviders} from './providers.mjs';
import {createLiveRuntime} from './runtime.mjs';
import {createYouTube} from './youtube.mjs';

const env=process.env,config=channelConfig(env);
if(!channelConfigured(config)||!env.SUPABASE_URL||!env.SUPABASE_SERVICE_ROLE_KEY||!env.OPENAI_API_KEY){
  console.error('Live Studio worker requires its approved channel, owner and provider configuration.');process.exit(1);
}
const db=createClient(env.SUPABASE_URL,env.SUPABASE_SERVICE_ROLE_KEY,{auth:{persistSession:false,autoRefreshToken:false},
  global:{fetch:(input,init={})=>fetch(input,{...init,signal:AbortSignal.any([init.signal,AbortSignal.timeout(15000)].filter(Boolean))})}});
const store=createLiveStore(db),runtime=createLiveRuntime({store,storage:db.storage,
  providers:createLiveProviders(new OpenAI({apiKey:env.OPENAI_API_KEY,maxRetries:0})),youtube:createYouTube(config),mode:'youtube',ownerId:config.ownerId});
const announce=async()=>{try{await store.call(config.ownerId,'announce');}catch{console.warn('Live Studio worker readiness unavailable.');}};
await announce();const heartbeat=setInterval(()=>void announce(),10000);runtime.start();
const shutdown=async()=>{clearInterval(heartbeat);runtime.stop();for(let n=0;n<20&&runtime.busy;n++)await new Promise(r=>setTimeout(r,500));process.exit(0);};
process.once('SIGTERM',()=>void shutdown());process.once('SIGINT',()=>void shutdown());
