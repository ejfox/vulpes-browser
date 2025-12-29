//! Vulpes Browser - CLI Test Entry Point
//!
//! Quick test harness for verifying HTTP fetch and HTML extraction.
//! Usage: zig build run -- https://example.com

const std = @import("std");
const http = @import("network/http.zig");
const text_extractor = @import("html/text_extractor.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;

    // Get URL from args or use default
    var args = std.process.args();
    _ = args.skip(); // skip program name

    const url = args.next() orelse "https://example.com";

    std.debug.print("Fetching: {s}\n", .{url});

    const start = std.time.milliTimestamp();

    var client = http.Client.init(allocator);
    defer client.deinit();

    const response = client.fetch(url, .{}) catch |err| {
        std.debug.print("Error: {}\n", .{err});
        return;
    };
    defer {
        allocator.free(response.body);
    }

    const fetch_time = std.time.milliTimestamp() - start;

    std.debug.print("Status: {d}\n", .{response.status});
    std.debug.print("Body size: {d} bytes\n", .{response.body.len});
    std.debug.print("Fetch time: {d}ms\n", .{fetch_time});

    // Extract text from HTML
    const extract_start = std.time.milliTimestamp();
    const text = text_extractor.extractText(allocator, response.body) catch |err| {
        std.debug.print("Extract error: {}\n", .{err});
        return;
    };
    defer allocator.free(text);

    const extract_time = std.time.milliTimestamp() - extract_start;
    const total_time = std.time.milliTimestamp() - start;

    std.debug.print("Text size: {d} bytes\n", .{text.len});
    std.debug.print("Extract time: {d}ms\n", .{extract_time});
    std.debug.print("Total time: {d}ms\n", .{total_time});
    std.debug.print("\n--- Extracted Text ---\n", .{});

    const preview_len = @min(text.len, 1000);
    std.debug.print("{s}\n", .{text[0..preview_len]});
}
