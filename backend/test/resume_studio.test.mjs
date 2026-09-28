import test from 'node:test';
import assert from 'node:assert/strict';
import { resumeTextPolicy } from '../resume_studio/policy.mjs';

test('private resume facts cannot enable web search or file generation', () => {
  for (const command of ['Current CEO, 2026-present. Email: candidate@example.test', 'Write a cover letter for the latest stock market news role.', 'Import a Word document with today’s date.']) {
    assert.deepEqual(resumeTextPolicy({ purpose: 'resume_studio', command }), {liveSearchNeeded:false,fileRequested:false});
  }
});
test('unrelated requests retain the existing search and file policy', () => {
  for (const body of [{}, {purpose:'chat'}, {purpose:['resume_studio']}, null]) assert.equal(resumeTextPolicy(body),null);
});
