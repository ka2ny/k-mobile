// k-beam's service worker: the app's own files for a quick start, notifications from the
// computer while the app is closed, and Android's share menu (files and text handed to the app).
// Nothing from /api/ is ever cached: those answers belong to this phone's pairing.
"use strict";

const SHELL = "khole-share-v19";
// every path is the registration's own: "/" on its old address, "/beam/" inside the k-hole app
const BASE = new URL(self.registration.scope);
const at = (p) => new URL(p, BASE).pathname;
const FILES = ["", "app.js", "app.css", "manifest.webmanifest", "icon.svg", "icon-192.png"].map(at);

// Unified mode keeps its navigation and settings available offline too.
if (BASE.pathname === "/beam/") FILES.push("/switch.js", "/switch.css", "/mobile-sans.woff2", "/mobile-mono.woff2");

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(SHELL).then((c) => c.addAll(FILES)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys()
    .then((keys) => Promise.all(keys.filter((k) => k.startsWith("khole-share-v") && k !== SHELL).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});

async function shareTarget(request) {
  // Android: Share > k-beam POSTs here. Keep what came, then open the app, which sends it.
  const form = await request.formData();
  const cache = await caches.open("khole-share-in");
  for (const k of await cache.keys()) await cache.delete(k);
  const files = form.getAll("files").filter((f) => f && typeof f === "object" && "size" in f);
  for (let i = 0; i < files.length; i++) {
    await cache.put(at(`shared/${i}`), new Response(files[i], {
      headers: { "Content-Type": files[i].type || "application/octet-stream", "X-Name": encodeURIComponent(files[i].name || `file-${i}`) },
    }));
  }
  const meta = { count: files.length, title: String(form.get("title") || ""), text: String(form.get("text") || ""), url: String(form.get("url") || "") };
  await cache.put(at("shared/meta"), new Response(JSON.stringify(meta), { headers: { "Content-Type": "application/json" } }));
  return Response.redirect(new URL("?shared=1", BASE).href, 303);
}

self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (url.origin !== location.origin) return;
  if (url.pathname === at("share-target") && e.request.method === "POST") {
    e.respondWith(shareTarget(e.request));
    return;
  }
  if (e.request.method !== "GET" || url.pathname.startsWith(at("api/")) || url.search) return;
  if (!FILES.includes(url.pathname)) return;
  // The network first (a computer that updated serves the new app), the kept copy when it doesn't answer.
  e.respondWith(fetch(e.request).then((r) => {
    if (r.ok) {
      const copy = r.clone();
      caches.open(SHELL).then((c) => c.put(e.request, copy));
    }
    return r;
  }).catch(() => caches.match(e.request).then((r) => r || Response.error())));
});

self.addEventListener("push", (e) => {
  let m = {};
  try { m = e.data ? e.data.json() : {}; } catch (err) { m = {}; }
  if (m.clear) {
    e.waitUntil(self.registration.getNotifications({ tag: m.clear }).then((ns) => ns.forEach((n) => n.close())));
    return;
  }
  const title = String(m.title || "k-beam").slice(0, 80);
  const body = String(m.body || "Something arrived from the computer.").slice(0, 200);
  e.waitUntil(self.registration.showNotification(title, {
    body, tag: String(m.tag || m.item || "khole-share"), icon: at("icon-192.png"), badge: at("icon-192.png"),
    data: { item: m.item || "", folder: !!m.folder },
  }).then(() => (self.navigator.setAppBadge && m.waiting ? self.navigator.setAppBadge(m.waiting) : null)).catch(() => {}));
});

self.addEventListener("notificationclick", (e) => {
  e.notification.close();
  const home = BASE.href;
  const to = e.notification.data && e.notification.data.folder ? home + "#folder" : home;
  e.waitUntil(self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((list) => {
    for (const c of list) {
      if (c.url.startsWith(home) && "focus" in c) return (to !== home && "navigate" in c ? c.navigate(to) : Promise.resolve(c)).then((w) => (w || c).focus());
    }
    return self.clients.openWindow(to);
  }));
});
