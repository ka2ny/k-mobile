// Agents on the phone: the app opens without a connection (it says it can't reach the computer),
// and a push says which agent needs you; tapping it opens that agent. Nothing from /api is kept.
const CACHE = 'khole-agents-mobile-cohesion-17';
// paths are the registration's own: "/" on its own address, "/agents/" inside the k-hole app
const BASE = new URL(self.registration.scope);
const at = p => new URL(p, BASE).pathname;
const SHELL = ['', 'app.js', 'app.css', 'model.js', 'omp.js', 'tokens.css', 'plex-sans.woff2', 'plex-mono.woff2', 'icon.svg', 'icon-180.png', 'manifest.webmanifest'].map(at);
// Unified mode keeps its navigation and settings available offline too.
if (BASE.pathname === "/agents/") SHELL.push("/switch.js", "/switch.css", "/mobile-sans.woff2", "/mobile-mono.woff2");

self.addEventListener('install', e => e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())));
self.addEventListener('activate', e => e.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(k => k.startsWith('khole-agents-') && k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())));
self.addEventListener('fetch', e => {
  const u = new URL(e.request.url);
  if (e.request.method !== 'GET' || u.origin !== location.origin || !SHELL.includes(u.pathname)) return;
  e.respondWith(fetch(e.request).then(r => { if (r.ok) { const copy = r.clone(); caches.open(CACHE).then(c => c.put(u.pathname, copy)); } return r; }).catch(() => caches.match(u.pathname)));
});

// a push carries {title, body, agent, tag}; the words are written on the computer
self.addEventListener('push', e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch { d = {}; }
  const agent = typeof d.agent === 'string' && /^[a-f0-9-]{36}$/i.test(d.agent) ? d.agent : '';
  const title = String(d.title || 'An agent needs you').slice(0, 120), body = String(d.body || '').slice(0, 240);
  e.waitUntil((async () => {
    if (d.clear && agent) { for (const n of await self.registration.getNotifications({tag: 'agent-' + agent})) n.close(); }
    else await self.registration.showNotification(title, {body, tag: agent ? 'agent-' + agent : 'agents', data: {agent}, icon: at('icon-180.png'), badge: at('icon.svg'), renotify: true});
    if (Number.isFinite(d.badge) && self.navigator.setAppBadge) { try { if (d.badge > 0) await self.navigator.setAppBadge(d.badge); else await self.navigator.clearAppBadge(); } catch { /* no badge */ } }
  })());
});
self.addEventListener('notificationclick', e => {
  e.notification.close();
  const agent = e.notification.data?.agent || '';
  e.waitUntil((async () => {
    const wins = await self.clients.matchAll({type: 'window', includeUncontrolled: true});
    for (const w of wins) { if (w.url.startsWith(BASE.href)) { await w.focus(); if (agent) w.postMessage({agent}); return; } }
    await self.clients.openWindow(BASE.href + (agent ? '#agent=' + agent : ''));
  })());
});
