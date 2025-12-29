//! Vulpes Browser - HTML Text Extractor
//!
//! MINIMALIST DESIGN: Extract visible text from HTML for display.
//!
//! This module provides fast text extraction without full DOM parsing.
//! Focus areas:
//!   - Skip script, style, and invisible elements
//!   - Decode common HTML entities
//!   - Preserve meaningful whitespace/line breaks
//!   - Fast single-pass parsing
//!

const std = @import("std");

/// Tags whose content should be completely skipped
const skip_tags = [_][]const u8{
    "script",
    "style",
    "head",
    "meta",
    "link",
    "title",
    "noscript",
    "template",
    "svg",
    "math",
};

/// Tags that should insert a newline
const block_tags = [_][]const u8{
    "p",
    "div",
    "br",
    "h1",
    "h2",
    "h3",
    "h4",
    "h5",
    "h6",
    "li",
    "tr",
    "hr",
    "blockquote",
    "pre",
    "section",
    "article",
    "header",
    "footer",
    "nav",
    "aside",
    "main",
};

/// Extract visible text from HTML content.
/// Caller owns returned slice and must free with same allocator.
pub fn extractText(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    var i: usize = 0;
    var in_skip_tag: ?[]const u8 = null;
    var last_was_space = true; // Start true to avoid leading space

    while (i < html.len) {
        // Check for tag start
        if (html[i] == '<') {
            const tag_end = std.mem.indexOfScalarPos(u8, html, i + 1, '>') orelse {
                i += 1;
                continue;
            };

            const tag_content = html[i + 1 .. tag_end];

            // Handle closing tag
            if (tag_content.len > 0 and tag_content[0] == '/') {
                const tag_name = getTagName(tag_content[1..]);
                if (in_skip_tag) |skip| {
                    if (std.ascii.eqlIgnoreCase(tag_name, skip)) {
                        in_skip_tag = null;
                    }
                } else {
                    // Check if block tag - add newline
                    if (isBlockTag(tag_name)) {
                        if (result.items.len > 0 and result.items[result.items.len - 1] != '\n') {
                            try result.append(allocator, '\n');
                            last_was_space = true;
                        }
                    }
                }
            } else {
                // Opening or self-closing tag
                const tag_name = getTagName(tag_content);

                // Check if we should skip this tag's content
                if (isSkipTag(tag_name)) {
                    in_skip_tag = tag_name;
                }

                // Block tags add newline before
                if (isBlockTag(tag_name)) {
                    if (result.items.len > 0 and result.items[result.items.len - 1] != '\n') {
                        try result.append(allocator, '\n');
                        last_was_space = true;
                    }
                }

                // Handle self-closing br
                if (std.ascii.eqlIgnoreCase(tag_name, "br")) {
                    try result.append(allocator, '\n');
                    last_was_space = true;
                }
            }

            i = tag_end + 1;
            continue;
        }

        // Skip content inside skip tags
        if (in_skip_tag != null) {
            i += 1;
            continue;
        }

        // Handle HTML entity
        if (html[i] == '&') {
            const entity_end = std.mem.indexOfScalarPos(u8, html, i + 1, ';') orelse {
                // Not a valid entity, treat as text
                if (!last_was_space) {
                    try result.append(allocator, html[i]);
                }
                i += 1;
                continue;
            };

            // Don't process entities that are too long (not real entities)
            if (entity_end - i > 10) {
                try result.append(allocator, html[i]);
                i += 1;
                continue;
            }

            const entity = html[i + 1 .. entity_end];
            const decoded = decodeEntity(entity);
            if (decoded) |char| {
                if (char == ' ' or char == '\n' or char == '\t') {
                    if (!last_was_space) {
                        try result.append(allocator, ' ');
                        last_was_space = true;
                    }
                } else {
                    try result.append(allocator, char);
                    last_was_space = false;
                }
            }
            i = entity_end + 1;
            continue;
        }

        // Regular text
        const char = html[i];
        if (char == ' ' or char == '\n' or char == '\r' or char == '\t') {
            if (!last_was_space) {
                try result.append(allocator, ' ');
                last_was_space = true;
            }
        } else {
            try result.append(allocator, char);
            last_was_space = false;
        }

        i += 1;
    }

    // Trim trailing whitespace
    while (result.items.len > 0) {
        const last = result.items[result.items.len - 1];
        if (last == ' ' or last == '\n' or last == '\r' or last == '\t') {
            _ = result.pop();
        } else {
            break;
        }
    }

    return result.toOwnedSlice(allocator);
}

fn getTagName(tag_content: []const u8) []const u8 {
    // Find end of tag name (space, /, or end)
    var end: usize = 0;
    while (end < tag_content.len) {
        const c = tag_content[end];
        if (c == ' ' or c == '\t' or c == '\n' or c == '/' or c == '>') {
            break;
        }
        end += 1;
    }
    return tag_content[0..end];
}

fn isSkipTag(name: []const u8) bool {
    for (skip_tags) |skip| {
        if (std.ascii.eqlIgnoreCase(name, skip)) {
            return true;
        }
    }
    return false;
}

fn isBlockTag(name: []const u8) bool {
    for (block_tags) |block| {
        if (std.ascii.eqlIgnoreCase(name, block)) {
            return true;
        }
    }
    return false;
}

fn decodeEntity(entity: []const u8) ?u8 {
    // Numeric entities
    if (entity.len > 1 and entity[0] == '#') {
        if (entity[1] == 'x' or entity[1] == 'X') {
            // Hex entity &#xNN;
            const hex_val = std.fmt.parseInt(u8, entity[2..], 16) catch return null;
            return hex_val;
        } else {
            // Decimal entity &#NN;
            const dec_val = std.fmt.parseInt(u8, entity[1..], 10) catch return null;
            return dec_val;
        }
    }

    // Named entities (common ones)
    const entities = [_]struct { name: []const u8, char: u8 }{
        .{ .name = "nbsp", .char = ' ' },
        .{ .name = "amp", .char = '&' },
        .{ .name = "lt", .char = '<' },
        .{ .name = "gt", .char = '>' },
        .{ .name = "quot", .char = '"' },
        .{ .name = "apos", .char = '\'' },
        .{ .name = "copy", .char = 'c' }, // (c) simplified
        .{ .name = "reg", .char = 'r' }, // (r) simplified
        .{ .name = "mdash", .char = '-' },
        .{ .name = "ndash", .char = '-' },
        .{ .name = "bull", .char = '*' },
        .{ .name = "middot", .char = '.' },
        .{ .name = "hellip", .char = '.' }, // ... simplified
    };

    for (entities) |e| {
        if (std.mem.eql(u8, entity, e.name)) {
            return e.char;
        }
    }

    return null;
}

// =============================================================================
// Tests
// =============================================================================

test "basic text extraction" {
    const html = "<p>Hello <b>World</b>!</p>";
    const text = try extractText(std.testing.allocator, html);
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("Hello World!", text);
}

test "skip script tags" {
    const html = "<p>Before</p><script>alert('hi');</script><p>After</p>";
    const text = try extractText(std.testing.allocator, html);
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("Before\nAfter", text);
}

test "decode entities" {
    const html = "Hello&nbsp;World &amp; Friends";
    const text = try extractText(std.testing.allocator, html);
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("Hello World & Friends", text);
}

test "collapse whitespace" {
    const html = "Hello    \n\n   World";
    const text = try extractText(std.testing.allocator, html);
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("Hello World", text);
}

test "block elements add newlines" {
    const html = "<h1>Title</h1><p>Paragraph</p>";
    const text = try extractText(std.testing.allocator, html);
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("Title\nParagraph", text);
}
