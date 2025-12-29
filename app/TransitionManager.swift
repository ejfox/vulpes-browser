// TransitionManager.swift
// vulpes-browser
//
// Manages page transition effects with shader-based visual flair
// Modular, standalone system for 70s wobbles, glitches, and future effects

import Metal
import Foundation

/// Available transition styles for page navigation
enum TransitionStyle: String, CaseIterable {
    case wiggle70s = "70s Dream Sequence"  // Wobbly VHS-style
    case glitch = "Cyberpunk Glitch"       // Datamosh corruption
    case none = "Instant"                  // No transition

    var shaderFilename: String? {
        switch self {
        case .wiggle70s: return "transition-70s.glsl"
        case .glitch: return "transition-glitch.glsl"
        case .none: return nil
        }
    }
}

/// Handles shader-based page transition effects
class TransitionManager {

    // MARK: - Singleton
    static let shared = TransitionManager()

    // MARK: - State
    private(set) var isTransitioning: Bool = false
    private var transitionStartTime: CFAbsoluteTime = 0
    private var currentStyle: TransitionStyle = .none

    /// Duration of transition in seconds
    var transitionDuration: CFAbsoluteTime = 0.6

    /// Current shader pipeline (nil when not transitioning)
    private(set) var shaderPipeline: MTLRenderPipelineState?

    /// Reference to Metal device (set during first transition)
    private var device: MTLDevice?

    // MARK: - Configuration

    /// Whether transitions are enabled
    var transitionsEnabled: Bool = true

    /// Weight for random style selection (0.0 = always wiggle, 1.0 = always glitch)
    var glitchProbability: Double = 0.3

    // MARK: - Transition Control

    /// Trigger a page transition effect
    /// - Parameters:
    ///   - style: The transition style (or nil for random selection)
    ///   - device: Metal device for shader compilation
    ///   - vertexFunction: The fullscreen vertex function
    func trigger(
        style: TransitionStyle? = nil,
        device: MTLDevice,
        vertexFunction: MTLFunction
    ) {
        guard transitionsEnabled else { return }

        self.device = device

        // Select style (random if not specified)
        let selectedStyle: TransitionStyle
        if let style = style, style != .none {
            selectedStyle = style
        } else {
            // Random selection based on probability
            selectedStyle = Double.random(in: 0...1) < glitchProbability ? .glitch : .wiggle70s
        }

        // Load shader
        guard loadShader(style: selectedStyle, device: device, vertexFunction: vertexFunction) else {
            print("TransitionManager: Failed to load shader, skipping transition")
            return
        }

        currentStyle = selectedStyle
        isTransitioning = true
        transitionStartTime = CFAbsoluteTimeGetCurrent()

        print("TransitionManager: Started \(selectedStyle.rawValue) transition")
    }

    /// Get current transition progress (0.0 to 1.0)
    /// Returns the normalized time within the transition
    func currentProgress() -> Float {
        guard isTransitioning else { return 0.0 }

        let elapsed = CFAbsoluteTimeGetCurrent() - transitionStartTime
        let progress = elapsed / transitionDuration

        // Check if transition is complete
        if progress >= 1.0 {
            endTransition()
            return 0.0
        }

        return Float(progress)
    }

    /// Get iTime value for shader (peaks at 0.5 for smooth in-out)
    func shaderTime() -> Float {
        let progress = currentProgress()
        // Map 0->1 progress to 0->1->0 for symmetric effect
        // Use sine curve for smooth easing
        return progress
    }

    /// Check if transition should still be rendered
    func shouldRender() -> Bool {
        if !isTransitioning { return false }

        // Update and check if complete
        _ = currentProgress()
        return isTransitioning
    }

    /// Manually end the transition
    func endTransition() {
        isTransitioning = false
        currentStyle = .none
        shaderPipeline = nil
        print("TransitionManager: Transition complete")
    }

    // MARK: - Shader Loading

    private func loadShader(
        style: TransitionStyle,
        device: MTLDevice,
        vertexFunction: MTLFunction
    ) -> Bool {
        guard let filename = style.shaderFilename else { return false }

        // Look for shader in multiple locations
        var shaderPath: String?

        // 1. App bundle
        let baseName = filename.replacingOccurrences(of: ".glsl", with: "")
        if let bundlePath = Bundle.main.path(forResource: baseName, ofType: "glsl") {
            shaderPath = bundlePath
        }

        // 2. Project shaders folder (development)
        if shaderPath == nil {
            let projectPath = "/Users/ejfox/code/vulpes-browser/shaders/\(filename)"
            if FileManager.default.fileExists(atPath: projectPath) {
                shaderPath = projectPath
            }
        }

        // 3. User config folder
        if shaderPath == nil {
            let configPath = NSHomeDirectory() + "/.config/vulpes/shaders/\(filename)"
            if FileManager.default.fileExists(atPath: configPath) {
                shaderPath = configPath
            }
        }

        guard let path = shaderPath else {
            print("TransitionManager: Shader not found: \(filename)")
            return false
        }

        print("TransitionManager: Loading shader from \(path)")

        // Compile shader
        if let pipeline = GLSLTranspiler.createPipeline(
            from: path,
            device: device,
            vertexFunction: vertexFunction
        ) {
            shaderPipeline = pipeline
            return true
        }

        return false
    }

    // MARK: - Style Cycling

    /// Get next style in the rotation (for testing)
    func nextStyle(after style: TransitionStyle) -> TransitionStyle {
        let styles = TransitionStyle.allCases.filter { $0 != .none }
        guard let currentIndex = styles.firstIndex(of: style) else {
            return styles.first ?? .wiggle70s
        }
        let nextIndex = (currentIndex + 1) % styles.count
        return styles[nextIndex]
    }
}

// MARK: - Notification for Transition Events

extension Notification.Name {
    static let transitionStarted = Notification.Name("transitionStarted")
    static let transitionEnded = Notification.Name("transitionEnded")
}
