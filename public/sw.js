// The k-hole phone app's own worker, at /: it keeps only the hub's few files. Remote, k-beam and
// Agents each have their own worker (the Assistant's page is live, never cached) under their own path, which controls their pages; nothing
// of theirs (and no /api/, /app/ answer) is cached or answered here.
"use strict";
const CACHE = "khole-app-v19";
const FILES = ["/", "/index.html", "/hub.css", "/hub.js", "/switch.js", "/switch.css", "/manifest.webmanifest", "/mobile-sans.woff2", "/mobile-mono.woff2"];
const PARTS = /^\/(remote|beam|agents|assistant|api|app)(\/|$)/;

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(FILES)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  // only the hub's own older caches; the parts clean up theirs
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k.startsWith("khole-app-") && k !== CACHE)
    .map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin || PARTS.test(url.pathname)) return;
  if (!FILES.includes(url.pathname)) return;
  e.respondWith(
    fetch(e.request).then((r) => {
      if (r.ok) { const copy = r.clone(); caches.open(CACHE).then((c) => c.put(url.pathname, copy)); }
      return r;
    }).catch(() => caches.match(url.pathname).then((r) => r || caches.match("/index.html")))
  );
});
