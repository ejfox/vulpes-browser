# HTML Parsing

## Overview

HTML parsing transforms raw bytes into a structured Document Object Model (DOM). This document covers our approach to parsing, which balances spec compliance with pragmatic simplicity.

## The WHATWG HTML Standard

The [WHATWG HTML Living Standard](https://html.spec.whatwg.org/multipage/parsing.html) defines the canonical parsing algorithm. Modern browsers follow this spec closely.

Key insight from Ladybird:
> "The specifications today are stellar technical documents whose algorithms can be implemented with considerably less effort and guesswork than in the past."

## Parsing Pipeline

```
Raw Bytes
    │
    ▼
┌─────────────────────┐
│  Encoding Detection │  ← UTF-8, UTF-16, etc.
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│     Tokenizer       │  ← Bytes → Tokens
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│   Tree Builder      │  ← Tokens → DOM Tree
└─────────────────────┘
    │
    ▼
  Document
```

## Phase 1: Naive Text Extraction

For the initial prototype, we skip proper parsing:

```zig
pub fn extractText(html: []const u8) ExtractResult {
    var result = ExtractResult.init(allocator);
    var in_tag = false;
    var in_script = false;
    var in_style = false;

    var i: usize = 0;
    while (i < html.len) : (i += 1) {
        const c = html[i];

        if (c == '<') {
            in_tag = true;
            // Check for script/style
            if (startsWithIgnoreCase(html[i..], "<script")) in_script = true;
            if (startsWithIgnoreCase(html[i..], "<style")) in_style = true;
            if (startsWithIgnoreCase(html[i..], "</script")) in_script = false;
            if (startsWithIgnoreCase(html[i..], "</style")) in_style = false;
            continue;
        }

        if (c == '>') {
            in_tag = false;
            continue;
        }

        if (!in_tag and !in_script and !in_style) {
            result.appendChar(c);
        }
    }

    return result;
}
```

**Limitations:**
- Doesn't build DOM tree
- Can't handle malformed HTML
- No entity decoding
- No link extraction

**Good enough for:** example.com, simple pages

## Phase 2: Proper Tokenizer

### Tokenizer States

The HTML tokenizer is a state machine. Key states:

```zig
const State = enum {
    data,                    // Normal text
    tag_open,                // Saw '<'
    end_tag_open,            // Saw '</'
    tag_name,                // Reading tag name
    self_closing_start_tag,  // Saw '/' in tag
    before_attribute_name,   // Space after tag name
    attribute_name,          // Reading attribute name
    after_attribute_name,    // After attribute name
    before_attribute_value,  // Saw '='
    attribute_value_double_quoted,
    attribute_value_single_quoted,
    attribute_value_unquoted,
    bogus_comment,          // Malformed comment
    markup_declaration_open, // Saw '<!'
    comment_start,
    comment,
    comment_end,
    doctype,
    // ... more states
};
```

### Token Types

```zig
const Token = union(enum) {
    doctype: Doctype,
    start_tag: StartTag,
    end_tag: EndTag,
    comment: []const u8,
    character: u21,  // Unicode codepoint
    eof,

    const Doctype = struct {
        name: ?[]const u8,
        public_id: ?[]const u8,
        system_id: ?[]const u8,
        force_quirks: bool,
    };

    const StartTag = struct {
        name: []const u8,
        attributes: []Attribute,
        self_closing: bool,
    };

    const EndTag = struct {
        name: []const u8,
    };

    const Attribute = struct {
        name: []const u8,
        value: []const u8,
    };
};
```

### Tokenizer Implementation

```zig
pub const Tokenizer = struct {
    input: []const u8,
    pos: usize,
    state: State,
    return_state: State,  // For nested states
    current_token: ?Token,
    temp_buffer: ArrayList(u8),

    pub fn init(allocator: Allocator, html: []const u8) Tokenizer {
        return .{
            .input = html,
            .pos = 0,
            .state = .data,
            .return_state = .data,
            .current_token = null,
            .temp_buffer = ArrayList(u8).init(allocator),
        };
    }

    pub fn next(self: *Tokenizer) ?Token {
        while (self.pos < self.input.len) {
            const c = self.consume();

            switch (self.state) {
                .data => {
                    if (c == '<') {
                        self.state = .tag_open;
                    } else if (c == '&') {
                        self.return_state = .data;
                        self.state = .character_reference;
                    } else {
                        return .{ .character = c };
                    }
                },
                .tag_open => {
                    if (c == '!') {
                        self.state = .markup_declaration_open;
                    } else if (c == '/') {
                        self.state = .end_tag_open;
                    } else if (isAsciiAlpha(c)) {
                        self.current_token = .{ .start_tag = .{} };
                        self.reconsume(.tag_name);
                    } else {
                        // Parse error, emit '<' as character
                        self.reconsume(.data);
                        return .{ .character = '<' };
                    }
                },
                // ... many more states
            }
        }

        return .eof;
    }

    fn consume(self: *Tokenizer) u8 {
        const c = self.input[self.pos];
        self.pos += 1;
        return c;
    }

    fn reconsume(self: *Tokenizer, new_state: State) void {
        self.pos -= 1;
        self.state = new_state;
    }
};
```

### Character References (Entities)

HTML entities like `&amp;`, `&lt;`, `&#65;`:

```zig
// Build at comptime from entity list
const named_entities = comptime blk: {
    // From https://html.spec.whatwg.org/entities.json
    var map = std.StringHashMap([]const u21).init();
    map.put("amp", &[_]u21{'&'});
    map.put("lt", &[_]u21{'<'});
    map.put("gt", &[_]u21{'>'});
    map.put("quot", &[_]u21{'"'});
    map.put("nbsp", &[_]u21{0xA0});
    // ... 2000+ more
    break :blk map;
};

fn decodeCharacterReference(input: []const u8) ?[]const u21 {
    if (input[0] == '#') {
        // Numeric reference
        if (input[1] == 'x' or input[1] == 'X') {
            // Hex: &#x41; → 'A'
            const code = std.fmt.parseInt(u21, input[2..], 16) catch return null;
            return &[_]u21{code};
        } else {
            // Decimal: &#65; → 'A'
            const code = std.fmt.parseInt(u21, input[1..], 10) catch return null;
            return &[_]u21{code};
        }
    } else {
        // Named: &amp; → '&'
        return named_entities.get(input);
    }
}
```

## Phase 2: Tree Construction

### DOM Node Types

```zig
const Node = union(enum) {
    document: *Document,
    doctype: *DocumentType,
    element: *Element,
    text: *Text,
    comment: *Comment,
};

const Document = struct {
    children: ArrayList(Node),
    doctype: ?*DocumentType,
    // Head, body convenience pointers
    head: ?*Element,
    body: ?*Element,
};

const Element = struct {
    tag_name: []const u8,
    namespace: Namespace,
    attributes: ArrayList(Attribute),
    children: ArrayList(Node),
    parent: ?*Element,

    // Convenience methods
    pub fn getElementById(self: *Element, id: []const u8) ?*Element { ... }
    pub fn getElementsByTagName(self: *Element, name: []const u8) []*Element { ... }
    pub fn getAttribute(self: *Element, name: []const u8) ?[]const u8 { ... }
};

const Text = struct {
    data: []const u8,
    parent: ?*Element,
};
```

### Tree Builder Algorithm

The tree builder maintains:
- Stack of open elements
- List of active formatting elements
- Head/body element pointers
- Insertion mode

```zig
const InsertionMode = enum {
    initial,
    before_html,
    before_head,
    in_head,
    after_head,
    in_body,
    text,
    in_table,
    // ... more modes
    after_body,
    after_after_body,
};

pub const TreeBuilder = struct {
    document: *Document,
    open_elements: ArrayList(*Element),
    active_formatting: ArrayList(?*Element),
    insertion_mode: InsertionMode,
    head: ?*Element,

    pub fn processToken(self: *TreeBuilder, token: Token) void {
        switch (self.insertion_mode) {
            .initial => self.handleInitial(token),
            .before_html => self.handleBeforeHtml(token),
            .in_body => self.handleInBody(token),
            // ...
        }
    }

    fn handleInBody(self: *TreeBuilder, token: Token) void {
        switch (token) {
            .start_tag => |tag| {
                if (eql(tag.name, "p")) {
                    if (self.hasElementInButtonScope("p")) {
                        self.closePElement();
                    }
                    self.insertHtmlElement(tag);
                } else if (eql(tag.name, "a")) {
                    // Adoption agency algorithm for links
                    self.handleAnchor(tag);
                }
                // ... many more cases
            },
            .end_tag => |tag| {
                // Handle closing tags
            },
            .character => |c| {
                self.insertCharacter(c);
            },
            // ...
        }
    }
};
```

### Error Recovery

HTML is forgiving. These should all parse:

```html
<p>Unclosed paragraph
<b><i>Misnested</b></i>
<table><tr><td>Missing tbody
<html><html> <!-- duplicate -->
```

The spec defines exactly how to handle each case.

## Memory Management

DOM trees have complex relationships (parent/child/sibling). We use arena allocation:

```zig
pub fn parseHtml(allocator: Allocator, html: []const u8) !*Document {
    var arena = std.heap.ArenaAllocator.init(allocator);

    // All DOM nodes allocated from arena
    var document = try arena.allocator().create(Document);
    var builder = TreeBuilder.init(arena.allocator(), document);
    var tokenizer = Tokenizer.init(arena.allocator(), html);

    while (tokenizer.next()) |token| {
        builder.processToken(token);
    }

    return document;
    // Arena freed when document is freed
}
```

## Performance Considerations

### Lazy Parsing (Future)

Don't parse what you don't need:
- Skip `<script>` contents entirely
- Lazy-parse `<style>` blocks
- Stream tokens without building full tree for display

### SIMD Text Processing (Future)

Fast scanning for special characters:
- `<` (tag start)
- `&` (entity)
- `>` (tag end)

```zig
fn findSpecialChars(input: []const u8) []usize {
    // Use NEON/AVX2 to scan 16+ bytes at once
    const needles = @splat(16, @as(u8, '<'));
    // ...
}
```

## Testing

### Conformance Tests

html5lib provides test suites:
- Tokenizer tests (tokenizer/*.dat)
- Tree construction tests (tree-construction/*.dat)

```zig
test "tokenizer - html5lib" {
    const test_cases = @embedFile("tests/html5lib-tests/tokenizer/test1.dat");
    // Parse test format, run tokenizer, compare output
}
```

### Fuzz Testing

Feed random bytes to find crashes:
```bash
zig build fuzz-html
```

## References

- [WHATWG HTML Parsing](https://html.spec.whatwg.org/multipage/parsing.html)
- [html5lib Tests](https://github.com/html5lib/html5lib-tests)
- [Ladybird LibHTML](https://github.com/LadybirdBrowser/ladybird/tree/master/Userland/Libraries/LibWeb/HTML/Parser)
- [Let's build a browser engine! Part 2](https://limpet.net/mbrubeck/2014/08/11/toy-layout-engine-2.html)

## See Also

- [css-parsing.md](css-parsing.md) - CSS parser
- [../architecture/libvulpes-core.md](../architecture/libvulpes-core.md) - Core architecture
