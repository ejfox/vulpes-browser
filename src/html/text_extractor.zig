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
//!   - Extract and number links
//!

const std = @import("std");

/// Maximum number of links to track
const MAX_LINKS = 99;
/// Maximum number of images to track
const MAX_IMAGES = 50;

/// Control characters for marking link text
/// These are parsed by Swift to apply blue color
const LINK_START: u8 = 0x01; // SOH - Start of Heading
const LINK_END: u8 = 0x02; // STX - Start of Text
const PRE_START: u8 = 0x03; // ETX - End of Text
const PRE_END: u8 = 0x04; // EOT - End of Transmission
const EMPH_START: u8 = 0x11; // DC1 - Device Control 1
const EMPH_END: u8 = 0x12; // DC2 - Device Control 2
const STRONG_START: u8 = 0x13; // DC3 - Device Control 3
const STRONG_END: u8 = 0x14; // DC4 - Device Control 4
const CODE_START: u8 = 0x15; // NAK - Negative Acknowledge
const CODE_END: u8 = 0x16; // SYN - Synchronous Idle
const QUOTE_START: u8 = 0x17; // ETB - End of Transmission Block
const QUOTE_END: u8 = 0x18; // CAN - Cancel
const H1_START: u8 = 0x19; // EM - End of Medium
const H2_START: u8 = 0x1A; // SUB - Substitute
const H3_START: u8 = 0x1B; // ESC - Escape
const H4_START: u8 = 0x1C; // FS - File Separator
const HEADING_END: u8 = 0x1D; // GS - Group Separator
const IMAGE_MARKER: u8 = 0x1E; // RS - Record Separator (marks image placeholder)

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

/// Extract visible text from HTML content.
/// Caller owns returned slice and must free with same allocator.
/// Links are extracted and appended at the end as numbered references.
/// Images are marked with IMAGE_MARKER control character and listed separately.
pub fn extractText(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    errdefer result.deinit(allocator);

    // Track extracted links
    var links: [MAX_LINKS][]const u8 = undefined;
    var link_count: usize = 0;

    // Track extracted images
    var images: [MAX_IMAGES][]const u8 = undefined;
    var image_count: usize = 0;

    // Track current link state
    var in_link: bool = false;
    var current_href: ?[]const u8 = null;
    var in_pre: bool = false;
    var list_depth: u8 = 0;

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
                if (std.ascii.eqlIgnoreCase(tag_name, "pre")) {
                    if (in_pre) {
                        try result.append(allocator, PRE_END);
                    }
                    in_pre = false;
                    try appendNewlines(allocator, &result, 2);
                    last_was_space = true;
                }

                if (std.ascii.eqlIgnoreCase(tag_name, "blockquote")) {
                    try result.append(allocator, QUOTE_END);
                    try appendNewlines(allocator, &result, 2);
                    last_was_space = true;
                }

                if (isHeadingTag(tag_name)) {
                    try result.append(allocator, HEADING_END);
                }

                if (std.ascii.eqlIgnoreCase(tag_name, "em") or std.ascii.eqlIgnoreCase(tag_name, "i")) {
                    try result.append(allocator, EMPH_END);
                }

                if (std.ascii.eqlIgnoreCase(tag_name, "strong") or std.ascii.eqlIgnoreCase(tag_name, "b")) {
                    try result.append(allocator, STRONG_END);
                }

                if (std.ascii.eqlIgnoreCase(tag_name, "code")) {
                    try result.append(allocator, CODE_END);
                }

                    if (std.ascii.eqlIgnoreCase(tag_name, "ul") or std.ascii.eqlIgnoreCase(tag_name, "ol")) {
                        if (list_depth > 0) list_depth -= 1;
                        try appendNewlines(allocator, &result, 1);
                        last_was_space = true;
                    }

                    // Check for closing </a> tag
                    if (std.ascii.eqlIgnoreCase(tag_name, "a")) {
                        if (in_link and current_href != null) {
                            // Mark end of link text
                            try result.append(allocator, LINK_END);

                            // Add link number marker
                            if (link_count < MAX_LINKS) {
                                links[link_count] = current_href.?;
                                link_count += 1;

                                // Insert [N] marker
                                try result.append(allocator, ' ');
                                try result.append(allocator, '[');
                                var num_buf: [3]u8 = undefined;
                                const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{link_count}) catch "?";
                                try result.appendSlice(allocator, num_str);
                                try result.append(allocator, ']');
                                last_was_space = false;
                            }
                        }
                        in_link = false;
                        current_href = null;
                    }

                    const spacing_after = blockSpacingAfter(tag_name);
                    if (spacing_after > 0) {
                        try appendNewlines(allocator, &result, spacing_after);
                        last_was_space = true;
                    }
                }
            } else {
                // Opening or self-closing tag
                const tag_name = getTagName(tag_content);

                // Check if we should skip this tag's content
                if (isSkipTag(tag_name)) {
                    in_skip_tag = tag_name;
                }

                const spacing_before = blockSpacingBefore(tag_name);
                if (spacing_before > 0) {
                    try appendNewlines(allocator, &result, spacing_before);
                    last_was_space = true;
                }

                if (std.ascii.eqlIgnoreCase(tag_name, "pre")) {
                    in_pre = true;
                    try result.append(allocator, PRE_START);
                    last_was_space = true;
                }

                if (std.ascii.eqlIgnoreCase(tag_name, "blockquote")) {
                    try result.append(allocator, QUOTE_START);
                    last_was_space = true;
                }

                if (std.ascii.eqlIgnoreCase(tag_name, "em") or std.ascii.eqlIgnoreCase(tag_name, "i")) {
                    try result.append(allocator, EMPH_START);
                }

                if (std.ascii.eqlIgnoreCase(tag_name, "strong") or std.ascii.eqlIgnoreCase(tag_name, "b")) {
                    try result.append(allocator, STRONG_START);
                }

                if (std.ascii.eqlIgnoreCase(tag_name, "code")) {
                    try result.append(allocator, CODE_START);
                }

                if (std.ascii.eqlIgnoreCase(tag_name, "ul") or std.ascii.eqlIgnoreCase(tag_name, "ol")) {
                    if (list_depth < 10) list_depth += 1;
                    last_was_space = true;
                }

                if (std.ascii.eqlIgnoreCase(tag_name, "li")) {
                    try appendNewlines(allocator, &result, 1);
                    const indent_levels: u8 = if (list_depth > 1) list_depth - 1 else 0;
                    for (0..indent_levels) |_| {
                        try result.appendSlice(allocator, "  ");
                    }
                    try result.appendSlice(allocator, "- ");
                    last_was_space = true;
                }

                // Check for <a> tag and extract href
                if (std.ascii.eqlIgnoreCase(tag_name, "a")) {
                    current_href = extractHref(html[i..tag_end + 1]);
                    if (current_href != null and link_count < MAX_LINKS) {
                        in_link = true;
                        // Mark start of link text for blue styling
                        try result.append(allocator, LINK_START);
                    } else {
                        in_link = false;
                        current_href = null;
                    }
                }

                // Handle <img> tags - extract src and insert image marker
                if (std.ascii.eqlIgnoreCase(tag_name, "img")) {
                    if (extractImgSrc(html[i..tag_end + 1])) |img_src| {
                        if (image_count < MAX_IMAGES) {
                            images[image_count] = img_src;
                            // Insert image placeholder with number
                            try result.append(allocator, IMAGE_MARKER);
                            var num_buf: [3]u8 = undefined;
                            const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{image_count + 1}) catch "?";
                            try result.appendSlice(allocator, num_str);
                            try result.append(allocator, IMAGE_MARKER);
                            image_count += 1;
                            try result.append(allocator, ' ');
                            last_was_space = true;
                        }
                    }
                }

                if (isHeadingTag(tag_name)) {
                    const heading_start = headingStartMarker(tag_name) orelse HEADING_END;
                    try result.append(allocator, heading_start);
                }

                // Handle self-closing br
                if (std.ascii.eqlIgnoreCase(tag_name, "br")) {
                    try appendNewlines(allocator, &result, 1);
                    last_was_space = true;
                }

                if (std.ascii.eqlIgnoreCase(tag_name, "hr")) {
                    try appendNewlines(allocator, &result, 1);
                    try result.appendSlice(allocator, "----------------------------------------");
                    try appendNewlines(allocator, &result, 1);
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
                if (in_pre or !last_was_space) {
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
                if (in_pre) {
                    try result.append(allocator, char);
                    last_was_space = (char == ' ' or char == '\n' or char == '\t' or char == '\r');
                } else {
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
            }
            i = entity_end + 1;
            continue;
        }

        // Regular text
        const char = html[i];
        if (in_pre) {
            try result.append(allocator, char);
            last_was_space = (char == ' ' or char == '\n' or char == '\r' or char == '\t');
        } else {
            if (char == ' ' or char == '\n' or char == '\r' or char == '\t') {
                if (!last_was_space) {
                    try result.append(allocator, ' ');
                    last_was_space = true;
                }
            } else {
                try result.append(allocator, char);
                last_was_space = false;
            }
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

    // Append links section if we found any
    if (link_count > 0) {
        try result.appendSlice(allocator, "\n\n---\nLinks:\n");
        for (links[0..link_count], 1..) |href, num| {
            try result.append(allocator, '[');
            var num_buf: [3]u8 = undefined;
            const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{num}) catch "?";
            try result.appendSlice(allocator, num_str);
            try result.appendSlice(allocator, "] ");
            try result.appendSlice(allocator, href);
            try result.append(allocator, '\n');
        }
    }

    // Append images section if we found any
    if (image_count > 0) {
        try result.appendSlice(allocator, "\n---\nImages:\n");
        for (images[0..image_count], 1..) |src, num| {
            try result.append(allocator, '[');
            var num_buf: [3]u8 = undefined;
            const num_str = std.fmt.bufPrint(&num_buf, "{d}", .{num}) catch "?";
            try result.appendSlice(allocator, num_str);
            try result.appendSlice(allocator, "] ");
            try result.appendSlice(allocator, src);
            try result.append(allocator, '\n');
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

/// Extract href attribute value from an <a> tag
fn extractHref(tag: []const u8) ?[]const u8 {
    // Look for href= (case insensitive)
    var i: usize = 0;
    while (i + 5 < tag.len) {
        if ((tag[i] == 'h' or tag[i] == 'H') and
            (tag[i + 1] == 'r' or tag[i + 1] == 'R') and
            (tag[i + 2] == 'e' or tag[i + 2] == 'E') and
            (tag[i + 3] == 'f' or tag[i + 3] == 'F') and
            tag[i + 4] == '=')
        {
            i += 5;

            // Skip whitespace
            while (i < tag.len and (tag[i] == ' ' or tag[i] == '\t')) {
                i += 1;
            }

            if (i >= tag.len) return null;

            // Check for quote
            const quote = tag[i];
            if (quote == '"' or quote == '\'') {
                i += 1;
                const start = i;
                while (i < tag.len and tag[i] != quote) {
                    i += 1;
                }
                if (i > start) {
                    return tag[start..i];
                }
            } else {
                // Unquoted value - ends at space or >
                const start = i;
                while (i < tag.len and tag[i] != ' ' and tag[i] != '>' and tag[i] != '\t') {
                    i += 1;
                }
                if (i > start) {
                    return tag[start..i];
                }
            }
            return null;
        }
        i += 1;
    }
    return null;
}

/// Extract src attribute value from an <img> tag
fn extractImgSrc(tag: []const u8) ?[]const u8 {
    // Look for src= (case insensitive)
    var i: usize = 0;
    while (i + 4 < tag.len) {
        if ((tag[i] == 's' or tag[i] == 'S') and
            (tag[i + 1] == 'r' or tag[i + 1] == 'R') and
            (tag[i + 2] == 'c' or tag[i + 2] == 'C') and
            tag[i + 3] == '=')
        {
            i += 4;

            // Skip whitespace
            while (i < tag.len and (tag[i] == ' ' or tag[i] == '\t')) {
                i += 1;
            }

            if (i >= tag.len) return null;

            // Check for quote
            const quote = tag[i];
            if (quote == '"' or quote == '\'') {
                i += 1;
                const start = i;
                while (i < tag.len and tag[i] != quote) {
                    i += 1;
                }
                if (i > start) {
                    return tag[start..i];
                }
            } else {
                // Unquoted value - ends at space or >
                const start = i;
                while (i < tag.len and tag[i] != ' ' and tag[i] != '>' and tag[i] != '\t') {
                    i += 1;
                }
                if (i > start) {
                    return tag[start..i];
                }
            }
            return null;
        }
        i += 1;
    }
    return null;
}

fn isSkipTag(name: []const u8) bool {
    for (skip_tags) |skip| {
        if (std.ascii.eqlIgnoreCase(name, skip)) {
            return true;
        }
    }
    return false;
}

fn isHeadingTag(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "h1") or
        std.ascii.eqlIgnoreCase(name, "h2") or
        std.ascii.eqlIgnoreCase(name, "h3") or
        std.ascii.eqlIgnoreCase(name, "h4") or
        std.ascii.eqlIgnoreCase(name, "h5") or
        std.ascii.eqlIgnoreCase(name, "h6");
}

fn headingStartMarker(name: []const u8) ?u8 {
    if (std.ascii.eqlIgnoreCase(name, "h1")) return H1_START;
    if (std.ascii.eqlIgnoreCase(name, "h2")) return H2_START;
    if (std.ascii.eqlIgnoreCase(name, "h3")) return H3_START;
    if (std.ascii.eqlIgnoreCase(name, "h4")) return H4_START;
    return H2_START;
}

fn blockSpacingBefore(name: []const u8) u8 {
    // HTML Living Standard + CSS UA defaults: block elements have margin-block.
    // We approximate one line of separation before block elements.
    if (isHeadingTag(name)) return 1;
    if (std.ascii.eqlIgnoreCase(name, "p") or
        std.ascii.eqlIgnoreCase(name, "div") or
        std.ascii.eqlIgnoreCase(name, "section") or
        std.ascii.eqlIgnoreCase(name, "article") or
        std.ascii.eqlIgnoreCase(name, "header") or
        std.ascii.eqlIgnoreCase(name, "footer") or
        std.ascii.eqlIgnoreCase(name, "nav") or
        std.ascii.eqlIgnoreCase(name, "aside") or
        std.ascii.eqlIgnoreCase(name, "main") or
        std.ascii.eqlIgnoreCase(name, "blockquote") or
        std.ascii.eqlIgnoreCase(name, "pre") or
        std.ascii.eqlIgnoreCase(name, "ul") or
        std.ascii.eqlIgnoreCase(name, "ol") or
        std.ascii.eqlIgnoreCase(name, "hr"))
    {
        return 1;
    }
    return 0;
}

fn blockSpacingAfter(name: []const u8) u8 {
    // Approximate margin-block-end for block elements as a blank line.
    if (isHeadingTag(name)) return 2;
    if (std.ascii.eqlIgnoreCase(name, "p") or
        std.ascii.eqlIgnoreCase(name, "div") or
        std.ascii.eqlIgnoreCase(name, "section") or
        std.ascii.eqlIgnoreCase(name, "article") or
        std.ascii.eqlIgnoreCase(name, "header") or
        std.ascii.eqlIgnoreCase(name, "footer") or
        std.ascii.eqlIgnoreCase(name, "nav") or
        std.ascii.eqlIgnoreCase(name, "aside") or
        std.ascii.eqlIgnoreCase(name, "main") or
        std.ascii.eqlIgnoreCase(name, "blockquote") or
        std.ascii.eqlIgnoreCase(name, "pre") or
        std.ascii.eqlIgnoreCase(name, "ul") or
        std.ascii.eqlIgnoreCase(name, "ol") or
        std.ascii.eqlIgnoreCase(name, "hr"))
    {
        return 2;
    }
    if (std.ascii.eqlIgnoreCase(name, "tr")) return 1;
    return 0;
}

fn appendNewlines(allocator: std.mem.Allocator, result: *std.ArrayListUnmanaged(u8), count: u8) !void {
    if (count == 0 or result.items.len == 0) return;
    var existing: u8 = 0;
    var idx = result.items.len;
    while (idx > 0 and result.items[idx - 1] == '\n' and existing < count) {
        existing += 1;
        idx -= 1;
    }

    if (existing >= count) return;
    for (existing..count) |_| {
        try result.append(allocator, '\n');
    }
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

    const expected = &[_]u8{
        'H', 'e', 'l', 'l', 'o', ' ',
        STRONG_START, 'W', 'o', 'r', 'l', 'd', STRONG_END, '!',
    };
    try std.testing.expectEqualStrings(expected, text);
}

test "skip script tags" {
    const html = "<p>Before</p><script>alert('hi');</script><p>After</p>";
    const text = try extractText(std.testing.allocator, html);
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("Before\n\nAfter", text);
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

    const expected = &[_]u8{
        H1_START, 'T', 'i', 't', 'l', 'e', HEADING_END,
        '\n', '\n',
        'P', 'a', 'r', 'a', 'g', 'r', 'a', 'p', 'h',
    };
    try std.testing.expectEqualStrings(expected, text);
}

test "extract links with href" {
    const html = "<p>Visit <a href=\"https://example.com\">Example</a> for more info.</p>";
    const text = try extractText(std.testing.allocator, html);
    defer std.testing.allocator.free(text);

    // Should contain link marker and link section
    try std.testing.expect(std.mem.indexOf(u8, text, "[1]") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "https://example.com") != null);
}

test "multiple links numbered correctly" {
    const html = "<p><a href=\"/a\">A</a> and <a href=\"/b\">B</a></p>";
    const text = try extractText(std.testing.allocator, html);
    defer std.testing.allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "[1]") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "[2]") != null);
}

test "list items render bullets" {
    const html = "<ul><li>One</li><li>Two</li></ul>";
    const text = try extractText(std.testing.allocator, html);
    defer std.testing.allocator.free(text);

    try std.testing.expectEqualStrings("- One\n- Two", text);
}

test "pre preserves whitespace" {
    const html = "<pre>line 1\n  line 2</pre>";
    const text = try extractText(std.testing.allocator, html);
    defer std.testing.allocator.free(text);

    const expected = &[_]u8{ PRE_START, 'l', 'i', 'n', 'e', ' ', '1', '\n', ' ', ' ', 'l', 'i', 'n', 'e', ' ', '2', PRE_END };
    try std.testing.expectEqualStrings(expected, text);
}

test "emphasis markers" {
    const html = "<p><em>Hi</em> <strong>There</strong></p>";
    const text = try extractText(std.testing.allocator, html);
    defer std.testing.allocator.free(text);

    const expected = &[_]u8{
        EMPH_START, 'H', 'i', EMPH_END, ' ',
        STRONG_START, 'T', 'h', 'e', 'r', 'e', STRONG_END,
    };
    try std.testing.expectEqualStrings(expected, text);
}

test "code markers" {
    const html = "<p>Use <code>curl</code> here</p>";
    const text = try extractText(std.testing.allocator, html);
    defer std.testing.allocator.free(text);

    const expected = &[_]u8{
        'U', 's', 'e', ' ',
        CODE_START, 'c', 'u', 'r', 'l', CODE_END, ' ',
        'h', 'e', 'r', 'e',
    };
    try std.testing.expectEqualStrings(expected, text);
}

test "blockquote markers" {
    const html = "<blockquote>Quote</blockquote>";
    const text = try extractText(std.testing.allocator, html);
    defer std.testing.allocator.free(text);

    const expected = &[_]u8{ QUOTE_START, 'Q', 'u', 'o', 't', 'e', QUOTE_END };
    try std.testing.expectEqualStrings(expected, text);
}

test "heading markers" {
    const html = "<h2>Title</h2>";
    const text = try extractText(std.testing.allocator, html);
    defer std.testing.allocator.free(text);

    const expected = &[_]u8{ H2_START, 'T', 'i', 't', 'l', 'e', HEADING_END };
    try std.testing.expectEqualStrings(expected, text);
}
