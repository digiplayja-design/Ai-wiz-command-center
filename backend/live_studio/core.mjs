import {randomUUID} from 'node:crypto';

export class LiveStudioError extends Error {
  constructor(message, status = 400) { super(message); this.name = 'LiveStudioError'; this.status = status; }
}
export const fail = (message, status) => { throw new LiveStudioError(message, status); };
export const uuid = value => {
  if (typeof value !== 'string' || !/^[a-f\d]{8}-[a-f\d]{4}-[1-8][a-f\d]{3}-[89ab][a-f\d]{3}-[a-f\d]{12}$/i.test(value)) fail('Refresh the studio before trying again.');
  return value.toLowerCase();
};
export const text = (value, max, label) => {
  if (typeof value !== 'string' || !value.trim() || value.length > max || /[\u0000-\u001f\u007f]/.test(value)) fail(`${label} must contain 1–${max} characters on one line.`);
  return value.trim();
};
export const CATEGORIES = ['technology', 'business', 'sports', 'culture', 'politics', 'religion'];
export const ACTIVE = ['queued', 'preparing', 'live', 'paused'];
export function showInput(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail('Choose your show settings.');
  if (!CATEGORIES.includes(value.category)) fail('Choose a show category.');
  if (![900, 1800].includes(value.durationSeconds)) fail('Choose a 15- or 30-minute show.');
  if (![1, 2].includes(value.hostCount)) fail('Choose K-Nova alone or K-Nova with the Analyst.');
  return {title: text(value.title, 80, 'Show title'), topic: text(value.topic, 240, 'Topic'),
    category: value.category, durationSeconds: value.durationSeconds, hostCount: value.hostCount};
}
export function queueInput(value, now = Date.now()) {
  if (!['rehearsal', 'youtube'].includes(value?.mode)) fail('Choose a private rehearsal or YouTube pilot.');
  if (value.consent !== true) fail('Confirm AI processing and the generation limits before starting.');
  if (value.mode === 'youtube' && value.confirmed !== true) fail('Confirm the unlisted YouTube broadcast.');
  let scheduledAt = null;
  if (value.scheduledAt != null) {
    const time = Date.parse(value.scheduledAt);
    if (typeof value.scheduledAt !== 'string' || !Number.isFinite(time) || time < now + 60000 || time > now + 7 * 86400000) fail('Schedule between one minute and seven days from now.');
    if (value.mode !== 'youtube') fail('Rehearsals start immediately.');
    scheduledAt = new Date(time).toISOString();
  }
  return {mode: value.mode, scheduledAt, requestId: uuid(value.requestId)};
}
export function publicShow(show) {
  if (!show) return null;
  const keys = ['id', 'config', 'state', 'mode', 'version', 'created_at', 'updated_at', 'scheduled_at',
    'started_at', 'deadline_at', 'progress', 'error', 'watch_url', 'has_replay', 'command'];
  return Object.fromEntries(keys.filter(key => show[key] !== undefined).map(key => [key, show[key]]));
}
export function channelConfig(env = process.env) {
  return {ownerId: env.LIVE_STUDIO_BROADCAST_OWNER_ID || '', clientId: env.LIVE_STUDIO_YOUTUBE_CLIENT_ID || '',
    clientSecret: env.LIVE_STUDIO_YOUTUBE_CLIENT_SECRET || '', refreshToken: env.LIVE_STUDIO_YOUTUBE_REFRESH_TOKEN || '',
    enabled: env.LIVE_STUDIO_YOUTUBE_ENABLED === 'true'};
}
export const channelConfigured = c => Boolean(c.enabled && c.ownerId && c.clientId && c.clientSecret && c.refreshToken);
export const workerToken = () => randomUUID();
