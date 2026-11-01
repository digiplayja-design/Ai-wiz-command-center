// Model choice is fixed when an authenticated voice session is registered.
// Keep the prior protocol for installed builds; never relabel Astra as Sol.
export const BRAIN_MODEL = 'gpt-6.1-sol';
export const BRAIN_EFFORT = 'max';
export const BRAIN_PROTOCOL = 'sol-6.1-max-v1';
export const BRAIN_PROFILES = Object.freeze([
  Object.freeze({protocol: BRAIN_PROTOCOL, model: BRAIN_MODEL, effort: BRAIN_EFFORT, label: 'GPT-6.1 Sol Max'}),
  Object.freeze({protocol: 'astra-max-v1', model: 'gpt-6-astra', effort: 'max', label: 'GPT-6 Astra Max'}),
]);
export const profileForProtocol = protocol => BRAIN_PROFILES.find(profile => profile.protocol === protocol) || null;
export const brainProfile = req => profileForProtocol(req.headers?.['x-korlix-brain-voice']);
export const isBrainVoice = req => brainProfile(req) !== null;
export const matchesBrainModel = (actual, expected) => typeof actual === 'string' &&
  (actual === expected || actual.startsWith(`${expected}-`));
