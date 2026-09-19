'use strict';
// Zoom L16 is signed 16-bit little-endian PCM. Retain only numeric levels;
// no audio buffers, files or speaker identities leave the callback.
function pcmLevel(buffer, size) {
  if (!Buffer.isBuffer(buffer) || !Number.isSafeInteger(size) || size !== buffer.length ||
      size < 2 || size > 192000 || size % 2) return null;
  let squares = 0, peak = 0;
  for (let i = 0; i < size; i += 2) {
    const sample = buffer.readInt16LE(i) / 32768;
    squares += sample * sample; peak = Math.max(peak, Math.abs(sample));
  }
  const rms = Math.sqrt(squares / (size / 2));
  return {level:rms === 0 ? 0 : Math.round(Math.max(0, Math.min(1, (20 * Math.log10(rms) + 60) / 60)) * 100),
    peak:Math.round(peak * 100)};
}
function createAudioLevelMeter({clock = () => require('node:perf_hooks').performance.now()} = {}) {
  let last = null, packets = 0, recent = [];
  return Object.freeze({
    accept(level) {
      if (!level || !Number.isInteger(level.level) || level.level < 0 || level.level > 100 ||
          !Number.isInteger(level.peak) || level.peak < 0 || level.peak > 100) return false;
      const at = clock();
      last = at; packets = Math.min(Number.MAX_SAFE_INTEGER, packets + 1);
      recent = recent.filter(x => at - x.at < 1200).slice(-199);
      recent.push({at, ...level}); return true;
    },
    snapshot(active) {
      const ageMs = last === null || !active ? null : Math.max(0, Math.floor(clock() - last));
      const values = active ? recent.filter(x => clock() - x.at < 1200) : [];
      return {received:active && packets > 0, packets:active ? packets : 0,
        ageMs:ageMs === null ? null : Math.min(ageMs, 86400000),
        level:values.reduce((n,x) => Math.max(n,x.level), 0),
        peak:values.reduce((n,x) => Math.max(n,x.peak), 0)};
    },
    clear() { last = null; packets = 0; recent = []; }
  });
}
module.exports = {pcmLevel, createAudioLevelMeter};
