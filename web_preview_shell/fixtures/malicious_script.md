# Security Sanitization Fixture

This document deliberately contains dangerous HTML in its **source**. The
sanitizer (DOMPurify) is responsible for stripping it so that none of it
executes. A UI test should confirm the sentinel text below renders while no
alert fires.

SECURITY_FIXTURE_SENTINEL_OK

An inline script that must be removed:

<script>alert(1)</script>

An image with an `onerror` handler that must not fire:

<img src=x onerror=alert(1)>

A link using a `javascript:` URI that must be neutralized:

<a href="javascript:alert(1)">click</a>

An iframe pointing at an external origin that must be stripped:

<iframe src="https://example.com"></iframe>

This is a normal paragraph after the dangerous elements. If you can read this
sentence and the sentinel above, the page rendered safely.
