//! Vulpes Browser - Build Configuration
//!
//! This build file configures libvulpes as a static library with C ABI,
//! intended for consumption by a Swift/macOS application.
//!
//! Build targets:
//!   - libvulpes.a: Static library for linking into Swift app
//!
//! Usage:
//!   zig build              # Build the library
//!   zig build -Doptimize=ReleaseSafe  # Build optimized
//!
//! Note: This uses Zig 0.15+ build API with addLibrary() instead of
//! the deprecated addStaticLibrary().
//!

const std = @import("std");

pub fn build(b: *std.Build) void {
    // =========================================================================
    // Target Configuration
    // =========================================================================
    // Default to native target. The Swift app will link this library,
    // so we need to ensure ABI compatibility with Apple's toolchain.
    // We use standardTargetOptions without defaults to let the build system
    // pick up the correct macOS SDK paths and frameworks.
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});

    // =========================================================================
    // Static Library: libvulpes
    // =========================================================================
    // Build as a static library with C ABI exports.
    // This allows Swift to call into our Zig code via the C header (vulpes.h).
    //
    // In Zig 0.15+, we use addLibrary() with linkage option instead of
    // the deprecated addStaticLibrary().
    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "vulpes",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
            // Link libc for standard C interop
            .link_libc = true,
        }),
    });

    // =========================================================================
    // macOS Framework Linking
    // =========================================================================
    // Security.framework is required for TLS certificate verification.
    // Zig's std.http.Client can use system certificate stores, but on macOS
    // we need Security.framework to access the keychain and trusted roots.
    //
    // This enables proper HTTPS connections without bundling our own CA certs.
    lib.linkFramework("Security");

    // CoreFoundation is often needed alongside Security.framework
    // for CFData, CFString, and other types used in certificate APIs.
    lib.linkFramework("CoreFoundation");

    // =========================================================================
    // Header Generation
    // =========================================================================
    // Install the C header so Swift can import it.
    // The header is manually maintained in src/vulpes.h to ensure
    // clean Swift interop with proper nullability annotations.
    b.installFile("src/vulpes.h", "include/vulpes.h");

    // Install the built library
    b.installArtifact(lib);

    // =========================================================================
    // CLI Test Executable
    // =========================================================================
    // Run with: zig build run -- https://example.com
    const exe = b.addExecutable(.{
        .name = "vulpes-cli",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run CLI test");
    run_step.dependOn(&run_cmd.step);

    // =========================================================================
    // Unit Tests
    // =========================================================================
    // Run with: zig build test
    const lib_unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
}
