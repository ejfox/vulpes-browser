# Text Layout

## Overview

Text layout transforms styled DOM elements into positioned boxes ready for rendering. This is the core of making content readable—proper line breaking, paragraph spacing, and text flow.

## Layout Pipeline

```
Styled DOM
    │
    ▼
┌─────────────────────┐
│   Box Generation    │  ← Elements → Boxes
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│   Block Layout      │  ← Vertical positioning
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│   Inline Layout     │  ← Line breaking, text flow
└─────────────────────┘
    │
    ▼
  Layout Tree
```

## Box Model

Every element generates a box:

```
┌─────────────────────────────────────────────┐
│                   margin                    │
│   ┌─────────────────────────────────────┐   │
│   │              border                 │   │
│   │   ┌─────────────────────────────┐   │   │
│   │   │          padding            │   │   │
│   │   │   ┌─────────────────────┐   │   │   │
│   │   │   │      content        │   │   │   │
│   │   │   │                     │   │   │   │
│   │   │   └─────────────────────┘   │   │   │
│   │   │                             │   │   │
│   │   └─────────────────────────────┘   │   │
│   │                                     │   │
│   └─────────────────────────────────────┘   │
│                                             │
└─────────────────────────────────────────────┘
```

### Box Structure

```zig
const LayoutBox = struct {
    // Position (relative to parent)
    x: f32,
    y: f32,

    // Dimensions
    width: f32,
    height: f32,

    // Box model
    margin: EdgeSizes,
    padding: EdgeSizes,
    border: EdgeSizes,

    // Content
    box_type: BoxType,

    // Tree structure
    children: ArrayList(*LayoutBox),
    parent: ?*LayoutBox,
};

const BoxType = union(enum) {
    block: *Element,
    inline_box: *Element,
    text: TextBox,
    anonymous_block,  // Wrapper for mixed content
};

const TextBox = struct {
    text: []const u8,
    style: ComputedStyle,
    // After layout:
    lines: []TextLine,
};

const TextLine = struct {
    text: []const u8,
    width: f32,
    baseline: f32,
};

const EdgeSizes = struct {
    top: f32 = 0,
    right: f32 = 0,
    bottom: f32 = 0,
    left: f32 = 0,
};
```

## Box Generation

Transform DOM into layout boxes:

```zig
fn generateBoxes(element: *Element, style: ComputedStyle) ?*LayoutBox {
    // Don't generate boxes for display: none
    if (style.display == .none) return null;

    const box = allocator.create(LayoutBox);
    box.* = .{
        .box_type = switch (style.display) {
            .block => .{ .block = element },
            .inline_box => .{ .inline_box = element },
            else => .{ .block = element },
        },
    };

    // Generate child boxes
    for (element.children) |child| {
        switch (child) {
            .element => |el| {
                const child_style = computeStyle(el, style);
                if (generateBoxes(el, child_style)) |child_box| {
                    child_box.parent = box;
                    box.children.append(child_box);
                }
            },
            .text => |text| {
                // Text nodes become text boxes
                const text_box = allocator.create(LayoutBox);
                text_box.* = .{
                    .box_type = .{ .text = .{ .text = text.data, .style = style } },
                };
                box.children.append(text_box);
            },
        }
    }

    return box;
}
```

## Block Layout

Block elements stack vertically:

```zig
fn layoutBlock(box: *LayoutBox, containing_width: f32) void {
    // Calculate width
    box.width = calculateBlockWidth(box, containing_width);

    // Position children and accumulate height
    var y: f32 = box.padding.top;

    for (box.children.items) |child| {
        child.x = box.padding.left + child.margin.left;
        child.y = y + child.margin.top;

        // Layout child (may be block or inline)
        switch (child.box_type) {
            .block => layoutBlock(child, box.width - box.padding.left - box.padding.right),
            .inline_box, .text => {
                // Inline content gets wrapped in anonymous block
                layoutInline(child, box.width - box.padding.left - box.padding.right);
            },
        }

        y = child.y + child.height + child.margin.bottom;
    }

    // Set height (explicit or calculated)
    if (box.style.height) |h| {
        box.height = h;
    } else {
        box.height = y + box.padding.bottom;
    }
}

fn calculateBlockWidth(box: *LayoutBox, containing_width: f32) f32 {
    // CSS width calculation
    // auto margins expand to fill space
    // explicit width is used if set
    // max-width constrains

    const style = box.style;

    if (style.width) |w| {
        return @min(w, style.max_width orelse containing_width);
    }

    // Block elements are full width by default
    return containing_width - box.margin.left - box.margin.right;
}
```

## Inline Layout (Line Breaking)

The hard part: flowing text into lines.

```zig
fn layoutInline(container: *LayoutBox, available_width: f32) void {
    var line_builder = LineBuilder.init(available_width);

    for (container.children.items) |child| {
        switch (child.box_type) {
            .text => |*text_box| {
                layoutText(text_box, &line_builder);
            },
            .inline_box => {
                // Inline elements (like <a>, <b>) flow with text
                layoutInlineElement(child, &line_builder);
            },
        }
    }

    // Finalize last line
    line_builder.finishLine();

    // Set container height from lines
    container.height = line_builder.total_height;
}

const LineBuilder = struct {
    lines: ArrayList(Line),
    current_line: Line,
    available_width: f32,
    total_height: f32,

    const Line = struct {
        boxes: ArrayList(*LayoutBox),
        width: f32,
        height: f32,
        baseline: f32,
    };

    fn addWord(self: *LineBuilder, word: []const u8, style: ComputedStyle) void {
        const word_width = measureText(word, style);

        // Does it fit on current line?
        if (self.current_line.width + word_width > self.available_width) {
            if (self.current_line.boxes.items.len > 0) {
                // Start new line
                self.finishLine();
            }
        }

        // Add to current line
        self.current_line.width += word_width;
        // ... add box reference
    }

    fn finishLine(self: *LineBuilder) void {
        if (self.current_line.boxes.items.len == 0) return;

        // Calculate line height (max of all boxes)
        const line_height = calculateLineHeight(self.current_line);

        // Vertical alignment
        alignBaselines(self.current_line);

        self.total_height += line_height;
        self.lines.append(self.current_line);
        self.current_line = Line.init();
    }
};
```

### Word Breaking

```zig
fn layoutText(text_box: *TextBox, line_builder: *LineBuilder) void {
    const text = text_box.text;
    const style = text_box.style;

    var word_start: usize = 0;
    var i: usize = 0;

    while (i < text.len) {
        const c = text[i];

        if (isWhitespace(c)) {
            if (i > word_start) {
                // Add word
                line_builder.addWord(text[word_start..i], style);
            }

            if (c == '\n') {
                // Hard line break
                line_builder.finishLine();
            } else {
                // Soft space
                line_builder.addSpace(style);
            }

            word_start = i + 1;
        }

        i += 1;
    }

    // Last word
    if (i > word_start) {
        line_builder.addWord(text[word_start..i], style);
    }
}
```

### Unicode-Aware Breaking

For proper international text:

```zig
fn findBreakPoints(text: []const u8) []usize {
    // UAX #14: Unicode Line Breaking Algorithm
    // For simplicity, we break on:
    // - Spaces
    // - After hyphens
    // - Before/after CJK characters

    var breaks = ArrayList(usize).init(allocator);

    var iter = std.unicode.Utf8Iterator.init(text);
    var pos: usize = 0;

    while (iter.nextCodepoint()) |cp| {
        if (isBreakOpportunity(cp)) {
            breaks.append(pos);
        }
        pos += std.unicode.utf8CodepointSequenceLength(cp);
    }

    return breaks.items;
}
```

## Text Measurement

Accurate text measurement is crucial:

```zig
fn measureText(text: []const u8, style: ComputedStyle) f32 {
    const font = fontManager.getFont(style.font_family, style.font_weight, style.font_style);
    const size = style.font_size;

    var width: f32 = 0;

    var iter = std.unicode.Utf8Iterator.init(text);
    while (iter.nextCodepoint()) |cp| {
        const glyph = font.getGlyph(cp);
        width += glyph.advance * size;
    }

    return width;
}

fn measureLineHeight(style: ComputedStyle) f32 {
    const font = fontManager.getFont(style.font_family, style.font_weight, style.font_style);
    const metrics = font.getMetrics(style.font_size);

    if (style.line_height) |lh| {
        return lh * style.font_size;
    }

    return metrics.ascent + metrics.descent + metrics.line_gap;
}
```

## Scrolling

For terminal/GUI scrolling:

```zig
const Viewport = struct {
    x: f32,
    y: f32,
    width: f32,
    height: f32,
    scroll_y: f32,

    pub fn visibleBoxes(self: Viewport, root: *LayoutBox) []*LayoutBox {
        // Return only boxes that intersect viewport
        var visible = ArrayList(*LayoutBox).init(allocator);
        collectVisible(root, self, &visible);
        return visible.items;
    }

    fn collectVisible(box: *LayoutBox, viewport: Viewport, out: *ArrayList(*LayoutBox)) void {
        const box_top = box.absoluteY();
        const box_bottom = box_top + box.height;
        const view_top = viewport.scroll_y;
        const view_bottom = view_top + viewport.height;

        // Check intersection
        if (box_bottom < view_top or box_top > view_bottom) {
            return;  // Not visible
        }

        out.append(box);

        for (box.children.items) |child| {
            collectVisible(child, viewport, out);
        }
    }
};
```

## Link Hit Testing

For keyboard navigation and (future) mouse clicks:

```zig
const HitTestResult = struct {
    box: *LayoutBox,
    link: ?*Element,  // Nearest ancestor <a>
};

fn hitTest(root: *LayoutBox, x: f32, y: f32) ?HitTestResult {
    return hitTestRecursive(root, x, y, null);
}

fn hitTestRecursive(
    box: *LayoutBox,
    x: f32,
    y: f32,
    current_link: ?*Element,
) ?HitTestResult {
    // Update link context
    var link = current_link;
    if (box.box_type == .inline_box or box.box_type == .block) {
        const element = box.element();
        if (std.mem.eql(u8, element.tag_name, "a")) {
            link = element;
        }
    }

    // Check if point is in box
    if (x >= box.x and x < box.x + box.width and
        y >= box.y and y < box.y + box.height)
    {
        // Check children (front to back)
        var i = box.children.items.len;
        while (i > 0) {
            i -= 1;
            if (hitTestRecursive(box.children.items[i], x, y, link)) |result| {
                return result;
            }
        }

        return .{ .box = box, .link = link };
    }

    return null;
}
```

## Performance Considerations

### Incremental Layout

Don't re-layout everything on scroll:

```zig
const LayoutCache = struct {
    root: ?*LayoutBox,
    viewport_width: f32,
    dirty: bool,

    pub fn getLayout(self: *LayoutCache, document: *Document, width: f32) *LayoutBox {
        if (self.root != null and self.viewport_width == width and !self.dirty) {
            return self.root.?;
        }

        // Full relayout
        self.root = layoutDocument(document, width);
        self.viewport_width = width;
        self.dirty = false;

        return self.root.?;
    }

    pub fn invalidate(self: *LayoutCache) void {
        self.dirty = true;
    }
};
```

### Text Measurement Caching

Font metrics are expensive:

```zig
const TextMeasureCache = struct {
    // Key: (text_hash, font_id, size)
    cache: std.HashMap(CacheKey, f32),

    pub fn measure(self: *TextMeasureCache, text: []const u8, font: FontId, size: f32) f32 {
        const key = CacheKey{ .text_hash = hashText(text), .font = font, .size = size };

        if (self.cache.get(key)) |width| {
            return width;
        }

        const width = actuallyMeasure(text, font, size);
        self.cache.put(key, width);
        return width;
    }
};
```

## Terminal-Specific Layout

For vulpes-tui, layout is simpler:

```zig
fn layoutForTerminal(document: *Document, columns: u32) TerminalLayout {
    // Fixed-width characters
    // No sub-pixel positioning
    // Lines map directly to terminal rows

    var lines = ArrayList(TerminalLine).init(allocator);
    var current_line = TerminalLine.init(columns);

    for (document.body.children) |node| {
        layoutNodeToTerminal(node, &lines, &current_line, columns);
    }

    return .{ .lines = lines.items };
}

const TerminalLine = struct {
    chars: []TerminalChar,

    const TerminalChar = struct {
        char: u21,
        style: TerminalStyle,
    };
};
```

## References

- [CSS Visual Formatting Model](https://www.w3.org/TR/CSS22/visuren.html)
- [CSS Box Model](https://www.w3.org/TR/CSS22/box.html)
- [Unicode Line Breaking](https://unicode.org/reports/tr14/)
- [Let's build a browser engine! Part 5](https://limpet.net/mbrubeck/2014/09/08/toy-layout-engine-5-boxes.html)

## See Also

- [rendering.md](rendering.md) - Drawing the layout
- [html-parsing.md](html-parsing.md) - Building the DOM
- [css-parsing.md](css-parsing.md) - Styling elements
