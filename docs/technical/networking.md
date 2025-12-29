# Networking

## Overview

vulpes needs to fetch web content over HTTP/HTTPS. Our networking layer is intentionally simple—no HTTP/2, no WebSockets, no persistent connections beyond keep-alive. Just fast, reliable fetching.

## Requirements

- HTTP/1.1 GET requests
- HTTPS with TLS 1.2+
- Certificate verification
- Redirect following
- Timeout handling
- Basic caching

## HTTP Client

### Request Structure

```zig
const Request = struct {
    method: Method,
    url: Url,
    headers: []Header,
    body: ?[]const u8,

    const Method = enum { GET, HEAD, POST };

    const Header = struct {
        name: []const u8,
        value: []const u8,
    };
};

const Response = struct {
    status: u16,
    headers: []Header,
    body: []const u8,
};
```

### Basic Implementation

```zig
pub fn fetch(url: Url, config: Config) !Response {
    // Resolve DNS
    const address = try resolveDns(url.host);

    // Connect
    const socket = try std.net.tcpConnectToAddress(address, url.port);
    defer socket.close();

    // Wrap in TLS if HTTPS
    const stream = if (url.scheme == .https)
        try TlsStream.init(socket, url.host)
    else
        socket;
    defer if (url.scheme == .https) stream.deinit();

    // Send request
    try sendRequest(stream, url, config);

    // Read response
    return try readResponse(stream, config);
}

fn sendRequest(stream: anytype, url: Url, config: Config) !void {
    var buffer: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    const writer = fbs.writer();

    try writer.print("GET {s} HTTP/1.1\r\n", .{url.path orelse "/"});
    try writer.print("Host: {s}\r\n", .{url.host});
    try writer.print("User-Agent: {s}\r\n", .{config.user_agent});
    try writer.print("Accept: text/html,application/xhtml+xml\r\n", .{});
    try writer.print("Accept-Encoding: identity\r\n", .{});  // No compression for simplicity
    try writer.print("Connection: close\r\n", .{});
    try writer.print("\r\n", .{});

    try stream.writeAll(fbs.getWritten());
}

fn readResponse(stream: anytype, config: Config) !Response {
    var buffer = ArrayList(u8).init(allocator);
    var total_read: usize = 0;

    // Read headers
    var headers_end: ?usize = null;
    while (headers_end == null and total_read < config.max_response_size) {
        var chunk: [8192]u8 = undefined;
        const n = try stream.read(&chunk);
        if (n == 0) break;

        try buffer.appendSlice(chunk[0..n]);
        total_read += n;

        // Look for \r\n\r\n
        if (std.mem.indexOf(u8, buffer.items, "\r\n\r\n")) |pos| {
            headers_end = pos;
        }
    }

    // Parse status line and headers
    const header_section = buffer.items[0..headers_end.?];
    const status = parseStatusLine(header_section);
    const headers = parseHeaders(header_section);

    // Read body (based on Content-Length or chunked)
    const body_start = headers_end.? + 4;
    const content_length = getContentLength(headers);

    if (content_length) |len| {
        // Read remaining body
        while (buffer.items.len - body_start < len) {
            var chunk: [8192]u8 = undefined;
            const n = try stream.read(&chunk);
            if (n == 0) break;
            try buffer.appendSlice(chunk[0..n]);
        }
    }

    return .{
        .status = status,
        .headers = headers,
        .body = buffer.items[body_start..],
    };
}
```

## TLS Integration

### macOS (SecureTransport)

```zig
// platform/tls/securetransport.zig
const Security = @cImport(@cInclude("Security/Security.h"));

pub const TlsStream = struct {
    context: Security.SSLContextRef,
    socket: std.net.Stream,

    pub fn init(socket: std.net.Stream, hostname: []const u8) !TlsStream {
        const context = Security.SSLCreateContext(
            null,
            Security.kSSLClientSide,
            Security.kSSLStreamType,
        );

        // Set hostname for SNI
        _ = Security.SSLSetPeerDomainName(context, hostname.ptr, hostname.len);

        // Set read/write callbacks
        _ = Security.SSLSetIOFuncs(context, readCallback, writeCallback);
        _ = Security.SSLSetConnection(context, @ptrCast(&socket));

        // Handshake
        var result = Security.SSLHandshake(context);
        while (result == Security.errSSLWouldBlock) {
            result = Security.SSLHandshake(context);
        }

        if (result != Security.errSecSuccess) {
            return error.TlsHandshakeFailed;
        }

        return .{ .context = context, .socket = socket };
    }

    pub fn read(self: *TlsStream, buffer: []u8) !usize {
        var processed: usize = 0;
        const result = Security.SSLRead(self.context, buffer.ptr, buffer.len, &processed);
        if (result != Security.errSecSuccess and result != Security.errSSLWouldBlock) {
            return error.TlsReadFailed;
        }
        return processed;
    }

    pub fn write(self: *TlsStream, data: []const u8) !usize {
        var processed: usize = 0;
        const result = Security.SSLWrite(self.context, data.ptr, data.len, &processed);
        if (result != Security.errSecSuccess) {
            return error.TlsWriteFailed;
        }
        return processed;
    }

    pub fn deinit(self: *TlsStream) void {
        _ = Security.SSLClose(self.context);
        Security.CFRelease(self.context);
    }
};
```

## URL Parsing

Following WHATWG URL Standard (simplified):

```zig
pub const Url = struct {
    scheme: Scheme,
    host: []const u8,
    port: u16,
    path: ?[]const u8,
    query: ?[]const u8,
    fragment: ?[]const u8,

    const Scheme = enum { http, https };

    pub fn parse(input: []const u8) !Url {
        var url = Url{
            .scheme = .https,
            .host = "",
            .port = 443,
            .path = null,
            .query = null,
            .fragment = null,
        };

        var remaining = input;

        // Scheme
        if (std.mem.indexOf(u8, remaining, "://")) |scheme_end| {
            const scheme_str = remaining[0..scheme_end];
            url.scheme = std.meta.stringToEnum(Scheme, scheme_str) orelse return error.InvalidScheme;
            url.port = if (url.scheme == .https) 443 else 80;
            remaining = remaining[scheme_end + 3 ..];
        }

        // Fragment
        if (std.mem.indexOf(u8, remaining, "#")) |frag_start| {
            url.fragment = remaining[frag_start + 1 ..];
            remaining = remaining[0..frag_start];
        }

        // Query
        if (std.mem.indexOf(u8, remaining, "?")) |query_start| {
            url.query = remaining[query_start + 1 ..];
            remaining = remaining[0..query_start];
        }

        // Path
        if (std.mem.indexOf(u8, remaining, "/")) |path_start| {
            url.path = remaining[path_start..];
            remaining = remaining[0..path_start];
        }

        // Host and port
        if (std.mem.indexOf(u8, remaining, ":")) |port_start| {
            url.host = remaining[0..port_start];
            url.port = std.fmt.parseInt(u16, remaining[port_start + 1 ..], 10) catch return error.InvalidPort;
        } else {
            url.host = remaining;
        }

        return url;
    }

    pub fn resolve(self: Url, relative: []const u8) !Url {
        // Resolve relative URLs
        if (std.mem.startsWith(u8, relative, "//")) {
            // Protocol-relative
            return Url.parse(std.fmt.allocPrint(allocator, "{s}:{s}", .{ @tagName(self.scheme), relative }));
        }

        if (std.mem.startsWith(u8, relative, "/")) {
            // Absolute path
            var new_url = self;
            new_url.path = relative;
            return new_url;
        }

        if (std.mem.startsWith(u8, relative, "http://") or std.mem.startsWith(u8, relative, "https://")) {
            // Full URL
            return Url.parse(relative);
        }

        // Relative path
        var new_url = self;
        // ... path resolution logic
        return new_url;
    }
};
```

## Redirect Handling

```zig
pub fn fetchWithRedirects(url: Url, config: Config) !Response {
    var current_url = url;
    var redirects: u8 = 0;

    while (redirects < config.max_redirects) {
        const response = try fetch(current_url, config);

        switch (response.status) {
            301, 302, 303, 307, 308 => {
                const location = getHeader(response.headers, "Location") orelse return error.MissingLocation;
                current_url = try current_url.resolve(location);
                redirects += 1;
            },
            else => return response,
        }
    }

    return error.TooManyRedirects;
}
```

## Caching

Simple file-based cache:

```zig
const Cache = struct {
    cache_dir: []const u8,

    const CacheEntry = struct {
        url: []const u8,
        etag: ?[]const u8,
        last_modified: ?[]const u8,
        expires: ?i64,
        body: []const u8,
    };

    pub fn get(self: *Cache, url: Url) ?CacheEntry {
        const path = self.cachePath(url);
        const file = std.fs.openFileAbsolute(path, .{}) catch return null;
        defer file.close();

        // Read and parse cache entry
        // Check expiration
        // Return if valid
    }

    pub fn put(self: *Cache, url: Url, response: Response) !void {
        const entry = CacheEntry{
            .url = url.toString(),
            .etag = getHeader(response.headers, "ETag"),
            .last_modified = getHeader(response.headers, "Last-Modified"),
            .expires = parseExpires(response.headers),
            .body = response.body,
        };

        const path = self.cachePath(url);
        const file = try std.fs.createFileAbsolute(path, .{});
        defer file.close();

        // Serialize and write entry
    }

    fn cachePath(self: *Cache, url: Url) []const u8 {
        const hash = std.hash.Wyhash.hash(0, url.toString());
        return std.fmt.allocPrint(allocator, "{s}/{x}", .{ self.cache_dir, hash });
    }
};
```

## Timeout Handling

```zig
pub fn fetchWithTimeout(url: Url, config: Config) !Response {
    const deadline = std.time.milliTimestamp() + config.timeout_ms;

    // DNS resolution with timeout
    const address = try resolveWithTimeout(url.host, deadline);

    // Connect with timeout
    const socket = try connectWithTimeout(address, url.port, deadline);
    defer socket.close();

    // Set socket timeout for read/write
    try socket.setReadTimeout(deadline - std.time.milliTimestamp());

    // ... rest of fetch
}

fn resolveWithTimeout(host: []const u8, deadline: i64) !std.net.Address {
    // Use getaddrinfo with timeout thread
    // Or async DNS library
}
```

## Error Handling

```zig
const NetworkError = error{
    // DNS
    DnsResolutionFailed,
    DnsTimeout,

    // Connection
    ConnectionRefused,
    ConnectionTimeout,
    ConnectionReset,

    // TLS
    TlsHandshakeFailed,
    CertificateInvalid,
    CertificateExpired,

    // HTTP
    InvalidResponse,
    TooManyRedirects,
    ResponseTooLarge,

    // General
    Timeout,
    OutOfMemory,
};

pub fn describeError(err: NetworkError) []const u8 {
    return switch (err) {
        .DnsResolutionFailed => "Could not resolve hostname",
        .ConnectionRefused => "Connection refused by server",
        .TlsHandshakeFailed => "Secure connection failed",
        .CertificateInvalid => "Invalid security certificate",
        // ...
    };
}
```

## Security

### HTTPS Only (Default)

```zig
pub fn validateUrl(url: Url, config: Config) !void {
    if (url.scheme == .http and !config.allow_insecure) {
        return error.InsecureProtocol;
    }
}
```

### Certificate Pinning (Future)

```zig
const PinnedCert = struct {
    host: []const u8,
    sha256: [32]u8,
};

const pinned_certs = [_]PinnedCert{
    // Pin critical domains
    .{ .host = "github.com", .sha256 = ... },
};
```

## Configuration

```zig
const NetworkConfig = struct {
    // Timeouts
    dns_timeout_ms: u32 = 5_000,
    connect_timeout_ms: u32 = 10_000,
    read_timeout_ms: u32 = 30_000,

    // Limits
    max_response_size: usize = 10 * 1024 * 1024,  // 10MB
    max_redirects: u8 = 10,

    // Identity
    user_agent: []const u8 = "vulpes/0.1",

    // Security
    allow_insecure: bool = false,
    verify_certificates: bool = true,

    // Caching
    cache_enabled: bool = true,
    cache_dir: []const u8 = "~/.cache/vulpes",
};
```

## See Also

- [../architecture/platform-abstraction.md](../architecture/platform-abstraction.md) - TLS backends
- [html-parsing.md](html-parsing.md) - Processing fetched content
