// k-hole's service worker: the app shell opens instantly (and says so when the
// computer is away); the API is never cached. Network first, so a k-hole update
// reaches the phone on the next open.
"use strict";
const CACHE = "khole-shell-v25";
const SHELL = ["./", "index.html", "app.css", "app.js", "manifest.webmanifest", "icon.svg", "icon-192.png", "icon-512.png", "apple-touch-icon.png"];

// Unified mode keeps its navigation and settings available offline too.
if (new URL(self.registration.scope).pathname === "/remote/") SHELL.push("/switch.js", "/switch.css", "/mobile-sans.woff2", "/mobile-mono.woff2");

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});
self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k.startsWith("khole-shell-") && k !== CACHE).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});
self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin || url.pathname.startsWith("/api/")) return;
  e.respondWith(
    fetch(e.request).then((r) => {
      if (r.ok) { const copy = r.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy)); }
      return r;
    }).catch(() => caches.match(e.request).then((r) => r || caches.match("index.html")))
  );
});
