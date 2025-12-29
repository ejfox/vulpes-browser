# Ladybird: Design Inspiration

## Overview

[Ladybird](https://ladybird.dev) is a from-scratch web browser by Andreas Kling, originally developed as part of SerenityOS. It proves that building a new browser engine is still possible in 2024, and provides valuable lessons for vulpes.

## Key Takeaways for vulpes

### 1. Following Web Standards

> "The ECMAScript, HTML, and CSS specifications today are (for the most part) stellar technical documents whose algorithms can be implemented with considerably less effort and guesswork than in the past."

Modern web specs are actually good documentation. The WHATWG HTML spec includes pseudocode-like algorithms:

```
// From HTML spec - parsing algorithm
1. Let token be the current token
2. If token is a start tag whose name is "html"
3. Process the token using the rules for "in body"
4. ...
```

**vulpes application:**
- Use specs as primary documentation
- Name our functions/states after spec terminology
- New contributors can cross-reference

**Key specs:**
- [WHATWG HTML](https://html.spec.whatwg.org/) - HTML parsing
- [WHATWG URL](https://url.spec.whatwg.org/) - URL parsing
- [W3C CSS](https://www.w3.org/Style/CSS/) - CSS parsing
- [WHATWG Fetch](https://fetch.spec.whatwg.org/) - Networking

### 2. Correctness Before Optimization

> "We are currently not putting much effort into optimizing Ladybird for performance. Instead, our primary focus is on addressing issues related to correctness and compatibility."

**Order of operations:**
1. Make it work (correct)
2. Make it work on real sites (compatible)
3. Make it fast (optimize)

**vulpes application:**
- Don't optimize until profiled
- A slow correct parser beats a fast broken one
- "Premature optimization is the root of all evil"

### 3. Lean Codebase

Ladybird: ~425,000 lines of C++
Chromium: ~35,000,000 lines

That's 82x smaller. Yes, Ladybird does less, but it demonstrates that intentional scope creates maintainable codebases.

**vulpes target:**
- Phase 1 (text browser): ~5,000-10,000 lines
- Phase 2 (usable): ~20,000-30,000 lines
- Phase 3 (polished): ~50,000 lines

If we exceed these, something's wrong.

### 4. Multi-Process Architecture

Ladybird uses process isolation:
- Main UI process
- WebContent renderer processes (per tab)
- ImageDecoder process
- RequestServer process

**vulpes application:**
- For terminal UI: single process is fine
- For GUI: consider process-per-page for crash isolation
- Network in separate process for sandboxing

### 5. Self-Reliance Culture

> "They avoid 3rd party dependencies and build everything themselves—in part because it's fun, but also because it creates total accountability."

This is extreme, but the principle is sound: understand your dependencies.

**vulpes balance:**
- Build: HTML/CSS parsing, layout, text rendering
- Use: System TLS, system fonts, standard networking
- Avoid: Massive frameworks, WebKit/Gecko, Electron

### 6. Language Evolution

Ladybird started in C++ (from SerenityOS), now transitioning to Swift for memory safety.

**vulpes approach:**
- Zig for core (memory safety without borrow checker fights)
- Swift for macOS GUI (native, safe)
- Zig for Linux GUI (GTK bindings)

### 7. No Monetization Pressure

> "They're not monetizing users in any way—no default search deals, no cryptocurrencies or monetizing user data, just sponsorships and donations."

**vulpes reality:**
- Personal project = zero monetization pressure
- Build what's useful, not what's profitable
- No dark patterns, no upsells

### 8. Accessible to New Developers

> "Our hope is to make the Ladybird development experience so accessible to new developers that anybody can become a browser developer."

**vulpes application:**
- Clear documentation (you're reading it)
- Spec-aligned code (one architecture to learn)
- Incremental complexity (start with text-only)

## What Ladybird Does That We Won't

### Full Web Compatibility
Ladybird aims to run "the whole web." We aim to run our curated subset.

### JavaScript Engine
Ladybird has LibJS. We skip JavaScript entirely.

### Multi-Tab/Multi-Window
Ladybird is a full browser. vulpes-tui shows one page at a time.

### Process-Per-Tab
Overkill for a terminal browser.

### All CSS Features
Ladybird implements full CSS. We implement readable subset.

## What Ladybird Does That We Should Copy

### Spec-First Implementation
Read the spec, implement the spec.

### Incremental Compatibility
Start with simple pages, expand support iteratively.

### Clear Separation
LibWeb (engine) vs browser UI is clean.

### Test Against Real Sites
Not just spec compliance tests, actual websites.

## Ladybird Resources

### Primary Sources
- [Ladybird Official Site](https://ladybird.dev)
- [Announcement Post](https://awesomekling.github.io/Ladybird-a-new-cross-platform-browser-project/)
- [How We're Building the "Impossible"](https://awesomekling.substack.com/p/how-were-building-a-browser-when)

### Videos
- Andreas Kling's YouTube channel (search "Ladybird browser")
- State of the Browser talks

### Code
- [GitHub - LadybirdBrowser/ladybird](https://github.com/LadybirdBrowser/ladybird)

## Ladybird vs vulpes Comparison

| Aspect | Ladybird | vulpes |
|--------|----------|--------|
| Goal | Full web browser | Personal reading tool |
| JavaScript | Full engine (LibJS) | None |
| CSS | Full support | Readable subset |
| Target | General public | Just us |
| Size | ~425k lines | ~20k lines target |
| Language | C++ → Swift | Zig |
| Team | Funded project | Solo/small |

## See Also

- [ghostty.md](ghostty.md) - Ghostty inspiration
- [prior-art.md](prior-art.md) - Other browser projects
- [../principles.md](../principles.md) - Our principles
