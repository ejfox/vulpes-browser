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

    // Track if fully initialized
    private var isMetalReady = false

    // Simple render timer to ensure the first frame is drawn.
    private var renderTimer: Timer?

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

        isMetalReady = true
        print("MetalView: Metal initialized successfully")
        print("  Device: \(device.name)")
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
    func loadURL(_ url: String) {
        currentURL = url
        displayedText = "Loading \(url)..."
        updateTextDisplay()

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
                self?.displayedText = text
                self?.updateTextDisplay()
            }
        }
    }

    /// Update the text vertex buffer with current displayedText
    private func updateTextDisplay() {
        guard let atlas = glyphAtlas else { return }

        let scale = CGFloat(metalLayer.contentsScale)
        let fontSize: CGFloat = 16.0 * scale
        let font = CTFontCreateWithName("SF Pro Text" as CFString, fontSize, nil)
        let lineHeight: Float = Float(fontSize * 1.4)

        // Use first 2000 chars to avoid huge vertex buffers
        let text = String(displayedText.prefix(2000))
        let chars = Array(text.utf16)
        guard !chars.isEmpty else {
            textVertexCount = 0
            return
        }

        var glyphs = [CGGlyph](repeating: 0, count: chars.count)
        let mapped = CTFontGetGlyphsForCharacters(font, chars, &glyphs, chars.count)
        guard mapped else { return }

        var vertices: [Vertex] = []
        vertices.reserveCapacity(glyphs.count * 6)

        let margin: Float = Float(20.0 * scale)
        let maxWidth: Float = Float(bounds.width * scale) - margin * 2
        var penX: Float = margin
        var penY: Float = margin + Float(fontSize)

        let color = SIMD4<Float>(0.9, 0.9, 0.9, 1.0)

        for (i, glyph) in glyphs.enumerated() {
            // Handle newlines
            if chars[i] == 0x000A { // newline
                penX = margin
                penY += lineHeight
                continue
            }

            guard let entry = atlas.entry(for: glyph, font: font) else { continue }

            // Word wrap
            if penX + Float(entry.advance) > maxWidth {
                penX = margin
                penY += lineHeight
            }

            // Position glyph relative to baseline (penY)
            // bearing.y is offset from baseline to bottom of glyph (negative for descenders)
            // In Y-down coords: top = baseline - (bearing.y + height), bottom = baseline - bearing.y
            let x1 = penX + Float(entry.bearing.x)
            let y1 = penY - Float(entry.bearing.y) - Float(entry.size.height)  // top
            let x2 = x1 + Float(entry.size.width)
            let y2 = penY - Float(entry.bearing.y)  // bottom (at baseline for non-descenders)

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

            penX += Float(entry.advance)
        }

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

        // Load initial page
        loadURL("https://ejfox.com")
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

        print("MetalView: render() - drawableSize: \(drawableSize)")
        var uniforms = Uniforms(
            viewportSize: SIMD2<Float>(Float(drawableSize.width), Float(drawableSize.height))
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)

        // Create a command buffer for this frame
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("MetalView: Failed to create command buffer")
            return
        }

        // Create a render pass descriptor
        let renderPassDescriptor = MTLRenderPassDescriptor()
        renderPassDescriptor.colorAttachments[0].texture = drawable.texture
        renderPassDescriptor.colorAttachments[0].loadAction = .clear
        renderPassDescriptor.colorAttachments[0].storeAction = .store

        // Background color - dark theme default
        // TODO: Get from libvulpes theme
        renderPassDescriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: 0.1,
            green: 0.1,
            blue: 0.12,
            alpha: 1.0
        )

        // Create the render encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            print("MetalView: Failed to create render encoder")
            return
        }

        // Set the solid color pipeline
        renderEncoder.setRenderPipelineState(solidPipelineState)

        // Bind uniform buffer (viewport size)
        renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)

        // Draw text content using glyph atlas
        if let atlas = glyphAtlas, let textBuffer = textVertexBuffer, textVertexCount > 0 {
            renderEncoder.setRenderPipelineState(glyphPipelineState)
            renderEncoder.setVertexBuffer(textBuffer, offset: 0, index: 0)
            renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            renderEncoder.setFragmentTexture(atlas.texture, index: 0)
            renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: textVertexCount)
        }

        // TODO: Process render commands from libvulpes
        // let commands = VulpesBridge.shared.getRenderCommands()
        // for command in commands {
        //     switch command {
        //     case .rect(let rect, let color):
        //         drawRect(encoder: renderEncoder, rect: rect, color: color)
        //     case .glyph(let glyph, let position, let color):
        //         drawGlyph(encoder: renderEncoder, glyph: glyph, position: position, color: color)
        //     }
        // }

        // Finish encoding
        renderEncoder.endEncoding()

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

        // TODO: Translate to libvulpes key code and send
        // let modifiers = translateModifiers(event.modifierFlags)
        // let keyCode = translateKeyCode(event.keyCode)
        // VulpesBridge.shared.sendKeyDown(keyCode: keyCode, modifiers: modifiers)

        // For now, just log
        print("MetalView: keyDown - keyCode: \(event.keyCode), characters: \(event.characters ?? "")")

        // Request redraw after input
        needsDisplay = true
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
        // Convert to view coordinates
        let point = convert(event.locationInWindow, from: nil)

        // TODO: Send to libvulpes for hit testing
        // VulpesBridge.shared.sendMouseDown(x: Float(point.x), y: Float(point.y))

        print("MetalView: mouseDown at \(point)")
    }

    override func scrollWheel(with event: NSEvent) {
        // TODO: Send scroll delta to libvulpes
        // VulpesBridge.shared.sendScroll(deltaX: Float(event.scrollingDeltaX),
        //                                 deltaY: Float(event.scrollingDeltaY))
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
