import test from 'node:test';
import assert from 'node:assert/strict';
import express from 'express';
import {canUseBrainDirections, brainDirectionLinks, DIRECTIONS_FEATURE} from '../brain_projection/directions.mjs';
import {registerBrainProjection} from '../brain_projection/routes.mjs';

test('directions preserve the full user destination and use fixed provider origins without keys or automatic navigation', () => {
  const destination = '1000 Fifth Avenue, New York, NY 10028 & Suite 2';
  for (const mode of ['driving', 'walking', 'transit']) {
    const result = brainDirectionLinks({destination, mode, userId: 'someone-else', url: 'https://evil.example'});
    assert.equal(result.destination, destination);
    assert.equal(result.addressVerified, false);
    assert.equal(result.requiresConfirmation, true);
    const google = new URL(result.googleMapsUrl), apple = new URL(result.appleMapsUrl);
    assert.equal(google.origin, 'https://www.google.com');
    assert.equal(google.pathname, '/maps/dir/');
    assert.equal(google.searchParams.get('destination'), destination);
    assert.equal(google.searchParams.get('travelmode'), mode);
    assert.equal(google.searchParams.has('dir_action'), false);
    assert.equal(apple.origin, 'https://maps.apple.com');
    assert.equal(apple.pathname, '/directions');
    assert.equal(apple.searchParams.get('destination'), destination);
    assert.equal(apple.searchParams.has('start'), false);
  }
  for (const body of [{destination: ''}, {destination: 'x'.repeat(301)}, {destination: 'NY\nNY'},
    {destination: 'https://evil.example'}, {destination: 'New York', mode: 'javascript'}]) {
    assert.throws(() => brainDirectionLinks(body));
  }
});

test('only active unexpired UID-bound server grants allow directions', async () => {
  const checks = [];
  let data = [{status: 'active', expires_at: null}];
  let error = null;
  const db = {from(table) {checks.push(['from',table]); return this;}, select(fields) {checks.push(['select',fields]); return this;},
    eq(field,value) {checks.push([field,value]); return this;}, then(resolve) {return Promise.resolve({data,error}).then(resolve);}};
  assert.equal(await canUseBrainDirections(db, 'verified-uid'), true);
  assert.deepEqual(checks.slice(2), [['user_id','verified-uid'],['feature_key',DIRECTIONS_FEATURE]]);
  for (const rows of [[], [{status:'revoked',expires_at:null}], [{status:'active',expires_at:'invalid'}],
    [{status:'active',expires_at:'2020-01-01'}]]) {
    data = rows;
    assert.equal(await canUseBrainDirections(db, 'verified-uid'), false);
  }
  data = [{status:'active',expires_at:'2099-01-01'}];
  assert.equal(await canUseBrainDirections(db, 'verified-uid'), true);
  error = {message:'private database details'};
  await assert.rejects(canUseBrainDirections(db, 'verified-uid'), e => e.statusCode === 503 && !e.message.includes('private'));
  assert.equal(await canUseBrainDirections(null,'uid'), false);
});

test('config and directions authenticate the current UID and fail closed without broadening research or map access', async t => {
  const app = express(); app.use(express.json({limit:'8kb'}));
  const seen=[];
  registerBrainProjection(app, {environment:{}, requireUser: async req => {
    const id = req.headers['x-test-user']; if (!id) throw Object.assign(new Error('sign in'),{statusCode:401});
    return {id};
  }, directionsAccess: async user => {seen.push(user.id); return user.id === 'authorized-owner';}});
  const server = app.listen(0,'127.0.0.1');
  await new Promise(resolve=>server.once('listening',resolve));
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  const base=`http://127.0.0.1:${server.address().port}`;
  const call=(path,id,body)=>fetch(base+'/api/brain-projection/'+path,{method:body?'POST':'GET',
    headers:{...(id?{'x-test-user':id}:{}),'content-type':'application/json'},body:body?JSON.stringify(body):undefined});
  assert.equal((await call('directions',null,{destination:'New York'})).status,401);
  const denied=await call('directions','other-user',{destination:'New York',userId:'authorized-owner',email:'support@example.com'});
  assert.equal(denied.status,403);
  const config=await (await call('config','authorized-owner')).json();
  assert.equal(config.directionsAvailable,true); assert.equal(config.mapAvailable,false);
  assert.equal((await (await call('config','other-user')).json()).directionsAvailable,false);
  const allowed=await call('directions','authorized-owner',{destination:'New York',mode:'walking'});
  assert.equal(allowed.status,200); assert.equal(allowed.headers.get('cache-control'),'no-store');
  assert.equal((await allowed.json()).mode,'walking');
  assert.deepEqual(new Set(seen),new Set(['other-user','authorized-owner']));
});
