// Behavioural test for the ruling-page templates.
// Needs Node 18+ and Playwright: `npm i --no-save playwright && npx playwright install chromium`.
// Run from the repository root: node plugins/ruling-page/scripts/template.test.mjs
//
// Checks, for template.html and template-threads.html:
//   1. In a sandboxed frame with storage blocked (as in a Claude app artifact), the page renders with no
//      script errors and says answers are NOT saved instead of "Answers save in this browser".
//   2. With storage available, the page keeps "Answers save in this browser" (so the warning is not always on).
//   3. Card text is shown literally: an HTML payload in every string field creates no element and no side effect.
//   4. "Copy my answers": when the clipboard works the page says Copied; when both clipboard routes fail it
//      says it could not copy, and leaves the answers visible and selected for a manual copy.
//   5. Page state: STATE live shows "This needs you"; a page with no STATE has no banner and nothing switched off;
//      answered and replaced switch the answer controls and Copy off, fold the old cards (still readable and
//      printable) and keep saved answers unchanged when the cards are clicked or typed in; a broken STATE (unknown
//      status, a .md, mailto: or text link, a missing field) logs one console error naming the fault.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

let chromium;
try { ({ chromium } = await import("playwright")); }
catch { console.error("template.test: Playwright is not installed (npm i --no-save playwright && npx playwright install chromium)"); process.exit(2); }

const here = dirname(fileURLToPath(import.meta.url));
const refs = join(here, "..", "skills", "ruling-page", "references");
const PAYLOAD = `<img src=x onerror="window.parent.postMessage('injected','*');document.body.dataset.injected='yes'">`;
const idPayload = n => `<b id="inj${n}" onmouseover="document.body.dataset.injected='yes'">${n}</b>`;
let failures = 0;
const check = (ok, msg) => { if (!ok) { failures++; console.error("FAIL " + msg); } else console.log("ok   " + msg); };

function withPayload(name, html) {
  if (name === "template.html") {
    const data = `const D = [{ id: ${JSON.stringify(idPayload("K1"))}, group: ${JSON.stringify(PAYLOAD)}, title: ${JSON.stringify(PAYLOAD)}, q: ${JSON.stringify(PAYLOAD)}, opts: [[${JSON.stringify(PAYLOAD)}, ${JSON.stringify(PAYLOAD)}], ["B", "b"]], pick: 0, why: ${JSON.stringify(PAYLOAD)}, ev: ${JSON.stringify(PAYLOAD)} }];\n</script>`;
    const out = html.replace(/const D = \[[\s\S]*?\n\];\n<\/script>/, data);
    if (out === html) throw new Error("template.html: could not find the D array to replace");
    return out;
  }
  const t = { id: idPayload("Q1"), group: PAYLOAD, title: PAYLOAD, asked: PAYLOAD, when: PAYLOAD, answer: PAYLOAD, owed: PAYLOAD, ev: PAYLOAD,
    branches: [{ id: idPayload("Q1a"), q: PAYLOAD, opts: [[PAYLOAD, PAYLOAD], ["No", "n"]], pick: 0, why: PAYLOAD }] };
  const out = html.replace(/const T = \[[\s\S]*?\n\];\n/, `const T = [${JSON.stringify(t)}];\n`);
  if (out === html) throw new Error("template-threads.html: could not find the T array to replace");
  return out;
}

const browser = await chromium.launch();
for (const name of ["template.html", "template-threads.html"]) {
  const html = readFileSync(join(refs, name), "utf8");

  // 1, 3, 4: sandboxed frame, storage and clipboard blocked, payload in every field
  {
    const page = await browser.newPage();
    const errors = []; let injected = false;
    page.on("pageerror", e => errors.push(e.message));
    page.on("console", m => { if (m.type() === "error") errors.push(m.text()); });
    await page.exposeFunction("__injected", () => { injected = true; });
    await page.setContent(`<script>addEventListener('message', e => { if (e.data === 'injected') window.__injected(); });</script><iframe id="f" sandbox="allow-scripts" style="width:1200px;height:900px"></iframe>`);
    await page.$eval("#f", (f, h) => { f.srcdoc = h; }, withPayload(name, html));
    await page.waitForTimeout(800);
    const fr = page.frames()[1];
    const saved = await fr.evaluate(() => document.getElementById("saved").textContent);
    check(errors.length === 0, `${name}: no script errors with storage blocked (${errors.join(" | ") || "none"})`);
    check(/not saved/i.test(saved), `${name}: says answers are not saved when storage is blocked ("${saved}")`);
    // The lightbox ships one empty <img id="tp-lb-img"> in the template; any other image or injected element fails.
    const found = await fr.evaluate(() => [...document.querySelectorAll("img:not(#tp-lb-img), b[id^=inj]")].map(e => e.outerHTML.slice(0, 80)));
    const imgs = found.length;
    const flag = await fr.evaluate(() => document.body.dataset.injected || "");
    const literal = await fr.evaluate(p => document.body.innerText.includes(p.slice(0, 20)) && document.body.innerText.includes('<b id="inj'), PAYLOAD);
    check(imgs === 0 && flag === "" && !injected, `${name}: HTML in card fields and ids creates no element and runs nothing (elements ${imgs}${imgs ? ": " + found.join(" ; ") : ""}, flag "${flag}", message ${injected})`);
    check(literal, `${name}: HTML in card fields is shown literally`);
    // Both clipboard routes fail: the page must not claim Copied, and must leave the answers selected.
    await fr.evaluate(() => {
      Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: () => Promise.reject(new Error("blocked")) } });
      document.execCommand = () => false;
    });
    await fr.click("#copy");
    await page.waitForTimeout(300);
    const fail = await fr.evaluate(() => ({ toast: document.getElementById("toast").textContent, shown: getComputedStyle(document.getElementById("out")).display,
      text: document.getElementById("out").textContent.trim(), sel: String(window.getSelection()).trim() }));
    check(/could not copy/i.test(fail.toast) && !/^copied/i.test(fail.toast), `${name}: says it could not copy when the clipboard is blocked ("${fail.toast}")`);
    check(fail.shown !== "none" && fail.text.length > 0 && fail.sel === fail.text, `${name}: leaves the answers visible and selected for a manual copy`);
    // Clipboard works: the page says Copied.
    await fr.evaluate(() => { Object.defineProperty(navigator, "clipboard", { configurable: true, value: { writeText: () => Promise.resolve() } }); });
    await fr.click("#copy");
    await page.waitForTimeout(300);
    const okToast = await fr.evaluate(() => document.getElementById("toast").textContent);
    check(/^copied/i.test(okToast), `${name}: says Copied when the clipboard works ("${okToast}")`);
    await page.close();
  }

  // 2: normal origin, storage available
  {
    const page = await browser.newPage();
    await page.route("http://ruling.test/**", r => r.fulfill({ contentType: "text/html", body: html }));
    await page.goto("http://ruling.test/page.html");
    await page.waitForTimeout(300);
    const saved = await page.evaluate(() => document.getElementById("saved").textContent);
    check(/save in this browser/i.test(saved), `${name}: keeps "Answers save in this browser" when storage works ("${saved}")`);
    await page.close();
  }
}
// 5: page state
const LIVE = 'const STATE = {status: "live"};\n';
async function statePage(name, state) {
  const html = readFileSync(join(refs, name), "utf8");
  if (!html.includes(LIVE)) throw new Error(name + ": the template does not ship STATE live");
  const page = await browser.newPage(), errors = [];
  page.on("pageerror", e => errors.push("pageerror: " + e.message));
  page.on("console", m => { if (m.type() === "error") errors.push(m.text()); });
  const body = html.replace(LIVE, state === null ? "" : "const STATE = " + state + ";\n");
  await page.route("http://ruling.test/**", r => r.fulfill({ contentType: "text/html", body }));
  await page.goto("http://ruling.test/" + name.replace(".html", "") + "-" + Math.random().toString(36).slice(2) + ".html");
  await page.waitForTimeout(400);
  return { page, errors };
}
const banner = page => page.evaluate(() => { const b = document.querySelectorAll(".tp-pstate"); return { n: b.length, state: b[0] && b[0].dataset.state,
  head: b[0] && b[0].querySelector(".tp-pstate-head").textContent, links: b[0] ? [...b[0].querySelectorAll("a")].map(a => a.getAttribute("href")) : [] }; });
for (const name of ["template.html", "template-threads.html"]) {
  {
    const { page, errors } = await statePage(name, '{status: "live"}');
    const b = await banner(page), off = await page.evaluate(() => document.querySelector(".tp").classList.contains("tp-off") || document.getElementById("copy").disabled);
    check(b.n === 1 && b.state === "live" && /needs you/.test(b.head) && !off && !errors.length, `${name}: STATE live shows "This needs you" and leaves the page on (${JSON.stringify(b)} ${errors.join(" | ")})`);
    await page.close();
  }
  {
    const { page, errors } = await statePage(name, null);
    const r = await page.evaluate(() => ({ banners: document.querySelectorAll(".tp-pstate").length, off: document.querySelector(".tp").classList.contains("tp-off"),
      fold: !!document.querySelector("details.tp-old"), copy: document.getElementById("copy").disabled, text: typeof window.rulingText === "function" }));
    check(r.banners === 0 && !r.off && !r.fold && !r.copy && r.text && !errors.length, `${name}: no STATE line: no banner, nothing switched off (${JSON.stringify(r)} ${errors.join(" | ")})`);
    await page.close();
  }
  for (const [st, want] of [['{status: "answered", answered_on: "12 Nov 2026", answers_in: "plan.html#rulings"}', "answered"],
                            ['{status: "replaced", replaced_by: "../new/rulings.html", replaced_on: "12 Nov 2026"}', "replaced"]]) {
    const { page, errors } = await statePage(name, st);
    const b = await banner(page);
    check(b.n === 1 && b.state === want && /^Nothing for you to answer here/.test(b.head) && b.links.length === 1 && /\.html/.test(b.links[0]) && !errors.length,
      `${name}: ${want}: banner says nothing to answer and links the other page (${JSON.stringify(b)} ${errors.join(" | ")})`);
    const before = await page.evaluate(() => ({ text: window.rulingText(), store: JSON.stringify(localStorage) }));
    const ctl = await page.evaluate(() => { const c = document.getElementById("tp-cards"), d = c.closest("details.tp-old");
      return { folded: !!d && !d.open, copy: document.getElementById("copy").disabled && document.getElementById("tp-copy2").disabled,
        answersOff: [...c.querySelectorAll("input, textarea, button:not(.tp-frame)")].every(x => x.disabled) }; });
    check(ctl.folded && ctl.copy && ctl.answersOff, `${name}: ${want}: old cards folded, Copy and every answer control off (${JSON.stringify(ctl)})`);
    await page.evaluate(() => { document.querySelector("details.tp-old").open = true; });
    const radio = await page.$("#tp-cards input[type=radio]:not(:checked)");
    if (radio) await radio.click({ force: true }).catch(() => {});
    const ta = await page.$("#tp-cards textarea");
    if (ta) { await ta.focus().catch(() => {}); await page.keyboard.type("changed").catch(() => {}); }
    await page.keyboard.press("Space").catch(() => {});
    const after = await page.evaluate(() => ({ text: window.rulingText(), store: JSON.stringify(localStorage) }));
    check(after.text === before.text && after.store === before.store, `${name}: ${want}: clicking and typing in the old cards changes nothing saved or copied`);
    const read = await page.evaluate(() => { const c = document.getElementById("tp-cards"), m = c.querySelector("details.tp-more:not([open]) > summary"), f = c.querySelector(".tp-frame"), lb = document.getElementById("tp-lb");
      let more = null, pic = null; if (m) { m.click(); more = m.parentElement.open; } if (f) { f.click(); pic = lb.open; if (lb.open) lb.close(); } return { more, pic }; });
    if (name === "template.html") check(read.more === true && read.pic === true, `${name}: ${want}: folded text and pictures in the old cards still open (${JSON.stringify(read)})`);
    const pr = await page.evaluate(() => { const d = document.querySelector("details.tp-old"); d.open = false; dispatchEvent(new Event("beforeprint")); const o = d.open; dispatchEvent(new Event("afterprint")); return [o, d.open]; });
    check(pr[0] === true && pr[1] === false, `${name}: ${want}: printing opens the old cards and folds them again (${pr})`);
    await page.close();
  }
  for (const [st, rx] of [['{status: "done"}', /STATE\.status must be live, answered or replaced/], ['"answered"', /STATE must be an object/],
                          ['{status: "replaced", replaced_by: "x/rulings.md", replaced_on: "12 Nov 2026"}', /never a \.md/],
                          ['{status: "replaced", replaced_by: "mailto:someone@example.com", replaced_on: "12 Nov 2026"}', /must be another page's \.html/],
                          ['{status: "answered", answered_on: "12 Nov 2026", answers_in: "answers.txt"}', /must be another page's \.html/],
                          ['{status: "replaced", replaced_on: "12 Nov 2026"}', /STATE\.replaced_by is missing/],
                          ['{status: "answered", answers_in: "plan.html"}', /STATE\.answered_on is missing/]]) {
    const { page, errors } = await statePage(name, st);
    check(errors.length === 1 && rx.test(errors[0]), `${name}: ${st} logs one console error naming the fault (${errors.join(" | ") || "none"})`);
    await page.close();
  }
  {
    const { page, errors } = await statePage(name, '{status: "answered", answered_on: "12 Nov 2026"}');
    check(!errors.length, `${name}: answered with no answers_in is allowed (${errors.join(" | ") || "no errors"})`);
    await page.close();
  }
}
await browser.close();
if (failures) { console.error(`template.test: ${failures} failure(s)`); process.exit(1); }
console.log("template.test: all passed");
