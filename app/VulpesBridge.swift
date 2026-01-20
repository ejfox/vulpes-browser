// VulpesBridge.swift
// vulpes-browser
//
// Swift wrapper for libvulpes C API.
// Provides a clean Swift interface to the Zig browser engine.

import Foundation

/// Swift wrapper for the Vulpes browser engine.
/// Handles memory management and provides Swift-native types.
class VulpesBridge {

    static let shared = VulpesBridge()

    private init() {
        // Initialize the Zig library
        let result = vulpes_init()
        if result != 0 {
            print("VulpesBridge: Failed to initialize vulpes: \(result)")
        } else {
            print("VulpesBridge: Initialized - version \(version)")
        }
    }

    deinit {
        vulpes_deinit()
    }

    /// Library version string
    var version: String {
        guard let cStr = vulpes_version() else { return "unknown" }
        return String(cString: cStr)
    }

    /// Check if library is initialized
    var isInitialized: Bool {
        vulpes_is_initialized() != 0
    }

    // MARK: - HTTP Fetch

    /// Result of an HTTP fetch operation
    struct FetchResult {
        let status: UInt16
        let body: Data
    }

    /// Fetch failure details (maps to vulpes_error_t)
    struct FetchFailure {
        let code: Int
        let message: String
    }

    /// Fetch a URL and return the response body.
    /// - Parameter url: The URL to fetch
    /// - Returns: FetchResult on success, nil on failure
    func fetch(url: String) -> FetchResult? {
        switch fetchWithError(url: url) {
        case .success(let result):
            return result
        case .failure:
            return nil
        }
    }

    /// Fetch a URL and return detailed errors on failure.
    /// - Parameter url: The URL to fetch
    /// - Returns: Result with FetchResult or FetchFailure
    func fetchWithError(url: String) -> Result<FetchResult, FetchFailure> {
        NSLog("VulpesBridge: fetching \(url)")

        guard let result = vulpes_fetch(url) else {
            NSLog("VulpesBridge: fetch returned nil")
            return .failure(FetchFailure(code: 99, message: "Unknown error (null response)"))
        }
        defer { vulpes_fetch_free(result) }

        guard result.pointee.error_code == 0 else {
            let code = Int(result.pointee.error_code)
            NSLog("VulpesBridge: fetch error code: \(code)")
            return .failure(FetchFailure(code: code, message: errorMessage(for: code)))
        }

        guard let bodyPtr = result.pointee.body else {
            NSLog("VulpesBridge: fetch returned nil body")
            return .success(FetchResult(status: result.pointee.status, body: Data()))
        }

        NSLog("VulpesBridge: fetch success - status \(result.pointee.status), \(result.pointee.body_len) bytes")
        let body = Data(bytes: bodyPtr, count: result.pointee.body_len)
        return .success(FetchResult(status: result.pointee.status, body: body))
    }

    // MARK: - Text Extraction

    /// Extract visible text from HTML content.
    /// - Parameter html: Raw HTML data
    /// - Returns: Extracted text string, or nil on failure
    func extractText(from html: Data) -> String? {
        NSLog("VulpesBridge: extracting text from \(html.count) bytes")

        return html.withUnsafeBytes { ptr -> String? in
            guard let baseAddress = ptr.baseAddress else {
                NSLog("VulpesBridge: extractText - no base address")
                return nil
            }

            guard let result = vulpes_extract_text(
                baseAddress.assumingMemoryBound(to: UInt8.self),
                html.count
            ) else {
                NSLog("VulpesBridge: extractText returned nil")
                return nil
            }
            defer { vulpes_text_free(result) }

            guard result.pointee.error_code == 0 else {
                NSLog("VulpesBridge: extractText error: \(result.pointee.error_code)")
                return nil
            }

            guard let textPtr = result.pointee.text else {
                NSLog("VulpesBridge: extractText returned empty")
                return ""
            }

            NSLog("VulpesBridge: extractText success - \(result.pointee.text_len) bytes")

            // Create string from UTF-8 bytes (using decoding which handles invalid sequences)
            let buffer = UnsafeBufferPointer(start: textPtr, count: result.pointee.text_len)
            let text = String(decoding: buffer, as: UTF8.self)
            return text
        }
    }

    // MARK: - Combined Fetch + Extract

    /// Fetch a URL and extract visible text from the HTML response.
    /// - Parameter url: The URL to fetch
    /// - Returns: Extracted text, or nil on failure
    func fetchAndExtract(url: String) -> String? {
        guard let result = fetch(url: url) else {
            NSLog("VulpesBridge: fetchAndExtract - fetch failed")
            return nil
        }

        // Handle non-200 responses gracefully
        if result.status != 200 {
            NSLog("VulpesBridge: fetchAndExtract - HTTP status \(result.status)")
            // Try to extract content anyway (404 pages often have useful info)
            if let text = extractText(from: result.body), !text.isEmpty {
                return "HTTP \(result.status)\n\n\(text)"
            }
            return "HTTP \(result.status) - \(httpStatusMessage(Int(result.status)))"
        }

        let text = extractText(from: result.body)
        NSLog("VulpesBridge: fetchAndExtract - extracted text: \(text?.prefix(100) ?? "nil")")
        return text
    }

    /// Get human-readable HTTP status message
    private func httpStatusMessage(_ status: Int) -> String {
        switch status {
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Page Not Found"
        case 500: return "Internal Server Error"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        default: return "Error"
        }
    }

    private func errorMessage(for code: Int) -> String {
        switch code {
        case 1: return "Engine not initialized"
        case 2: return "Engine already initialized"
        case 3: return "Invalid URL"
        case 4: return "Out of memory"
        case 5: return "Network error"
        case 6: return "Parse error"
        default: return "Unknown error"
        }
    }
}
