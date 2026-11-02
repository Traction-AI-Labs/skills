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
await browser.close();
if (failures) { console.error(`template.test: ${failures} failure(s)`); process.exit(1); }
console.log("template.test: all passed");
