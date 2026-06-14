/* preview.js
 *
 * Defines window.renderMarkdown(payload) for the iOS WKWebView "Markdown Web
 * Preview" feature.
 *
 * Pipeline:
 *   payload.markdown (string)
 *     -> markdown-it (html:true, linkify:true)   render to HTML string
 *     -> DOMPurify.sanitize (strict allowlist)
 *     -> set into #content
 *
 * payload shape (parsed JS object, NOT string-concatenated into HTML):
 *   { markdown: string, theme: "dark" | "light" }
 *
 * Vendor globals (loaded before this file):
 *   window.markdownit  (markdown-it 14.x UMD)
 *   window.DOMPurify   (DOMPurify 3.x UMD)
 */
(function () {
  "use strict";

  // ---- markdown-it instance ----
  // html:true lets a safe HTML-in-Markdown subset pass through (DOMPurify is the
  // real gatekeeper). linkify autolinks bare URLs. typographer is optional/cosmetic.
  var md = window.markdownit({
    html: true,
    linkify: true,
    typographer: true,
    breaks: false
  });

  // ---- DOMPurify allowlist ----
  var SANITIZE_CONFIG = {
    ALLOWED_TAGS: [
      // text / block
      "p", "strong", "em", "code", "pre", "blockquote",
      "ul", "ol", "li",
      "h1", "h2", "h3", "h4", "h5", "h6",
      "hr", "br", "a",
      "table", "thead", "tbody", "tr", "th", "td",
      "details", "summary",
      // layout
      "div", "span",
      // images
      "img",
      // inline SVG
      "svg", "path", "rect", "text", "line", "polyline", "polygon",
      "circle", "ellipse", "g", "defs", "marker",
      // gradients are commonly used inside SVG cards
      "linearGradient", "radialGradient", "stop",
      // CAUTION: <style> is allowed so HTML/CSS "cards" render styled.
      // RISK: CSS can still do visual things (e.g. position/overlay, url() that
      // hits no network here, expression() is dead in modern engines). We accept
      // this because card rendering is a product requirement and the content is
      // user/author markdown, not arbitrary remote pages. DOMPurify keeps the
      // *markup* safe; it does NOT fully sandbox CSS. See README/caveats.
      "style"
    ],
    ALLOWED_ATTR: [
      // generic
      "class", "id", "title",
      // links / media
      "href", "src", "alt", "width", "height",
      // svg root
      "viewBox", "xmlns", "preserveAspectRatio",
      // svg geometry / paint
      "d", "cx", "cy", "r", "rx", "ry",
      "x", "y", "x1", "y1", "x2", "y2",
      "points", "transform",
      "fill", "stroke", "stroke-width", "stroke-linecap", "stroke-linejoin",
      "stroke-dasharray", "opacity", "fill-opacity", "stroke-opacity",
      "text-anchor", "font-size", "font-family", "font-weight",
      // gradients
      "offset", "stop-color", "stop-opacity",
      "gradientUnits", "gradientTransform", "spreadMethod",
      "x1", "y1", "x2", "y2",
      // marker / defs refs
      "marker-end", "marker-start", "marker-mid",
      "markerWidth", "markerHeight", "refX", "refY", "orient",
      // details
      "open"
    ],
    // Keep <style> contents intact (DOMPurify otherwise can drop them).
    ADD_TAGS: ["style"],
    // FORCE_BODY makes DOMPurify parse the fragment in <body> context. Without
    // it, a leading <style> is parsed into <head> and silently dropped, so the
    // HTML/CSS card styles would vanish. (DOMPurify still sanitizes the CSS.)
    FORCE_BODY: true,
    // Block dangerous URI schemes everywhere; allow http/https/mailto/data:image
    ALLOWED_URI_REGEXP:
      /^(?:(?:https?|mailto|tel):|data:image\/(?:png|jpeg|gif|webp|svg\+xml);|[^a-z]|[a-z+.-]+(?:[^a-z+.\-:]|$))/i,
    // Defensive: these are stripped by the allowlist anyway, but be explicit.
    FORBID_TAGS: ["script", "iframe", "object", "embed", "form", "input"],
    FORBID_ATTR: ["onerror", "onload", "onclick"],
    // We keep inline SVG; DOMPurify's default profile already handles SVG safely.
    USE_PROFILES: { html: true, svg: true, svgFilters: false }
  };

  // Extra defense: drop any attribute starting with "on" (event handlers) and
  // any href/src that resolves to a javascript: scheme, regardless of casing or
  // whitespace tricks. DOMPurify already does this, but the hook makes intent
  // explicit and survives config drift.
  if (window.DOMPurify && typeof window.DOMPurify.addHook === "function") {
    window.DOMPurify.addHook("uponSanitizeAttribute", function (_node, data) {
      var name = (data.attrName || "").toLowerCase();
      if (name.indexOf("on") === 0) {
        data.keepAttr = false;
        return;
      }
      if (name === "href" || name === "src" || name === "xlink:href") {
        var val = (data.attrValue || "").replace(/\s+/g, "").toLowerCase();
        if (val.indexOf("javascript:") === 0 || val.indexOf("vbscript:") === 0) {
          data.keepAttr = false;
        }
      }
    });
  }

  function getContentEl() {
    return document.getElementById("content");
  }

  function applyTheme(theme) {
    var t = theme === "light" ? "light" : "dark"; // default dark
    var root = document.documentElement;
    root.setAttribute("data-theme", t);
    if (document.body) {
      document.body.setAttribute("data-theme", t);
    }
    return t;
  }

  // Wrap every <table> in a horizontally-scrollable container so wide tables
  // don't blow out the narrow phone layout.
  function wrapTables(container) {
    var tables = container.querySelectorAll("table");
    for (var i = 0; i < tables.length; i++) {
      var table = tables[i];
      if (table.parentNode && table.parentNode.classList &&
          table.parentNode.classList.contains("md-table-wrap")) {
        continue;
      }
      var wrap = document.createElement("div");
      wrap.className = "md-table-wrap";
      table.parentNode.insertBefore(wrap, table);
      wrap.appendChild(table);
    }
  }

  // Bridge clicks on <a>/<img> to the native Swift handler if present.
  // In a plain browser (verification) the handler won't exist, so we guard.
  function hasBridge() {
    return !!(window.webkit &&
              window.webkit.messageHandlers &&
              window.webkit.messageHandlers.previewBridge &&
              typeof window.webkit.messageHandlers.previewBridge.postMessage === "function");
  }

  function postToBridge(msg) {
    if (hasBridge()) {
      window.webkit.messageHandlers.previewBridge.postMessage(msg);
    }
  }

  function installClickBridge(container) {
    container.addEventListener("click", function (ev) {
      var node = ev.target;
      // walk up to nearest <a> or <img>
      while (node && node !== container) {
        var tag = node.tagName ? node.tagName.toLowerCase() : "";
        if (tag === "a") {
          var href = node.getAttribute("href") || "";
          // Let in-page anchors (#...) behave natively.
          if (href.charAt(0) !== "#") {
            ev.preventDefault();
            postToBridge({ type: "link", href: href });
          }
          return;
        }
        if (tag === "img") {
          ev.preventDefault();
          postToBridge({ type: "image", src: node.getAttribute("src") || "" });
          return;
        }
        node = node.parentNode;
      }
    }, false);
  }

  var bridgeInstalled = false;

  /**
   * window.renderMarkdown(payload)
   * @param {{markdown: string, theme: ("dark"|"light")}} payload
   */
  function renderMarkdown(payload) {
    var content = getContentEl();
    if (!content) {
      // Nothing we can do; surface to console for native debugging.
      if (window.console) console.error("renderMarkdown: #content not found");
      return;
    }

    try {
      payload = payload || {};
      applyTheme(payload.theme);

      var markdown = typeof payload.markdown === "string" ? payload.markdown : "";

      // markdown -> raw HTML
      var rawHtml = md.render(markdown);

      // raw HTML -> sanitized HTML (strict allowlist)
      var clean = window.DOMPurify.sanitize(rawHtml, SANITIZE_CONFIG);

      content.innerHTML = clean;

      wrapTables(content);

      if (!bridgeInstalled) {
        installClickBridge(content);
        bridgeInstalled = true;
      }
    } catch (err) {
      // Never leave a blank page: show a readable error.
      var msg = (err && err.message) ? err.message : String(err);
      var box = document.createElement("div");
      box.className = "preview-error";
      box.textContent = "Preview render error:\n" + msg;
      content.innerHTML = "";
      content.appendChild(box);
      if (window.console) console.error("renderMarkdown failed:", err);
    }
  }

  window.renderMarkdown = renderMarkdown;
})();
