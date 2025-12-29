# What We Won't Build

## The Importance of Anti-Scope

Defining what we *won't* build is as important as defining what we will. This document is our explicit anti-scope—a commitment to say "no" so we can say "yes" to what matters.

> "People think focus means saying yes to the thing you've got to focus on. But that's not what it means at all. It means saying no to the hundred other good ideas." — Steve Jobs

## Definite No's

### JavaScript Engine

**Status:** Will never implement

**Rationale:**
- JavaScript engines are decades of work (V8, SpiderMonkey, JavaScriptCore)
- Most JavaScript on the web is hostile to users (tracking, ads, anti-features)
- Pages that require JavaScript usually work better in a full browser
- Our target content (docs, blogs, articles) largely works without JS

**What this means:**
- No script execution
- `<script>` tags are ignored
- Event handlers (`onclick`, etc.) do nothing
- JSON in script tags can be extracted for structured data

**Exception consideration:** If we ever want scripting, we'd embed Lua or a minimal language—not implement ECMAScript.

### WebAssembly

**Status:** Will never implement

**Rationale:**
- Requires JavaScript to be useful in browsers
- Complex runtime requirements
- Zero benefit for reading-focused use case

### Video/Audio Playback

**Status:** Will never implement natively

**Rationale:**
- Codec licensing complexity
- Massive scope creep
- Not needed for text-focused browsing

**Alternative:** Detect media and offer to open in system player (`mpv`, QuickTime, etc.)

### WebGL/WebGPU

**Status:** Will never implement

**Rationale:**
- Requires JavaScript
- Massive attack surface
- Zero use for document viewing

### Service Workers / PWAs

**Status:** Will never implement

**Rationale:**
- Requires JavaScript
- Complex offline/caching semantics
- We're a browser, not an app platform

### Web Components / Shadow DOM

**Status:** Will never implement

**Rationale:**
- Requires JavaScript
- Adds complexity for minimal benefit
- Regular HTML elements are fine

### WebRTC

**Status:** Will never implement

**Rationale:**
- Requires JavaScript
- Complex P2P networking
- Not document-related

### WebSockets

**Status:** Will never implement

**Rationale:**
- Requires JavaScript to be useful
- Persistent connections don't fit our model
- Pages load, display, done

### IndexedDB / Web Storage

**Status:** Will never implement

**Rationale:**
- Requires JavaScript
- We don't need client-side storage
- Privacy benefit of not storing anything

### Cookies

**Status:** Won't implement initially, might add basic session cookies later

**Rationale:**
- Most cookies are tracking-related
- Complicates privacy model
- Many sites work without them

**Possible future:** Read-only cookies for authenticated sites (GitHub, etc.) imported from another browser.

### CSS Grid

**Status:** Won't implement (initially)

**Rationale:**
- Complex layout algorithm
- Most grid layouts degrade gracefully
- Block/inline flow covers 90% of cases

**Possible future:** Simple grid support if we find too many sites break without it.

### CSS Flexbox

**Status:** Won't implement (initially)

**Rationale:**
- Same reasoning as Grid
- Flow layout handles most cases

### CSS Animations / Transitions

**Status:** Won't implement

**Rationale:**
- Adds complexity
- No benefit for reading
- Often used for annoying effects

### Custom Fonts (@font-face)

**Status:** Won't implement (initially)

**Rationale:**
- Network requests for fonts slow pages
- System fonts are readable
- Reduces fingerprinting surface

**Possible future:** Opt-in font loading for specific sites.

### SVG (complex)

**Status:** Partial support only

**Rationale:**
- Full SVG is enormously complex
- Simple paths/shapes: yes
- Filters, animations, scripting: no

### Canvas

**Status:** Won't implement

**Rationale:**
- Requires JavaScript
- Primarily for apps, not documents

### Web Forms (complex)

**Status:** Basic support only

**Rationale:**
- Text inputs: yes
- Submit buttons: yes
- File uploads: maybe later
- Complex validation: no (server-side is fine)

### Print Stylesheet Support

**Status:** Won't implement

**Rationale:**
- Terminal output doesn't print
- For GUI, system print dialog handles it
- Scope creep

### Accessibility APIs (full)

**Status:** Partial

**Rationale:**
- Terminal is inherently screen-reader compatible
- We output semantic structure
- Full ARIA support is massive scope

**What we will do:**
- Proper heading hierarchy
- Alt text for images (when we support images)
- Semantic HTML structure
- High contrast support

## Probably No's (Revisit If Needed)

### Images

**Status:** Off by default, possible opt-in later

**Rationale:**
- Increases page weight significantly
- Many images are tracking pixels or ads
- Alt text often sufficient

**Possible future:** `vulpes --images https://example.com`

### Tables (complex)

**Status:** Basic only

**Rationale:**
- Simple data tables: yes
- Nested tables, layout tables: no
- Most modern sites don't use table layout

### iframes

**Status:** Probably no

**Rationale:**
- Often used for ads
- Cross-origin complexity
- Can degrade to link

**Possible future:** Same-origin iframes for documentation sites.

### HTTP/2, HTTP/3

**Status:** HTTP/1.1 initially, HTTP/2 possibly later

**Rationale:**
- HTTP/1.1 is simpler and sufficient
- Most servers support HTTP/1.1
- HTTP/2 benefits mainly for many parallel requests (which we don't make)

### Redirects (complex chains)

**Status:** Limited

**Rationale:**
- 3-5 redirects: yes
- 10+ redirect chains: suspicious, abort

### Form POST

**Status:** Maybe later

**Rationale:**
- GET requests cover many use cases
- POST requires careful handling
- Authentication flows need this

## Scope Creep Warning Signs

If you find yourself thinking any of these, stop:

- "It would be cool if..."
- "Modern browsers do..."
- "It's only a few hundred lines..."
- "We're already most of the way there..."
- "Users might want..."

Before adding anything, ask:
1. Does this serve reading-focused browsing?
2. What's the maintenance burden?
3. Does this complicate the architecture?
4. Can the user just open Firefox instead?

## The Feature Addition Process

For something to move from "no" to "yes":

1. **Demonstrated need**: Not theoretical, actual pages we use
2. **Bounded scope**: Clear implementation boundary
3. **Graceful degradation**: Works without it, better with it
4. **No downstream complexity**: Doesn't require other features
5. **Written justification**: Document why in this file

## See Also

- [principles.md](principles.md) - Core design principles
- [../roadmap/](../roadmap/) - What we *are* building
