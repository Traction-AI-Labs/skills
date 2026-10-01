// Behavioural test for the call-prep template.
// Needs Node 18+ and Playwright: `npm i --no-save playwright && npx playwright install chromium`.
// Run from the repository root: node plugins/call-prep/scripts/template.test.mjs
//
// Checks that in a sandboxed frame with storage blocked (as in a Claude app artifact) the page renders
// with no script errors, the j key jumps to the next section, and a checkbox still toggles.
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

let chromium;
try { ({ chromium } = await import("playwright")); }
catch { console.error("template.test: Playwright is not installed (npm i --no-save playwright && npx playwright install chromium)"); process.exit(2); }

const here = dirname(fileURLToPath(import.meta.url));
const html = readFileSync(join(here, "..", "skills", "call-prep", "references", "prep-template.html"), "utf8");
let failures = 0;
const check = (ok, msg) => { if (!ok) { failures++; console.error("FAIL " + msg); } else console.log("ok   " + msg); };

const browser = await chromium.launch();
const page = await browser.newPage();
const errors = [];
page.on("pageerror", e => errors.push(e.message));
page.on("console", m => { if (m.type() === "error") errors.push(m.text()); });
await page.setContent(`<iframe id="f" sandbox="allow-scripts" style="width:1200px;height:420px"></iframe>`);
await page.$eval("#f", (f, h) => { f.srcdoc = h; }, html);
await page.waitForTimeout(800);
const fr = page.frames()[1];
check(errors.length === 0, `no script errors with storage blocked (${errors.join(" | ") || "none"})`);
const before = await fr.evaluate(() => scrollY);
// Dispatch inside the frame: keyboard input from the test page does not reach a sandboxed srcdoc frame.
await fr.evaluate(() => document.dispatchEvent(new KeyboardEvent("keydown", { key: "j", bubbles: true })));
await page.waitForTimeout(700);
const after = await fr.evaluate(() => scrollY);
check(after > before, `j jumps to the next section (scrollY ${before} -> ${after})`);
const box = await fr.$("input[type=checkbox]");
check(!!box, "the template has a checkbox");
if (box) { await box.click(); check(await box.isChecked(), "a checkbox toggles with storage blocked"); }
await browser.close();
if (failures) { console.error(`template.test: ${failures} failure(s)`); process.exit(1); }
console.log("template.test: all passed");
