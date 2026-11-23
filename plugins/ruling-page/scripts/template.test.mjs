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
//   6. Design cards (a branch, in template-threads.html): one with pictures is drawn with them; one with no `frames`, one
//      whose only picture is a `data:image/` address with no payload and one whose only picture has an unusable `src` (a
//      same-page `#` reference or a `?` one), one whose only picture is a data address with a whitespace-only payload, are
//      each refused: drawn as a refusal with no answer controls, left out of the tally, the rail and the strip, named on
//      the last line of the copied answers, and logged as one console error naming it. A card with no `design` flag and no
//      pictures is still drawn, and so is one whose only picture has a `#` source (no thumbnail, no refusal, no error). A
//      design card's picture that fails to load logs one console error, and the card is still drawn; two that fail log
//      one error for the card, not one each.
//   7. Saved answers and the bridge: with the page's saved answers seeded for a card that stays, a refused design card (a
//      refused branch and its drawn sibling in template-threads.html) and a part the page no longer draws, the saved
//      answer is still shown, and what is posted to the host (choice_id and text) and what is copied holds only the
//      answers of the parts drawn now, while what is stored stays stored.
//   8. In template-threads.html a thread that carries `design: true` logs one console error naming it, and is still drawn.
//   9. An answered page that holds a refused card (a refused branch): the refusal is folded away with the old cards.
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
// 6: design cards
{
  const PNG = "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 4 4"><rect width="4" height="4"/></svg>');
  const OPTS = [["One", "first"], ["Two", "second"]];
  const frame = src => ({ src, cap: "a picture" });
  // [id, design?, frames?]; the answer is in the ids: DRAWN ones can be answered, REFUSED ones cannot.
  const DEF = [["A1", true, [frame(PNG)]], ["B1", true, undefined], ["C1", true, [frame("data:image/png;base64,")]], ["D1", true, [frame("#frame")]],
               ["E1", undefined, undefined], ["F1", true, [frame("missing-picture.png")]], ["G1", true, [frame("?frame")]],
               ["H1", true, [frame("data:image/png;base64, ")]], ["I1", true, [frame("missing-a.png"), frame("missing-b.png")]],
               ["J1", undefined, [frame("#frame")]]];
  const DRAWN = ["A1", "E1", "F1", "I1", "J1"], REFUSED = ["B1", "C1", "D1", "G1", "H1"];
  const mk = (id, design, frames) => { const o = { id, q: "Question " + id, opts: OPTS, pick: 0, why: "Because." };
    if (design) o.design = true; if (frames) o.frames = frames; return o; };
  const data = name => name === "template.html"
    ? "const D = " + JSON.stringify(DEF.map(([id, d, f]) => ({ ...mk(id, d, f), title: "Card " + id }))) + ";\n</script>"
    : "const T = " + JSON.stringify([{ id: "T1", title: "Thread", asked: "A question", when: "today", answer: "An answer", owed: "",
        branches: DEF.map(([id, d, f]) => mk("T" + id, d, f)) }]) + ";\n";
  for (const name of ["template.html", "template-threads.html"]) {
    const threads = name === "template-threads.html", pre = threads ? "T" : "", sel = id => "#card-" + (threads ? "T1" : id);
    const html = readFileSync(join(refs, name), "utf8").replace(threads ? /const T = \[[\s\S]*?\n\];\n/ : /const D = \[[\s\S]*?\n\];\n<\/script>/, () => data(name));
    const page = await browser.newPage(), errors = [];
    page.on("pageerror", e => errors.push("pageerror: " + e.message));
    page.on("console", m => { if (m.type() === "error") errors.push(m.text()); });
    await page.route("http://ruling.test/**", r => r.request().url().endsWith(".png")
      ? r.fulfill({ contentType: "image/png", body: "not an image" }) : r.fulfill({ contentType: "text/html", body: html }));
    await page.goto("http://ruling.test/design-" + Math.random().toString(36).slice(2) + ".html");
    await page.waitForTimeout(600);
    const got = await page.evaluate(({ threads, pre, drawn, refused }) => {
      const out = { drawn: {}, refused: {} };
      const box = id => threads ? document.querySelector("#card-T1") : document.getElementById("card-" + id);
      for (const id of drawn) {
        const root = threads ? [...document.querySelectorAll("#card-T1 fieldset.tp-part")].find(f => f.textContent.includes(pre + id)) : box(id);
        out.drawn[id] = root ? { controls: root.querySelectorAll("input").length, pictures: root.querySelectorAll(".tp-frame img").length, refused: !!root.classList.contains("tp-refused") } : null;
      }
      for (const id of refused) {
        const root = [...document.querySelectorAll(".tp-refused")].find(e => e.textContent.includes(pre + id));
        out.refused[id] = root ? { controls: root.querySelectorAll("input, textarea, button, select, a, fieldset").length, pictures: root.querySelectorAll("img").length,
          asCard: root.classList.contains("tp-card") || !!root.closest("fieldset.tp-part") } : null;
      }
      const lines = window.rulingText().split("\n");
      out.first = lines[0]; out.last = lines[lines.length - 1];
      out.listed = lines.filter(l => refused.some(id => new RegExp("^\\s*" + pre + id + "\\b").test(l)) && !/^Needs pictures/.test(l));
      out.tally = document.getElementById("tp-tally").textContent;
      out.rail = document.querySelectorAll("#tp-rail li a").length; out.segs = document.querySelectorAll("#tp-strip .tp-seg").length;
      out.refusals = document.querySelectorAll(".tp-refused").length;
      out.eager = [...document.querySelectorAll(".tp-frame img")].every(i => i.getAttribute("loading") !== "lazy");
      return out;
    }, { threads, pre, drawn: DRAWN, refused: REFUSED });
    const A = got.drawn.A1, E = got.drawn.E1, F = got.drawn.F1, I = got.drawn.I1, J = got.drawn.J1;
    check(A && A.pictures === 1 && A.controls === 2 && !A.refused, `${name}: a design ${threads ? "branch" : "card"} with a picture is drawn with it and its controls (${JSON.stringify(A)})`);
    check(E && E.pictures === 0 && E.controls === 2 && !E.refused, `${name}: a ${threads ? "branch" : "card"} with no design flag and no pictures is still drawn (${JSON.stringify(E)})`);
    check(F && F.controls === 2 && F.pictures === 1, `${name}: a design ${threads ? "branch" : "card"} whose picture will not load is still drawn (${JSON.stringify(F)})`);
    check(I && I.controls === 2 && I.pictures === 2, `${name}: a design ${threads ? "branch" : "card"} whose two pictures will not load is still drawn with both (${JSON.stringify(I)})`);
    check(J && J.controls === 2 && J.pictures === 0 && !J.refused && !errors.some(e => e.includes(`"${pre}J1"`)),
      `${name}: a ${threads ? "branch" : "card"} with no design flag and one picture with a # source is drawn with its controls, no thumbnail, no refusal and no console error (${JSON.stringify(J)})`);
    for (const id of REFUSED) {
      const r = got.refused[id], named = errors.filter(e => e.includes(`"${pre}${id}"`) && /no usable picture/.test(e));
      check(r && r.controls === 0 && r.pictures === 0 && !r.asCard && got.refusals === REFUSED.length, `${name}: ${id} is refused: drawn with no controls and no picture, not as a ${threads ? "decision" : "card"} (${JSON.stringify(r)})`);
      check(named.length === 1, `${name}: ${id} logs one console error naming it (${named.length})`);
    }
    const n = threads ? 1 : DRAWN.length, want = threads ? new RegExp(`^Open questions: 0 of 1 answers read, 0 of ${DRAWN.length} decisions answered`) : new RegExp(`^Rulings.*: 0 of ${DRAWN.length} answered`);
    check(want.test(got.first) && new RegExp(" of " + n + "\\b").test(got.tally) && got.rail === n && got.segs === n && !got.listed.length,
      `${name}: the refused ones are out of the tally, the rail, the strip and the answers (${got.first} | ${got.tally} | rail ${got.rail}, strip ${got.segs} | ${got.listed.join(" ; ") || "none listed"})`);
    check(got.last === "Needs pictures, not answerable yet: " + REFUSED.map(id => pre + id).join(", "), `${name}: the last line of the copied answers names the refused ones ("${got.last}")`);
    check(got.eager, `${name}: a design ${threads ? "branch" : "card"}'s pictures load at once`);
    const lost = errors.filter(e => /did not load/.test(e));
    check(lost.length === 2 && lost.filter(e => e.includes(`"${pre}F1"`)).length === 1 && lost.filter(e => e.includes(`"${pre}I1"`)).length === 1,
      `${name}: a design ${threads ? "branch" : "card"}'s picture that fails to load logs one console error naming it, and two that fail log one for the ${threads ? "branch" : "card"} (${lost.length}: ${lost.join(" | ")})`);
    const other = errors.filter(e => !/no usable picture|did not load/.test(e));
    check(other.length === 0, `${name}: no other console errors (${other.join(" | ") || "none"})`);
    await page.close();
  }
}
// 7, 8, 9: saved answers and the bridge, a thread's design flag, the answered page
{
  const NAMES = ["template.html", "template-threads.html"];
  const ABC = [["Alpha", "a"], ["Beta", "b"], ["Gamma", "g"]], RF = [["Refused-one", "x"], ["Refused-two", "y"]];
  const rand = () => Math.random().toString(36).slice(2);
  const withData = (name, items, extra = "") => {
    const html = readFileSync(join(refs, name), "utf8"), threads = name === "template-threads.html";
    const out = html.replace(threads ? /const T = \[[\s\S]*?\n\];\n/ : /const D = \[[\s\S]*?\n\];\n<\/script>/,
      () => extra + (threads ? "const T = " + JSON.stringify(items) + ";\n" : "const D = " + JSON.stringify(items) + ";\n</script>"));
    if (out === html) throw new Error(name + ": could not find the data array to replace");
    return out;
  };
  const thread = branches => ({ id: "T1", title: "Thread", asked: "A question", when: "today", answer: "An answer", owed: "", branches });
  const same = (a, b) => JSON.stringify(Object.entries(a).sort()) === JSON.stringify(Object.entries(b).sort());
  for (const name of NAMES) {
    const threads = name === "template-threads.html";
    // 7: a card that stays (a part it no longer draws is still stored), a refused design card or branch, the bridge set
    const items = threads
      ? [thread([{ id: "T1r", design: true, q: "Refused branch", opts: RF, pick: 0 }, { id: "T1s", q: "Sibling branch", opts: ABC, pick: 0 }])]
      : [{ id: "K1", title: "Card that stays", parts: [{ id: "K1a", q: "Part a", opts: ABC, pick: 0 }, { id: "K1b", q: "Part b", opts: ABC, pick: 0 }] },
         { id: "R1", title: "Refused card", design: true, q: "Refused", opts: RF, pick: 0 }];
    const seed = threads ? { T1: { a: { "b:T1r": 1, "b:T1s": 2 }, n: {} } } : { K1: { a: { "p:K1a": 2, "p:old-zz": 1 }, n: {} }, R1: { a: { _: 1 }, n: {} } };
    const stays = threads ? "T1" : "K1", want = threads ? { "b:T1s": 1 } : { "p:K1a": 2, "p:K1b": 1 };
    const html = withData(name, items, 'const RULING_BRIDGE = {origin: "http://ruling.test", id: "r1"};\n');
    const path = "/saved-" + rand() + ".html", errors = [];
    const page = await browser.newPage();
    page.on("pageerror", e => errors.push("pageerror: " + e.message));
    page.on("console", m => { if (m.type() === "error") errors.push(m.text()); });
    await page.route("http://ruling.test/**", r => r.request().url().endsWith("/host.html")
      ? r.fulfill({ contentType: "text/html", body: '<script>window.__msgs = []; addEventListener("message", e => window.__msgs.push(e.data));</script>' })
      : r.fulfill({ contentType: "text/html", body: html }));
    await page.goto("http://ruling.test/host.html");
    await page.evaluate(([k, v]) => localStorage.setItem(k, v), ["ruling-page:" + path, JSON.stringify({ __v: 2, cards: seed, page: {} })]);
    await page.evaluate(src => { const f = document.createElement("iframe"); f.src = src; f.style.cssText = "width:1200px;height:900px"; document.body.appendChild(f); }, path);
    await page.waitForTimeout(700);
    const fr = page.frames().find(f => f.url().endsWith(path));
    const radios = label => fr.evaluate(l => { const f = [...document.querySelectorAll("fieldset.tp-part")].find(x => x.textContent.includes(l));
      return f ? [...f.querySelectorAll("input[type=radio]")].map(i => i.checked) : null; }, label);
    const shown = await radios(threads ? "Sibling branch" : "Part a");
    check(shown && shown.join() === "false,false,true", `${name}: the saved answer of the card that stays is shown (${JSON.stringify(shown)})`);
    await fr.evaluate(l => { const f = [...document.querySelectorAll("fieldset.tp-part")].find(x => x.textContent.includes(l)); f.querySelectorAll("input[type=radio]")[1].click(); }, threads ? "Sibling branch" : "Part b");
    await page.waitForTimeout(300);
    const msgs = (await page.evaluate(() => window.__msgs)).filter(m => m && m.ruling_id === "r1");
    const mine = msgs.filter(m => m.card_id === stays), last = mine[mine.length - 1];
    check(last && same(JSON.parse(last.choice_id), want), `${name}: the changed card posts only the answers of the parts it draws now (${last ? last.choice_id : "no message"} want ${JSON.stringify(want)})`);
    check(msgs.length > 0 && msgs.every(m => !/old-zz|T1r/.test(String(m.choice_id)) && !String(m.text).includes("Refused-two") && m.card_id !== "R1"),
      `${name}: no posted message carries the refused ${threads ? "branch" : "card"}'s answer or a part that is not drawn (${msgs.length} messages)`);
    const copied = await fr.evaluate(() => window.rulingText());
    check(!copied.includes("Refused-two") && copied.includes(threads ? "Beta" : "Gamma"), `${name}: the copied answers do not hold the refused ${threads ? "branch" : "card"}'s answer and show the answer of the part that is drawn`);
    const stored = JSON.parse(await page.evaluate(k => localStorage.getItem(k), "ruling-page:" + path));
    const kept = threads ? stored.cards.T1.a["b:T1r"] === 1 : stored.cards.R1.a._ === 1 && stored.cards.K1.a["p:old-zz"] === 1;
    check(kept && !errors.filter(e => !/no usable picture/.test(e)).length, `${name}: what is stored for a part the page does not draw stays stored (${errors.join(" | ") || "no errors"})`);
    await page.close();
  }
  // 8: the design flag on a thread
  {
    const html = withData("template-threads.html", [{ ...thread([{ id: "T1a", q: "Branch", opts: ABC, pick: 0 }]), design: true }]), errors = [];
    const page = await browser.newPage();
    page.on("pageerror", e => errors.push("pageerror: " + e.message));
    page.on("console", m => { if (m.type() === "error") errors.push(m.text()); });
    await page.route("http://ruling.test/**", r => r.fulfill({ contentType: "text/html", body: html }));
    await page.goto("http://ruling.test/flag-" + rand() + ".html");
    await page.waitForTimeout(500);
    const drawn = await page.evaluate(() => ({ inputs: document.querySelectorAll("#card-T1 fieldset.tp-part input[type=radio]").length, refused: document.querySelectorAll(".tp-refused").length }));
    check(errors.length === 1 && errors[0].includes('"T1"') && /belongs on a branch/.test(errors[0]), `template-threads.html: a thread that carries design: true logs one console error naming it (${errors.join(" | ") || "none"})`);
    check(drawn.inputs === 3 && drawn.refused === 0, `template-threads.html: a thread that carries design: true is still drawn as usual (${JSON.stringify(drawn)})`);
    await page.close();
  }
  // 9: an answered page that holds a refused card
  for (const name of NAMES) {
    const threads = name === "template-threads.html";
    const items = threads
      ? [thread([{ id: "T1r", design: true, q: "Refused branch", opts: RF, pick: 0 }, { id: "T1s", q: "Sibling branch", opts: ABC, pick: 0 }])]
      : [{ id: "K1", title: "Card", q: "Question", opts: ABC, pick: 0 }, { id: "R1", title: "Refused card", design: true, q: "Refused", opts: RF, pick: 0 }];
    const html = withData(name, items).replace(LIVE, 'const STATE = {status: "answered", answered_on: "12 Nov 2026"};\n');
    const page = await browser.newPage();
    page.on("console", m => { /* the refusal's own console error is expected */ });
    await page.route("http://ruling.test/**", r => r.fulfill({ contentType: "text/html", body: html }));
    await page.goto("http://ruling.test/answered-" + rand() + ".html");
    await page.waitForTimeout(500);
    const r = await page.evaluate(() => { const boxes = [...document.querySelectorAll(".tp-refused")], d = document.querySelector("details.tp-old");
      return { n: boxes.length, folded: !!d && boxes.every(b => d.contains(b)) && !d.open }; });
    check(r.n === 1 && r.folded && !(await page.locator(".tp-refused").isVisible()), `${name}: on an answered page the refusal is folded away with the old cards (${JSON.stringify(r)})`);
    await page.close();
  }
}
await browser.close();
if (failures) { console.error(`template.test: ${failures} failure(s)`); process.exit(1); }
console.log("template.test: all passed");
