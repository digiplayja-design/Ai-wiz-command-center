import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {hasUnlimitedAccess,authenticatedDeveloperUser,UNLIMITED_COMPATIBILITY_LIMIT,UNLIMITED_FEATURE_LIMITS} from '../security/developer_access.mjs';
import {entitlement} from '../music/core.mjs';

const id='10000000-0000-4000-8000-000000000001';
test('only the matching server-owned enabled grant decorates an authenticated user',()=>{
  const user={id,email:'developer@example.invalid',developer_unlimited:true,user_metadata:{developer_unlimited:true}};
  for(const account of [null,{id},{id,developer_access:{enabled:false}},{id:'10000000-0000-4000-8000-000000000002',developer_access:{enabled:true}},
    {id,is_disabled:true,developer_access:{enabled:true}}]) {
    assert.equal(hasUnlimitedAccess(authenticatedDeveloperUser(user,account)),false);
  }
  for(const grant of [{enabled:true},[{enabled:true}]]) {
    assert.equal(hasUnlimitedAccess(authenticatedDeveloperUser(user,{id,developer_access:grant})),true);
  }
  assert.equal(hasUnlimitedAccess({id,user_metadata:{developer_unlimited:true}}),false);
  assert.equal(hasUnlimitedAccess({id,app_metadata:{developer_unlimited:true}}),false);
});

test('Music Studio enables the developer plan without enabling the add-on for other users',()=>{
  const developer=entitlement({id,developer_unlimited:true},{});
  assert.equal(developer.active,true);
  assert.equal(developer.unlimited,true);
  assert.equal(developer.billingRequired,false);
  assert.equal(developer.plan.monthlyGenerations,UNLIMITED_COMPATIBILITY_LIMIT);
  assert.equal(entitlement({id,user_metadata:{developer_unlimited:true}},{}).active,false);
  assert.equal(entitlement({id,developer_unlimited:true,is_disabled:true},{}).active,false);
});

test('AI checks remove developer budgets while preserving paid and free account quotas',async()=>{
  const source=await readFile(new URL('../server.js',import.meta.url),'utf8');
  const section=(a,b)=>source.slice(source.indexOf(a),source.indexOf(b,source.indexOf(a)));
  const code=section('function getTierLimits(','function getMonthKey(')+section('function checkUsageAllowed(','async function incrementUsage(');
  const {checkUsageAllowed,getTierLimits}=Function('hasUnlimitedAccess','UNLIMITED_FEATURE_LIMITS',code+';return {checkUsageAllowed,getTierLimits};')(hasUnlimitedAccess,UNLIMITED_FEATURE_LIMITS);
  const exhausted={standard_generations:5000000000,credits_used:5000000000};
  assert.equal(checkUsageAllowed({profile:{id,tier:'enterprise',developer_unlimited:true},usageCounter:exhausted,creditsNeeded:3}).allowed,true);
  assert.equal(checkUsageAllowed({profile:{id,tier:'enterprise'},usageCounter:exhausted,creditsNeeded:3}).allowed,false);
  assert.equal(checkUsageAllowed({profile:{id,tier:'basic'},usageCounter:{standard_generations:3},creditsNeeded:1}).allowed,false);
  assert.equal(getTierLimits('enterprise',{id,developer_unlimited:true}).unlimited,true);
  assert.equal(getTierLimits('enterprise',{id}).dailyRequestLimit,250);
});
