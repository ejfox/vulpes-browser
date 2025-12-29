# Future Ideas

## Overview

This document captures ideas that are explicitly out of scope for Phases 1-3 but might be interesting later. These are not commitments—they're possibilities to revisit once the core is solid.

## Categorized Ideas

### Reading Experience

#### Readability Extraction
Automatic extraction of main content, removing navigation, ads, sidebars.
- Similar to Firefox Reader View or Readability.js
- Heuristic-based content detection
- Could be default mode

#### Save for Offline
Download and store pages locally.
- SQLite or file-based storage
- Full-text search across saved pages
- Could integrate with org-mode or Obsidian

#### Annotations
Highlight text, add notes to pages.
- Local storage per URL
- Markdown notes
- Export functionality

#### Reading Statistics
Track reading habits.
- Pages read per day/week
- Time spent reading
- Word count completed

#### Text-to-Speech
Read pages aloud.
- System TTS integration
- Keyboard controls (play/pause/skip)
- Speed control

### Navigation & Discovery

#### Bookmarks
Save and organize links.
- Hierarchical folders or tags
- Quick access bar
- Import from browser

#### History Search
Full-text search of browsing history.
- What was that article about X?
- Time-based filtering
- Privacy: local only

#### RSS/Atom Support
Built-in feed reader.
- Auto-discover feeds from pages
- Simple chronological view
- No algorithmic sorting

#### Link Preview
Preview links before following.
- Popup/tooltip with page summary
- Keyboard shortcut to trigger
- Fetch in background

### Integration

#### Clipboard Integration
Smart clipboard handling.
- Copy as Markdown
- Copy as plain text (clean)
- Copy URL with title

#### External Editor
Open page source in editor.
- For debugging HTML issues
- Configurable editor command

#### Open in Full Browser
Quick escape hatch.
- Keyboard shortcut to open in Firefox/Chrome
- For JS-required sites

#### Shell Integration
Use from scripts.
- `vulpes --dump https://...` for plain text
- `vulpes --links https://...` for link extraction
- Pipe-friendly output

### Privacy & Security

#### Tor Support
Browse over Tor network.
- Optional at runtime
- Tor Browser bundle integration
- .onion address support

#### Allowlist Mode
Only allow specific domains.
- Parental controls
- Focus mode (only docs sites)
- Security hardening

#### Request Logging
See what the browser fetches.
- Debug mode showing all requests
- Export for analysis

### Formats

#### Gemini Protocol
Support for gemini:// URLs.
- Simpler than HTTP
- Text-focused protocol
- Growing community

#### Gopher Support
Classic protocol support.
- gopher:// URLs
- Text menu navigation
- Historical interest

#### Markdown Rendering
Render .md files directly.
- Local file support
- GitHub-flavored markdown
- Syntax highlighting

#### Man Page Viewing
`vulpes man:ls` or local files.
- Render man pages beautifully
- Hyperlinks between pages
- Search across man pages

### Developer Features

#### View Source
Show formatted HTML source.
- Syntax highlighting
- Line numbers
- DOM tree view (maybe)

#### Network Inspector
See requests and timing.
- Waterfall view
- Response headers
- Cache status

#### CSS Inspector
See computed styles.
- Click element to inspect
- Show cascade
- Debug why things look wrong

### Performance

#### Aggressive Caching
Cache everything possible.
- Disk cache for responses
- Memory cache for parsed DOM
- Predictive pre-fetching

#### Parallel Fetching
Fetch resources concurrently.
- CSS, images in parallel
- Connection pooling
- Priority hints

### Accessibility

#### Screen Reader Mode
Optimized for screen readers.
- Proper ARIA labels
- Logical reading order
- Skip navigation links

#### High Contrast Mode
Beyond dark/light themes.
- System high contrast integration
- Custom high contrast palettes
- Force colors option

#### Font Scaling
Beyond base font size.
- Zoom entire page
- Minimum font size enforcement
- Line spacing options

### Experimental

#### LLM Summarization
Summarize long articles.
- Local model (llama.cpp)
- API integration (optional)
- Privacy-preserving

#### Content Filtering
Block specific content.
- Ad domains
- Tracking scripts (already blocked by no-JS)
- Custom rules

#### Custom CSS Injection
User stylesheets per site.
- Override site styles
- Force readability
- Dark mode for sites that lack it

#### Vim Mode (Advanced)
Beyond basic navigation.
- Marks
- Macros
- Registers (for URLs)

## Evaluation Criteria

Before implementing any future idea, ask:

1. **Does it serve reading?** Core use case is reading content.
2. **Is it simple?** Can it be implemented cleanly?
3. **Does it add maintenance burden?** Every feature has ongoing cost.
4. **Can it be a separate tool?** Maybe it's better as a companion utility.
5. **Does anyone besides me want it?** Personal tool, but interesting to others.

## Idea Graveyard

Ideas explicitly rejected:

### JavaScript (Light)
"Just basic JS for interactive docs"
- Rejected: Slippery slope, massive complexity
- Alternative: Open in full browser

### Sync Across Devices
"Sync bookmarks/history to cloud"
- Rejected: Privacy concerns, complexity
- Alternative: Export/import files

### Extension System
"Let users add features"
- Rejected: Massive scope creep
- Alternative: Keep it simple, fork if needed

### Multiple Tabs
"Like a real browser"
- Rejected: Adds UI complexity
- Alternative: Multiple windows, or terminal tabs

### Edit Mode
"Edit HTML on the page"
- Rejected: Not a reading feature
- Alternative: Use dev tools in full browser

## Contributing Ideas

This is a personal project, but ideas are welcome:
- Open an issue with the idea
- Explain the use case
- Suggest implementation approach
- Accept that most ideas won't be implemented

## See Also

- [phase-1-hello-web.md](phase-1-hello-web.md) - Current focus
- [../design-philosophy/what-we-wont-build.md](../design-philosophy/what-we-wont-build.md) - Anti-scope
