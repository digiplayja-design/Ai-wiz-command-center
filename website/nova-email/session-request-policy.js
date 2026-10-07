/* Session credentials may leave this page only for the KORLIX API. */
(function (root, factory) {
  const policy = factory();
  if (typeof module === 'object' && module.exports) module.exports = policy;
  else root.KorlixEmailRequestPolicy = policy;
})(typeof globalThis === 'object' ? globalThis : this, function () {
  'use strict';
  const apiOrigin = 'https://chee-chai-chee-backend.onrender.com';

  function claims(token) {
    try {
      const part = String(token).split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
      return JSON.parse(atob(part.padEnd(Math.ceil(part.length / 4) * 4, '=')));
    } catch (_) { return null; }
  }

  function sessionScope(token) {
    const value = claims(token);
    return value && typeof value.sub === 'string' && value.sub &&
      typeof value.iss === 'string' && value.iss
      ? JSON.stringify([value.iss, value.sub, value.session_id || '']) : '';
  }

  function chooseSessionToken(mainToken, candidates = [], now = Date.now()) {
    const scope = sessionScope(mainToken);
    if (!scope) return '';
    // A fresh private token may help after rotation, but it cannot select a
    // different person/session or restore a session the main app signed out.
    return [mainToken, ...candidates]
      .filter(token => sessionScope(token) === scope &&
        Number(claims(token)?.exp) * 1000 > now + 30000)
      .sort((a, b) => Number(claims(b).exp) - Number(claims(a).exp))[0] || '';
  }

  function apiUrl(value) {
    let url;
    try { url = new URL(value); } catch (_) {
      throw new Error('The Email Center request must use the secure KORLIX API.');
    }
    if (url.origin !== apiOrigin || url.username || url.password ||
        !url.pathname.startsWith('/api/') || url.hash) {
      throw new Error('The Email Center request must use the secure KORLIX API.');
    }
    return url.href;
  }

  async function request(value, options = {}, fetcher = globalThis.fetch) {
    // Validate before fetch: a stored setting or absolute response URL must
    // never redirect an access token or refresh-token body to another host.
    const url = apiUrl(value);
    return fetcher(url, {
      ...options,
      redirect: 'error',
      credentials: 'omit',
      referrerPolicy: 'no-referrer',
    });
  }

  return Object.freeze({apiOrigin, apiUrl, request, sessionScope, chooseSessionToken});
});
