import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createSocialCallConfig,socialRelayReadiness,socialCallConfig} from '../social/calls.mjs';
const env={TWILIO_ACCOUNT_SID:'AC'+'a'.repeat(32),TWILIO_AUTH_TOKEN:'fixture-management-secret'};
const relay=[{urls:'turn:fixture.example:443?transport=tcp',username:'ephemeral-user',credential:'ephemeral-token'}];
test('existing provider issues ephemeral credentials; concurrent requests share work per member',async()=>{
 let calls=0;const config=createSocialCallConfig({env,fetchImpl:async(url,options)=>{calls++;assert.match(url,/api.twilio.com/);assert.match(options.body,/Ttl=14400/);assert(options.signal);return {ok:true,json:async()=>({ice_servers:relay})};}});
 const [a,b]=await Promise.all([config('a'),config('a')]);assert.equal(calls,1);assert(a.relay);assert.deepEqual(a,b);assert.equal(a.relayStatus,'ready');assert(!JSON.stringify(a).includes(env.TWILIO_AUTH_TOKEN));
 await config('b');assert.equal(calls,2);
});
test('static relay wins, credentials are required for readiness, and disabled calling never contacts provider',async()=>{
 assert.equal(socialCallConfig({SOCIAL_ICE_SERVERS:JSON.stringify([{urls:'turn:fixture.example'}])}).relay,false);
 assert.equal(socialRelayReadiness({}).mode,'direct-only');assert.equal(socialRelayReadiness(env).mode,'twilio');
 let calls=0;const fetchImpl=async()=>{calls++;throw Error();};
 assert((await createSocialCallConfig({env:{...env,SOCIAL_ICE_SERVERS:JSON.stringify(relay)},fetchImpl})('a')).relay);
 assert.equal((await createSocialCallConfig({env:{...env,SOCIAL_CALLS_ENABLED:'false'},fetchImpl})('a')).enabled,false);
 assert.equal((await createSocialCallConfig({env:{...env,SOCIAL_TURN_PROVIDER:'disabled'},fetchImpl})('a')).relay,false);
 assert.equal(calls,0);
});
test('provider failures are explicit and do not expose secrets or prevent direct connectivity',async()=>{
 let calls=0;const config=createSocialCallConfig({env,logger:{warn(){}},fetchImpl:async()=>{calls++;return {ok:false};}});
 const r=await config('a');assert.equal(r.relay,false);assert.equal(r.relayStatus,'unavailable');assert(r.iceServers.length);await config('a');assert.equal(calls,2);
});
