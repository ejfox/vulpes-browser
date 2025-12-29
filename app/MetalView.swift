// MetalView.swift
// vulpes-browser
//
// NSView subclass that handles all Metal rendering for the browser
//
// Architecture Note:
// This view receives render commands from libvulpes and draws them using Metal.
// The glyph atlas (texture containing pre-rendered glyphs) is managed by libvulpes
// and shared with this view for text rendering.
//
// Rendering Pipeline:
// 1. libvulpes processes input and layout
// 2. libvulpes generates render commands (draw rect, draw glyph, etc.)
// 3. Swift bridge marshals commands to this view
// 4. MetalView batches commands into Metal draw calls
// 5. CAMetalLayer presents the frame

import AppKit
import CoreText
import Metal
import QuartzCore
import simd

// MARK: - Vertex Data Structures

// Must match Shaders.metal Vertex struct layout
struct Vertex {
    var position: SIMD2<Float>  // Pixel coordinates
    var texCoord: SIMD2<Float>  // UV coordinates (0-1)
    var color: SIMD4<Float>     // RGBA color
}

// Must match Shaders.metal Uniforms struct
struct Uniforms {
    var viewportSize: SIMD2<Float>
}

// For custom GLSL shaders (Ghostty/Shadertoy compatibility)
struct PostProcessUniforms {
    var iResolution: SIMD2<Float>
    var iTime: Float
    var _padding: Float = 0  // Align to 16 bytes
}

class MetalView: NSView {

    // MARK: - Metal Infrastructure

    // Core Metal objects - created once, reused every frame
    private var device: MTLDevice!
    private var commandQueue: MTLCommandQueue!

    // Access the layer as CAMetalLayer
    private var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    // Render pipelines for different draw modes
    private var solidPipelineState: MTLRenderPipelineState!
    private var glyphPipelineState: MTLRenderPipelineState!
    private var particlePipelineState: MTLRenderPipelineState!  // Additive blending for particles
    private var glowPipelineState: MTLRenderPipelineState!      // Additive blending for link glow
    private var bloomPipelineState: MTLRenderPipelineState!     // Post-process bloom effect
    private var customShaderPipeline: MTLRenderPipelineState?   // Custom GLSL shader (optional)

    // Offscreen render target for two-pass bloom
    private var offscreenTexture: MTLTexture?
    private var bloomEnabled: Bool = true

    // Post-process uniforms for custom shaders (Shadertoy/Ghostty compatibility)
    private var postProcessUniformBuffer: MTLBuffer?
    private var shaderStartTime: CFAbsoluteTime = 0

    // Vertex descriptor for our Vertex struct
    private var vertexDescriptor: MTLVertexDescriptor!

    // Uniform buffer for viewport size
    private var uniformBuffer: MTLBuffer!

    // MARK: - Glyph Atlas
    private var glyphAtlas: GlyphAtlas?

    // MARK: - Content Display
    private var testVertexBuffer: MTLBuffer?
    private var textVertexBuffer: MTLBuffer?
    private var textVertexCount: Int = 0

    // Current displayed text content
    private var displayedText: String = "Loading..."
    private var currentURL: String = ""

    // Extracted links for navigation
    private var extractedLinks: [String] = []

    // Focused link for Tab navigation (-1 = no focus, 0+ = link index)
    private var focusedLinkIndex: Int = -1

    // Link hit boxes for click detection (in point coordinates, not pixels)
    private struct LinkHitBox {
        let linkIndex: Int
        var minX: Float
        var minY: Float
        var maxX: Float
        var maxY: Float
    }
    private var linkHitBoxes: [LinkHitBox] = []

    // Hovered link for glow effect with animation
    private var hoveredLinkIndex: Int = -1
    private var glowIntensity: Float = 0.0        // Current glow level (0-1)
    private var targetGlowIntensity: Float = 0.0  // Target glow level
    private var lastGlowUpdate: CFAbsoluteTime = 0
    private let glowFadeInSpeed: Float = 8.0      // How fast glow appears
    private let glowFadeOutSpeed: Float = 2.5     // How slow glow fades (inertia)

    // MARK: - Particle System
    private struct Particle {
        var x: Float
        var y: Float
        var vx: Float
        var vy: Float
        var life: Float  // 0-1, fades out as it decreases
        var maxLife: Float
        var size: Float
        var r: Float
        var g: Float
        var b: Float
    }
    private var particles: [Particle] = []
    private var particleVertexBuffer: MTLBuffer?
    private var lastParticleUpdate: CFAbsoluteTime = 0
    private let maxParticles = 2000
    private let particleSpawnCount = 150  // Lots of tiny particles per click

    // Callback when URL changes (for updating URL bar)
    var onURLChange: ((String) -> Void)?
    var onContentLoaded: ((String, String) -> Void)?

    // Callback to focus URL bar
    var onRequestURLBarFocus: (() -> Void)?

    // Scroll state
    private var scrollOffset: Float = 0.0
    private var contentHeight: Float = 0.0  // Total height of rendered content
    private var scrollSpeed: Float = 40.0   // Pixels per j/k press (configurable)

    // Key sequence tracking (for gg, etc.)
    private var lastKeyChar: String = ""
    private var lastKeyTime: CFAbsoluteTime = 0

    // Track if fully initialized
    private var isMetalReady = false

    // MARK: - Error Page Effects
    private var errorShaderPipeline: MTLRenderPipelineState?
    private var currentHttpError: Int = 0  // 0 = no error, 404/500/etc = error
    private var errorShaderStartTime: CFAbsoluteTime = 0

    // Simple render timer to ensure the first frame is drawn.
    private var renderTimer: Timer?
    private var configObserver: NSObjectProtocol?

    // MARK: - Layer-Backed View Setup

    // Tell AppKit we want a layer
    override var wantsUpdateLayer: Bool { true }

    // Return CAMetalLayer as our backing layer
    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.device = MTLCreateSystemDefaultDevice()
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        // Transparent for frosted glass effect
        layer.isOpaque = false
        layer.backgroundColor = CGColor.clear
        return layer
    }

    // MARK: - Initialization

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true  // Triggers makeBackingLayer
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        commonInit()
    }

    private func commonInit() {
        // Layer is now ready
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        // Get device from layer
        guard let device = metalLayer.device else {
            fatalError("MetalView: Metal layer has no device")
        }
        self.device = device

        // Create command queue
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("MetalView: Failed to create command queue")
        }
        self.commandQueue = commandQueue

        // Create vertex descriptor
        setupVertexDescriptor()

        // Create render pipelines
        setupRenderPipelines()

        // Create uniform buffer
        setupUniformBuffer()

        // Create glyph atlas for text rendering
        glyphAtlas = GlyphAtlas(device: device)

        // Apply config settings
        applyConfig()

        // Try to load custom GLSL shader if configured
        loadCustomShader()

        configObserver = NotificationCenter.default.addObserver(
            forName: .vulpesConfigReloaded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyConfig()
            self?.loadCustomShader()
            self?.updateTextDisplay()
            self?.needsDisplay = true
        }

        // Record shader start time for iTime uniform
        shaderStartTime = CFAbsoluteTimeGetCurrent()

        isMetalReady = true
        print("MetalView: Metal initialized successfully")
        print("  Device: \(device.name)")
    }

    deinit {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    /// Apply settings from VulpesConfig
    private func applyConfig() {
        let config = VulpesConfig.shared
        bloomEnabled = config.bloomEnabled
        scrollSpeed = config.scrollSpeed

        // Create post-process uniform buffer for custom shaders
        postProcessUniformBuffer = device.makeBuffer(
            length: MemoryLayout<PostProcessUniforms>.stride,
            options: .storageModeShared
        )
        postProcessUniformBuffer?.label = "PostProcess Uniforms"

        print("MetalView: Config applied - bloom=\(bloomEnabled), homePage=\(config.homePage)")
    }

    /// Load custom GLSL shader if specified in config
    private func loadCustomShader() {
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
    private func triggerPageTransition() {
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
    private func setErrorShader(forStatus status: Int) {
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
    private func clearErrorState() {
        currentHttpError = 0
        errorShaderPipeline = nil
    }

    private func setupVertexDescriptor() {
        vertexDescriptor = MTLVertexDescriptor()

        // Position: float2 at offset 0
        vertexDescriptor.attributes[0].format = .float2
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0

        // TexCoord: float2 at offset 8 (after position)
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<SIMD2<Float>>.stride
        vertexDescriptor.attributes[1].bufferIndex = 0

        // Color: float4 at offset 16 (after position + texCoord)
        vertexDescriptor.attributes[2].format = .float4
        vertexDescriptor.attributes[2].offset = MemoryLayout<SIMD2<Float>>.stride * 2
        vertexDescriptor.attributes[2].bufferIndex = 0

        // Stride for the entire vertex
        vertexDescriptor.layouts[0].stride = MemoryLayout<Vertex>.stride
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
    }

    private func setupRenderPipelines() {
        // Load shader library from default bundle
        guard let library = device.makeDefaultLibrary() else {
            fatalError("MetalView: Failed to load shader library. Ensure Shaders.metal is compiled.")
        }

        guard let vertexFunction = library.makeFunction(name: "vertexShader") else {
            fatalError("MetalView: Failed to load vertexShader function")
        }

        guard let fragmentSolid = library.makeFunction(name: "fragmentShaderSolid") else {
            fatalError("MetalView: Failed to load fragmentShaderSolid function")
        }

        guard let fragmentGlyph = library.makeFunction(name: "fragmentShaderGlyph") else {
            fatalError("MetalView: Failed to load fragmentShaderGlyph function")
        }

        // Create solid color pipeline (for rectangles)
        let solidDescriptor = MTLRenderPipelineDescriptor()
        solidDescriptor.label = "Solid Pipeline"
        solidDescriptor.vertexFunction = vertexFunction
        solidDescriptor.fragmentFunction = fragmentSolid
        solidDescriptor.vertexDescriptor = vertexDescriptor
        solidDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Enable alpha blending
        solidDescriptor.colorAttachments[0].isBlendingEnabled = true
        solidDescriptor.colorAttachments[0].rgbBlendOperation = .add
        solidDescriptor.colorAttachments[0].alphaBlendOperation = .add
        solidDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        solidDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        solidDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        solidDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            solidPipelineState = try device.makeRenderPipelineState(descriptor: solidDescriptor)
        } catch {
            fatalError("MetalView: Failed to create solid pipeline state: \(error)")
        }

        // Create glyph pipeline (for textured quads)
        let glyphDescriptor = MTLRenderPipelineDescriptor()
        glyphDescriptor.label = "Glyph Pipeline"
        glyphDescriptor.vertexFunction = vertexFunction
        glyphDescriptor.fragmentFunction = fragmentGlyph
        glyphDescriptor.vertexDescriptor = vertexDescriptor
        glyphDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Same blending for glyphs
        glyphDescriptor.colorAttachments[0].isBlendingEnabled = true
        glyphDescriptor.colorAttachments[0].rgbBlendOperation = .add
        glyphDescriptor.colorAttachments[0].alphaBlendOperation = .add
        glyphDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        glyphDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        glyphDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        glyphDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            glyphPipelineState = try device.makeRenderPipelineState(descriptor: glyphDescriptor)
        } catch {
            fatalError("MetalView: Failed to create glyph pipeline state: \(error)")
        }

        // Create particle pipeline with ADDITIVE blending for glow effect
        guard let fragmentParticle = library.makeFunction(name: "fragmentShaderParticle") else {
            fatalError("MetalView: Failed to load fragmentShaderParticle function")
        }

        let particleDescriptor = MTLRenderPipelineDescriptor()
        particleDescriptor.label = "Particle Pipeline"
        particleDescriptor.vertexFunction = vertexFunction
        particleDescriptor.fragmentFunction = fragmentParticle
        particleDescriptor.vertexDescriptor = vertexDescriptor
        particleDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // ADDITIVE blending: result = src * srcAlpha + dst * 1
        // This makes particles glow by adding light to the scene
        particleDescriptor.colorAttachments[0].isBlendingEnabled = true
        particleDescriptor.colorAttachments[0].rgbBlendOperation = .add
        particleDescriptor.colorAttachments[0].alphaBlendOperation = .add
        particleDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        particleDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        particleDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        particleDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one

        do {
            particlePipelineState = try device.makeRenderPipelineState(descriptor: particleDescriptor)
        } catch {
            fatalError("MetalView: Failed to create particle pipeline state: \(error)")
        }

        // Create glow pipeline - similar additive blending for link hover glow
        guard let fragmentGlow = library.makeFunction(name: "fragmentShaderGlow") else {
            fatalError("MetalView: Failed to load fragmentShaderGlow function")
        }

        let glowDescriptor = MTLRenderPipelineDescriptor()
        glowDescriptor.label = "Glow Pipeline"
        glowDescriptor.vertexFunction = vertexFunction
        glowDescriptor.fragmentFunction = fragmentGlow
        glowDescriptor.vertexDescriptor = vertexDescriptor
        glowDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Additive blending for glow
        glowDescriptor.colorAttachments[0].isBlendingEnabled = true
        glowDescriptor.colorAttachments[0].rgbBlendOperation = .add
        glowDescriptor.colorAttachments[0].alphaBlendOperation = .add
        glowDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        glowDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
        glowDescriptor.colorAttachments[0].destinationRGBBlendFactor = .one
        glowDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .one

        do {
            glowPipelineState = try device.makeRenderPipelineState(descriptor: glowDescriptor)
        } catch {
            fatalError("MetalView: Failed to create glow pipeline state: \(error)")
        }

        // Create bloom post-process pipeline (fullscreen quad with scene texture)
        guard let vertexFullscreen = library.makeFunction(name: "vertexShaderFullscreen") else {
            fatalError("MetalView: Failed to load vertexShaderFullscreen function")
        }

        guard let fragmentBloom = library.makeFunction(name: "fragmentShaderBloom") else {
            fatalError("MetalView: Failed to load fragmentShaderBloom function")
        }

        let bloomDescriptor = MTLRenderPipelineDescriptor()
        bloomDescriptor.label = "Bloom Pipeline"
        bloomDescriptor.vertexFunction = vertexFullscreen
        bloomDescriptor.fragmentFunction = fragmentBloom
        // No vertex descriptor needed - we generate vertices in shader
        bloomDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Normal blending for final output
        bloomDescriptor.colorAttachments[0].isBlendingEnabled = false

        do {
            bloomPipelineState = try device.makeRenderPipelineState(descriptor: bloomDescriptor)
        } catch {
            fatalError("MetalView: Failed to create bloom pipeline state: \(error)")
        }

        print("MetalView: Render pipelines created")
    }

    private func setupUniformBuffer() {
        // Allocate buffer for uniforms
        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<Uniforms>.stride,
            options: .storageModeShared
        )
        uniformBuffer.label = "Uniforms"

        // Initialize with current size
        updateUniforms()
    }

    private func updateUniforms() {
        var uniforms = Uniforms(
            viewportSize: SIMD2<Float>(Float(bounds.width), Float(bounds.height))
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)
    }

    private func setupTestGeometry() {
        // Create a test rectangle to verify the pipeline works
        // This draws a colored quad in the upper-left area
        //
        // Note: Coordinates are in PIXELS (drawable space), not points
        // For Retina displays, multiply point coordinates by contentsScale
        //
        // Will be removed once we have real render commands from libvulpes

        let scale = Float(metalLayer.contentsScale)

        // Rectangle from (50, 50) to (400, 200) in points, scaled for Retina
        let x1 = 50.0 * scale
        let y1 = 50.0 * scale
        let x2 = 400.0 * scale
        let y2 = 200.0 * scale

        let vertices: [Vertex] = [
            // Triangle 1
            Vertex(position: SIMD2<Float>(x1, y1), texCoord: SIMD2<Float>(0, 0), color: SIMD4<Float>(0.4, 0.7, 1.0, 1.0)),
            Vertex(position: SIMD2<Float>(x2, y1), texCoord: SIMD2<Float>(1, 0), color: SIMD4<Float>(0.4, 0.7, 1.0, 1.0)),
            Vertex(position: SIMD2<Float>(x1, y2), texCoord: SIMD2<Float>(0, 1), color: SIMD4<Float>(0.4, 0.7, 1.0, 1.0)),
            // Triangle 2
            Vertex(position: SIMD2<Float>(x2, y1), texCoord: SIMD2<Float>(1, 0), color: SIMD4<Float>(0.4, 0.7, 1.0, 1.0)),
            Vertex(position: SIMD2<Float>(x2, y2), texCoord: SIMD2<Float>(1, 1), color: SIMD4<Float>(0.4, 0.7, 1.0, 1.0)),
            Vertex(position: SIMD2<Float>(x1, y2), texCoord: SIMD2<Float>(0, 1), color: SIMD4<Float>(0.4, 0.7, 1.0, 1.0)),
        ]

        testVertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            options: .storageModeShared
        )
        testVertexBuffer?.label = "Test Vertices"
    }

    // MARK: - URL Loading

    /// Load a URL and display extracted text
    /// - Parameters:
    ///   - url: The URL to load
    ///   - addToHistory: Whether to add this URL to navigation history (default: true)
    func loadURL(_ url: String, addToHistory: Bool = true) {
        // Clear any previous error state
        clearErrorState()

        // Trigger transition effect
        triggerPageTransition()

        // Track in navigation history
        if addToHistory {
            NavigationHistory.shared.push(url)
        }

        currentURL = url
        scrollOffset = 0  // Reset scroll position for new page
        focusedLinkIndex = -1  // Reset link focus
        displayedText = "Loading \(url)..."
        updateTextDisplay()

        // Notify URL bar
        onURLChange?(url)

        // Fetch in background
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let startTime = CFAbsoluteTimeGetCurrent()

            guard let text = VulpesBridge.shared.fetchAndExtract(url: url) else {
                DispatchQueue.main.async {
                    self?.displayedText = "Failed to load \(url)"
                    self?.updateTextDisplay()
                }
                return
            }

            let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
            print("MetalView: Loaded \(url) in \(Int(elapsed))ms - \(text.count) chars")

            DispatchQueue.main.async {
                // Check if this is an HTTP error response
                if text.hasPrefix("HTTP ") {
                    // Parse error code from "HTTP 404" or "HTTP 500"
                    let parts = text.prefix(10).split(separator: " ")
                    if parts.count >= 2, let status = Int(parts[1]) {
                        self?.setErrorShader(forStatus: status)
                    }
                }

                self?.displayedText = text
                self?.parseLinks(from: text)
                self?.updateTextDisplay()
                self?.onContentLoaded?(url, text)
            }
        }
    }

    func snapshotState() -> (url: String, text: String, scrollOffset: Float) {
        return (currentURL, displayedText, scrollOffset)
    }

    func loadTabContent(url: String, text: String, scrollOffset: Float) {
        currentURL = url
        displayedText = text
        self.scrollOffset = scrollOffset
        focusedLinkIndex = -1
        parseLinks(from: text)
        updateTextDisplay()
        onURLChange?(url)
        needsDisplay = true
    }

    /// Go back in navigation history
    func goBack() {
        guard let url = NavigationHistory.shared.goBack() else {
            print("MetalView: Can't go back - at start of history")
            return
        }
        loadURL(url, addToHistory: false)
    }

    /// Go forward in navigation history
    func goForward() {
        guard let url = NavigationHistory.shared.goForward() else {
            print("MetalView: Can't go forward - at end of history")
            return
        }
        loadURL(url, addToHistory: false)
    }

    /// Parse links from the "Links:" section of extracted text
    private func parseLinks(from text: String) {
        extractedLinks = []

        // Find the Links: section
        guard let linksRange = text.range(of: "---\nLinks:\n") else {
            return
        }

        let linksSection = String(text[linksRange.upperBound...])

        // Parse each line like "[1] https://..."
        for line in linksSection.components(separatedBy: "\n") {
            // Skip empty lines
            guard !line.isEmpty else { continue }

            // Extract URL after "] "
            if let bracketEnd = line.firstIndex(of: "]"),
               let spaceAfter = line.index(bracketEnd, offsetBy: 1, limitedBy: line.endIndex),
               line[spaceAfter] == " " {
                let urlStart = line.index(after: spaceAfter)
                let url = String(line[urlStart...])
                extractedLinks.append(url)
            }
        }

        print("MetalView: Parsed \(extractedLinks.count) links")
    }

    /// Update the text vertex buffer with current displayedText
    private func updateTextDisplay() {
        guard let atlas = glyphAtlas else { return }

        let scale = CGFloat(metalLayer.contentsScale)
        let fontSize: CGFloat = 16.0 * scale
        let font = CTFontCreateWithName("SF Pro Text" as CFString, fontSize, nil)
        let lineHeight: Float = Float(fontSize * 1.4)

        let text = displayedText
        let chars = Array(text.utf16)
        guard !chars.isEmpty else {
            textVertexCount = 0
            return
        }

        let monoFont = CTFontCreateWithName("SF Mono" as CFString, fontSize, nil)
        let h1Scale: CGFloat = 1.8
        let h2Scale: CGFloat = 1.5
        let h3Scale: CGFloat = 1.3
        let h4Scale: CGFloat = 1.15
        let h1Font = CTFontCreateWithName("SF Pro Text" as CFString, fontSize * h1Scale, nil)
        let h2Font = CTFontCreateWithName("SF Pro Text" as CFString, fontSize * h2Scale, nil)
        let h3Font = CTFontCreateWithName("SF Pro Text" as CFString, fontSize * h3Scale, nil)
        let h4Font = CTFontCreateWithName("SF Pro Text" as CFString, fontSize * h4Scale, nil)

        var glyphsNormal = [CGGlyph](repeating: 0, count: chars.count)
        var glyphsMono = [CGGlyph](repeating: 0, count: chars.count)
        var glyphsH1 = [CGGlyph](repeating: 0, count: chars.count)
        var glyphsH2 = [CGGlyph](repeating: 0, count: chars.count)
        var glyphsH3 = [CGGlyph](repeating: 0, count: chars.count)
        var glyphsH4 = [CGGlyph](repeating: 0, count: chars.count)
        // Note: mapped may be false if some chars (like control chars) can't be mapped
        // We continue anyway and skip unmappable glyphs
        _ = CTFontGetGlyphsForCharacters(font, chars, &glyphsNormal, chars.count)
        _ = CTFontGetGlyphsForCharacters(monoFont, chars, &glyphsMono, chars.count)
        _ = CTFontGetGlyphsForCharacters(h1Font, chars, &glyphsH1, chars.count)
        _ = CTFontGetGlyphsForCharacters(h2Font, chars, &glyphsH2, chars.count)
        _ = CTFontGetGlyphsForCharacters(h3Font, chars, &glyphsH3, chars.count)
        _ = CTFontGetGlyphsForCharacters(h4Font, chars, &glyphsH4, chars.count)

        let spaceChar: [UniChar] = [0x0020]
        var normalSpaceGlyph: CGGlyph = 0
        var monoSpaceGlyph: CGGlyph = 0
        var h1SpaceGlyph: CGGlyph = 0
        var h2SpaceGlyph: CGGlyph = 0
        var h3SpaceGlyph: CGGlyph = 0
        var h4SpaceGlyph: CGGlyph = 0
        _ = CTFontGetGlyphsForCharacters(font, spaceChar, &normalSpaceGlyph, 1)
        _ = CTFontGetGlyphsForCharacters(monoFont, spaceChar, &monoSpaceGlyph, 1)
        _ = CTFontGetGlyphsForCharacters(h1Font, spaceChar, &h1SpaceGlyph, 1)
        _ = CTFontGetGlyphsForCharacters(h2Font, spaceChar, &h2SpaceGlyph, 1)
        _ = CTFontGetGlyphsForCharacters(h3Font, spaceChar, &h3SpaceGlyph, 1)
        _ = CTFontGetGlyphsForCharacters(h4Font, spaceChar, &h4SpaceGlyph, 1)

        var vertices: [Vertex] = []
        vertices.reserveCapacity(chars.count * 6)

        let margin: Float = Float(20.0 * scale)
        let quoteIndent: Float = Float(24.0 * scale)
        let viewportWidth: Float = Float(bounds.width * scale) - margin * 2
        let targetLineWidth = VulpesConfig.shared.readableLineWidth
        let contentWidth: Float
        if targetLineWidth <= 0 {
            contentWidth = viewportWidth
        } else if let spaceEntry = atlas.entry(for: normalSpaceGlyph, font: font) {
            let readableWidth = Float(spaceEntry.advance) * max(20.0, targetLineWidth)
            contentWidth = min(viewportWidth, readableWidth)
        } else {
            contentWidth = viewportWidth
        }
        var quoteDepth: Int = 0
        func lineStartX() -> Float {
            margin + quoteIndent * Float(quoteDepth)
        }
        func lineMaxX() -> Float {
            let maxX = margin + contentWidth
            return max(maxX, lineStartX() + 1.0)
        }

        func headingFont(for level: Int, h1: CTFont, h2: CTFont, h3: CTFont, h4: CTFont) -> CTFont {
            switch level {
            case 1:
                return h1
            case 2:
                return h2
            case 3:
                return h3
            default:
                return h4
            }
        }

        func headingGlyph(for level: Int, h1: [CGGlyph], h2: [CGGlyph], h3: [CGGlyph], h4: [CGGlyph], index: Int) -> CGGlyph {
            switch level {
            case 1:
                return h1[index]
            case 2:
                return h2[index]
            case 3:
                return h3[index]
            default:
                return h4[index]
            }
        }

        func headingSpaceGlyph(for level: Int, h1: CGGlyph, h2: CGGlyph, h3: CGGlyph, h4: CGGlyph) -> CGGlyph {
            switch level {
            case 1:
                return h1
            case 2:
                return h2
            case 3:
                return h3
            default:
                return h4
            }
        }
        var penX: Float = lineStartX()
        var penY: Float = margin + Float(fontSize)
        let baseLineHeight: Float = lineHeight
        let h1LineHeight: Float = lineHeight * Float(h1Scale)
        let h2LineHeight: Float = lineHeight * Float(h2Scale)
        let h3LineHeight: Float = lineHeight * Float(h3Scale)
        let h4LineHeight: Float = lineHeight * Float(h4Scale)
        var currentLineHeight: Float = baseLineHeight
        var extraSpacingAfterHeading: Float = 0

        // Apply scroll offset (negative = content moves up)
        let scrollAdjust = -scrollOffset * Float(scale)

        // Colors
        let normalColor = SIMD4<Float>(0.9, 0.9, 0.9, 1.0)
        let linkColor = SIMD4<Float>(0.4, 0.6, 1.0, 1.0)  // Traditional blue
        let focusedLinkColor = SIMD4<Float>(1.0, 0.8, 0.2, 1.0)  // Gold/yellow for focus
        var currentColor = normalColor
        var currentLinkIndex = -1  // Track which link we're in

        // Track link hit boxes
        linkHitBoxes = []
        var currentLinkHitBox: LinkHitBox? = nil

        let linkStart: UInt16 = 0x0001
        let linkEnd: UInt16 = 0x0002
        let preStart: UInt16 = 0x0003
        let preEnd: UInt16 = 0x0004
        let emphStart: UInt16 = 0x0011
        let emphEnd: UInt16 = 0x0012
        let strongStart: UInt16 = 0x0013
        let strongEnd: UInt16 = 0x0014
        let codeStart: UInt16 = 0x0015
        let codeEnd: UInt16 = 0x0016
        let quoteStart: UInt16 = 0x0017
        let quoteEnd: UInt16 = 0x0018
        let h1Start: UInt16 = 0x0019
        let h2Start: UInt16 = 0x001A
        let h3Start: UInt16 = 0x001B
        let h4Start: UInt16 = 0x001C
        let headingEnd: UInt16 = 0x001D

        var inPre = false
        var inLink = false
        var inEmphasis = false
        var inStrong = false
        var inCode = false
        var headingLevel: Int = 0
        var pendingEntries: [GlyphAtlas.GlyphEntry] = []
        pendingEntries.reserveCapacity(32)
        var pendingWidth: Float = 0

        func updateCurrentColor() {
            var base = inLink ? linkColor : normalColor
            if inLink && currentLinkIndex == focusedLinkIndex {
                base = focusedLinkColor
            }
            if headingLevel > 0 && !inLink {
                base = SIMD4<Float>(1.0, 1.0, 1.0, base.w)
            }

            if inStrong {
                base = SIMD4<Float>(
                    min(base.x * 1.15, 1.0),
                    min(base.y * 1.15, 1.0),
                    min(base.z * 1.15, 1.0),
                    base.w
                )
            }
            if inEmphasis {
                base = SIMD4<Float>(base.x * 0.9, base.y * 0.9, base.z * 0.9, base.w)
            }
            if inCode {
                base = SIMD4<Float>(base.x * 0.95, base.y * 0.95, base.z * 0.95, base.w)
            }

            currentColor = base
        }

        func appendGlyph(_ entry: GlyphAtlas.GlyphEntry, color: SIMD4<Float>) {
            // Position glyph relative to baseline (penY)
            // bearing.y is offset from baseline to bottom of glyph (negative for descenders)
            // In Y-down coords: top = baseline - (bearing.y + height), bottom = baseline - bearing.y
            let x1 = penX + Float(entry.bearing.x)
            let y1 = penY - Float(entry.bearing.y) - Float(entry.size.height) + scrollAdjust  // top
            let x2 = x1 + Float(entry.size.width)
            let y2 = penY - Float(entry.bearing.y) + scrollAdjust  // bottom (at baseline for non-descenders)

            let u0 = Float(entry.uvRect.minX)
            let u1 = Float(entry.uvRect.maxX)
            let v0 = Float(entry.uvRect.maxY)
            let v1 = Float(entry.uvRect.minY)

            vertices.append(Vertex(position: SIMD2<Float>(x1, y1), texCoord: SIMD2<Float>(u0, v0), color: color))
            vertices.append(Vertex(position: SIMD2<Float>(x2, y1), texCoord: SIMD2<Float>(u1, v0), color: color))
            vertices.append(Vertex(position: SIMD2<Float>(x1, y2), texCoord: SIMD2<Float>(u0, v1), color: color))
            vertices.append(Vertex(position: SIMD2<Float>(x2, y1), texCoord: SIMD2<Float>(u1, v0), color: color))
            vertices.append(Vertex(position: SIMD2<Float>(x2, y2), texCoord: SIMD2<Float>(u1, v1), color: color))
            vertices.append(Vertex(position: SIMD2<Float>(x1, y2), texCoord: SIMD2<Float>(u0, v1), color: color))

            // Expand link hit box if we're in a link
            if currentLinkHitBox != nil {
                // Use positions without scroll adjust for hit testing
                let hitX1 = penX + Float(entry.bearing.x)
                let hitY1 = penY - Float(entry.bearing.y) - Float(entry.size.height)
                let hitX2 = hitX1 + Float(entry.size.width)
                let hitY2 = penY - Float(entry.bearing.y)

                currentLinkHitBox!.minX = min(currentLinkHitBox!.minX, hitX1)
                currentLinkHitBox!.minY = min(currentLinkHitBox!.minY, hitY1)
                currentLinkHitBox!.maxX = max(currentLinkHitBox!.maxX, hitX2)
                currentLinkHitBox!.maxY = max(currentLinkHitBox!.maxY, hitY2)
            }

            penX += Float(entry.advance)
        }

        func flushPendingWord() {
            guard pendingWidth > 0 else { return }

            if penX + pendingWidth > lineMaxX() && penX > lineStartX() {
                penX = lineStartX()
                penY += currentLineHeight
            }

            for entry in pendingEntries {
                appendGlyph(entry, color: currentColor)
            }

            pendingEntries.removeAll(keepingCapacity: true)
            pendingWidth = 0
        }

        for i in 0..<chars.count {
            let char = chars[i]

            if char == linkStart {
                flushPendingWord()
                currentLinkIndex += 1
                inLink = true
                updateCurrentColor()
                // Start tracking hit box for this link
                currentLinkHitBox = LinkHitBox(
                    linkIndex: currentLinkIndex,
                    minX: Float.greatestFiniteMagnitude,
                    minY: Float.greatestFiniteMagnitude,
                    maxX: -Float.greatestFiniteMagnitude,
                    maxY: -Float.greatestFiniteMagnitude
                )
                continue
            }
            if char == linkEnd {
                flushPendingWord()
                inLink = false
                updateCurrentColor()
                // Save hit box if we have one
                if var hitBox = currentLinkHitBox {
                    // Convert from pixels to points
                    // Keep in CONTENT SPACE (don't add scrollOffset)
                    // Mouse coords will be converted to content space for comparison
                    hitBox.minX /= Float(scale)
                    hitBox.minY /= Float(scale)
                    hitBox.maxX /= Float(scale)
                    hitBox.maxY /= Float(scale)
                    linkHitBoxes.append(hitBox)
                }
                currentLinkHitBox = nil
                continue
            }
            if char == preStart {
                flushPendingWord()
                inPre = true
                continue
            }
            if char == preEnd {
                flushPendingWord()
                inPre = false
                continue
            }
            if char == h1Start {
                flushPendingWord()
                headingLevel = 1
                currentLineHeight = h1LineHeight
                updateCurrentColor()
                continue
            }
            if char == h2Start {
                flushPendingWord()
                headingLevel = 2
                currentLineHeight = h2LineHeight
                updateCurrentColor()
                continue
            }
            if char == h3Start {
                flushPendingWord()
                headingLevel = 3
                currentLineHeight = h3LineHeight
                updateCurrentColor()
                continue
            }
            if char == h4Start {
                flushPendingWord()
                headingLevel = 4
                currentLineHeight = h4LineHeight
                updateCurrentColor()
                continue
            }
            if char == headingEnd {
                flushPendingWord()
                headingLevel = 0
                currentLineHeight = baseLineHeight
                extraSpacingAfterHeading = baseLineHeight * 0.25
                updateCurrentColor()
                continue
            }
            if char == emphStart {
                flushPendingWord()
                inEmphasis = true
                updateCurrentColor()
                continue
            }
            if char == emphEnd {
                flushPendingWord()
                inEmphasis = false
                updateCurrentColor()
                continue
            }
            if char == strongStart {
                flushPendingWord()
                inStrong = true
                updateCurrentColor()
                continue
            }
            if char == strongEnd {
                flushPendingWord()
                inStrong = false
                updateCurrentColor()
                continue
            }
            if char == codeStart {
                flushPendingWord()
                inCode = true
                updateCurrentColor()
                continue
            }
            if char == codeEnd {
                flushPendingWord()
                inCode = false
                updateCurrentColor()
                continue
            }
            if char == quoteStart {
                flushPendingWord()
                if penX != lineStartX() {
                    penX = lineStartX()
                    penY += currentLineHeight
                }
                quoteDepth += 1
                penX = lineStartX()
                continue
            }
            if char == quoteEnd {
                flushPendingWord()
                quoteDepth = max(0, quoteDepth - 1)
                penX = lineStartX()
                continue
            }

            // Handle newlines
            if char == 0x000A { // newline
                flushPendingWord()
                penX = lineStartX()
                penY += currentLineHeight + extraSpacingAfterHeading
                extraSpacingAfterHeading = 0
                continue
            }

            let useMono = inPre || inCode
            let isHeading = headingLevel > 0 && !useMono
            let glyph = useMono ? glyphsMono[i] : (isHeading ? headingGlyph(for: headingLevel, h1: glyphsH1, h2: glyphsH2, h3: glyphsH3, h4: glyphsH4, index: i) : glyphsNormal[i])
            let activeFont = useMono ? monoFont : (isHeading ? headingFont(for: headingLevel, h1: h1Font, h2: h2Font, h3: h3Font, h4: h4Font) : font)

            if inPre {
                if char == 0x0009 { // tab
                    if let spaceEntry = atlas.entry(for: monoSpaceGlyph, font: monoFont) {
                        penX += Float(spaceEntry.advance) * 4
                    }
                    continue
                }
                if char == 0x0020 { // space
                    if let spaceEntry = atlas.entry(for: monoSpaceGlyph, font: monoFont) {
                        penX += Float(spaceEntry.advance)
                    }
                    continue
                }
                guard let entry = atlas.entry(for: glyph, font: activeFont) else { continue }
                appendGlyph(entry, color: currentColor)
                continue
            }

            if char == 0x0020 || char == 0x0009 {
                flushPendingWord()
                if penX > lineStartX() {
                    let spaceGlyph = useMono ? monoSpaceGlyph : (isHeading ? headingSpaceGlyph(for: headingLevel, h1: h1SpaceGlyph, h2: h2SpaceGlyph, h3: h3SpaceGlyph, h4: h4SpaceGlyph) : normalSpaceGlyph)
                    if let spaceEntry = atlas.entry(for: spaceGlyph, font: activeFont) {
                        penX += Float(spaceEntry.advance)
                    }
                }
                continue
            }

            guard let entry = atlas.entry(for: glyph, font: activeFont) else { continue }
            pendingEntries.append(entry)
            pendingWidth += Float(entry.advance)
        }

        flushPendingWord()

        // Track content height for scroll bounds
        contentHeight = penY / Float(scale)

        guard !vertices.isEmpty else {
            textVertexCount = 0
            return
        }

        textVertexCount = vertices.count
        textVertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            options: .storageModeShared
        )
        textVertexBuffer?.label = "Text Vertices"

        needsDisplay = true
    }

    // MARK: - View Lifecycle

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        guard isMetalReady else { return }

        // Update drawable size for Retina
        metalLayer.drawableSize = CGSize(
            width: bounds.width * metalLayer.contentsScale,
            height: bounds.height * metalLayer.contentsScale
        )

        print("MetalView: setFrameSize - bounds: \(bounds), drawableSize: \(metalLayer.drawableSize)")

        // Recreate geometry with correct scale
        if bounds.width > 0 && bounds.height > 0 {
            setupTestGeometry()
            updateTextDisplay()
        }

        // Request redraw
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard let window = window, isMetalReady else { return }
        print("MetalView: viewDidMoveToWindow")

        // Update layer scale from window's screen
        if let screen = window.screen {
            metalLayer.contentsScale = screen.backingScaleFactor
        }

        // Set drawable size now that we have real bounds
        metalLayer.drawableSize = CGSize(
            width: bounds.width * metalLayer.contentsScale,
            height: bounds.height * metalLayer.contentsScale
        )

        // Create test geometry
        setupTestGeometry()

        print("MetalView: Ready - bounds: \(bounds), drawableSize: \(metalLayer.drawableSize)")
        startRenderTimer()
        needsDisplay = true
        render()

        // Load initial page from config
        loadURL(VulpesConfig.shared.homePage)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)

        if newWindow == nil {
            stopRenderTimer()
        }
    }

    override var acceptsFirstResponder: Bool {
        // Must accept first responder to receive keyboard events
        return true
    }

    // Called when wantsUpdateLayer is true
    override func updateLayer() {
        render()
    }

    private func startRenderTimer() {
        guard renderTimer == nil else { return }

        renderTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.render()
        }
        renderTimer?.tolerance = 1.0 / 120.0
    }

    private func stopRenderTimer() {
        renderTimer?.invalidate()
        renderTimer = nil
    }

    // MARK: - Rendering
    //
    // Render Command Types (from libvulpes):
    // - Clear: Fill background with color
    // - Rect: Draw a solid rectangle (selections, cursors, etc.)
    // - Glyph: Draw a single glyph from the atlas
    // - GlyphRun: Draw multiple glyphs (batched for efficiency)
    //
    // Batching Strategy:
    // - Group consecutive glyphs into single draw calls
    // - Minimize state changes (texture binds, color changes)
    // - Use instanced rendering for repeated elements

    override func draw(_ dirtyRect: NSRect) {
        render()
    }

    /// Ensure offscreen texture exists and matches drawable size
    private func ensureOffscreenTexture(size: CGSize) {
        let width = Int(size.width)
        let height = Int(size.height)

        // Check if we need to recreate
        if let existing = offscreenTexture,
           existing.width == width && existing.height == height {
            return
        }

        // Create new offscreen texture
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private

        offscreenTexture = device.makeTexture(descriptor: descriptor)
        offscreenTexture?.label = "Offscreen Scene Texture"
    }

    func render() {
        guard isMetalReady else { return }

        // Ensure we have a valid drawable size
        let drawableSize = metalLayer.drawableSize
        guard drawableSize.width > 0 && drawableSize.height > 0 else {
            print("MetalView: Invalid drawable size: \(drawableSize)")
            return
        }

        // Get the next drawable from the Metal layer
        guard let drawable = metalLayer.nextDrawable() else {
            print("MetalView: No drawable available")
            return
        }

        var uniforms = Uniforms(
            viewportSize: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

        // Create a command buffer for this frame
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("MetalView: Failed to create command buffer")
            return
        }

        // Update animations
        let now = CFAbsoluteTimeGetCurrent()
        if lastParticleUpdate > 0 {
            let deltaTime = Float(now - lastParticleUpdate)
            let cappedDelta = min(deltaTime, 0.1)  // Cap to avoid huge jumps
            updateParticles(deltaTime: cappedDelta)
            updateGlowAnimation(deltaTime: cappedDelta)
        }
        lastParticleUpdate = now

        // ============================================================
        // PASS 1: Render scene to offscreen texture (if bloom enabled)
        // ============================================================
        let targetTexture: MTLTexture
        if bloomEnabled {
            ensureOffscreenTexture(size: drawableSize)
            guard let offscreen = offscreenTexture else {
                print("MetalView: Failed to create offscreen texture")
                return
            }
            targetTexture = offscreen
        } else {
            targetTexture = drawable.texture
        }

        // Create render pass for scene
        let scenePassDescriptor = MTLRenderPassDescriptor()
        scenePassDescriptor.colorAttachments[0].texture = targetTexture
        scenePassDescriptor.colorAttachments[0].loadAction = .clear
        scenePassDescriptor.colorAttachments[0].storeAction = .store
        scenePassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0
        )

        guard let sceneEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: scenePassDescriptor) else {
            print("MetalView: Failed to create scene encoder")
            return
        }

        // Set the solid color pipeline
        sceneEncoder.setRenderPipelineState(solidPipelineState)
        sceneEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)

        // Draw glow effect BEHIND text (if hovering a link)
        let (glowBuffer, glowCount) = buildGlowVertices()
        if let glowBuffer = glowBuffer, glowCount > 0 {
            sceneEncoder.setRenderPipelineState(glowPipelineState)
            sceneEncoder.setVertexBuffer(glowBuffer, offset: 0, index: 0)
            sceneEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            sceneEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: glowCount)
        }

        // Draw text content using glyph atlas
        if let atlas = glyphAtlas, let textBuffer = textVertexBuffer, textVertexCount > 0 {
            sceneEncoder.setRenderPipelineState(glyphPipelineState)
            sceneEncoder.setVertexBuffer(textBuffer, offset: 0, index: 0)
            sceneEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            sceneEncoder.setFragmentTexture(atlas.texture, index: 0)
            sceneEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: textVertexCount)
        }

        // Draw particles ON TOP of text (additive blending for glow)
        let (particleBuffer, particleCount) = buildParticleVertices()
        if let particleBuffer = particleBuffer, particleCount > 0 {
            sceneEncoder.setRenderPipelineState(particlePipelineState)
            sceneEncoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
            sceneEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            sceneEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: particleCount)
        }

        sceneEncoder.endEncoding()

        // ============================================================
        // PASS 2: Apply post-process shader (bloom or custom GLSL)
        // ============================================================
        if bloomEnabled {
            let bloomPassDescriptor = MTLRenderPassDescriptor()
            bloomPassDescriptor.colorAttachments[0].texture = drawable.texture
            bloomPassDescriptor.colorAttachments[0].loadAction = .clear
            bloomPassDescriptor.colorAttachments[0].storeAction = .store
            bloomPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
                red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0
            )

            guard let bloomEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: bloomPassDescriptor) else {
                print("MetalView: Failed to create bloom encoder")
                return
            }

            // Check if transition is active
            let transitionManager = TransitionManager.shared
            let isTransitioning = transitionManager.shouldRender()

            // Update post-process uniforms
            if let uniformBuffer = postProcessUniformBuffer {
                var postUniforms: PostProcessUniforms

                if isTransitioning {
                    // Use transition-specific time (0 to 1 progress)
                    postUniforms = PostProcessUniforms(
                        iResolution: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
                        iTime: transitionManager.shaderTime()
                    )
                    // Keep rendering during transition
                    DispatchQueue.main.async { [weak self] in
                        self?.needsDisplay = true
                    }
                } else {
                    // Normal shader time
                    postUniforms = PostProcessUniforms(
                        iResolution: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
                        iTime: Float(now - shaderStartTime)
                    )
                }
                memcpy(uniformBuffer.contents(), &postUniforms, MemoryLayout<PostProcessUniforms>.stride)
                bloomEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            }

            // Select shader pipeline: transition > error > custom > bloom
            if isTransitioning, let transitionPipeline = transitionManager.shaderPipeline {
                bloomEncoder.setRenderPipelineState(transitionPipeline)
            } else if currentHttpError != 0, let errorPipeline = errorShaderPipeline {
                // Error shader - use error-specific time for continuous animation
                var errorUniforms = PostProcessUniforms(
                    iResolution: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height)),
                    iTime: Float(now - errorShaderStartTime)
                )
                memcpy(uniformBuffer.contents(), &errorUniforms, MemoryLayout<PostProcessUniforms>.stride)
                bloomEncoder.setRenderPipelineState(errorPipeline)
                // Keep rendering for continuous animation
                DispatchQueue.main.async { [weak self] in
                    self?.needsDisplay = true
                }
            } else if let customPipeline = customShaderPipeline {
                bloomEncoder.setRenderPipelineState(customPipeline)
            } else {
                bloomEncoder.setRenderPipelineState(bloomPipelineState)
            }

            bloomEncoder.setFragmentTexture(offscreenTexture, index: 0)
            // Draw fullscreen quad (6 vertices generated in shader)
            bloomEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

            bloomEncoder.endEncoding()
        }

        // Present the drawable
        commandBuffer.present(drawable)

        // Submit to GPU
        commandBuffer.commit()
    }

    // MARK: - Keyboard Event Handling
    //
    // Key Code Translation:
    // macOS uses virtual key codes (hardware-independent)
    // libvulpes uses its own key code enum
    // This view translates between them
    //
    // Special handling needed for:
    // - Escape (exit modes, cancel operations)
    // - Return/Enter (confirm, activate)
    // - Tab (focus navigation)
    // - Arrow keys (navigation)
    // - Modifier combinations (Cmd+K for command palette, etc.)

    override func keyDown(with event: NSEvent) {
        // Don't call super - we handle all keys ourselves
        // This prevents the system beep

        if event.modifierFlags.contains(.command) {
            return
        }

        guard let chars = event.charactersIgnoringModifiers else { return }

        switch chars {
        case "j":
            scrollBy(lines: 1)
            lastKeyChar = ""
        case "k":
            scrollBy(lines: -1)
            lastKeyChar = ""
        case "d":
            // Half page down (Ctrl+D style)
            scrollBy(lines: 10)
            lastKeyChar = ""
        case "u":
            // Half page up (Ctrl+U style)
            scrollBy(lines: -10)
            lastKeyChar = ""
        case "G":
            // Jump to bottom
            scrollToBottom()
            lastKeyChar = ""
        case "\t": // Tab
            if event.modifierFlags.contains(.shift) {
                cycleToPrevLink()
            } else {
                cycleToNextLink()
            }
            lastKeyChar = ""
        case "\r": // Enter/Return
            if focusedLinkIndex >= 0 {
                followLink(number: focusedLinkIndex + 1)
            }
            lastKeyChar = ""
        case "g":
            // gg to jump to top
            let now = CFAbsoluteTimeGetCurrent()
            if lastKeyChar == "g" && (now - lastKeyTime) < 0.5 {
                scrollToTop()
                lastKeyChar = ""
            } else {
                lastKeyChar = "g"
                lastKeyTime = now
            }
        case "/":
            // Focus URL bar (vim-style)
            NotificationCenter.default.post(name: .focusURLBar, object: nil)
            lastKeyChar = ""
        case "b":
            // Go back in history
            goBack()
            lastKeyChar = ""
        case "f":
            // Go forward in history
            goForward()
            lastKeyChar = ""
        default:
            // Check for number keys 1-9 for link navigation
            if let num = Int(chars), num >= 1 && num <= 9 {
                followLink(number: num)
                lastKeyChar = ""
            } else {
                lastKeyChar = ""
                print("MetalView: keyDown - keyCode: \(event.keyCode), characters: \(chars)")
            }
        }

        // Request redraw after input
        needsDisplay = true
    }

    // MARK: - Scrolling

    private func scrollBy(lines: Int) {
        let delta = Float(lines) * scrollSpeed
        scrollOffset = max(0, scrollOffset + delta)

        // Clamp to content bounds
        let maxScroll = max(0, contentHeight - Float(bounds.height) + 40)
        scrollOffset = min(scrollOffset, maxScroll)

        updateTextDisplay()
    }

    private func scrollToTop() {
        scrollOffset = 0
        updateTextDisplay()
    }

    private func scrollToBottom() {
        let maxScroll = max(0, contentHeight - Float(bounds.height) + 40)
        scrollOffset = maxScroll
        updateTextDisplay()
    }

    // MARK: - Particle System

    /// Spawn burst of particles across a rectangular area (link explosion effect)
    private func spawnParticles(at point: CGPoint, color: SIMD3<Float>? = nil) {
        spawnParticlesInArea(
            minX: Float(point.x) - 5,
            minY: Float(point.y) - 5,
            maxX: Float(point.x) + 5,
            maxY: Float(point.y) + 5,
            color: color
        )
    }

    /// Spawn particles across a link's bounding box - letters explode into particles
    private func spawnParticlesFromLink(hitBox: LinkHitBox, color: SIMD3<Float>? = nil) {
        // Adjust for scroll offset
        let minY = hitBox.minY - scrollOffset
        let maxY = hitBox.maxY - scrollOffset

        spawnParticlesInArea(
            minX: hitBox.minX,
            minY: minY,
            maxX: hitBox.maxX,
            maxY: maxY,
            color: color
        )
    }

    /// Core particle spawning - distributes particles across rectangular area
    private func spawnParticlesInArea(minX: Float, minY: Float, maxX: Float, maxY: Float, color: SIMD3<Float>? = nil) {
        let scale = Float(metalLayer.contentsScale)

        // Default to link blue
        let baseColor = color ?? SIMD3<Float>(0.4, 0.6, 1.0)

        // Calculate area for density-based spawning
        let width = (maxX - minX) * scale
        let height = (maxY - minY) * scale
        let area = width * height

        // More particles for larger links (density-based)
        let particleCount = min(maxParticles / 4, max(particleSpawnCount, Int(area / 20)))

        for _ in 0..<particleCount {
            // Random position within the link bounds
            let x = Float.random(in: minX...maxX) * scale
            let y = Float.random(in: minY...maxY) * scale

            // Explode outward from the link - velocity based on position
            let centerX = (minX + maxX) / 2 * scale
            let centerY = (minY + maxY) / 2 * scale

            // Direction away from center
            let dx = x - centerX
            let dy = y - centerY
            let dist = sqrt(dx * dx + dy * dy) + 0.1

            // Slower, more graceful velocity
            let speed = Float.random(in: 60...180) * scale
            let vx = (dx / dist) * speed + Float.random(in: -30...30) * scale
            let vy = (dy / dist) * speed + Float.random(in: -40...40) * scale

            // Always 1px dots
            let size: Float = 1.0 * scale
            // Longer lifetime for graceful fade
            let maxLife = Float.random(in: 0.6...1.4)

            // Color variation
            let colorVariation: Float = 0.12
            let r = baseColor.x + Float.random(in: -colorVariation...colorVariation)
            let g = baseColor.y + Float.random(in: -colorVariation...colorVariation)
            let b = baseColor.z + Float.random(in: -colorVariation...colorVariation)

            let particle = Particle(
                x: x,
                y: y,
                vx: vx,
                vy: vy,
                life: 1.0,
                maxLife: maxLife,
                size: size,
                r: min(1, max(0, r)),
                g: min(1, max(0, g)),
                b: min(1, max(0, b))
            )

            // Maintain max particle count
            if particles.count >= maxParticles {
                particles.removeFirst()
            }
            particles.append(particle)
        }
    }

    /// Update particle physics and remove dead particles
    private func updateParticles(deltaTime: Float) {
        // Gentler gravity for more floaty feel
        let gravity: Float = 40.0 * Float(metalLayer.contentsScale)
        // More drag for graceful slowdown
        let drag: Float = 0.96

        particles = particles.compactMap { p in
            var particle = p

            // Update velocity (gentle gravity + smooth drag)
            particle.vy += gravity * deltaTime
            particle.vx *= pow(drag, deltaTime * 60)  // Frame-rate independent drag
            particle.vy *= pow(drag, deltaTime * 60)

            // Update position
            particle.x += particle.vx * deltaTime
            particle.y += particle.vy * deltaTime

            // Slower life decay for longer-lasting particles
            particle.life -= deltaTime / particle.maxLife

            // Remove dead particles
            if particle.life <= 0 {
                return nil
            }
            return particle
        }
    }

    /// Update glow animation with easing
    private func updateGlowAnimation(deltaTime: Float) {
        let diff = targetGlowIntensity - glowIntensity

        if abs(diff) < 0.001 {
            glowIntensity = targetGlowIntensity
            return
        }

        // Different speeds for fade-in vs fade-out (inertia on fade-out)
        let speed = diff > 0 ? glowFadeInSpeed : glowFadeOutSpeed

        // Quad ease-out for smooth deceleration
        let t = 1.0 - pow(1.0 - min(deltaTime * speed, 1.0), 2.0)
        glowIntensity += diff * Float(t)

        // Clamp
        glowIntensity = max(0, min(1, glowIntensity))
    }

    /// Build vertex buffer for all active particles
    private func buildParticleVertices() -> (MTLBuffer?, Int) {
        guard !particles.isEmpty else { return (nil, 0) }

        var vertices: [Vertex] = []
        vertices.reserveCapacity(particles.count * 6)

        for p in particles {
            // Fade alpha as life decreases
            let alpha = p.life * 0.8

            // Shrink slightly as particle dies
            let sizeMultiplier = 0.5 + (p.life * 0.5)
            let halfSize = p.size * sizeMultiplier

            let x1 = p.x - halfSize
            let y1 = p.y - halfSize
            let x2 = p.x + halfSize
            let y2 = p.y + halfSize

            let color = SIMD4<Float>(p.r, p.g, p.b, alpha)

            // Two triangles for quad - use texCoords for soft edge calculation in shader
            vertices.append(Vertex(position: SIMD2<Float>(x1, y1), texCoord: SIMD2<Float>(0, 0), color: color))
            vertices.append(Vertex(position: SIMD2<Float>(x2, y1), texCoord: SIMD2<Float>(1, 0), color: color))
            vertices.append(Vertex(position: SIMD2<Float>(x1, y2), texCoord: SIMD2<Float>(0, 1), color: color))
            vertices.append(Vertex(position: SIMD2<Float>(x2, y1), texCoord: SIMD2<Float>(1, 0), color: color))
            vertices.append(Vertex(position: SIMD2<Float>(x2, y2), texCoord: SIMD2<Float>(1, 1), color: color))
            vertices.append(Vertex(position: SIMD2<Float>(x1, y2), texCoord: SIMD2<Float>(0, 1), color: color))
        }

        let buffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            options: .storageModeShared
        )
        buffer?.label = "Particle Vertices"

        return (buffer, vertices.count)
    }

    /// Build glow quad for hovered link with animated intensity
    private func buildGlowVertices() -> (MTLBuffer?, Int) {
        // Show glow if we have intensity (allows fade-out after mouse leaves)
        guard glowIntensity > 0.01, hoveredLinkIndex >= 0, hoveredLinkIndex < linkHitBoxes.count else {
            return (nil, 0)
        }

        let hitBox = linkHitBoxes[hoveredLinkIndex]
        let scale = Float(metalLayer.contentsScale)

        // Expand hitbox for glow effect - grows with intensity for "bloom" feel
        let baseGlowPadding: Float = 8.0 * scale
        let maxGlowPadding: Float = 16.0 * scale
        let glowPadding = baseGlowPadding + (maxGlowPadding - baseGlowPadding) * glowIntensity

        let x1 = hitBox.minX * scale - glowPadding
        let y1 = (hitBox.minY - scrollOffset) * scale - glowPadding
        let x2 = hitBox.maxX * scale + glowPadding
        let y2 = (hitBox.maxY - scrollOffset) * scale + glowPadding

        // Glow color - intensity affects alpha with eased curve
        let easedIntensity = glowIntensity * glowIntensity  // Quad ease for smoother ramp
        let color = SIMD4<Float>(0.3, 0.5, 1.0, 0.35 * easedIntensity)

        var vertices: [Vertex] = []
        vertices.append(Vertex(position: SIMD2<Float>(x1, y1), texCoord: SIMD2<Float>(0, 0), color: color))
        vertices.append(Vertex(position: SIMD2<Float>(x2, y1), texCoord: SIMD2<Float>(1, 0), color: color))
        vertices.append(Vertex(position: SIMD2<Float>(x1, y2), texCoord: SIMD2<Float>(0, 1), color: color))
        vertices.append(Vertex(position: SIMD2<Float>(x2, y1), texCoord: SIMD2<Float>(1, 0), color: color))
        vertices.append(Vertex(position: SIMD2<Float>(x2, y2), texCoord: SIMD2<Float>(1, 1), color: color))
        vertices.append(Vertex(position: SIMD2<Float>(x1, y2), texCoord: SIMD2<Float>(0, 1), color: color))

        let buffer = device.makeBuffer(
            bytes: vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            options: .storageModeShared
        )
        buffer?.label = "Glow Vertices"

        return (buffer, vertices.count)
    }

    // MARK: - Link Navigation

    /// Focus the first link (called when Tab from URL bar)
    func focusFirstLink() {
        guard !extractedLinks.isEmpty else { return }
        focusedLinkIndex = 0
        updateTextDisplay()
    }

    /// Focus the last link (called when Shift+Tab from URL bar)
    func focusLastLink() {
        guard !extractedLinks.isEmpty else { return }
        focusedLinkIndex = extractedLinks.count - 1
        updateTextDisplay()
    }

    private func cycleToNextLink() {
        guard !extractedLinks.isEmpty else { return }

        focusedLinkIndex += 1
        if focusedLinkIndex >= extractedLinks.count {
            // Wrap to URL bar
            focusedLinkIndex = -1
            onRequestURLBarFocus?()
            return
        }

        updateTextDisplay()
    }

    private func cycleToPrevLink() {
        guard !extractedLinks.isEmpty else { return }

        focusedLinkIndex -= 1
        if focusedLinkIndex < -1 {
            focusedLinkIndex = extractedLinks.count - 1
        } else if focusedLinkIndex == -1 {
            onRequestURLBarFocus?()
            return
        }

        updateTextDisplay()
    }

    private func followLink(number: Int) {
        let index = number - 1  // Links are 1-indexed
        guard index >= 0 && index < extractedLinks.count else {
            print("MetalView: No link \(number) (have \(extractedLinks.count) links)")
            return
        }

        // Spawn particles from the link (if we have a hit box for it)
        if let hitBox = linkHitBoxes.first(where: { $0.linkIndex == index }) {
            spawnParticlesFromLink(hitBox: hitBox, color: SIMD3<Float>(0.4, 0.6, 1.0))
        }

        var url = extractedLinks[index]

        // Handle relative URLs
        if url.hasPrefix("/") {
            // Construct absolute URL from current page
            if let currentURLObj = URL(string: currentURL),
               let baseURL = URL(string: "/", relativeTo: currentURLObj) {
                url = baseURL.absoluteString.dropLast() + url
            }
        }

        print("MetalView: Following link \(number): \(url)")
        loadURL(url)
    }

    override func keyUp(with event: NSEvent) {
        // TODO: Send key up to libvulpes if needed
        // Most keys don't need keyUp handling for vim-style navigation
    }

    override func flagsChanged(with event: NSEvent) {
        // Handle modifier key changes (Shift, Control, Option, Command)
        // TODO: Track modifier state for libvulpes
    }

    // MARK: - Mouse Event Handling
    //
    // While vulpes is keyboard-driven, mouse support is still useful for:
    // - Clicking links
    // - Selecting text
    // - Scrolling (trackpad)

    override func mouseDown(with event: NSEvent) {
        // Convert to view coordinates (AppKit has origin at bottom-left)
        let point = convert(event.locationInWindow, from: nil)

        // Convert to top-left origin (our rendering coordinate system)
        let x = Float(point.x)
        let y = Float(bounds.height - point.y)

        // Add scroll offset to get content-space Y (hit boxes are stored in content space)
        let contentY = y + scrollOffset

        // Check if click is on a link
        if let hitBox = linkHitBoxes.first(where: { box in
            x >= box.minX && x <= box.maxX && contentY >= box.minY && contentY <= box.maxY
        }) {
            // Focus and follow the link (followLink handles particles now)
            focusedLinkIndex = hitBox.linkIndex
            updateTextDisplay()
            followLink(number: hitBox.linkIndex + 1)
            return
        }

        // No particles for non-link clicks - keep it clean
        // Take focus from URL bar
        window?.makeFirstResponder(self)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let x = Float(point.x)
        let y = Float(bounds.height - point.y)

        // Add scroll offset to get content-space Y (hit boxes are stored in content space)
        let contentY = y + scrollOffset

        // Find which link we're hovering over (if any)
        let newHoveredIndex = linkHitBoxes.firstIndex { box in
            x >= box.minX && x <= box.maxX && contentY >= box.minY && contentY <= box.maxY
        }.map { linkHitBoxes[$0].linkIndex } ?? -1

        // Update hovered link and animate glow
        if newHoveredIndex != hoveredLinkIndex {
            // Only update hoveredLinkIndex when entering a new link
            // Keep old index during fade-out so glow stays on correct link
            if newHoveredIndex >= 0 {
                hoveredLinkIndex = newHoveredIndex
            }
        }

        // Set target glow intensity (animation will interpolate)
        targetGlowIntensity = newHoveredIndex >= 0 ? 1.0 : 0.0

        // Update cursor
        if newHoveredIndex >= 0 {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Remove old tracking areas
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        // Add tracking area for mouse moved events
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }

    override func scrollWheel(with event: NSEvent) {
        // Handle trackpad and mouse wheel scrolling
        var deltaY = Float(event.scrollingDeltaY)

        // For trackpad momentum scrolling, the values are already in points
        // For mouse wheel, they're in lines - scale up
        if !event.hasPreciseScrollingDeltas {
            deltaY *= scrollSpeed
        }

        // Apply scroll (natural scrolling: positive delta = scroll up = content goes down)
        scrollOffset = max(0, scrollOffset - deltaY)

        // Clamp to content bounds
        let maxScroll = max(0, contentHeight - Float(bounds.height) + 40)
        scrollOffset = min(scrollOffset, maxScroll)

        updateTextDisplay()
    }

    // MARK: - Text Input Client
    //
    // TODO: Implement NSTextInputClient for proper text input
    // This is needed for:
    // - International keyboard layouts
    // - IME (Input Method Editor) for CJK languages
    // - Dead keys (compose sequences like Option+E, E for é)
    // - Emoji picker
}

// MARK: - Future Shader Code
//
// The Metal shaders will be simple:
//
// Vertex Shader:
// - Transform 2D positions from pixel space to clip space
// - Pass through UV coordinates for glyph rendering
// - Pass through color
//
// Fragment Shader (Solid):
// - Output the vertex color directly
// - Used for rectangles, selections, cursor
//
// Fragment Shader (Glyph):
// - Sample the glyph atlas texture
// - Alpha is from texture, RGB from vertex color
// - This allows colored text with a grayscale atlas
//
// Shader source will be in a separate .metal file
// or embedded as a string for simplicity
