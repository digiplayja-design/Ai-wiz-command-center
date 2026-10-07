(function (root) {
  'use strict';

  // October 15, 2026, 9:00 AM America/New_York (EDT, UTC−4).
  // Keep the visible <time> in index.html and the in-app launch date aligned.
  const LAUNCH_AT = Date.parse('2026-10-15T13:00:00Z');

  function remainingTime(now, target) {
    const totalSeconds = Math.max(0, Math.ceil((target - now) / 1000));
    return {
      days: Math.floor(totalSeconds / 86400),
      hours: Math.floor(totalSeconds / 3600) % 24,
      minutes: Math.floor(totalSeconds / 60) % 60,
      seconds: totalSeconds % 60,
      complete: totalSeconds === 0
    };
  }

  function mountCountdown(panel, environment) {
    const env = environment || {
      now: Date.now,
      setTimeout: root.setTimeout.bind(root),
      clearTimeout: root.clearTimeout.bind(root),
      document: root.document,
      window: root
    };
    const units = {};
    ['days', 'hours', 'minutes', 'seconds'].forEach(function (unit) {
      units[unit] = panel.querySelector('[data-countdown-' + unit + ']');
    });
    const heading = panel.querySelector('[data-countdown-heading]');
    const message = panel.querySelector('[data-countdown-message]');
    const announcement = panel.querySelector('[data-countdown-announcement]');
    let timer = null;
    let lastComplete = null;
    let disposed = false;
    let pageActive = true;

    function stopTimer() {
      if (timer !== null) {
        env.clearTimeout(timer);
        timer = null;
      }
    }

    function refresh() {
      stopTimer();
      if (disposed || !pageActive || env.document.visibilityState === 'hidden') return;
      const now = env.now();
      const remaining = remainingTime(now, LAUNCH_AT);
      Object.keys(units).forEach(function (unit) {
        const text = String(remaining[unit]).padStart(2, '0');
        if (units[unit].textContent !== text) units[unit].textContent = text;
      });
      if (remaining.complete !== lastComplete) {
        panel.classList.toggle('is-complete', remaining.complete);
        heading.textContent = remaining.complete ? 'The launch date has arrived.' : 'The countdown is on.';
        message.textContent = remaining.complete ? 'Explore KORLIX. Your next idea starts here.' : 'A date to look forward to. A hub to explore today.';
        // Announce the transition once, never every second.
        announcement.textContent = remaining.complete ? 'The scheduled KORLIX web launch date has arrived. You can explore the web app.' : '';
        lastComplete = remaining.complete;
      }
      if (!remaining.complete) {
        // Recompute from the real clock each tick and immediately on resume.
        // No accumulated decrement drift when a tab or phone is suspended.
        timer = env.setTimeout(refresh, 1000 - (now % 1000));
      }
    }

    function hidePage() { pageActive = false; stopTimer(); }
    function showPage() { pageActive = true; refresh(); }
    env.document.addEventListener('visibilitychange', refresh);
    env.window.addEventListener('pagehide', hidePage);
    env.window.addEventListener('pageshow', showPage);
    refresh();

    return function dispose() {
      disposed = true;
      stopTimer();
      env.document.removeEventListener('visibilitychange', refresh);
      env.window.removeEventListener('pagehide', hidePage);
      env.window.removeEventListener('pageshow', showPage);
    };
  }

  if (typeof module !== 'undefined' && module.exports) {
    module.exports = { LAUNCH_AT: LAUNCH_AT, remainingTime: remainingTime, mountCountdown: mountCountdown };
  } else if (root.document) {
    const panel = root.document.querySelector('[data-launch-countdown]');
    if (panel) mountCountdown(panel);
  }
})(typeof window !== 'undefined' ? window : globalThis);
