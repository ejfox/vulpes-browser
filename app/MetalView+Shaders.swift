// MetalView+Shaders.swift
// vulpes-browser
//
// Custom shader loading, transitions, and error page effects.

import AppKit
import Metal

// MARK: - Shader Loading Extension

extension MetalView {

    /// Load custom GLSL shader if specified in config
    func loadCustomShader() {
        guard let shaderPath = VulpesConfig.shared.shaderPath else {
            print("MetalView: No custom shader configured, using built-in bloom")
            return
        }

        print("MetalView: Loading custom shader from \(shaderPath)")

        // Get the fullscreen vertex function from our library
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "vertexShaderFullscreen") else {
            print("MetalView: Failed to get fullscreen vertex shader")
            return
        }

        // Use GLSL transpiler to load and compile the shader
        if let pipeline = GLSLTranspiler.createPipeline(
            from: shaderPath,
            device: device,
            vertexFunction: vertexFunction
        ) {
            customShaderPipeline = pipeline
            print("MetalView: Custom shader loaded successfully!")
        } else {
            print("MetalView: Failed to load custom shader, falling back to built-in bloom")
        }
    }

    /// Trigger a page transition effect using TransitionManager
    func triggerPageTransition() {
        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "vertexShaderFullscreen") else {
            return
        }

        TransitionManager.shared.trigger(
            device: device,
            vertexFunction: vertexFunction
        )

        // Keep rendering during transition
        needsDisplay = true
    }

    /// Load and apply an error shader for HTTP errors
    func setErrorShader(forStatus status: Int) {
        currentHttpError = status
        errorShaderStartTime = CFAbsoluteTimeGetCurrent()

        // Pick shader based on error code
        let shaderName: String
        switch status {
        case 404:
            shaderName = "error-404.glsl"
        case 500, 502, 503:
            shaderName = "error-500.glsl"
        default:
            // Use 404 shader for other errors
            shaderName = "error-404.glsl"
        }

        // Look for shader
        let projectPath = "/Users/ejfox/code/vulpes-browser/shaders/\(shaderName)"
        guard FileManager.default.fileExists(atPath: projectPath) else {
            print("MetalView: Error shader not found: \(shaderName)")
            return
        }

        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "vertexShaderFullscreen") else {
            return
        }

        if let pipeline = GLSLTranspiler.createPipeline(
            from: projectPath,
            device: device,
            vertexFunction: vertexFunction
        ) {
            errorShaderPipeline = pipeline
            print("MetalView: Error shader loaded for HTTP \(status)")
        }

        // Keep rendering for continuous animation
        needsDisplay = true
    }

    /// Clear error state (called when navigating away)
    func clearErrorState() {
        currentHttpError = 0
        errorShaderPipeline = nil
    }
}
