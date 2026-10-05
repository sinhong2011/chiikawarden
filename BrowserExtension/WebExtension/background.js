// Relays page requests to the Chiikawarden app (Safari: the extension's native handler; Chrome: the
// bundled `cw` native-messaging host). The app decides everything: what matches, Touch ID, saving.
const api = globalThis.browser ?? globalThis.chrome;
const HOST = "io.github.sinhong2011.chiikawarden";
const ALLOWED = new Set(["match", "fill", "save"]);

api.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || !ALLOWED.has(message.command) || !sender.tab) return false;
  // The page URL comes from the browser, not from the page, so a frame can't claim another site.
  const url = sender.url ?? sender.tab.url;
  const request = { ...message, url };
  Promise.resolve(api.runtime.sendNativeMessage(HOST, request))
    .then((reply) => sendResponse(reply ?? { ok: false, error: "No answer from Chiikawarden." }))
    .catch((error) => sendResponse({ ok: false, error: String(error?.message ?? error) }));
  return true; // async response
});
