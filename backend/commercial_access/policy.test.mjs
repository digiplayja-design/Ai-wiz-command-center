import test from 'node:test';
import assert from 'node:assert/strict';
import {FEATURES, TIERS, normalizeTier, effectiveTier, evaluateAccess, registerAccessPreview} from './policy.mjs';
import {GAS_RULES, allocateVoiceSeconds} from './voice_budget.mjs';
const USER = '00000000-0000-4000-8000-000000000001';
const OTHER = '00000000-0000-4000-8000-000000000002';
const WORKSPACE = '00000000-0000-4000-8000-000000000003';
const AT = Date.parse('2026-09-29T00:00:00Z');
const FUTURE = '2026-10-29T00:00:00Z';
const PAST = '2026-09-28T00:00:00Z';
const available = FEATURES.map(feature => feature.key);
const active = () => ({verified: true, status: 'active', expiresAt: FUTURE});
const account = (tier = 'basic') => ({userId: USER, accountStatus: 'active', plan: {...active(), tier}});
const decision = (featureKey, facts = account(), extra = {}) => evaluateAccess({userId: USER, facts, featureKey, availableFeatures: available, at: AT, ...extra});
const legacy = featureKey => ({...active(), source: 'legacy_paid_offer', offerId: 'synthetic-offer', userId: USER, workspaceId: null, featureKey});
const workspace = () => ({id: WORKSPACE, memberUserId: USER, membership: active(), plan: {...active(), tier: 'enterprise'}, permissions: ['workforce.employee']});

for (const [raw, expected] of [['basic','basic'], ['Pro','pro'], [' Ultra Premium ','ultra'], ['ultra_premium','ultra'], ['ultra-premium','ultra'], ['ENTERPRISE','enterprise']]) {
  test(`exact tier alias: ${raw}`, () => assert.equal(normalizeTier(raw), expected));
}
for (const raw of [null, undefined, '', 1, true, {}, [], 'premium', 'non_enterprise', 'not enterprise', 'enterprise_trial', 'ultra_enterprise', '__proto__', 'constructor', 'developer', 'pro-plus']) {
  test(`unknown tier is not elevated: ${JSON.stringify(raw)}`, () => assert.equal(normalizeTier(raw), null));
}
test('catalog is immutable and uniquely keyed', () => {
  assert.equal(FEATURES.length, new Set(available).size);
  assert.throws(() => { FEATURES[0].minimumTier = 'enterprise'; }, TypeError);
  assert.throws(() => { TIERS.push('developer'); }, TypeError);
});
// Independent approved grouping, rather than deriving expected access from code.
const floors = {
  basic: ['social.core','social.calls','social.games','chat','resume','email_enhancer','study','locator','camera_ask','cyber_defender','imagine_picture','improve_picture','logo','virtual_closet','babyblend','chat_memory','live_convo'],
  pro: ['agents.personal','brain_vault','app_studio','bookkeeping.core','tax_prep.organizer'],
  ultra: ['agents.advanced','video_generation','bookkeeping.advanced','tax_prep.linked_books','inventory','fieldproof','contract_radar','ai_visibility'],
  enterprise: ['crm','funnels','meeting_copilot','autonomous_outreach'],
};
for (const [minimum, keys] of Object.entries(floors)) for (const featureKey of keys) for (const tier of TIERS) {
  test(`${featureKey}: ${tier} matches the approved ${minimum} floor`, () => {
    const d = decision(featureKey, account(tier));
    const expected = TIERS.indexOf(tier) >= TIERS.indexOf(minimum);
    assert.equal(d.eligible, expected);
    assert.equal(d.reason, expected ? 'PLAN_ELIGIBLE' : 'UPGRADE_REQUIRED');
    assert.equal(d.requiresUsageCheck, expected);
    assert.equal(d.requiresResourceAuthorization, true);
  });
}
for (const tier of TIERS) {
  test(`${tier}: privacy controls are not paywalled`, () => {
    const facts = account(tier); facts.accountStatus = 'suspended'; facts.plan.expiresAt = PAST;
    const d = decision('account.controls', facts, {availableFeatures: []});
    assert.equal(d.eligible, true); assert.equal(d.requiresUsageCheck, false);
  });
  test(`${tier}: Music Production still requires its add-on`, () => assert.equal(decision('music_production', account(tier)).reason, 'ADDON_REQUIRED'));
}
for (const override of [{verified:false},{verified:'true'},{status:'pending'},{status:'refunded'},{expiresAt:PAST},{expiresAt:'bad'},{expiresAt:null},{expiresAt:undefined},{expiresAt:'2026-10-29'},{tier:'not_enterprise'}]) {
  test(`invalid or expired paid plan fails closed: ${JSON.stringify(override)}`, () => {
    const plan = {...active(), tier: 'enterprise', ...override};
    assert.equal(effectiveTier(plan, AT), 'basic');
    assert.equal(decision('crm', {...account(), plan}).eligible, false);
  });
}
test('explicit server-verified perpetual grant remains supported', () => assert.equal(effectiveTier({...active(), tier:'ultra', expiresAt:null, nonExpiring:true}, AT), 'ultra'));
test('exact expiry boundary is not active', () => assert.equal(effectiveTier({...active(), tier:'enterprise', expiresAt:new Date(AT).toISOString()}, AT), 'basic'));
test('invalid clock fails closed', () => assert.throws(() => decision('chat', account(), {at:NaN}), /ACCESS_CLOCK_INVALID/));
for (const featureKey of ['__proto__','constructor','unknown','CRM',null,{},[]]) {
  test(`unknown feature denied: ${JSON.stringify(featureKey)}`, () => assert.equal(decision(featureKey).reason, 'UNKNOWN_FEATURE'));
}
test('missing identity rejected', () => assert.throws(() => decision('chat', account(), {userId:undefined}), /ACCESS_IDENTITY_MISMATCH/));
test('cross-account facts rejected', () => assert.throws(() => decision('chat', {...account(), userId:OTHER}), /ACCESS_IDENTITY_MISMATCH/));
test('restricted account cannot generate', () => assert.equal(decision('chat', {...account(), accountStatus:'suspended'}).reason, 'ACCOUNT_RESTRICTED'));
for (const availableFeatures of [null,undefined,{},['crm'],[], 'chat']) {
  test(`no implicit feature activation: ${JSON.stringify(availableFeatures)}`, () => assert.equal(decision('chat', account(), {availableFeatures}).reason, 'FEATURE_NOT_AVAILABLE'));
}
test('GAS balance and developer voice exemption never elevate a subscription', () => {
  const facts = {...account(), gasSeconds:999999, developerUnlimitedVoice:true};
  assert.equal(decision('crm', facts).eligible, false);
  assert.equal(decision('meeting_copilot', facts).eligible, false);
  assert.equal(decision('music_production', facts).eligible, false);
});
test('valid exact grandfather benefit is retained without elevating the whole plan', () => {
  const facts = {...account(), legacyGrants:[legacy('bookkeeping.advanced')]};
  assert.equal(decision('bookkeeping.advanced', facts).reason, 'LEGACY_PAID_BENEFIT');
  assert.equal(decision('crm', facts).eligible, false);
});
for (const override of [{userId:OTHER},{featureKey:'*'},{workspaceId:WORKSPACE},{verified:false},{status:'revoked'},{expiresAt:PAST},{source:'ai_gas_purchase'},{offerId:''},{offerId:undefined}]) {
  test(`invalid grandfather grant cannot authorize: ${JSON.stringify(override)}`, () => {
    const facts = {...account(), legacyGrants:[{...legacy('crm'), ...override}]};
    assert.equal(decision('crm', facts).eligible, false);
  });
}
test('grandfather grant cannot enable an unavailable feature', () => assert.equal(decision('crm', {...account(), legacyGrants:[legacy('crm')]}, {availableFeatures:[]}).reason, 'FEATURE_NOT_AVAILABLE'));
test('Music add-on works on Basic without granting Ultra', () => {
  const facts = {...account(), addons:[{...active(), userId:USER, workspaceId:null, featureKey:'music_production'}]};
  assert.equal(decision('music_production', facts).eligible, true);
  assert.equal(decision('inventory', facts).eligible, false);
});
for (const override of [{userId:OTHER},{workspaceId:WORKSPACE},{featureKey:'live_convo'},{expiresAt:PAST},{verified:'true'}]) {
  test(`wrong/expired Music grant denied: ${JSON.stringify(override)}`, () => {
    const facts = {...account('enterprise'), addons:[{...active(), userId:USER, workspaceId:null, featureKey:'music_production', ...override}]};
    assert.equal(decision('music_production', facts).eligible, false);
  });
}
test('Basic employee can use an entitled employer workspace without personal Enterprise', () => {
  const facts = {...account(), workspace:workspace()};
  const d = decision('workforce.employee', facts, {workspaceId:WORKSPACE});
  assert.equal(d.eligible, true);
  assert.equal(decision('workforce.admin', facts, {workspaceId:WORKSPACE}).reason, 'WORKSPACE_PERMISSION_REQUIRED');
  assert.equal(decision('crm', facts).eligible, false);
});
test('workspace workforce administration requires an explicit permission', () => {
  const w = workspace(); w.permissions.push('workforce.admin');
  assert.equal(decision('workforce.admin', {...account(), workspace:w}, {workspaceId:WORKSPACE}).eligible, true);
});
test('personal Enterprise cannot bypass workspace membership', () => assert.equal(decision('workforce.employee', account('enterprise'), {workspaceId:WORKSPACE}).reason, 'WORKSPACE_MEMBERSHIP_REQUIRED'));
test('workforce requires explicit workspace scope', () => assert.equal(decision('workforce.employee', account('enterprise')).reason, 'WORKSPACE_REQUIRED'));
for (const override of [{id:OTHER},{memberUserId:OTHER},{membership:{...active(),status:'revoked'}},{membership:{...active(),expiresAt:PAST}}]) {
  test(`invalid workspace membership denied: ${JSON.stringify(override)}`, () => assert.equal(decision('workforce.employee', {...account('enterprise'), workspace:{...workspace(), ...override}}, {workspaceId:WORKSPACE}).eligible, false));
}
test('expired employer plan does not borrow employee personal Enterprise', () => {
  const w = workspace(); w.plan.expiresAt = PAST;
  assert.equal(decision('workforce.employee', {...account('enterprise'),workspace:w}, {workspaceId:WORKSPACE}).eligible, false);
});
test('workspace permissions cannot authorize a different organization', () => assert.equal(decision('workforce.employee', {...account(),workspace:workspace()}, {workspaceId:OTHER}).eligible, false));
test('invalid workspace identifier denied', () => assert.equal(decision('workforce.employee', {...account(),workspace:workspace()}, {workspaceId:'any'}).eligible, false));

function routeHarness(options = {}) {
  let handler;
  const seen = [];
  registerAccessPreview({get(path, callback) { assert.equal(path, '/api/commercial-access/preview'); handler = callback; }}, {
    requireUser:async () => ({id:USER}),
    loadFacts:async id => { seen.push(id); return account(); },
    loadAvailability:async () => available,
    now:() => AT, ...options,
  });
  const res = {statusCode:200, headers:{}, set(key,value){this.headers[key]=value;return this;}, status(code){this.statusCode=code;return this;}, json(value){this.body=value;return this;}};
  return {handler,res,seen};
}
test('preview endpoint ignores client-selected tier, owner, GAS and entitlements', async () => {
  const h = routeHarness();
  await h.handler({body:{userId:OTHER,tier:'enterprise',addons:[legacy('music_production')]}, query:{tier:'enterprise',userId:OTHER}, headers:{'x-tier':'enterprise'}}, h.res);
  assert.deepEqual(h.seen, [USER]); assert.equal(h.res.statusCode,200);
  assert.equal(h.res.headers['Cache-Control'],'no-store');
  assert.equal(h.res.body.previewOnly,true); assert.equal(h.res.body.enforcesLiveRoutes,false);
  assert.equal(h.res.body.decisions.find(d => d.featureKey==='crm').eligible,false);
  assert.equal(JSON.stringify(h.res.body).includes(USER),false);
});
test('unauthenticated preview never loads facts', async () => {
  const h = routeHarness({requireUser:async () => {throw new Error('private authentication details');}});
  await h.handler({},h.res); assert.equal(h.res.statusCode,401); assert.deepEqual(h.seen,[]);
  assert.deepEqual(h.res.body,{code:'AUTH_REQUIRED'});
});
test('resolver errors do not leak purchase tokens or database details', async () => {
  const h = routeHarness({loadFacts:async () => {throw new Error('purchase-token-secret');}});
  await h.handler({},h.res); assert.equal(h.res.statusCode,503); assert.deepEqual(h.res.body,{code:'ACCESS_UNAVAILABLE'});
});
test('preview rejects cross-account facts', async () => {
  const h = routeHarness({loadFacts:async () => ({...account('enterprise'),userId:OTHER})});
  await h.handler({},h.res); assert.equal(h.res.statusCode,401);
});
test('missing authoritative adapters rejected on registration', () => assert.throws(() => registerAccessPreview({get(){}}), /ACCESS_ADAPTER_REQUIRED/));

const allocate = extra => allocateVoiceSeconds({featureKey:'live_convo',activeSeconds:120,includedSeconds:60,purchasedSeconds:3600,...extra});
test('voice uses included seconds before GAS', () => assert.deepEqual(allocate(), {eligible:true,reason:'BALANCE_SUFFICIENT',includedDebit:60,gasDebit:60,remainingIncludedSeconds:0,remainingPurchasedSeconds:3540}));
test('insufficient voice allocation leaves all balances unchanged', () => assert.deepEqual(allocate({purchasedSeconds:59}), {eligible:false,reason:'INSUFFICIENT_VOICE_BALANCE',includedDebit:0,gasDebit:0,remainingIncludedSeconds:60,remainingPurchasedSeconds:59}));
test('zero server-measured active time consumes no allowance', () => {const d=allocate({activeSeconds:0}); assert.equal(d.includedDebit,0); assert.equal(d.gasDebit,0);});
test('developer voice exemption consumes neither balance', () => {const d=allocate({developerUnlimited:true}); assert.equal(d.includedDebit,0); assert.equal(d.gasDebit,0); assert.equal(d.remainingPurchasedSeconds,3600);});
for (const featureKey of ['social.calls','social.games','music_production','chat','meeting_copilot','phone_calls',undefined]) {
  test(`GAS is not used for ${featureKey}`, () => assert.throws(() => allocate({featureKey}), /NOT_AN_AI_GAS_SERVICE/));
}
for (const value of [-1, 0.1, '120', NaN, Infinity, Number.MAX_SAFE_INTEGER+1, null, true]) for (const field of ['activeSeconds','includedSeconds','purchasedSeconds']) {
  test(`voice rejects ${field}=${String(value)}`, () => assert.throws(() => allocate({[field]:value}), /INVALID_VOICE_SECONDS/));
}
for (const developerUnlimited of ['true',1,{},null]) {
  test(`voice exemption rejects non-boolean ${JSON.stringify(developerUnlimited)}`, () => assert.throws(() => allocate({developerUnlimited}), /INVALID_DEVELOPER_ENTITLEMENT/));
}
test('allocation does not sum balances unsafely at MAX_SAFE_INTEGER', () => {
  const d=allocate({activeSeconds:Number.MAX_SAFE_INTEGER,includedSeconds:Number.MAX_SAFE_INTEGER,purchasedSeconds:Number.MAX_SAFE_INTEGER});
  assert.equal(d.gasDebit,0); assert.equal(d.remainingPurchasedSeconds,Number.MAX_SAFE_INTEGER);
});
test('deterministic budget conservation for 10,000 allocations', () => {
  for (let i=0;i<10000;i++) {
    const includedSeconds=(i*17)%1000, purchasedSeconds=(i*31)%1000, activeSeconds=(i*43)%3000;
    const d=allocate({includedSeconds,purchasedSeconds,activeSeconds});
    assert.equal(d.eligible,activeSeconds<=includedSeconds+purchasedSeconds);
    assert.equal(d.includedDebit+d.remainingIncludedSeconds,includedSeconds);
    assert.equal(d.gasDebit+d.remainingPurchasedSeconds,purchasedSeconds);
    assert.equal(d.includedDebit+d.gasDebit,d.eligible?activeSeconds:0);
    assert.ok(d.remainingPurchasedSeconds>=0);
  }
});
test('GAS policy separates voice, tiers, Music and Social without automatic buying', () => {
  assert.equal(GAS_RULES.purchasedTimeChangesTier,false); assert.equal(GAS_RULES.socialCallsUseGas,false);
  assert.equal(GAS_RULES.musicUsesGas,false); assert.equal(GAS_RULES.autoPurchase,false);
  assert.equal(GAS_RULES.purchasedTimeRollsOver,true);
});
