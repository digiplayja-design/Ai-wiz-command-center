'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { LAUNCH_AT, remainingTime, mountCountdown } = require('../website/launch.js');

function fixture(now) {
  let clock = now;
  let nextTimer = 1;
  const scheduled = new Map();
  const elements = {};
  ['days', 'hours', 'minutes', 'seconds', 'heading', 'message', 'announcement'].forEach(name => {
    elements[name] = { textContent: '' };
  });
  const classes = new Set();
  const panel = {
    querySelector: selector => elements[selector.slice('[data-countdown-'.length, -1)],
    classList: { toggle: (name, enabled) => enabled ? classes.add(name) : classes.delete(name) }
  };
  function eventTarget() {
    const listeners = new Map();
    return {
      listeners,
      addEventListener: (name, callback) => listeners.set(name, callback),
      removeEventListener: (name, callback) => {
        if (listeners.get(name) === callback) listeners.delete(name);
      },
      fire: name => listeners.get(name)?.()
    };
  }
  const document = { ...eventTarget(), visibilityState: 'visible' };
  const window = eventTarget();
  const env = {
    document, window, now: () => clock,
    setTimeout: (callback, delay) => { const id = nextTimer++; scheduled.set(id, { callback, delay }); return id; },
    clearTimeout: id => scheduled.delete(id)
  };
  return {
    elements, classes, scheduled, document, window,
    setTime: value => { clock = value; },
    tick: () => {
      const [id, { callback }] = scheduled.entries().next().value;
      scheduled.delete(id);
      callback();
    },
    mount: () => mountCountdown(panel, env)
  };
}

test('target is 9 AM New York time on October 15, 2026', () => {
  assert.equal(new Date(LAUNCH_AT).toISOString(), '2026-10-15T13:00:00.000Z');
  const local = new Intl.DateTimeFormat('en-US', {
    timeZone: 'America/New_York', year: 'numeric', month: 'numeric', day: 'numeric', hour: 'numeric', hour12: false
  }).format(new Date(LAUNCH_AT));
  assert.match(local, /10\/15\/2026/);
  assert.match(local, /09/);
});

test('day rollover stays accurate and does not finish a partial second early', () => {
  assert.deepEqual(remainingTime(LAUNCH_AT - 86400000, LAUNCH_AT), { days: 1, hours: 0, minutes: 0, seconds: 0, complete: false });
  assert.deepEqual(remainingTime(LAUNCH_AT - 86399000, LAUNCH_AT), { days: 0, hours: 23, minutes: 59, seconds: 59, complete: false });
  assert.equal(remainingTime(LAUNCH_AT - 1, LAUNCH_AT).seconds, 1);
  assert.equal(remainingTime(LAUNCH_AT - 1, LAUNCH_AT).complete, false);
});

test('deadline and dates in the past have no negative values', () => {
  const complete = { days: 0, hours: 0, minutes: 0, seconds: 0, complete: true };
  assert.deepEqual(remainingTime(LAUNCH_AT, LAUNCH_AT), complete);
  assert.deepEqual(remainingTime(LAUNCH_AT + 86400000, LAUNCH_AT), complete);
});

test('late timer wakeup recalculates from clock instead of decrementing stale numbers', () => {
  const f = fixture(LAUNCH_AT - 125000);
  const dispose = f.mount();
  assert.equal(f.elements.minutes.textContent, '02');
  assert.equal(f.elements.seconds.textContent, '05');
  f.setTime(LAUNCH_AT - 64000);
  f.tick();
  assert.equal(f.elements.minutes.textContent, '01');
  assert.equal(f.elements.seconds.textContent, '04');
  assert.equal(f.elements.announcement.textContent, '');
  assert.equal(f.scheduled.size, 1);
  dispose();
});

test('hidden pages stop ticking and resume at the current time', () => {
  const f = fixture(LAUNCH_AT - 125000);
  const dispose = f.mount();
  f.document.visibilityState = 'hidden';
  f.document.fire('visibilitychange');
  assert.equal(f.scheduled.size, 0);
  f.setTime(LAUNCH_AT - 17000);
  f.document.visibilityState = 'visible';
  f.document.fire('visibilitychange');
  assert.equal(f.elements.minutes.textContent, '00');
  assert.equal(f.elements.seconds.textContent, '17');
  assert.equal(f.scheduled.size, 1);
  dispose();
});

test('page cache restore is safe and disposal removes all listeners', () => {
  const f = fixture(LAUNCH_AT - 125000);
  const dispose = f.mount();
  f.window.fire('pagehide');
  assert.equal(f.scheduled.size, 0);
  f.document.fire('visibilitychange');
  assert.equal(f.scheduled.size, 0);
  f.setTime(LAUNCH_AT - 3000);
  f.window.fire('pageshow');
  assert.equal(f.elements.seconds.textContent, '03');
  assert.equal(f.scheduled.size, 1);
  dispose();
  assert.equal(f.scheduled.size, 0);
  assert.equal(f.document.listeners.size, 0);
  assert.equal(f.window.listeners.size, 0);
});

test('completion announces the date once, stops ticking and makes no paid-access promise', () => {
  const f = fixture(LAUNCH_AT - 1000);
  const dispose = f.mount();
  f.setTime(LAUNCH_AT);
  f.tick();
  assert.equal(f.elements.seconds.textContent, '00');
  assert.equal(f.classes.has('is-complete'), true);
  assert.equal(f.scheduled.size, 0);
  assert.equal(f.elements.heading.textContent, 'The launch date has arrived.');
  assert.match(f.elements.announcement.textContent, /scheduled KORLIX web launch date has arrived/);
  assert.doesNotMatch(f.elements.message.textContent, /paid|enabled|unlimited|all features/i);
  const announcement = f.elements.announcement.textContent;
  f.window.fire('pageshow');
  assert.equal(f.elements.announcement.textContent, announcement);
  assert.equal(f.scheduled.size, 0);
  dispose();
});
