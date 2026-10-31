// Mis finanzas · service worker.
// - Guarda la app (página, config, librería) para poder abrirla sin conexión. Siempre intenta primero
//   la red para no quedarse con versiones viejas; solo si falla usa lo guardado.
// - Muestra las notificaciones.
const CACHE = "mf-app-v2";
const SHELL = ["./", "index.html", "config.js", "manifest.json", "icon-192.png", "apple-touch-icon.png",
  "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.117.3/dist/umd/supabase.js"];

self.addEventListener("install", e => {
  e.waitUntil(caches.open(CACHE).then(c => Promise.all(SHELL.map(u => c.add(new Request(u, { cache: "reload" })).catch(() => {})))));
  self.skipWaiting();
});
self.addEventListener("activate", e => e.waitUntil((async () => {
  for (const k of await caches.keys()) if (k !== CACHE) await caches.delete(k);
  await self.clients.claim();
})()));

// Red primero; si no hay red, lo guardado. Solo para la app misma, la librería y las fuentes (no para tus datos).
self.addEventListener("fetch", e => {
  const req = e.request, url = new URL(req.url);
  if (req.method !== "GET") return;
  const mine = url.origin === self.location.origin, lib = url.href.startsWith("https://cdn.jsdelivr.net/npm/@supabase/"), font = /fonts\.(googleapis|gstatic)\.com$/.test(url.hostname);
  if (!mine && !lib && !font) return;
  e.respondWith((async () => {
    const cache = await caches.open(CACHE);
    try {
      const res = await fetch(req);
      if (res.ok && (mine || lib || font)) cache.put(mine && req.mode === "navigate" ? "index.html" : req, res.clone());
      return res;
    } catch (err) {
      const hit = await cache.match(req, { ignoreSearch: true }) || (req.mode === "navigate" ? await cache.match("index.html") : null);
      if (hit) return hit;
      throw err;
    }
  })());
});

self.addEventListener("push", e => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch { d = { body: e.data ? e.data.text() : "" }; }
  e.waitUntil(self.registration.showNotification(d.title || "Mis finanzas", {
    body: d.body || "", tag: d.tag, icon: "icon-192.png", badge: "icon-192.png", data: { url: d.url || "./" },
  }));
});

// Al tocar la notificación: abre la app (o la trae al frente) en la sección indicada.
self.addEventListener("notificationclick", e => {
  e.notification.close();
  const url = new URL((e.notification.data && e.notification.data.url) || "./", self.registration.scope).href;
  e.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const w of wins) { if ("focus" in w) { await w.focus(); w.postMessage({ type: "open", url }); return; } }
    await self.clients.openWindow(url);
  })());
});
