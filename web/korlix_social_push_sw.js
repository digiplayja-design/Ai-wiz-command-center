/* Push-only service worker. It does not cache, intercept or control app pages. */
'use strict';
const STORE = 'korlix-social-push-v1';
function binding(value) {
  return new Promise((resolve, reject) => {
    const request = indexedDB.open(STORE, 1);
    request.onupgradeneeded = () => request.result.createObjectStore('settings');
    request.onerror = () => reject(request.error);
    request.onsuccess = () => {
      const db = request.result;
      const tx = db.transaction('settings', value === undefined ? 'readonly' : 'readwrite');
      const store = tx.objectStore('settings');
      const operation = value === undefined ? store.get('binding') : store.put(value, 'binding');
      let result;
      operation.onsuccess = () => { result = operation.result; };
      tx.oncomplete = () => { db.close(); resolve(result); };
      tx.onerror = () => { db.close(); reject(tx.error); };
    };
  });
}
self.addEventListener('install', event => event.waitUntil(self.skipWaiting()));
self.addEventListener('message', event => {
  const data = event.data || {};
  if (data.type !== 'bind' && data.type !== 'clear') return;
  if (data.type === 'bind' && !/^[0-9a-f-]{36}$/i.test(data.binding || '')) return;
  event.waitUntil((async () => {
    await binding(data.type === 'clear' ? '' : data.binding);
    const notifications = await self.registration.getNotifications();
    notifications.forEach(notification => notification.close());
    event.ports[0]?.postMessage({ok: true});
  })());
});
self.addEventListener('push', event => {
  event.waitUntil((async () => {
    let data;
    try { data = event.data?.json(); } catch (_) { return; }
    if (!data || !['call', 'message', 'group_message'].includes(data.kind)) return;
    if (!data.binding || data.binding !== await binding()) return;
    const expires = Date.parse(data.expiresAt);
    if (!Number.isFinite(expires) || expires <= Date.now()) return;
    await self.registration.showNotification('KORLIX Social', {
      body: data.kind === 'call' ? 'You have an incoming call. Open KORLIX to view it.' : 'You have a new message. Open KORLIX to read it.',
      icon: '../icons/Icon-192.png',
      tag: `korlix-social-${data.kind}-${String(data.eventId || '').slice(0, 80)}`,
      data: {binding: data.binding, expiresAt: data.expiresAt},
      requireInteraction: data.kind === 'call',
    });
  })());
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil((async () => {
    if (event.notification.data?.binding !== await binding()) return;
    // No caller identity, media consent or account authority comes from a push.
    // The opened app signs in and reloads the current account's server inbox.
    const target = new URL('../?social=1', self.registration.scope).href;
    const windows = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
    for (const client of windows) {
      if (new URL(client.url).origin === self.location.origin && new URL(client.url).pathname.startsWith(new URL('../', self.registration.scope).pathname)) {
        client.postMessage({type: 'korlix-social-open', binding: event.notification.data.binding});
        await client.focus();
        return;
      }
    }
    await self.clients.openWindow(target);
  })());
});
