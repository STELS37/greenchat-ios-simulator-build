const EVENT_NAME = "gc://desktop-call-notification";
const LEAVE_MS = 170;

const tauri = window.__TAURI__;
const invoke = tauri?.core?.invoke;
const listen = tauri?.event?.listen;
const root = document.getElementById("call-notification");
const callerName = document.getElementById("caller-name");
const callKind = document.getElementById("call-kind");
const avatar = document.getElementById("avatar");
const videoBadge = document.getElementById("video-badge");
const answer = document.getElementById("answer");
const decline = document.getElementById("decline");

let currentId = 0;
let actionPending = false;
let leaveTimer = 0;

function cleanName(value) {
  const compact = typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";
  return compact || "Пользователь Green Chat";
}

function initialFor(value) {
  const first = Array.from(cleanName(value))[0];
  return first ? first.toLocaleUpperCase("ru-RU") : "G";
}

function validPayload(value) {
  if (!value || typeof value !== "object") return null;
  const id = Number(value.id);
  if (!Number.isSafeInteger(id) || id <= 0) return null;
  return { id, name: cleanName(value.name), video: value.video === true };
}

function show(raw) {
  const payload = validPayload(raw);
  if (!payload) return;
  window.clearTimeout(leaveTimer);
  actionPending = false;
  currentId = payload.id;
  callerName.textContent = payload.name;
  avatar.textContent = initialFor(payload.name);
  callKind.textContent = payload.video ? "Видеозвонок в Green Chat" : "Аудиозвонок в Green Chat";
  videoBadge.hidden = !payload.video;
  answer.disabled = false;
  decline.disabled = false;
  root.setAttribute("aria-label", `Входящий ${payload.video ? "видео" : "аудио"}звонок. ${payload.name}`);
  root.classList.remove("is-visible", "is-leaving", "is-answering", "is-declining");
  void root.offsetWidth;
  window.requestAnimationFrame(() => root.classList.add("is-visible"));
}

function perform(action) {
  if (!currentId || actionPending || typeof invoke !== "function") return;
  actionPending = true;
  answer.disabled = true;
  decline.disabled = true;
  root.classList.add(action === "answer" ? "is-answering" : "is-declining");
  root.classList.remove("is-visible");
  root.classList.add("is-leaving");
  const id = currentId;
  currentId = 0;
  window.clearTimeout(leaveTimer);
  leaveTimer = window.setTimeout(() => {
    void invoke("desktop_call_notification_action", { id, action }).catch(() => {
      // Native handoff failed before the call controller saw the action. Restore the exact card instead
      // of leaving a ringing call behind an invisible, disabled notification.
      currentId = id;
      actionPending = false;
      answer.disabled = false;
      decline.disabled = false;
      root.classList.remove("is-leaving", "is-answering", "is-declining");
      root.classList.add("is-visible");
    });
  }, LEAVE_MS);
}

answer.addEventListener("click", () => perform("answer"));
decline.addEventListener("click", () => perform("decline"));

window.addEventListener("keydown", (event) => {
  if (event.key === "Enter") perform("answer");
  if (event.key === "Escape") perform("decline");
});

window.__gcShowDesktopCallNotification = show;

if (typeof listen === "function") {
  await listen(EVENT_NAME, (event) => show(event?.payload));
}
if (typeof invoke === "function") {
  await invoke("desktop_call_notification_ready").catch(() => {});
}
