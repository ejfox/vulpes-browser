# CSS Parsing

## Overview

CSS parsing transforms stylesheet text into a structure we can use for styling elements. vulpes implements a focused subset of CSS—enough for readable documents, not enough for complex web apps.

## Supported CSS Subset

### Phase 2 Properties

```
Typography:
  color
  font-size
  font-weight (normal, bold)
  font-style (normal, italic)
  text-decoration (none, underline, line-through)
  text-align (left, center, right)
  line-height

Box Model:
  margin (and margin-top/right/bottom/left)
  padding (and padding-top/right/bottom/left)
  width, max-width

Display:
  display (block, inline, none)

Colors:
  background-color

Lists:
  list-style-type (none, disc, decimal)
```

### Phase 3 Additions

```
More Typography:
  font-family
  letter-spacing
  word-spacing

Borders:
  border (and variants)
  border-radius

Visual:
  opacity
  visibility
```

### Explicitly Unsupported

```
Layout:
  flexbox (display: flex, etc.)
  grid (display: grid, etc.)
  float
  position (absolute, fixed, sticky)

Animation:
  animation-*
  transition-*
  transform

Advanced:
  calc()
  var() (custom properties)
  @media (mostly)
  @keyframes
  @font-face
```

## CSS Parsing Pipeline

```
CSS Text
    │
    ▼
┌─────────────────────┐
│     Tokenizer       │  ← Text → Tokens
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│      Parser         │  ← Tokens → Rules
└─────────────────────┘
    │
    ▼
┌─────────────────────┐
│  Cascade & Inherit  │  ← Rules → Computed Styles
└─────────────────────┘
    │
    ▼
  Computed Styles
```

## CSS Tokenizer

Following [CSS Syntax Module Level 3](https://www.w3.org/TR/css-syntax-3/).

### Token Types

```zig
const Token = union(enum) {
    ident: []const u8,        // color, div, etc.
    function: []const u8,     // rgb(
    at_keyword: []const u8,   // @media
    hash: Hash,               // #id or #fff
    string: []const u8,       // "hello" or 'hello'
    number: Number,           // 42, 3.14
    percentage: f32,          // 50%
    dimension: Dimension,     // 16px, 1.5em
    whitespace,
    colon,                    // :
    semicolon,                // ;
    comma,                    // ,
    open_brace,               // {
    close_brace,              // }
    open_paren,               // (
    close_paren,              // )
    open_bracket,             // [
    close_bracket,            // ]
    delim: u8,                // single character like > + ~
    eof,

    const Hash = struct {
        value: []const u8,
        is_id: bool,  // #id vs #fff (color)
    };

    const Number = struct {
        value: f32,
        is_integer: bool,
    };

    const Dimension = struct {
        value: f32,
        unit: []const u8,  // px, em, rem, etc.
    };
};
```

### Tokenizer Implementation

```zig
pub const Tokenizer = struct {
    input: []const u8,
    pos: usize,

    pub fn next(self: *Tokenizer) Token {
        self.skipWhitespace();

        if (self.pos >= self.input.len) return .eof;

        const c = self.input[self.pos];

        if (c == '/' and self.peek(1) == '*') {
            self.skipComment();
            return self.next();
        }

        if (isWhitespace(c)) {
            self.consumeWhitespace();
            return .whitespace;
        }

        if (c == '"' or c == '\'') {
            return .{ .string = self.consumeString(c) };
        }

        if (c == '#') {
            return self.consumeHash();
        }

        if (isDigit(c) or (c == '.' and isDigit(self.peek(1)))) {
            return self.consumeNumeric();
        }

        if (isNameStart(c)) {
            return self.consumeIdentLike();
        }

        // Single-character tokens
        self.pos += 1;
        return switch (c) {
            ':' => .colon,
            ';' => .semicolon,
            '{' => .open_brace,
            '}' => .close_brace,
            '(' => .open_paren,
            ')' => .close_paren,
            ',' => .comma,
            else => .{ .delim = c },
        };
    }

    fn consumeNumeric(self: *Tokenizer) Token {
        const value = self.consumeNumber();

        if (self.pos < self.input.len and self.input[self.pos] == '%') {
            self.pos += 1;
            return .{ .percentage = value };
        }

        if (isNameStart(self.peek(0))) {
            const unit = self.consumeName();
            return .{ .dimension = .{ .value = value, .unit = unit } };
        }

        return .{ .number = .{ .value = value, .is_integer = @mod(value, 1) == 0 } };
    }
};
```

## CSS Parser

### Rule Structure

```zig
const Stylesheet = struct {
    rules: ArrayList(Rule),
};

const Rule = union(enum) {
    style: StyleRule,
    at_rule: AtRule,  // @media, etc. (limited support)
};

const StyleRule = struct {
    selectors: ArrayList(Selector),
    declarations: ArrayList(Declaration),
};

const Declaration = struct {
    property: []const u8,
    value: Value,
    important: bool,
};

const Value = union(enum) {
    keyword: []const u8,      // auto, none, bold
    length: Length,           // 16px, 1.5em
    percentage: f32,          // 50%
    color: Color,             // #fff, rgb(), named
    number: f32,              // 1.5 (for line-height)
    string: []const u8,       // "Arial"
};

const Length = struct {
    value: f32,
    unit: enum { px, em, rem, percent, vw, vh },
};
```

### Selector Parsing

We support basic selectors:

```zig
const Selector = struct {
    components: ArrayList(SelectorComponent),
    specificity: Specificity,
};

const SelectorComponent = union(enum) {
    universal,                    // *
    type_selector: []const u8,    // div, p, a
    class: []const u8,            // .class
    id: []const u8,               // #id
    attribute: AttributeSelector, // [attr], [attr=val]
    pseudo_class: PseudoClass,    // :hover, :first-child
    combinator: Combinator,       // space, >, +, ~
};

const Combinator = enum {
    descendant,      // space
    child,           // >
    next_sibling,    // +
    subsequent_sibling, // ~
};

// Examples:
// "div" → [type_selector("div")]
// "div.class" → [type_selector("div"), class("class")]
// "div > p" → [type_selector("div"), combinator(child), type_selector("p")]
```

### Parser Implementation

```zig
pub const Parser = struct {
    tokenizer: Tokenizer,
    current_token: Token,

    pub fn parseStylesheet(self: *Parser) !Stylesheet {
        var rules = ArrayList(Rule).init(allocator);

        while (self.current_token != .eof) {
            if (self.current_token == .at_keyword) {
                try rules.append(.{ .at_rule = try self.parseAtRule() });
            } else {
                try rules.append(.{ .style = try self.parseStyleRule() });
            }
        }

        return .{ .rules = rules };
    }

    fn parseStyleRule(self: *Parser) !StyleRule {
        // Parse selectors until '{'
        const selectors = try self.parseSelectors();

        self.expect(.open_brace);

        // Parse declarations until '}'
        const declarations = try self.parseDeclarations();

        self.expect(.close_brace);

        return .{
            .selectors = selectors,
            .declarations = declarations,
        };
    }

    fn parseDeclaration(self: *Parser) !Declaration {
        // property: value;
        const property = self.expectIdent();
        self.expect(.colon);
        const value = try self.parseValue(property);
        const important = self.consumeIfImportant();
        _ = self.consumeIf(.semicolon);

        return .{
            .property = property,
            .value = value,
            .important = important,
        };
    }
};
```

## Value Parsing

### Colors

```zig
fn parseColor(token: Token) ?Color {
    switch (token) {
        .hash => |h| return Color.fromHex(h.value),
        .ident => |name| return Color.fromName(name),  // "red", "blue"
        .function => |name| {
            if (eql(name, "rgb")) return parseRgb();
            if (eql(name, "rgba")) return parseRgba();
            return null;
        },
        else => return null,
    }
}

const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn fromHex(hex: []const u8) ?Color {
        // #rgb, #rrggbb, #rgba, #rrggbbaa
        if (hex.len == 3) {
            // #rgb → #rrggbb
            return .{
                .r = parseHexDigit(hex[0]) * 17,
                .g = parseHexDigit(hex[1]) * 17,
                .b = parseHexDigit(hex[2]) * 17,
            };
        }
        if (hex.len == 6) {
            return .{
                .r = parseHexByte(hex[0..2]),
                .g = parseHexByte(hex[2..4]),
                .b = parseHexByte(hex[4..6]),
            };
        }
        return null;
    }

    pub fn fromName(name: []const u8) ?Color {
        // CSS named colors
        const named = comptime std.ComptimeStringMap(Color, .{
            .{ "black", .{ .r = 0, .g = 0, .b = 0 } },
            .{ "white", .{ .r = 255, .g = 255, .b = 255 } },
            .{ "red", .{ .r = 255, .g = 0, .b = 0 } },
            // ... 140+ named colors
        });
        return named.get(name);
    }
};
```

### Lengths

```zig
fn parseLength(token: Token) ?Length {
    switch (token) {
        .dimension => |d| {
            const unit = std.meta.stringToEnum(LengthUnit, d.unit) orelse return null;
            return .{ .value = d.value, .unit = unit };
        },
        .number => |n| {
            if (n.value == 0) {
                return .{ .value = 0, .unit = .px };  // 0 is valid without unit
            }
            return null;
        },
        .percentage => |p| {
            return .{ .value = p, .unit = .percent };
        },
        else => return null,
    }
}
```

## Specificity

```zig
const Specificity = struct {
    inline_style: u8,  // 1 if from style="" attribute
    ids: u8,           // #id count
    classes: u8,       // .class, [attr], :pseudo count
    elements: u8,      // element, ::pseudo count

    pub fn compare(a: Specificity, b: Specificity) std.math.Order {
        if (a.inline_style != b.inline_style) return std.math.order(a.inline_style, b.inline_style);
        if (a.ids != b.ids) return std.math.order(a.ids, b.ids);
        if (a.classes != b.classes) return std.math.order(a.classes, b.classes);
        return std.math.order(a.elements, b.elements);
    }
};

fn calculateSpecificity(selector: Selector) Specificity {
    var spec = Specificity{};
    for (selector.components) |comp| {
        switch (comp) {
            .id => spec.ids += 1,
            .class, .attribute, .pseudo_class => spec.classes += 1,
            .type_selector, .pseudo_element => spec.elements += 1,
            else => {},
        }
    }
    return spec;
}
```

## Style Sources

CSS comes from multiple places:

```zig
const StyleSource = enum {
    user_agent,     // Browser defaults (our defaults)
    user,           // User stylesheet (config)
    author_linked,  // <link rel="stylesheet">
    author_style,   // <style> elements
    author_inline,  // style="" attributes
};

// Cascade order (lowest to highest priority):
// 1. User agent
// 2. User normal
// 3. Author normal
// 4. Author !important
// 5. User !important
```

## Default Styles

Our user-agent stylesheet:

```zig
const user_agent_css =
    \\html, body { display: block; }
    \\head, script, style { display: none; }
    \\
    \\h1 { font-size: 2em; font-weight: bold; margin: 0.67em 0; }
    \\h2 { font-size: 1.5em; font-weight: bold; margin: 0.83em 0; }
    \\h3 { font-size: 1.17em; font-weight: bold; margin: 1em 0; }
    \\h4 { font-weight: bold; margin: 1.33em 0; }
    \\h5 { font-size: 0.83em; font-weight: bold; margin: 1.67em 0; }
    \\h6 { font-size: 0.67em; font-weight: bold; margin: 2.33em 0; }
    \\
    \\p { margin: 1em 0; }
    \\
    \\a { color: #0066cc; text-decoration: underline; }
    \\a:visited { color: #551a8b; }
    \\
    \\b, strong { font-weight: bold; }
    \\i, em { font-style: italic; }
    \\u { text-decoration: underline; }
    \\s, strike { text-decoration: line-through; }
    \\
    \\code, pre { font-family: monospace; }
    \\pre { margin: 1em 0; white-space: pre; }
    \\
    \\blockquote { margin: 1em 40px; }
    \\
    \\ul, ol { padding-left: 40px; margin: 1em 0; }
    \\li { display: list-item; }
    \\ul { list-style-type: disc; }
    \\ol { list-style-type: decimal; }
;
```

## References

- [CSS Syntax Module Level 3](https://www.w3.org/TR/css-syntax-3/)
- [CSS Cascading and Inheritance](https://www.w3.org/TR/css-cascade-4/)
- [Selectors Level 3](https://www.w3.org/TR/selectors-3/)
- [CSS 2.1 Default Stylesheet](https://www.w3.org/TR/CSS21/sample.html)

## See Also

- [html-parsing.md](html-parsing.md) - HTML parser
- [text-layout.md](text-layout.md) - Layout engine
