/* verify.mjs
 *
 * Headless verification of the Markdown Web Preview shell using jsdom.
 * It loads preview.html (which pulls in vendor/markdown-it.min.js,
 * vendor/purify.min.js, preview.js) exactly like the WKWebView would, then
 * drives window.renderMarkdown and asserts on the resulting DOM.
 *
 * jsdom is NOT bundled with the deliverable (the iOS app never needs it).
 * Install it in a throwaway temp dir, then point this script at it via the
 * JSDOM_PATH env var:
 *
 *   mkdir -p /tmp/md_vendor_fetch && cd /tmp/md_vendor_fetch && npm install jsdom
 *   cd <this folder> && \
 *     JSDOM_PATH=/tmp/md_vendor_fetch/node_modules/jsdom/lib/api.js node verify.mjs
 *
 * Exit code 0 = all checks passed.
 */
// jsdom is resolved from a path given via JSDOM_PATH env (so the deliverable
// folder needs no node_modules). Falls back to a bare "jsdom" import if the
// package is resolvable normally.
const jsdomSpecifier = process.env.JSDOM_PATH || "jsdom";
const { JSDOM } = await import(jsdomSpecifier);
import { readFileSync } from "node:fs";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));
const htmlPath = join(here, "preview.html");
const html = readFileSync(htmlPath, "utf8");

const results = [];
function check(name, pass, detail) {
  results.push({ name, pass: !!pass, detail: detail || "" });
}

const dom = new JSDOM(html, {
  url: pathToFileURL(htmlPath).href,
  runScripts: "dangerously",
  resources: "usable",
  pretendToBeVisual: true
});

// Wait for all <script src> tags to load and execute.
await new Promise((resolve) => {
  if (dom.window.document.readyState === "complete") return resolve();
  dom.window.addEventListener("load", () => resolve());
  // Safety timeout
  setTimeout(resolve, 4000);
});

const { window } = dom;

// Sanity: vendor globals + entry point present
check("setup: window.markdownit loaded", typeof window.markdownit === "function");
check("setup: window.DOMPurify loaded", !!(window.DOMPurify && window.DOMPurify.sanitize));
check("setup: window.renderMarkdown defined", typeof window.renderMarkdown === "function");

const contentEl = () => window.document.getElementById("content");

// ---- Test 1: plain markdown ----
const plainMd = [
  "# Heading One",
  "",
  "Some **bold** and a [link](https://example.com).",
  "",
  "- item a",
  "- item b",
  "",
  "| Col A | Col B |",
  "|-------|-------|",
  "| 1     | 2     |",
  "",
  "```js",
  "const x = 1;",
  "```"
].join("\n");

window.renderMarkdown({ markdown: plainMd, theme: "dark" });
{
  const c = contentEl();
  const hasH1 = !!c.querySelector("h1");
  const hasList = c.querySelectorAll("ul li").length >= 2;
  const hasTable = !!c.querySelector("table");
  const tableWrapped = !!c.querySelector(".md-table-wrap table");
  const hasCode = !!c.querySelector("pre code");
  const hasLink = !!c.querySelector('a[href="https://example.com"]');
  check(
    "1. plain markdown (h1/list/table/code/link)",
    hasH1 && hasList && hasTable && tableWrapped && hasCode && hasLink,
    `h1=${hasH1} list=${hasList} table=${hasTable} wrapped=${tableWrapped} code=${hasCode} link=${hasLink}`
  );
}

// ---- Test 2: HTML card with <style> ----
const cardMd = [
  "<style>.card{border-radius:12px}</style>",
  "",
  '<div class="card">',
  "  <h3>Card title</h3>",
  "  <p>Card body text.</p>",
  "</div>"
].join("\n");

window.renderMarkdown({ markdown: cardMd, theme: "dark" });
{
  const c = contentEl();
  const card = c.querySelector("div.card");
  const styleTag = c.querySelector("style");
  check(
    "2. HTML card (<style> + div.card) renders",
    !!card && !!styleTag,
    `card=${!!card} styleTag=${!!styleTag}`
  );
}

// ---- Test 3: inline SVG ----
const svgMd = [
  '<svg viewBox="0 0 100 100" width="100" height="100">',
  '  <circle cx="50" cy="50" r="40" fill="#5aa9ff" />',
  '  <path d="M10 10 L90 90" stroke="#fff" stroke-width="2" />',
  "</svg>"
].join("\n");

window.renderMarkdown({ markdown: svgMd, theme: "dark" });
{
  const c = contentEl();
  const svg = c.querySelector("svg");
  const circle = c.querySelector("svg circle");
  const path = c.querySelector("svg path");
  check(
    "3. inline SVG renders (svg/circle/path)",
    !!svg && !!circle && !!path,
    `svg=${!!svg} circle=${!!circle} path=${!!path}`
  );
}

// ---- Test 4: script injection stripped ----
const evilMd = [
  "Hello",
  "",
  "<script>alert(1)</scr" + "ipt>",
  "",
  '<img src="x" onerror="alert(2)">',
  "",
  '<a href="javascript:alert(3)">bad link</a>'
].join("\n");

window.renderMarkdown({ markdown: evilMd, theme: "dark" });
{
  const c = contentEl();
  const innerHTML = c.innerHTML;
  const noScriptTag = c.querySelector("script") === null && !/<script/i.test(innerHTML);
  const img = c.querySelector("img");
  const noOnError = !img || !img.hasAttribute("onerror");
  const a = c.querySelector("a");
  const noJsHref = !a || !/javascript:/i.test(a.getAttribute("href") || "");
  check(
    "4. <script>/onerror/javascript: stripped",
    noScriptTag && noOnError && noJsHref,
    `noScript=${noScriptTag} noOnError=${noOnError} noJsHref=${noJsHref}`
  );
}

// ---- Test 5: dark theme sets data-theme ----
window.renderMarkdown({ markdown: "# Dark", theme: "dark" });
const darkOK = window.document.documentElement.getAttribute("data-theme") === "dark";
window.renderMarkdown({ markdown: "# Light", theme: "light" });
const lightOK = window.document.documentElement.getAttribute("data-theme") === "light";
check(
  "5. theme sets data-theme (dark & light)",
  darkOK && lightOK,
  `dark=${darkOK} light=${lightOK}`
);

// ---- Report ----
let allPass = true;
console.log("\n=== Markdown Web Preview verification ===\n");
for (const r of results) {
  if (!r.pass) allPass = false;
  console.log(`${r.pass ? "PASS" : "FAIL"}  ${r.name}${r.detail ? "   [" + r.detail + "]" : ""}`);
}
console.log(`\n${allPass ? "ALL CHECKS PASSED" : "SOME CHECKS FAILED"}\n`);
process.exit(allPass ? 0 : 1);
