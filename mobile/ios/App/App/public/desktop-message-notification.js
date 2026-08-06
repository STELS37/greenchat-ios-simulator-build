const EVENT_NAME = "gc://desktop-message-notification";
const VISIBLE_MS = 7000;
const LEAVE_MS = 220;

const tauri = window.__TAURI__;
const invoke = tauri?.core?.invoke;
const listen = tauri?.event?.listen;
const root = document.getElementById("notification");
const sender = document.getElementById("sender");
const body = document.getElementById("body");
const hint = document.getElementById("hint");
const count = document.getElementById("count");
const close = document.getElementById("close");

let currentId = 0;
let dismissTimer = 0;
let hideTimer = 0;
let leaving = false;

function clearTimers() {
  window.clearTimeout(dismissTimer);
  window.clearTimeout(hideTimer);
  dismissTimer = 0;
  hideTimer = 0;
}

function compactText(value, limit) {
  const compact = typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";
  if (!compact) return null;
  const chars = Array.from(compact);
  return chars.length > limit ? `${chars.slice(0, limit).join("")}…` : compact;
}

function validPayload(value) {
  if (!value || typeof value !== "object") return null;
  const id = Number(value.id);
  const total = Number(value.count);
  if (!Number.isSafeInteger(id) || id <= 0) return null;
  return {
    id,
    count: Number.isFinite(total) ? Math.max(1, Math.trunc(total)) : 1,
    sender: compactText(value.sender, 72),
    body: compactText(value.body, 180) || "Новое сообщение",
    hasPreview: value.hasPreview === true,
  };
}

function finish(command) {
  const id = currentId;
  currentId = 0;
  leaving = false;
  root.classList.remove("is-visible", "is-leaving");
  if (id > 0 && invoke) void invoke(command, { id }).catch(() => {});
}

function leave(command = "desktop_message_notification_dismiss") {
  if (!currentId || leaving) return;
  leaving = true;
  clearTimers();
  root.classList.remove("is-visible");
  root.classList.add("is-leaving");
  hideTimer = window.setTimeout(() => finish(command), LEAVE_MS);
}

function show(raw) {
  const payload = validPayload(raw);
  if (!payload) return;
  clearTimers();
  leaving = false;
  currentId = payload.id;
  sender.textContent = payload.sender || "Новое сообщение";
  body.textContent = payload.body;
  body.hidden = !payload.sender && !payload.hasPreview;
  hint.hidden = !body.hidden;
  count.hidden = payload.count <= 1;
  count.textContent = payload.count > 99 ? "99+" : String(payload.count);
  const spoken = body.hidden
    ? "Новое сообщение. Открыть Green Chat"
    : `${sender.textContent}. ${payload.body}. Открыть Green Chat`;
  root.setAttribute("aria-label", spoken);

  root.classList.remove("is-visible", "is-leaving");
  void root.offsetWidth;
  window.requestAnimationFrame(() => root.classList.add("is-visible"));
  dismissTimer = window.setTimeout(() => leave(), VISIBLE_MS);
}

root.addEventListener("click", (event) => {
  if (event.target === close || close.contains(event.target)) return;
  leave("desktop_message_notification_open");
});

root.addEventListener("keydown", (event) => {
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    leave("desktop_message_notification_open");
  }
});

close.addEventListener("click", (event) => {
  event.preventDefault();
  event.stopPropagation();
  leave();
});

window.addEventListener("keydown", (event) => {
  if (event.key === "Escape") leave();
});

window.__gcShowDesktopMessageNotification = show;

if (typeof listen === "function") {
  await listen(EVENT_NAME, (event) => show(event?.payload));
}

if (typeof invoke === "function") {
  await invoke("desktop_message_notification_ready").catch(() => {});
}
