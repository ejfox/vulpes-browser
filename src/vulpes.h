/*
 * Vulpes Browser - C Header for Swift Interop
 *
 * This header defines the C interface to libvulpes, the Vulpes browser engine.
 * It is designed to be imported by Swift using a bridging header or module map.
 *
 * Swift Integration:
 * ------------------
 * Option 1: Bridging Header
 *   Add this file to your Xcode project and reference it in
 *   Build Settings > Swift Compiler > Objective-C Bridging Header
 *
 * Option 2: Module Map (recommended for frameworks)
 *   Create a module.modulemap:
 *   ```
 *   module Vulpes {
 *       header "vulpes.h"
 *       link "vulpes"
 *       export *
 *   }
 *   ```
 *
 * Swift Usage Example:
 * ```swift
 * import Vulpes
 *
 * class BrowserEngine {
 *     init() {
 *         let result = vulpes_init()
 *         guard result == 0 else {
 *             fatalError("Failed to initialize Vulpes: \(result)")
 *         }
 *     }
 *
 *     deinit {
 *         vulpes_deinit()
 *     }
 *
 *     var version: String {
 *         String(cString: vulpes_version())
 *     }
 * }
 * ```
 *
 * Memory Management:
 * ------------------
 * - Strings returned by vulpes functions are owned by the library unless
 *   documented otherwise. Do not free them.
 * - Functions that allocate memory for the caller will have corresponding
 *   vulpes_*_free() functions to release that memory.
 * - All pointers are non-null unless marked _Nullable.
 *
 * Thread Safety:
 * --------------
 * - vulpes_init() and vulpes_deinit() must be called from the main thread
 * - Other functions are thread-safe unless documented otherwise
 *
 */

#ifndef VULPES_H
#define VULPES_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================================
 * Version Information
 * ============================================================================ */

/**
 * Library version components for compatibility checking.
 */
#define VULPES_VERSION_MAJOR 0
#define VULPES_VERSION_MINOR 1
#define VULPES_VERSION_PATCH 0

/* ============================================================================
 * Error Codes
 * ============================================================================ */

/**
 * Error codes returned by vulpes functions.
 * Zero indicates success; non-zero indicates an error.
 */
typedef enum {
    VULPES_OK = 0,                    /* Success */
    VULPES_ERROR_NOT_INITIALIZED = 1, /* Library not initialized */
    VULPES_ERROR_ALREADY_INITIALIZED = 2,
    VULPES_ERROR_INVALID_ARGUMENT = 3,
    VULPES_ERROR_OUT_OF_MEMORY = 4,
    VULPES_ERROR_NETWORK = 5,         /* Network operation failed */
    VULPES_ERROR_PARSE = 6,           /* HTML/CSS parse error */
    VULPES_ERROR_UNKNOWN = 99
} vulpes_error_t;

/* ============================================================================
 * Opaque Types
 * ============================================================================
 *
 * These are forward declarations for opaque types.
 * The actual struct definitions are internal to the library.
 * Swift will see these as OpaquePointer types.
 */

/**
 * Browser context - holds state for a browsing session.
 * Create with vulpes_context_create(), destroy with vulpes_context_destroy().
 */
typedef struct vulpes_context vulpes_context_t;

/**
 * DOM document - represents a parsed HTML document.
 */
typedef struct vulpes_document vulpes_document_t;

/**
 * Render tree - layout and painting information.
 */
typedef struct vulpes_render_tree vulpes_render_tree_t;

/* ============================================================================
 * Core Library Functions
 * ============================================================================ */

/**
 * Initialize the Vulpes browser engine.
 *
 * Must be called before any other vulpes_* functions (except vulpes_version).
 * Safe to call multiple times; subsequent calls are no-ops.
 *
 * @return VULPES_OK on success, error code on failure.
 *
 * Thread Safety: Call from main thread only.
 */
int vulpes_init(void);

/**
 * Shutdown the Vulpes browser engine.
 *
 * Releases all resources. After calling, no vulpes_* functions should be
 * called except vulpes_init() to re-initialize.
 *
 * Thread Safety: Call from main thread only. Ensure no other threads
 * are using vulpes functions when this is called.
 */
void vulpes_deinit(void);

/**
 * Get the library version as a string.
 *
 * @return Null-terminated version string (e.g., "0.1.0-dev").
 *         The returned pointer is valid for the lifetime of the library.
 *         Do not free.
 */
const char* vulpes_version(void);

/**
 * Check if the library is initialized.
 *
 * @return 1 if initialized, 0 otherwise.
 */
int vulpes_is_initialized(void);

/* ============================================================================
 * HTTP Fetch API
 * ============================================================================ */

/**
 * Result of an HTTP fetch operation.
 * Allocated by vulpes_fetch, must be freed with vulpes_fetch_free.
 */
typedef struct {
    uint16_t status;       /* HTTP status code (200, 404, etc.) */
    uint8_t* _Nullable body;  /* Response body bytes */
    size_t body_len;       /* Length of body in bytes */
    int error_code;        /* 0 on success, vulpes_error_t on failure */
} vulpes_fetch_result_t;

/**
 * Fetch a URL and return the response.
 *
 * @param url Null-terminated URL string.
 * @return Pointer to result, or NULL on allocation failure.
 *         Caller must free with vulpes_fetch_free().
 *
 * Swift example:
 * ```swift
 * guard let result = vulpes_fetch(url) else { return }
 * defer { vulpes_fetch_free(result) }
 * if result.pointee.error_code == 0 {
 *     let body = Data(bytes: result.pointee.body!, count: result.pointee.body_len)
 * }
 * ```
 */
vulpes_fetch_result_t* _Nullable vulpes_fetch(const char* url);

/**
 * Free a vulpes_fetch_result_t returned by vulpes_fetch.
 */
void vulpes_fetch_free(vulpes_fetch_result_t* _Nullable result);

/* ============================================================================
 * Text Extraction API
 * ============================================================================ */

/**
 * Result of text extraction.
 * Allocated by vulpes_extract_text, must be freed with vulpes_text_free.
 */
typedef struct {
    uint8_t* _Nullable text;  /* Extracted text (UTF-8, not null-terminated) */
    size_t text_len;       /* Length of text in bytes */
    int error_code;        /* 0 on success, vulpes_error_t on failure */
} vulpes_text_result_t;

/**
 * Extract visible text from HTML content.
 *
 * Strips HTML tags, decodes entities, normalizes whitespace.
 * Skips script, style, and other non-visible elements.
 *
 * @param html Pointer to HTML bytes (not null-terminated).
 * @param html_len Length of HTML in bytes.
 * @return Pointer to result, or NULL on allocation failure.
 *         Caller must free with vulpes_text_free().
 *
 * Swift example:
 * ```swift
 * guard let result = vulpes_extract_text(htmlPtr, htmlLen) else { return }
 * defer { vulpes_text_free(result) }
 * if result.pointee.error_code == 0 {
 *     let text = String(bytes: UnsafeBufferPointer(start: result.pointee.text, count: result.pointee.text_len), encoding: .utf8)
 * }
 * ```
 */
vulpes_text_result_t* _Nullable vulpes_extract_text(const uint8_t* html, size_t html_len);

/**
 * Free a vulpes_text_result_t returned by vulpes_extract_text.
 */
void vulpes_text_free(vulpes_text_result_t* _Nullable result);

/* ============================================================================
 * Context Management (TODO)
 * ============================================================================
 *
 * A context represents an isolated browsing session with its own:
 *   - Cookie store
 *   - Cache
 *   - Connection pool
 *
 * Multiple contexts can exist simultaneously for multi-tab browsing.
 */

/*
 * TODO: Implement these functions
 *
 * vulpes_context_t* vulpes_context_create(void);
 * void vulpes_context_destroy(vulpes_context_t* ctx);
 */

/* ============================================================================
 * Rendering (TODO)
 * ============================================================================ */

/*
 * TODO: Implement these functions
 *
 * vulpes_render_tree_t* vulpes_layout(vulpes_document_t* doc, int width, int height);
 * void vulpes_render_to_context(vulpes_render_tree_t* tree, CGContextRef cgContext);
 */

#ifdef __cplusplus
}
#endif

#endif /* VULPES_H */
