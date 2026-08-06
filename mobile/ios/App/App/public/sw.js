// clients/web/sw.js — Green Chat service worker (T-408, CLIENTS.md §7.1).
// Classic (non-module) worker for maximal reach, incl. iOS Safari ≥ 16.4 PWA. build.mjs templates the
// two placeholders below at build time: __SW_VERSION__ (a content hash → a new SW per deploy) and
// __PRECACHE__ (the exact hashed app-shell URLs). Policy:
//   - precache the app shell; serve it for navigations (offline-first shell, SPA routing in the hash).
//   - API (/v1/*), including ACL-protected media, is NEVER cached by the service worker.
//   - a new worker waits (no auto-skipWaiting); the page shows an «Обновить» banner and posts SKIP_WAITING.
//   - push → showNotification; click → focus/open the target chat deep link.
"use strict";

const VERSION = "Y7S64FJ4";
const SHELL_CACHE = "gc-shell-" + VERSION;
// Deleted on activation for upgrades from builds that cached private /v1/files responses by URL.
const LEGACY_MEDIA_CACHE = "gc-media-v1";
const PRECACHE = ["/","/index.html","/assets/app.RDIU5UWU.css","/assets/app.Y7S64FJ4.js","/assets/chunk.3R52YSER.js","/assets/chunk.3UPOALN5.js","/assets/chunk.4OPZWSUS.js","/assets/chunk.4SGRZRDJ.js","/assets/chunk.553VKZ52.js","/assets/chunk.BLCH77FZ.js","/assets/chunk.BTZI4SSB.js","/assets/chunk.C34KMXTG.js","/assets/chunk.CEFR7CUJ.js","/assets/chunk.FFUW5R4W.js","/assets/chunk.FKMGW3JX.js","/assets/chunk.GX6UQENF.js","/assets/chunk.HDQ6PTY5.js","/assets/chunk.ITD6Q2B4.js","/assets/chunk.IXH3XKUI.js","/assets/chunk.KKKMLQPZ.js","/assets/chunk.KQS4EBIX.js","/assets/chunk.LTA4DV3D.js","/assets/chunk.OCXFFSUD.js","/assets/chunk.OTPFWLJS.js","/assets/chunk.R6MNQPFC.js","/assets/chunk.RPWKWGH5.js","/assets/chunk.UKNGYS6X.js","/assets/chunk.W6ZJBB3H.js","/assets/chunk.WAYP7RHX.js","/manifest.webmanifest","/icon.svg","/icon-maskable.svg","/apple-touch-icon.svg","/favicon.svg","/site-loader.js?v=55e39e12fa8814c99dca10cde6e2b80cdb13ec49","/downloads.json?v=55e39e12fa8814c99dca10cde6e2b80cdb13ec49","/site.css?v=55e39e12fa8814c99dca10cde6e2b80cdb13ec49"];

// ---- lifecycle ----------------------------------------------------------------------------------

self.addEventListener("install", (event) => {
  // Precache the shell for this version. Do NOT skipWaiting — a controlled tab keeps its old assets
  // until the user accepts the update, so a half-loaded new bundle can never mix with old chunks.
  event.waitUntil(caches.open(SHELL_CACHE).then((cache) => cache.addAll(PRECACHE)));
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    // Drop stale shell caches and purge the legacy private-media cache from vulnerable builds.
    const keys = await caches.keys();
    await Promise.all(
      keys.map((key) => (
        (key.startsWith("gc-shell-") && key !== SHELL_CACHE) || key === LEGACY_MEDIA_CACHE
          ? caches.delete(key)
          : undefined
      )),
    );
    await self.clients.claim();
  })());
});

self.addEventListener("message", (event) => {
  // The page's «Обновить» button posts this once the user accepts the waiting worker.
  if (event.data && event.data.type === "SKIP_WAITING") self.skipWaiting();
});

// ---- fetch routing ------------------------------------------------------------------------------

self.addEventListener("fetch", (event) => {
  const req = event.request;
  if (req.method !== "GET") return; // mutations always hit the network, never cached
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return; // cross-origin: let the browser handle it

  if (url.pathname.startsWith("/v1/")) {
    // API responses are identity/ACL scoped. Let the browser hit the network and honor the server's
    // no-store policy; caching by URL can leak one account's private response to the next account.
    return;
  }

  if (req.mode === "navigate") { event.respondWith(navigate(req)); return; }
  event.respondWith(cacheFirst(req));
});

// Navigations: try the network (fresh no-store shell picks up new hashed assets), fall back to the
// precached shell when offline so the app boots and resolves the route from the hash.
async function navigate(req) {
  try {
    return await fetch(req);
  } catch (_err) {
    const cache = await caches.open(SHELL_CACHE);
    return (await cache.match("/index.html")) || (await cache.match("/")) || Response.error();
  }
}

// Hashed assets are immutable → cache-first, populating the shell cache on first miss (post-update
// chunks land here). Non-asset statics were already precached.
async function cacheFirst(req) {
  const cache = await caches.open(SHELL_CACHE);
  const hit = await cache.match(req);
  if (hit) return hit;
  const res = await fetch(req);
  if (res && res.status === 200 && new URL(req.url).pathname.startsWith("/assets/")) {
    cache.put(req, res.clone()).catch(() => {});
  }
  return res;
}



// ---- push-latency sampling (T-418, strictly opt-in) --------------------------------------------
// A push can arrive with every page closed, so the KPI «доставка p95 < 5 с» is sampled HERE, in the
// worker, not on a page. We compare the dispatch time stamped on the payload (sent_at, unix seconds)
// against local receipt time and append {s, r} to the shared IndexedDB «gc-diag» → «samples» store; the
// page's Diagnostics controller drains it once a day. Gated on the SAME local consent flag the settings
// toggle writes (kv.consent === true) — without consent nothing is ever recorded. The schema here mirrors
// clients/web/src/diag_store.ts exactly. This path must never throw or delay the notification.

const DIAG_DB = "gc-diag";
const DIAG_DB_VERSION = 1;

function diagOpen() {
  return new Promise((resolve, reject) => {
    let req;
    try { req = indexedDB.open(DIAG_DB, DIAG_DB_VERSION); }
    catch (err) { reject(err); return; }
    req.onupgradeneeded = () => {
      const db = req.result;
      if (!db.objectStoreNames.contains("kv")) db.createObjectStore("kv");
      if (!db.objectStoreNames.contains("crashes")) db.createObjectStore("crashes", { keyPath: "id" });
      if (!db.objectStoreNames.contains("samples")) db.createObjectStore("samples", { autoIncrement: true });
    };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error || new Error("gc-diag open error"));
  });
}

function diagConsent(db) {
  return new Promise((resolve) => {
    try {
      const tx = db.transaction("kv", "readonly");
      const rq = tx.objectStore("kv").get("consent");
      rq.onsuccess = () => resolve(rq.result === true);
      tx.onerror = () => resolve(false);
      tx.onabort = () => resolve(false);
    } catch (_err) { resolve(false); }
  });
}

function diagAddSample(db, row) {
  return new Promise((resolve) => {
    try {
      const tx = db.transaction("samples", "readwrite");
      tx.objectStore("samples").add(row);
      tx.oncomplete = () => resolve();
      tx.onerror = () => resolve();
      tx.onabort = () => resolve();
    } catch (_err) { resolve(); }
  });
}

async function recordPushSample(data) {
  try {
    const sent = data ? Number(data.sent_at) : NaN;
    if (!Number.isFinite(sent) || sent <= 0) return; // no dispatch stamp → nothing to measure
    const db = await diagOpen();
    try {
      if (!(await diagConsent(db))) return; // opt-in only: no consent → record nothing
      await diagAddSample(db, { s: sent, r: Date.now() });
    } finally {
      db.close();
    }
  } catch (_err) {
    // Diagnostics must never disturb notification delivery.
  }
}

// ---- push --------------------------------------------------------------------------------------
// T-531 (DS-13, DEVICE_SECURITY §7): what a notification SHOWS is decided by the CLIENT-LOCAL display
// mode «full/name/generic», persisted by the settings screen into the shared «gc-diag» kv store
// (key "notify_mode") so this worker can read it with every page closed. The payload itself is already
// privacy-first (CLIENTS §8.3): identifiers only; title/body present ONLY on the recipient's server-side
// notify_preview opt-in — so mode "full" without opt-in still renders the generic strings.

const NOTIFY_MODE_KEY = "notify_mode";
const NOTIFY_MODE_DEFAULT = "full";

// Read the mode from gc-diag kv; ANY failure (no DB, no key, junk value) → the safe default. Bounded
// by a 500 ms race so a wedged IndexedDB can never delay the notification (same never-throw discipline
// as the T-418 helpers above).
function readNotifyMode() {
  const read = (async () => {
    const db = await diagOpen();
    try {
      return await new Promise((resolve) => {
        try {
          const tx = db.transaction("kv", "readonly");
          const rq = tx.objectStore("kv").get(NOTIFY_MODE_KEY);
          rq.onsuccess = () => resolve(rq.result);
          tx.onerror = () => resolve(undefined);
          tx.onabort = () => resolve(undefined);
        } catch (_err) { resolve(undefined); }
      });
    } finally {
      db.close();
    }
  })().catch(() => undefined);
  const timeout = new Promise((resolve) => setTimeout(() => resolve(undefined), 500));
  return Promise.race([read, timeout]).then(
    (v) => (v === "full" || v === "name" || v === "generic" ? v : NOTIFY_MODE_DEFAULT),
    () => NOTIFY_MODE_DEFAULT,
  );
}

// MIRROR of clients/core/src/notify_render.ts renderNotification — the authoritative, node-tested
// implementation. This worker is a classic (non-module) script and cannot import that TS module, so the
// logic is duplicated line-for-line; clients/core/test/notify_render_sw.test.ts runs THIS file in a vm
// and pins the two equal on shared fixtures. Edit both together. Contract: reads ONLY
// {chat_id, message_id, kind, title, body}; never throws; never logs payload content.
function renderNotification(payload, mode, hooks) {
  const p = payload !== null && typeof payload === "object" ? payload : {};
  const kind = p.kind;
  const chatId = p.chat_id;
  let hidden = false;
  if (hooks && typeof hooks.isHiddenChat === "function") {
    try { hidden = hooks.isHiddenChat(chatId) === true; } catch (_err) { hidden = false; }
  }
  const m = hidden ? "generic" : (mode === "full" || mode === "name" || mode === "generic" ? mode : NOTIFY_MODE_DEFAULT);
  // kind === "call" stays distinguishable in EVERY mode (incl. generic/hidden): «Входящий звонок» names
  // no one and quotes nothing, and calls must keep their urgency/renotify semantics (CLIENTS §8.3).
  const isCall = kind === "call";
  const genericBody = isCall ? "Входящий звонок" : "Новое сообщение";
  const sentTitle = typeof p.title === "string" && p.title !== "" ? p.title : null;
  const sentBody = typeof p.body === "string" && p.body !== "" ? p.body : null;
  const title = m === "generic" ? "Green Chat" : sentTitle !== null ? sentTitle : "Green Chat";
  const body = m === "full" && sentBody !== null ? sentBody : genericBody;
  const options = {
    body,
    icon: "/icon.svg",
    badge: "/icon-maskable.svg",
    data: { chat_id: chatId, message_id: p.message_id, kind },
    renotify: isCall,
  };
  if (isCall) {
    options.actions = [
      { action: "answer", title: "Ответить" },
      { action: "decline", title: "Отклонить" },
    ];
  }
  // Ordinary messages coalesce per chat; calls never coalesce, so every ring attempt stays visible.
  if (!isCall && chatId !== undefined && chatId !== null) options.tag = "gc-chat-" + String(chatId);
  return { title, options };
}

async function hasVisibleWindowClient() {
  try {
    const wins = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    return wins.some((win) => win.visibilityState === "visible");
  } catch (_err) {
    return false;
  }
}

self.addEventListener("push", (event) => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch (_err) { data = {}; }
  // Hidden chats (T-527) are not built yet — no hook is passed, every chat renders by mode. When T-527
  // lands it plugs an isHiddenChat predicate into the third argument here.
  event.waitUntil((async () => {
    // A stale session timestamp can make the server target an otherwise visible PWA in a multi-device
    // account. The worker is the final foreground guard: record latency, but do not duplicate the in-app
    // event with an OS tray notification while any controlled Green Chat window is visible.
    if (await hasVisibleWindowClient()) {
      await recordPushSample(data);
      return;
    }
    const mode = await readNotifyMode();
    const r = renderNotification(data, mode);
    // Show the notification AND (opt-in only) sample how long the push took to arrive.
    await Promise.all([
      self.registration.showNotification(r.title, r.options),
      recordPushSample(data),
    ]);
  })());
});

function callNotificationAction(raw, data) {
  const d = data && typeof data === "object" ? data : {};
  if (d.kind !== "call" || (raw !== "answer" && raw !== "decline")) return null;
  const chatId = Number(d.chat_id);
  if (!Number.isSafeInteger(chatId) || chatId <= 0) return null;
  return { action: raw, chat_id: chatId, received_at: Date.now() };
}

function notificationTarget(data, action) {
  const d = data && typeof data === "object" ? data : {};
  const chatId = Number(d.chat_id);
  const messageId = Number(d.message_id);
  if (!Number.isSafeInteger(chatId) || chatId <= 0) return "/?app=1#/";
  const actionQuery = action ? "&gc_call_action=" + action.action + "&gc_call_chat=" + chatId : "";
  const chat = "/?app=1" + actionQuery + "#/chat/" + chatId;
  return Number.isSafeInteger(messageId) && messageId > 0 ? chat + "/message/" + messageId : chat;
}

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  const data = event.notification.data;
  const action = callNotificationAction(event.action, data);
  const target = notificationTarget(data, action);
  event.waitUntil((async () => {
    const wins = await self.clients.matchAll({ type: "window", includeUncontrolled: true });
    for (const win of wins) {
      if (!("focus" in win)) continue;
      if (action && "postMessage" in win) {
        let posted = false;
        try {
          win.postMessage({ type: "gc.call.notification.action", ...action });
          posted = true;
        } catch (_err) { /* fall through to the cold-start navigation payload */ }
        if (posted) return win.focus();
      }
      try { if ("navigate" in win) await win.navigate(target); } catch (_err) { /* cross-origin nav guard */ }
      return win.focus();
    }
    if (self.clients.openWindow) return self.clients.openWindow(target);
    return undefined;
  })());
});
