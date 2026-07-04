// sw.js — Swish Strike service worker. Network-first for the app shell (so updates land
// immediately when online), cache fallback when offline. Cache-first for the big
// vendored model libraries, which never change between releases. Same-origin
// GET only — no third-party caching.
const CACHE = 'swishstrike-v1';
const VENDOR = /\/vendor\//;

self.addEventListener('install', (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) =>
      c.addAll([
        './index.html', './manifest.webmanifest', './icon.svg', './css/styles.css',
        './js/app.js', './js/games.js', './js/heroArt.js', './js/countingEngine.js',
        './js/tracker.js', './js/players.js', './js/coach.js', './js/sim.js', './js/detector.js',
        './js/vision/color.js', './js/vision/motion.js', './js/vision/ballDetector.js',
        './js/vision/poseDetector.js', './js/vision/calibrator.js',
      ]).catch(() => {})
    ).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin) return;

  if (VENDOR.test(url.pathname)) {
    // vendor libs: cache-first (large, immutable)
    e.respondWith(
      caches.match(e.request).then((hit) => hit || fetch(e.request).then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(e.request, copy));
        return res;
      }))
    );
    return;
  }

  // app shell: network-first, cache fallback (offline)
  e.respondWith(
    fetch(e.request).then((res) => {
      const copy = res.clone();
      caches.open(CACHE).then((c) => c.put(e.request, copy));
      return res;
    }).catch(() => caches.match(e.request))
  );
});
