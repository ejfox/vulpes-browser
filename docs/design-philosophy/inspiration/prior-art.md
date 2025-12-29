# Prior Art: Browser Projects

## Overview

Building a browser isn't a new idea. Many projects have attempted it with varying goals and approaches. This document surveys relevant prior art to learn from their successes and mistakes.

## Text-Mode Browsers

### Lynx

**Language:** C
**Status:** Active (since 1992!)
**Lines of Code:** ~250,000

The original text-mode browser. Still maintained, still useful.

**What we learn:**
- Text-only is a valid design choice
- Keyboard navigation is efficient
- 30+ years of edge cases are handled
- Accessibility is built-in

**What we do differently:**
- Modern language (Zig vs C)
- Simpler codebase (fewer legacy features)
- Better Unicode support
- Modern TLS

**Resources:**
- [Lynx Browser](https://lynx.browser.org/)

### w3m

**Language:** C
**Status:** Maintained
**Lines of Code:** ~100,000

Text browser with inline image support (in some terminals) and table rendering.

**What we learn:**
- Tables can work in terminal
- Images are possible (sixel, kitty protocol)
- Vim-like keybindings work well

**What we do differently:**
- Even simpler scope initially
- Modern codebase

### Links / ELinks

**Language:** C
**Status:** Links active, ELinks less maintained
**Lines of Code:** ~150,000

More featureful than Lynx, with better CSS support.

**What we learn:**
- CSS in terminal is possible
- Multiple rendering modes (text, graphics)
- Pull-down menus can work

### Browsh

**Language:** Go
**Status:** Active
**Lines of Code:** ~15,000

Runs Firefox headlessly and converts output to terminal.

**What we learn:**
- Full compatibility via proxy is possible
- But it's a workaround, not a solution
- Performance suffers

**Not our approach:** We want a real engine, not a proxy.

## Minimal GUI Browsers

### surf (suckless)

**Language:** C
**Status:** Active
**Lines of Code:** ~2,000

Minimal browser using WebKit for rendering.

**What we learn:**
- Minimal UI is viable
- WebKit does the heavy lifting
- Keyboard-driven works
- dmenu integration is clever

**What we do differently:**
- Own rendering engine (learning goal)
- Not dependent on WebKit

**Resources:**
- [surf - suckless.org](https://surf.suckless.org/)

### qutebrowser

**Language:** Python
**Status:** Active
**Lines of Code:** ~50,000

Vim-like browser using QtWebEngine (Chromium-based).

**What we learn:**
- Vim keybindings are loved
- Hint mode for links is brilliant
- Configuration via Python works
- Active community around minimal browsers

**What we do differently:**
- Own engine, not Chromium wrapper
- Native performance vs Python

**Resources:**
- [qutebrowser.org](https://www.qutebrowser.org/)

### Vimb

**Language:** C
**Status:** Maintained
**Lines of Code:** ~15,000

Another vim-like browser using WebKit.

**What we learn:**
- Similar lessons to surf/qutebrowser
- Single-window focus works

### NetSurf

**Language:** C
**Status:** Active
**Lines of Code:** ~200,000

Small footprint browser with its own engine. Runs on many platforms including RISC OS.

**What we learn:**
- Own engine is viable for constrained scope
- Portable C works everywhere
- Limited CSS/JS support is okay

**Resources:**
- [netsurf-browser.org](https://www.netsurf-browser.org/)

## From-Scratch Browser Engines

### Servo

**Language:** Rust
**Status:** Active (under Linux Foundation)
**Lines of Code:** ~500,000

Mozilla's experimental browser engine in Rust.

**What we learn:**
- Rust for browsers is viable (but hard)
- Parallel layout is possible
- WebRender for GPU rendering
- Spec compliance is massive work

**Resources:**
- [servo.org](https://servo.org/)

### Ladybird (LibWeb)

**Language:** C++ (→ Swift)
**Status:** Active
**Lines of Code:** ~425,000

See [ladybird.md](ladybird.md) for detailed analysis.

### Kosmonaut

**Language:** Rust
**Status:** Experimental/Learning
**Lines of Code:** ~10,000

Minimal browser engine for learning.

**What we learn:**
- Achievable scope for learning
- Focus on CSS painting
- Good reference for getting started

**Resources:**
- [GitHub - pyfisch/kosmonaut](https://github.com/nickswalker/kosmonaut)

### Robinson

**Language:** Rust
**Status:** Tutorial project
**Lines of Code:** ~2,000

Matt Brubeck's toy browser for learning.

**What we learn:**
- Minimal viable browser is ~2000 lines
- Great tutorial structure
- Simplified CSS/layout is tractable

**Resources:**
- [Let's build a browser engine!](https://limpet.net/mbrubeck/2014/08/08/toy-layout-engine-1.html)

## Zig/Rust Browser Experiments

### Lightpanda

**Language:** Zig
**Status:** Active (as of 2024)

Headless browser in Zig for web scraping.

**What we learn:**
- Zig for browser engines works
- Memory model thoughts (arenas vs borrow checker)
- Modern approach to browser building

**Key insight:**
> "Browser engines and garbage-collected runtimes are classic examples of code that fights the borrow checker in Rust, since you're constantly juggling different memory regions."

**Resources:**
- [Why We Built Lightpanda in Zig](https://lightpanda.io/blog/posts/why-we-built-lightpanda-in-zig)

### rust-minibrowser

**Language:** Rust
**Status:** Learning project
**Lines of Code:** ~6,000

Josh Marinacci's from-scratch browser.

**What we learn:**
- Achievable in ~6000 lines
- minifb for windowing
- font-kit for fonts
- Good reference implementation

**Resources:**
- [Building a Rust Web Browser](https://joshondesign.com/2020/03/10/rust_minibrowser)
- [GitHub](https://github.com/joshmarinacci/rust-minibrowser)

### Naglfar

**Language:** Rust
**Status:** Toy project
**Lines of Code:** ~5,000

Another toy browser for learning.

**Resources:**
- [GitHub - maekawatoshiki/naglfar](https://github.com/maekawatoshiki/naglfar)

## Educational Resources

### browser.engineering

**Type:** Book (free online)
**Language:** Python

Builds a complete browser from scratch in Python, explaining each component.

**Chapters cover:**
1. Downloading pages (HTTP)
2. Drawing to the screen
3. Formatting text
4. Constructing an HTML tree
5. Laying out pages
6. Applying author styles
7. Handling buttons and links
8. Sending data to servers
9. Running interactive scripts
10. Keeping data private
11. Adding visual effects
12. Scheduling and threading
13. Animating and compositing
14. Making content accessible
15. Supporting embedded content
16. Reusing previous computations

**What we learn:**
- Step-by-step browser construction
- Each component explained
- Reference for our implementation

**Resources:**
- [browser.engineering](https://browser.engineering/)

### Web Browser Engineering (Textbook)

More academic treatment of browser internals.

## Comparison Matrix

| Project | Language | Own Engine | JS | CSS | Scope |
|---------|----------|------------|-----|-----|-------|
| vulpes | Zig | Yes | No | Partial | Personal |
| Lynx | C | Yes | No | No | Text |
| surf | C | No (WebKit) | Yes | Yes | Minimal |
| qutebrowser | Python | No (Chromium) | Yes | Yes | Vim-like |
| NetSurf | C | Yes | Partial | Partial | Small footprint |
| Ladybird | C++/Swift | Yes | Yes | Yes | Full |
| Servo | Rust | Yes | Yes | Yes | Experimental |
| Kosmonaut | Rust | Yes | No | Partial | Learning |
| Robinson | Rust | Yes | No | Partial | Tutorial |
| Lightpanda | Zig | Yes | Partial | Partial | Headless |

## Key Lessons Aggregated

1. **Text-only is valid**: Lynx, w3m prove it works
2. **~5-10k lines is achievable**: Robinson, Kosmonaut, Naglfar
3. **Zig works for browsers**: Lightpanda validates the choice
4. **Spec-following helps**: Modern specs are implementable
5. **Skip JS for sanity**: Many projects do fine without it
6. **WebKit/Chromium is easy mode**: surf, qutebrowser take this path
7. **Own engine is hard but educational**: That's why we're doing it

## See Also

- [ghostty.md](ghostty.md) - Ghostty deep dive
- [ladybird.md](ladybird.md) - Ladybird deep dive
- [../../resources/reference-implementations.md](../../resources/reference-implementations.md) - Code to study
