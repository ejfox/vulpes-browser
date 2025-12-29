# Specifications

## Overview

vulpes follows web standards where practical. This document catalogs the specifications we reference and our level of compliance.

## Core Specifications

### HTML

**WHATWG HTML Living Standard**
- URL: https://html.spec.whatwg.org/
- Our compliance: Tokenization + Tree construction (subset)
- Key sections:
  - [Tokenization](https://html.spec.whatwg.org/multipage/parsing.html#tokenization)
  - [Tree Construction](https://html.spec.whatwg.org/multipage/parsing.html#tree-construction)
  - [Named Character References](https://html.spec.whatwg.org/multipage/named-characters.html)

**What we implement:**
- Full tokenizer (all states)
- Tree construction (common elements)
- Entity decoding

**What we skip:**
- `<template>` element handling
- Custom elements
- Shadow DOM
- Most scripting-related behavior

### CSS

**CSS Syntax Module Level 3**
- URL: https://www.w3.org/TR/css-syntax-3/
- Our compliance: Full tokenization, basic parsing

**CSS Cascading and Inheritance Level 4**
- URL: https://www.w3.org/TR/css-cascade-4/
- Our compliance: Basic cascade, no `@layer`

**Selectors Level 3**
- URL: https://www.w3.org/TR/selectors-3/
- Our compliance: Basic selectors only

**CSS Box Model Module Level 3**
- URL: https://www.w3.org/TR/css-box-3/
- Our compliance: Full box model, no fragmentation

**CSS Values and Units Level 3**
- URL: https://www.w3.org/TR/css-values-3/
- Our compliance: Basic units only (px, em, rem, %)

**CSS Colors Level 4**
- URL: https://www.w3.org/TR/css-color-4/
- Our compliance: hex, rgb(), named colors

### URL

**WHATWG URL Standard**
- URL: https://url.spec.whatwg.org/
- Our compliance: Basic parsing, resolution

**Key sections:**
- [URL Parsing](https://url.spec.whatwg.org/#url-parsing)
- [URL Serialization](https://url.spec.whatwg.org/#url-serializing)

### HTTP

**RFC 9110 - HTTP Semantics**
- URL: https://www.rfc-editor.org/rfc/rfc9110
- Our compliance: GET, HEAD only

**RFC 9112 - HTTP/1.1**
- URL: https://www.rfc-editor.org/rfc/rfc9112
- Our compliance: Basic request/response

### TLS

**RFC 8446 - TLS 1.3**
- URL: https://www.rfc-editor.org/rfc/rfc8446
- Our compliance: Via system libraries

**RFC 5246 - TLS 1.2**
- URL: https://www.rfc-editor.org/rfc/rfc5246
- Our compliance: Via system libraries

### Unicode

**Unicode Standard**
- URL: https://www.unicode.org/versions/latest/
- Our compliance: UTF-8 handling

**UAX #14 - Unicode Line Breaking Algorithm**
- URL: https://unicode.org/reports/tr14/
- Our compliance: Basic implementation

**UAX #29 - Unicode Text Segmentation**
- URL: https://unicode.org/reports/tr29/
- Our compliance: Word boundaries

## Compliance Matrix

| Spec | Status | Notes |
|------|--------|-------|
| HTML Tokenization | Full | All states implemented |
| HTML Tree Construction | Partial | Common elements only |
| CSS Syntax | Full | Tokenizer + basic parser |
| CSS Selectors | Partial | Type, class, ID, attribute |
| CSS Box Model | Full | margin, padding, border |
| CSS Flexbox | None | Not planned |
| CSS Grid | None | Not planned |
| URL Parsing | Full | Basic cases |
| HTTP/1.1 | Partial | GET, HEAD only |
| HTTP/2 | None | Not planned initially |
| TLS 1.2/1.3 | Full | Via system libraries |

## Test Suites

### html5lib

Repository: https://github.com/html5lib/html5lib-tests

Contains:
- Tokenizer tests
- Tree construction tests
- Serialization tests

How we use it:
```bash
# Download test files
git clone https://github.com/html5lib/html5lib-tests tests/html5lib-tests

# Run tests
zig build test-html5lib
```

### CSS Test Suites

W3C CSS Test Suites: https://github.com/nickswalker/csswg-test

We don't aim for full compliance, but useful for specific features.

### WPT (Web Platform Tests)

Repository: https://github.com/nickswalker/nickswalker/nickswalker/nickswalker/nickswalker

Too comprehensive for our scope, but useful reference.

## Specification Reading Tips

1. **HTML spec is excellent** - Pseudocode is directly implementable
2. **CSS specs are modular** - Read only what you need
3. **Use the editor's draft** - More up-to-date than TR versions
4. **Cross-reference** - Specs link to each other

## Quick Reference

### HTML Entities (Most Common)

```
&amp;    → &
&lt;     → <
&gt;     → >
&quot;   → "
&apos;   → '
&nbsp;   → (non-breaking space)
&copy;   → ©
&mdash;  → —
&ndash;  → –
&hellip; → …
```

### CSS Default Values

```css
display: inline;
position: static;
visibility: visible;
color: inherit;
background-color: transparent;
font-size: medium (16px);
font-weight: normal (400);
margin: 0;
padding: 0;
```

### HTTP Status Codes (Relevant)

```
200 OK
301 Moved Permanently
302 Found
304 Not Modified
400 Bad Request
403 Forbidden
404 Not Found
500 Internal Server Error
503 Service Unavailable
```

## See Also

- [tutorials.md](tutorials.md) - Learning resources
- [reference-implementations.md](reference-implementations.md) - Code to study
