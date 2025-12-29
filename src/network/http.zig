//! Vulpes Browser - HTTP Client Module
//!
//! PERFORMANCE FIRST: Optimized for time-to-first-byte and fast paint.
//!
//! This module provides HTTP/HTTPS networking using Zig's std.http.Client.
//! Focus areas:
//!   - Minimal allocation during request
//!   - Stream response body (don't buffer entire response)
//!   - Connection reuse via keep-alive
//!   - Fast TLS via system certificates
//!
//! Usage from C/Swift:
//! -------------------
//! This module's functions are not directly exported to C.
//! Instead, higher-level functions in lib.zig wrap these for the C ABI.
//!

const std = @import("std");
const http = std.http;
const Uri = std.Uri;

// =============================================================================
// Types
// =============================================================================

/// HTTP method enumeration
pub const Method = enum {
    GET,
    POST,
    PUT,
    DELETE,
    HEAD,
    OPTIONS,
    PATCH,

    pub fn toStd(self: Method) http.Method {
        return switch (self) {
            .GET => .GET,
            .POST => .POST,
            .PUT => .PUT,
            .DELETE => .DELETE,
            .HEAD => .HEAD,
            .OPTIONS => .OPTIONS,
            .PATCH => .PATCH,
        };
    }
};

/// Response from an HTTP request
pub const Response = struct {
    status: u16,
    body: []const u8,
    // TODO: Add headers, timing info, etc.

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
    }
};

/// Configuration for HTTP requests
pub const RequestOptions = struct {
    method: Method = .GET,
    headers: ?[]const Header = null,
    body: ?[]const u8 = null,
    timeout_ms: u32 = 30_000, // 30 second default
    follow_redirects: bool = true,
    max_redirects: u8 = 10,
};

/// HTTP header key-value pair
pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

/// Errors that can occur during HTTP operations
pub const HttpError = error{
    InvalidUrl,
    ConnectionFailed,
    TlsHandshakeFailed,
    CertificateError,
    Timeout,
    TooManyRedirects,
    InvalidResponse,
    OutOfMemory,
};

// =============================================================================
// HTTP Client
// =============================================================================

/// HTTP client with connection pooling and TLS support.
/// Optimized for minimal latency and fast first-byte delivery.
pub const Client = struct {
    allocator: std.mem.Allocator,
    inner: http.Client,

    const Self = @This();

    /// Initialize HTTP client with connection pooling.
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .inner = http.Client{ .allocator = allocator },
        };
    }

    /// Clean up client resources and close connections.
    pub fn deinit(self: *Self) void {
        self.inner.deinit();
    }

    /// Perform an HTTP request. Returns owned body slice.
    /// Caller must free response.body with the same allocator.
    ///
    /// Uses low-level request API for streaming - optimized for first-byte latency.
    pub fn fetch(self: *Self, url: []const u8, options: RequestOptions) !Response {
        _ = options; // TODO: use method from options

        const uri = Uri.parse(url) catch return HttpError.InvalidUrl;

        // Create request using low-level API for streaming control
        var req = self.inner.request(.GET, uri, .{
            .redirect_behavior = http.Client.Request.RedirectBehavior.init(10),
            .extra_headers = &.{
                .{ .name = "User-Agent", .value = "vulpes/0.1" },
            },
        }) catch return HttpError.ConnectionFailed;
        defer req.deinit();

        // Send request (no body for GET)
        req.sendBodiless() catch return HttpError.ConnectionFailed;

        // Receive response headers
        var redirect_buffer: [8 * 1024]u8 = undefined;
        var response = req.receiveHead(&redirect_buffer) catch return HttpError.InvalidResponse;

        // Read response body with decompression support
        var transfer_buffer: [64]u8 = undefined;
        var decompress: http.Decompress = undefined;

        // Allocate decompression buffer based on content encoding
        const decompress_buffer: []u8 = switch (response.head.content_encoding) {
            .identity => &.{},
            .zstd => self.allocator.alloc(u8, std.compress.zstd.default_window_len) catch return HttpError.OutOfMemory,
            .deflate, .gzip => self.allocator.alloc(u8, std.compress.flate.max_window_len) catch return HttpError.OutOfMemory,
            .compress => return HttpError.InvalidResponse,
        };
        defer if (decompress_buffer.len > 0) self.allocator.free(decompress_buffer);

        var reader = response.readerDecompressing(&transfer_buffer, &decompress, decompress_buffer);
        const max_body_size = std.Io.Limit.limited(10 * 1024 * 1024); // 10 MB

        const body = reader.allocRemaining(self.allocator, max_body_size) catch return HttpError.OutOfMemory;

        return Response{
            .status = @intFromEnum(response.head.status),
            .body = body,
        };
    }
};

// =============================================================================
// Convenience Functions
// =============================================================================

/// Simple GET request. Creates temporary client.
/// Caller must free response.body with the same allocator.
pub fn get(allocator: std.mem.Allocator, url: []const u8) !Response {
    var client = Client.init(allocator);
    defer client.deinit();
    return client.fetch(url, .{});
}

/// Simple POST request with body.
pub fn post(allocator: std.mem.Allocator, url: []const u8, body: []const u8) !Response {
    var client = Client.init(allocator);
    defer client.deinit();
    return client.fetch(url, .{
        .method = .POST,
        .body = body,
    });
}

// =============================================================================
// Tests
// =============================================================================

test "client initialization" {
    var client = Client.init(std.testing.allocator);
    defer client.deinit();
}

test "method conversion" {
    try std.testing.expectEqual(http.Method.GET, Method.GET.toStd());
    try std.testing.expectEqual(http.Method.POST, Method.POST.toStd());
}

// Integration test - requires network
test "fetch example.com" {
    if (true) return; // Skip by default - enable for manual testing

    var client = Client.init(std.testing.allocator);
    defer client.deinit();

    var response = try client.fetch("https://example.com", .{});
    defer response.deinit(std.testing.allocator);

    try std.testing.expect(response.status == 200);
    try std.testing.expect(response.body.len > 0);
}
