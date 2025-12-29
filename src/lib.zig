//! Vulpes Browser - Library Entry Point (libvulpes)
//!
//! This is the main entry point for the Vulpes browser engine library.
//! It exposes a C ABI interface for consumption by Swift/Objective-C code.
//!
//! Architecture Overview:
//! ----------------------
//! The browser engine is organized into these core modules:
//!
//!   - network: HTTP client, connection pooling, TLS (uses Security.framework)
//!   - parse:   HTML/CSS parsers, DOM tree construction
//!   - layout:  Box model, layout tree, text measurement
//!   - render:  Drawing commands, compositing, output to Metal/CoreGraphics
//!
//! Swift Integration:
//! ------------------
//! Swift imports this library via vulpes.h header file.
//! All exported functions use C calling convention (export fn with callconv(.c)).
//!
//! Memory Management:
//! ------------------
//! The library uses Zig's allocator model internally.
//! C API functions that return allocated memory provide corresponding free functions.
//!

const std = @import("std");

// =============================================================================
// Module Imports
// =============================================================================
// These modules form the core browser engine. Each handles a distinct concern.

// Network layer: HTTP/HTTPS client with macOS TLS integration
pub const network = @import("network/http.zig");

// HTML parsing and text extraction
pub const text_extractor = @import("html/text_extractor.zig");

// TODO: Implement these modules
// pub const layout = @import("layout/box.zig");
// pub const render = @import("render/painter.zig");

// =============================================================================
// Library State
// =============================================================================
// Global state for the library instance.
// In a full implementation, this would hold:
//   - Memory allocator
//   - Connection pool
//   - Cache state
//   - Configuration

const VulpesState = struct {
    initialized: bool = false,
    // allocator: ?std.mem.Allocator = null,
    // TODO: Add connection pool, cache, etc.
};

var global_state: VulpesState = .{};

// =============================================================================
// C ABI Exports
// =============================================================================
// These functions are exported with C calling convention for Swift interop.
// They appear in vulpes.h and are the primary interface to the library.

/// Initialize the Vulpes browser engine.
///
/// Must be called before any other vulpes_* functions.
/// Returns 0 on success, non-zero error code on failure.
///
/// Thread Safety: Call once from main thread during app initialization.
///
/// Example (Swift):
/// ```swift
/// let result = vulpes_init()
/// guard result == 0 else { fatalError("Failed to init vulpes") }
/// ```
export fn vulpes_init() callconv(.c) c_int {
    if (global_state.initialized) {
        // Already initialized - this is fine, return success
        return 0;
    }

    // TODO: Initialize subsystems
    // - Set up allocator
    // - Initialize connection pool
    // - Load cached data
    // - Verify Security.framework availability

    global_state.initialized = true;

    // Log initialization (using std.log which can be configured)
    std.log.info("vulpes: initialized", .{});

    return 0; // Success
}

/// Shutdown the Vulpes browser engine and free all resources.
///
/// After calling this, no other vulpes_* functions should be called
/// (except vulpes_init to re-initialize).
///
/// Thread Safety: Call once from main thread during app shutdown.
/// Ensure no other threads are using vulpes functions.
export fn vulpes_deinit() callconv(.c) void {
    if (!global_state.initialized) {
        return; // Nothing to do
    }

    // TODO: Cleanup subsystems
    // - Close all connections
    // - Flush caches
    // - Free allocated memory

    global_state.initialized = false;

    std.log.info("vulpes: deinitialized", .{});
}

/// Get the library version string.
///
/// Returns a null-terminated string with the version.
/// The returned pointer is valid for the lifetime of the library.
/// Do not free the returned pointer.
export fn vulpes_version() callconv(.c) [*:0]const u8 {
    return "0.1.0-dev";
}

/// Check if the library is initialized.
///
/// Returns 1 if initialized, 0 otherwise.
export fn vulpes_is_initialized() callconv(.c) c_int {
    return if (global_state.initialized) 1 else 0;
}

// =============================================================================
// HTTP Fetch API
// =============================================================================

/// Result of an HTTP fetch operation.
/// Allocated by vulpes_fetch, must be freed with vulpes_fetch_free.
pub const VulpesFetchResult = extern struct {
    status: u16,
    body: ?[*]u8,
    body_len: usize,
    error_code: c_int,
};

/// Global allocator for C API (page allocator for simplicity)
const c_allocator = std.heap.page_allocator;

/// Global HTTP client for reuse
var global_http_client: ?network.Client = null;

/// Fetch a URL and return the response.
///
/// Returns a VulpesFetchResult pointer. Caller must free with vulpes_fetch_free.
/// On error, status will be 0 and error_code will be non-zero.
///
/// Example (Swift):
/// ```swift
/// let result = vulpes_fetch(url)!
/// defer { vulpes_fetch_free(result) }
/// if result.pointee.error_code == 0 {
///     let body = Data(bytes: result.pointee.body!, count: result.pointee.body_len)
/// }
/// ```
export fn vulpes_fetch(url: [*:0]const u8) callconv(.c) ?*VulpesFetchResult {
    if (!global_state.initialized) {
        const result = c_allocator.create(VulpesFetchResult) catch return null;
        result.* = .{ .status = 0, .body = null, .body_len = 0, .error_code = 1 };
        return result;
    }

    // Initialize client if needed
    if (global_http_client == null) {
        global_http_client = network.Client.init(c_allocator);
    }

    // Convert C string to slice
    const url_slice = std.mem.sliceTo(url, 0);

    // Perform fetch
    const response = global_http_client.?.fetch(url_slice, .{}) catch {
        const result = c_allocator.create(VulpesFetchResult) catch return null;
        result.* = .{ .status = 0, .body = null, .body_len = 0, .error_code = 5 }; // NETWORK error
        return result;
    };

    // Create result
    const result = c_allocator.create(VulpesFetchResult) catch {
        c_allocator.free(response.body);
        return null;
    };

    result.* = .{
        .status = response.status,
        .body = @constCast(response.body.ptr),
        .body_len = response.body.len,
        .error_code = 0,
    };

    return result;
}

/// Free a VulpesFetchResult returned by vulpes_fetch.
export fn vulpes_fetch_free(result: ?*VulpesFetchResult) callconv(.c) void {
    if (result) |r| {
        if (r.body) |body| {
            c_allocator.free(body[0..r.body_len]);
        }
        c_allocator.destroy(r);
    }
}

// =============================================================================
// Text Extraction API
// =============================================================================

/// Result of text extraction.
/// Allocated by vulpes_extract_text, must be freed with vulpes_text_free.
pub const VulpesTextResult = extern struct {
    text: ?[*]u8,
    text_len: usize,
    error_code: c_int,
};

/// Extract visible text from HTML content.
///
/// Returns a VulpesTextResult pointer. Caller must free with vulpes_text_free.
///
/// Example (Swift):
/// ```swift
/// let result = vulpes_extract_text(htmlPtr, htmlLen)!
/// defer { vulpes_text_free(result) }
/// if result.pointee.error_code == 0 {
///     let text = String(bytes: UnsafeBufferPointer(start: result.pointee.text, count: result.pointee.text_len), encoding: .utf8)
/// }
/// ```
export fn vulpes_extract_text(html: [*]const u8, html_len: usize) callconv(.c) ?*VulpesTextResult {
    const html_slice = html[0..html_len];

    const text = text_extractor.extractText(c_allocator, html_slice) catch {
        const result = c_allocator.create(VulpesTextResult) catch return null;
        result.* = .{ .text = null, .text_len = 0, .error_code = 4 }; // OUT_OF_MEMORY
        return result;
    };

    const result = c_allocator.create(VulpesTextResult) catch {
        c_allocator.free(text);
        return null;
    };

    result.* = .{
        .text = @constCast(text.ptr),
        .text_len = text.len,
        .error_code = 0,
    };

    return result;
}

/// Free a VulpesTextResult returned by vulpes_extract_text.
export fn vulpes_text_free(result: ?*VulpesTextResult) callconv(.c) void {
    if (result) |r| {
        if (r.text) |text| {
            c_allocator.free(text[0..r.text_len]);
        }
        c_allocator.destroy(r);
    }
}

// =============================================================================
// Tests
// =============================================================================

test "init and deinit" {
    const result = vulpes_init();
    try std.testing.expectEqual(@as(c_int, 0), result);
    try std.testing.expectEqual(@as(c_int, 1), vulpes_is_initialized());

    vulpes_deinit();
    try std.testing.expectEqual(@as(c_int, 0), vulpes_is_initialized());
}

test "version string" {
    const version = vulpes_version();
    try std.testing.expect(version[0] != 0);
}
