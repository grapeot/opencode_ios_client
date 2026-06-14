# Broken HTML Degradation

This fixture mixes malformed HTML into Markdown. The renderer and sanitizer must
**not crash the WebView**; the page should degrade gracefully and still show the
sentinel paragraph at the end.

An unclosed div opening tag:

<div class="unfinished"

Some text that follows the broken div.

A span that is never closed:

<span style="color: teal;">teal text with no closing tag

A half-written style block:

<style>
.partial {
  color: red;
  background

More prose appears here even though the style block above was never closed.

A stray closing paragraph tag with no opener:

</p>

Mismatched tags:

<b><i>bold then italic closed in wrong order</b></i>

BROKEN_HTML_FIXTURE_SENTINEL_OK — this normal paragraph should still render
after all of the malformed markup above.
