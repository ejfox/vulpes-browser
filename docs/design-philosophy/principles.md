# Design Principles

## Core Philosophy

vulpes-browser is built on a fundamental belief: **the web has become hostile to readers**, and we can build something better for ourselves.

This is not about building a browser for everyone. It's about building a browser for *us*—people who value focus, speed, and intentionality over compatibility with every JavaScript framework and ad tracker.

## The Three Pillars

### 1. Intentionality Over Universality

Every feature must justify its existence. We don't implement something because "that's how browsers work." We implement it because it serves our actual use cases.

**Examples:**
- We support links because navigation is essential
- We support basic CSS because readability matters
- We don't support JavaScript because most pages work better without it
- We don't support cookies (initially) because we don't need persistent sessions

**Anti-pattern:** "Chrome does this, so we should too."

**Our pattern:** "Does this serve how *we* use the web?"

### 2. Correctness Before Performance

From Ladybird's philosophy:
> "We are currently not putting much effort into optimizing Ladybird for performance. Instead, our primary focus is on addressing issues related to correctness and compatibility."

A slow browser that works correctly is better than a fast browser that renders garbage. Performance comes from good architecture, not premature optimization.

**Order of priorities:**
1. Does it work? (correctness)
2. Does it work for the pages I actually visit? (compatibility)
3. Is it fast? (performance)
4. Is it beautiful? (polish)

### 3. Native Means Native

From Ghostty:
> "Fast, features, native feel is not mutually exclusive."

We don't use Electron. We don't use cross-platform UI frameworks that look the same everywhere (read: bad everywhere). When we build a GUI, it will be:
- Swift/AppKit on macOS
- GTK4 or native Wayland on Linux
- Platform-specific GPU APIs (Metal, Vulkan)

The terminal UI is our exception—terminals are inherently cross-platform.

## Specific Principles

### Simplicity Is Not Minimalism for Its Own Sake

surf (suckless browser) is ~2000 lines but uses WebKit for rendering. That's elegant—using the right tool for the job.

We're building our own renderer because:
1. Learning how browsers work is the goal
2. We want total control over the reading experience
3. WebKit/Gecko carry features we'll never use

But we won't avoid dependencies religiously. We'll use:
- System TLS libraries (no reimplementing crypto)
- System font libraries (fonts are hard)
- Standard networking (no reinventing TCP)

### The 80/20 Rule, Ruthlessly Applied

80% of our browsing happens on 20% of site types:
- Documentation sites
- Blogs and articles
- News sites
- GitHub/GitLab
- Wikipedia
- Hacker News

We optimize for *these*. If Twitter doesn't work, that's a feature.

### Fail Gracefully, Show Everything

A broken page should still show its content. If CSS parsing fails, show unstyled HTML. If a tag is unknown, show its text content. Never show a blank page when there's content to display.

```
┌─────────────────────────────────────────────┐
│ Best case: Fully styled, beautiful layout   │
├─────────────────────────────────────────────┤
│ Good: Readable text with basic formatting   │
├─────────────────────────────────────────────┤
│ Acceptable: Plain text, still readable      │
├─────────────────────────────────────────────┤
│ NEVER: Blank page or error message          │
└─────────────────────────────────────────────┘
```

### Reader Mode Is the Default Mode

Most browsers hide "reader mode" behind a button. For us, reader mode *is* the browser. Clean typography, focused content, no distractions.

If someone wants the full web experience, they can use Firefox.

### Speed Through Omission

The fastest code is code that doesn't run. We're fast not because we optimized everything, but because we don't do most things:

| Thing We Skip | Time Saved |
|---------------|------------|
| JavaScript execution | 100-5000ms |
| Ad/tracker requests | 500-2000ms |
| Web font loading | 200-500ms |
| Video/audio parsing | 50-200ms |
| Complex CSS (grid, flexbox) | 10-50ms |

### Security Through Simplicity

No JavaScript = no XSS
No cookies = no session hijacking
HTTPS only = no MITM
No plugins = no plugin vulnerabilities

We're not "security hardened"—we simply don't have most attack surface.

### Configuration Is Not Customization

We provide configuration for things that legitimately vary:
- Font size (accessibility)
- Color scheme (preference/accessibility)
- Keyboard bindings (workflow)
- Allowed hosts (security)

We don't provide configuration for:
- CSS support (it's either on or off)
- "Compatibility mode" (no hidden complexity)
- Feature flags (features are either done or not)

## What We Learn From Our Inspirations

### From Ghostty

- **libghostty pattern**: Separate core from UI
- **Comptime everything**: No runtime overhead for platform differences
- **Native is non-negotiable**: Platform-specific code where it matters
- **"70% font rendering"**: Respect that text rendering is hard and important

### From Ladybird

- **Follow the specs**: Modern web specs are actually good documentation
- **Accountability**: Own your dependencies (or lack thereof)
- **Correctness first**: Get it right, then get it fast
- **Fresh perspective**: Sometimes starting over is the right choice

### From surf/suckless

- **Minimal viable surface**: Do one thing well
- **Keyboard-driven**: Reduce cognitive load
- **Configuration via source**: If it doesn't change often, compile it in

### From Lynx

- **Text is primary**: The web is, at its core, documents
- **Speed is respect**: Respecting the user's time
- **Accessibility built-in**: Text-first is inherently accessible

## The Anti-Patterns We Reject

### "We Need Feature Parity"

No. We need features that serve our use cases.

### "Users Expect..."

We are the users. We know what we expect.

### "What About Edge Cases?"

Edge cases for our 20% of sites matter. Edge cases for the other 80% don't.

### "Industry Best Practices"

Industry best practices got us a web where simple articles require 10MB of JavaScript. We're trying something different.

### "Future-Proofing"

Build for today. Refactor when tomorrow arrives.

## See Also

- [what-we-wont-build.md](what-we-wont-build.md) - Explicit anti-scope
- [inspiration/ghostty.md](inspiration/ghostty.md) - Ghostty deep dive
- [inspiration/ladybird.md](inspiration/ladybird.md) - Ladybird deep dive
- [../roadmap/](../roadmap/) - How we'll build this incrementally
