# Spatial Cards: The HyperCard Vision

## The Metaphor

Traditional browsers: tabs in a strip, linear, cramped.
vulpes: **cards in space**, like a desk covered with research.

This isn't tabs. This is **spatial computing for the web**, inspired by:
- HyperCard's stacks and cards
- Research desks covered with papers
- Memory palaces and spatial thinking
- Apple Vision Pro's infinite canvas (stretch goal)

## Why Spatial?

### Humans Think Spatially

We remember *where* things are. "It was in the top-left of my desk." "The blue book on the second shelf."

Linear tabs destroy this:
```
[Tab 1][Tab 2][Tab 3][Tab 4][Tab 5][Tab 6][Tab 7]...
"Which tab was that article in?" → hunting
```

Spatial cards preserve it:
```
┌─────────┐        ┌─────────┐
│ Research│        │  Code   │
│ Paper   │        │  Docs   │
└─────────┘        └─────────┘

     ┌─────────┐
     │  HN     │
     │ Thread  │
     └─────────┘
           ┌─────────┐
           │Reference│
           └─────────┘
```

"The reference card is bottom-right" → found

### Cards Have Relationships

Group related content spatially:
- Research cluster (papers near each other)
- Documentation cluster (API docs, tutorials)
- Reading cluster (articles for later)

### Less UI, More Content

Cards can be smaller when not focused. You see *context* without *context switching*.

## Card Concepts

### The Card

A card is a browsing context:
- One URL/page
- Its own scroll position
- Its own history
- Position in space

```zig
const Card = struct {
    id: u64,

    // Content
    url: Url,
    document: *Document,
    scroll_y: f32,
    history: History,

    // Spatial
    position: Vec2,    // x, y in canvas space
    size: Vec2,        // width, height
    z_index: u32,      // stacking order

    // State
    loading: bool,
    focused: bool,
    minimized: bool,
};
```

### The Canvas

The infinite 2D space where cards live:

```zig
const Canvas = struct {
    cards: ArrayList(*Card),
    viewport: Viewport,      // What we're looking at
    zoom: f32,              // 0.1 to 2.0

    // Navigation
    focus: ?*Card,          // Currently active card
    selection: []*Card,     // Multi-select for grouping
};

const Viewport = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
};
```

### The Focus

One card is "focused" at a time—full-size, receiving input:

```
Focused view:
┌────────────────────────────────────────────────────────┐
│                                                        │
│                    FOCUSED CARD                        │
│                    (Full content)                      │
│                                                        │
└────────────────────────────────────────────────────────┘
        ┌───┐  ┌───┐  ┌───┐
        │ 2 │  │ 3 │  │ 4 │  ← Other cards (miniatures)
        └───┘  └───┘  └───┘
```

### Overview Mode

`Space` toggles overview—see all cards:

```
Overview:
┌─────────┐  ┌─────────┐  ┌─────────┐
│ Card 1  │  │ Card 2  │  │ Card 3  │
│         │  │         │  │         │
│ [a]     │  │ [s]     │  │ [d]     │
└─────────┘  └─────────┘  └─────────┘

┌─────────┐  ┌─────────┐
│ Card 4  │  │ Card 5  │
│         │  │         │
│ [f]     │  │ [g]     │
└─────────┘  └─────────┘

Type hint to focus card, or use j/k to navigate
```

## Keyboard Navigation

### Card Switching

```
Normal mode:
  gt            Next card (by z-order)
  gT            Previous card
  1gt, 2gt...   Go to card N

  Space         Toggle overview mode

  Ctrl-w c      Close current card
  Ctrl-w o      Close all other cards
  Ctrl-w s      Split (new card with same URL)

Overview mode:
  j/k           Navigate cards
  Enter         Focus selected card
  f             Link hints for cards
  Space/Esc     Exit overview

  d             Close highlighted card
  m             Move card (then j/k/h/l)
  g             Group selected cards
```

### Spatial Movement

```
In overview mode:
  h/j/k/l       Move focus spatially
  H/J/K/L       Move card position

  +/-           Zoom in/out
  0             Reset zoom

  Arrow keys    Pan viewport
  Shift-arrows  Pan faster
```

## Card Layouts

### Auto-Layout

New cards auto-position intelligently:

```zig
fn positionNewCard(canvas: *Canvas, from_card: ?*Card) Vec2 {
    if (from_card) |parent| {
        // Open near parent (following link)
        return findSpaceNear(canvas, parent.position);
    }

    // New card: find open space
    return findOpenSpace(canvas);
}

fn findSpaceNear(canvas: *Canvas, pos: Vec2) Vec2 {
    // Try right, then down, then up, then left
    const offsets = [_]Vec2{
        .{ .x = 320, .y = 0 },    // Right
        .{ .x = 0, .y = 240 },    // Down
        .{ .x = 0, .y = -240 },   // Up
        .{ .x = -320, .y = 0 },   // Left
    };

    for (offsets) |offset| {
        const candidate = pos.add(offset);
        if (!overlapsAnyCard(canvas, candidate)) {
            return candidate;
        }
    }

    // Fallback: stack with offset
    return pos.add(.{ .x = 20, .y = 20 });
}
```

### Manual Arrangement

Drag cards or use keyboard:

```
1. Enter overview (Space)
2. Navigate to card (j/k or hints)
3. Press m to move
4. Use h/j/k/l to position
5. Press Enter to confirm
```

### Snap to Grid (Optional)

```
:set grid on       Enable grid snapping
:set grid 100      100px grid
```

### Groups

Cluster related cards:

```
1. Enter overview
2. Select multiple cards (v to start visual select)
3. Move as group (m)
4. Or: :group "Research" to name the cluster
```

## Visual Design

### Card Appearance

```
Focused:
┌────────────────────────────────────────┐
│░░░░░░░░░░░░ URL + Controls ░░░░░░░░░░░│
│                                        │
│           Page Content                 │
│                                        │
│                                        │
└────────────────────────────────────────┘

Unfocused (in overview):
┌─────────────────────┐
│ Title...            │
│                     │
│ [Preview/Thumbnail] │
│                     │
└─────────────────────┘

Minimized:
┌───────────────┐
│ 📄 Title...  │
└───────────────┘
```

### Relationship Lines (Optional)

Show connections between cards:

```
┌─────────┐         ┌─────────┐
│ Article │─────────│ HN Disc │
│         │         │         │
└─────────┘         └─────────┘
      │
      │  ← "opened from" relationship
      ▼
┌─────────┐
│ Author's│
│  Blog   │
└─────────┘
```

### Focus Animation

Smooth transition when focusing:

```zig
fn focusCard(card: *Card) void {
    // Animate viewport to center on card
    animator.animateTo(viewport, .{
        .x = card.position.x - viewport.width / 2,
        .y = card.position.y - viewport.height / 2,
    });

    // Animate card to full size
    animator.animateTo(card.size, full_size);

    // Dim other cards
    for (cards) |other| {
        if (other != card) {
            animator.animateTo(other.opacity, 0.3);
        }
    }
}
```

## Data-Dense Mode

When you want maximum content:

```
:set density high

┌──────────────────────────────────────────────────────┐
│                    NO CHROME AT ALL                  │
│                                                      │
│  Just content. URL in status line. Everything       │
│  accessible via keyboard.                            │
│                                                      │
├──────────────────────────────────────────────────────┤
│ NORMAL │ example.com │ Card 1/5 │ 42%               │
└──────────────────────────────────────────────────────┘
```

Zero chrome except:
- Content
- Minimal status bar
- Mode indicator

## Vision Pro (Stretch Goal)

On visionOS, spatial becomes *truly* spatial:

```
Physical space:
- Cards float in your environment
- Arrange around your desk
- Glance at a card to preview
- Pinch to focus
- Cards persist in space

Hand tracking:
- Drag cards naturally
- Pinch to create new card
- Two-handed resize

Eye tracking:
- Look at card → highlights
- Look + pinch → focus
- Peripheral preview of nearby cards
```

But the keyboard-first interaction model remains:
- Bluetooth keyboard works
- All shortcuts functional
- Eye/hand is *supplementary*

## Implementation Phases

### Phase 2: Basic Cards

- Multiple cards (like tabs)
- Linear switching (gt/gT)
- Overview mode (Space)
- Close/open operations

### Phase 3: Spatial

- Positioned cards
- Canvas navigation
- Manual arrangement
- Groups

### Phase 4: Polish

- Animations
- Relationship lines
- Thumbnails
- Mini-previews

### Stretch: visionOS

- Spatial positioning
- Hand/eye input
- Environment awareness

## Configuration

```toml
# ~/.config/vulpes/config.toml

[cards]
# Auto-arrange new cards
auto_layout = true
# Grid snapping
grid_enabled = false
grid_size = 50

# Overview
overview_scale = 0.15
show_previews = true
show_relationships = false

[cards.appearance]
# Unfocused card opacity
unfocused_opacity = 0.8
# Card shadows
shadows = true
# Border radius
corner_radius = 8
```

## See Also

- [keyboard-first.md](keyboard-first.md) - Keyboard interaction
- [principles.md](principles.md) - Design principles
- [inspiration/](inspiration/) - HyperCard and spatial UI influences
