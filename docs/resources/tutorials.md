# Tutorials & Learning Resources

## Browser Engineering

### browser.engineering (Essential)

**URL:** https://browser.engineering/

The definitive guide to building a browser from scratch. Written by Web developers at Google, implements a complete browser in Python.

**Why it's great:**
- Progressive complexity
- Explains the "why" not just "how"
- Covers all major components
- Python code is readable

**Chapters:**
1. Downloading Web Pages - HTTP basics
2. Drawing to the Screen - Graphics fundamentals
3. Formatting Text - Text rendering
4. Constructing an HTML Tree - Parsing
5. Laying Out Pages - Layout algorithms
6. Applying Author Styles - CSS cascade
7. Handling Buttons and Links - Interaction
8. Sending Information to Servers - Forms
9. Running Interactive Scripts - (We skip this)
10-16. Advanced topics

### Let's build a browser engine! (Matt Brubeck)

**URL:** https://limpet.net/mbrubeck/2014/08/08/toy-layout-engine-1.html

A series of blog posts building "robinson" in Rust.

**Parts:**
1. Getting Started
2. HTML
3. CSS
4. Style
5. Boxes
6. Block Layout
7. Painting

**Why it's great:**
- Concise and focused
- Rust code (closer to Zig than Python)
- Minimal viable implementation

### Web Browser Engineering (Academic)

**URL:** Various university courses

More theoretical treatment of browser architecture.

## Zig Learning

### Zig Language Reference

**URL:** https://ziglang.org/documentation/master/

Official documentation. Dense but comprehensive.

### Ziglearn

**URL:** https://ziglearn.org/

Friendlier introduction to Zig concepts.

### Zig by Example

**URL:** https://zig-by-example.com/

Quick reference for common patterns.

### Karl Seguin's Blog

Various deep dives into Zig patterns.

## Systems Programming

### Ghostty's Zig Patterns

**URL:** https://mitchellh.com/writing/ghostty-and-useful-zig-patterns

Essential reading for understanding how to build production Zig software.

**Key patterns:**
- Comptime interfaces
- Data table processing
- @Type for dynamic types
- Multi-language integration

### Crafting Interpreters

**URL:** https://craftinginterpreters.com/

Not browser-specific, but excellent for parsing and language implementation. The tokenizer/parser patterns apply directly.

## Typography & Text

### The Elements of Typographic Style (Book)

By Robert Bringhurst. The definitive guide to typography.

### Practical Typography (Web)

**URL:** https://practicaltypography.com/

Web-focused typography principles. Informs our reader mode design.

### Text Rendering Hates You

**URL:** https://faultlore.com/blah/text-hates-you/

The comprehensive guide to why text rendering is hard. Read this before implementing text layout.

### Modern Text Rendering with Linux

**URL:** https://mrandri19.github.io/2019/07/24/modern-text-rendering-linux-overview.html

Linux-focused but explains the full stack (though we're macOS-only).

## macOS Development

### Apple Developer Documentation

**URL:** https://developer.apple.com/documentation/

Official docs for:
- AppKit
- SwiftUI
- Metal
- Core Text

### Metal by Example

**URL:** https://metalbyexample.com/

Introduction to Metal for graphics programming.

### objc.io

**URL:** https://www.objc.io/

High-quality articles on Apple platform development.

## Networking

### HTTP Made Really Easy

**URL:** https://www.jmarshall.com/easy/http/

Simple explanation of HTTP/1.1.

### High Performance Browser Networking

**URL:** https://hpbn.co/

By Ilya Grigorik. Deep dive into browser networking. We implement a fraction of this, but it's good context.

### The Illustrated TLS Connection

**URL:** https://tls.ulfheim.net/

Visual explanation of TLS handshake. Helpful for understanding what our TLS library does.

## Video Resources

### Andreas Kling's YouTube

Browser development livestreams from Ladybird creator.

**URL:** https://www.youtube.com/@awesomekling

### Computerphile

Various videos on web technologies, Unicode, etc.

### Tsoding Daily

Live coding streams often touching systems programming.

## Community Resources

### Hacker News

Good discussions on browser development:
- Search: "browser engine" site:news.ycombinator.com
- Ladybird threads
- Servo threads

### Reddit r/programming

Occasional browser-related discussions.

### Lobsters

Higher signal-to-noise for systems programming topics.

## Books

### "The Browser Hacker's Handbook"

Security-focused but good for understanding browser architecture.

### "High Performance Web Sites" by Steve Souders

Understanding what makes sites slow (and thus what we can skip).

### "Designing Data-Intensive Applications"

Overkill for a browser, but excellent systems thinking.

## Study Path

### Phase 1 Foundation

1. Read browser.engineering chapters 1-5
2. Do the Zig tutorial
3. Read Ghostty Zig Patterns
4. Build a minimal HTTP client

### Phase 2 Parser Development

1. Read WHATWG HTML tokenization section
2. Study html5lib test format
3. Implement tokenizer with tests
4. Read browser.engineering chapter 4-6
5. Implement tree builder

### Phase 3 Layout & Rendering

1. Read CSS Box Model spec
2. Read "Text Rendering Hates You"
3. Study Apple Core Text docs
4. Implement basic layout
5. Read browser.engineering chapters 10+

### Phase 4 Polish

1. Study typography resources
2. Read Metal by Example
3. Implement GPU text rendering
4. Profile and optimize

## See Also

- [specifications.md](specifications.md) - Standards we follow
- [reference-implementations.md](reference-implementations.md) - Code to study
