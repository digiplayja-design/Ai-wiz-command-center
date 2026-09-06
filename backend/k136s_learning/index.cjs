'use strict';
// K136S - Nova Secure Spoken Learning and Brain Management (backend module).
// Phase B: pure domain model. Not mounted anywhere; backend/server.js is untouched until the integration gate.
const stateMachine = require('./domain/state_machine.cjs');
const classifier = require('./domain/classifier.cjs');
const policyCheck = require('./domain/policy_check.cjs');
const normalizeDiff = require('./domain/normalize_diff.cjs');
const similarity = require('./domain/similarity.cjs');
const approvalService = require('./services/approval_service.cjs');
const memoryStore = require('./adapters/memory_store.cjs');

module.exports = Object.freeze({
  K136S_VERSION: 'B1',
  ...stateMachine,
  classify: classifier.classify, reclassify: classifier.reclassify, parseExpiry: classifier.parseExpiry, SENSITIVITY: classifier.SENSITIVITY,
  checkPolicy: policyCheck.check, POLICY_LIMITS: policyCheck.LIMITS,
  normalize: normalizeDiff.normalize, contentHash: normalizeDiff.contentHash, diffWords: normalizeDiff.diffWords,
  ...similarity,
  createApprovalService: approvalService.createApprovalService, hashToken: approvalService.hashToken,
  createMemoryStore: memoryStore.createMemoryStore,
});
