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
    var scrollOffset: Float
    var _padding: Float = 0
}

// For custom GLSL shaders (Ghostty/Shadertoy compatibility)
struct PostProcessUniforms {
    var iResolution: SIMD2<Float>
    var iTime: Float
    var _padding: Float = 0  // Align to 16 bytes
}

// MARK: - Particle System Types (file-level for extension access)

struct Particle {
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

// MARK: - Link Hit Box (file-level for extension access)

struct LinkHitBox {
    let linkIndex: Int
    var minX: Float
    var minY: Float
    var maxX: Float
    var maxY: Float
}

class MetalView: NSView {

    // MARK: - Metal Infrastructure

    // Core Metal objects - created once, reused every frame
    var device: MTLDevice!
    var commandQueue: MTLCommandQueue!

    // Access the layer as CAMetalLayer
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    // Render pipelines for different draw modes
    var solidPipelineState: MTLRenderPipelineState!
    var glyphPipelineState: MTLRenderPipelineState!
    var particlePipelineState: MTLRenderPipelineState!  // Additive blending for particles
    var glowPipelineState: MTLRenderPipelineState!      // Additive blending for link glow
    var bloomPipelineState: MTLRenderPipelineState!     // Post-process bloom effect
    var customShaderPipeline: MTLRenderPipelineState?   // Custom GLSL shader (optional)

    // Offscreen render target for two-pass bloom
    var offscreenTexture: MTLTexture?
    var bloomEnabled: Bool = false  // Disabled by default for sharp text

    // Post-process uniforms for custom shaders (Shadertoy/Ghostty compatibility)
    var postProcessUniformBuffer: MTLBuffer?
    var shaderStartTime: CFAbsoluteTime = 0

    // Vertex descriptor for our Vertex struct
    var vertexDescriptor: MTLVertexDescriptor!

    // Uniform buffer for viewport size
    var uniformBuffer: MTLBuffer!

    // MARK: - Glyph Atlas
    var glyphAtlas: GlyphAtlas?
    
    // MARK: - Image Atlas
    var imageAtlas: ImageAtlas?
    var imagePipelineState: MTLRenderPipelineState!

    // MARK: - Content Display
    var testVertexBuffer: MTLBuffer?
    var textVertexBuffer: MTLBuffer?
    var textVertexCount: Int = 0

    // Current displayed text content
    var displayedText: String = "Loading..."
    var currentURL: String = ""
    var baseURLForCurrentPage: URL?

    // Extracted links for navigation
    var extractedLinks: [String] = []

    // Extracted images for rendering
    var extractedImages: [String] = []

    // CSS-extracted page style (colors)
    var pageStyle: VulpesBridge.PageStyle = .default

    // Image placement data (position and size for each image)
    // ImagePlacement struct is defined in MetalView+TextRendering.swift
    var imagePlacements: [ImagePlacement] = []

    // Focused link for Tab navigation (-1 = no focus, 0+ = link index)
    var focusedLinkIndex: Int = -1

    // Link hit boxes for click detection (in point coordinates, not pixels)
    var linkHitBoxes: [LinkHitBox] = []

    // Hovered link for glow effect with animation
    var hoveredLinkIndex: Int = -1
    var glowIntensity: Float = 0.0        // Current glow level (0-1)
    var targetGlowIntensity: Float = 0.0  // Target glow level
    private var lastGlowUpdate: CFAbsoluteTime = 0
    let glowFadeInSpeed: Float = 8.0      // How fast glow appears
    let glowFadeOutSpeed: Float = 2.5     // How slow glow fades (inertia)

    // MARK: - Particle System
    var particles: [Particle] = []
    private var particleVertexBuffer: MTLBuffer?
    var lastParticleUpdate: CFAbsoluteTime = 0
    let maxParticles = 2000
    let particleSpawnCount = 150  // Lots of tiny particles per click

    // MARK: - Hint Mode (Vimium-style link navigation)
    var hintModeActive: Bool = false
    var hintBuffer: String = ""
    var hintLabels: [String] = []
    var hintModeStartTime: CFAbsoluteTime = 0
    let hintChars: [Character] = ["a", "s", "d", "f", "j", "k", "l", "g", "h", "q", "w", "e", "r", "t", "u", "i", "o", "p"]

    // Callback when URL changes (for updating URL bar)
    var onURLChange: ((String) -> Void)?
    var onContentLoaded: ((String, String) -> Void)?
    var onScrollChange: ((Float, Float) -> Void)?

    // Callback to focus URL bar
    var onRequestURLBarFocus: (() -> Void)?

    // Scroll state
    var scrollOffset: Float = 0.0
    var contentHeight: Float = 0.0  // Total height of rendered content
    var scrollSpeed: Float = 40.0   // Pixels per j/k press (configurable)
    var scrollVelocity: Float = 0.0
    var scrollAnimator: Timer?
    var lastScrollUpdate: CFAbsoluteTime = 0

    // Key sequence tracking (for gg, etc.)
    private var lastKeyChar: String = ""
    private var lastKeyTime: CFAbsoluteTime = 0

    // Track if fully initialized
    var isMetalReady = false

    // MARK: - Error Page Effects
    var errorShaderPipeline: MTLRenderPipelineState?
    var currentHttpError: Int = 0  // 0 = no error, 404/500/etc = error
    var errorShaderStartTime: CFAbsoluteTime = 0

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
        
        // Create image atlas for image rendering
        imageAtlas = ImageAtlas(device: device)

        // Apply config settings
        applyConfig()

        // Try to load custom GLSL shader if configured
        loadCustomShader()
        
        // Listen for image load notifications to re-layout and redraw
        // Re-layout is needed because now we know the actual image dimensions
        NotificationCenter.default.addObserver(
            forName: .imageLoaded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateTextDisplay()
            self?.needsDisplay = true
        }

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
        TransitionManager.shared.transitionsEnabled = config.transitionsEnabled

        // Create post-process uniform buffer for custom shaders
        postProcessUniformBuffer = device.makeBuffer(
            length: MemoryLayout<PostProcessUniforms>.stride,
            options: .storageModeShared
        )
        postProcessUniformBuffer?.label = "PostProcess Uniforms"

        print("MetalView: Config applied - bloom=\(bloomEnabled), homePage=\(config.homePage)")
    }

    // Note: Shader functions moved to MetalView+Shaders.swift:
    // - loadCustomShader()
    // - triggerPageTransition()
    // - setErrorShader(forStatus:)
    // - clearErrorState()

    // Note: Setup functions moved to MetalView+Setup.swift:
    // - setupVertexDescriptor()
    // - setupRenderPipelines()
    // - setupUniformBuffer()
    // - updateUniforms()
    // - setupTestGeometry()


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
        needsDisplay = true
        render()

        // Load initial page from config
        loadURL(VulpesConfig.shared.homePage)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
    }

    override var acceptsFirstResponder: Bool {
        // Must accept first responder to receive keyboard events
        return true
    }

    // Called when wantsUpdateLayer is true
    override func updateLayer() {
        render()
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

        // Handle Escape key first (exit hint mode)
        if event.keyCode == 53 { // Escape
            if hintModeActive {
                exitHintMode()
            }
            needsDisplay = true
            return
        }

        if event.modifierFlags.contains(.command) {
            return
        }

        guard let chars = event.charactersIgnoringModifiers else { return }

        // Handle hint mode input - capture ALL keys while in hint mode
        if hintModeActive {
            if let char = chars.first, char.isLetter {
                handleHintInput(char)
            } else {
                // Non-letter key exits hint mode
                exitHintMode()
            }
            needsDisplay = true
            return
        }

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
            // Enter hint mode (Vimium-style)
            enterHintMode()
            lastKeyChar = ""
        case "F":
            // Go forward in history (Shift+f)
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

    // MARK: - Scrolling (see MetalView+Scrolling.swift)

    // MARK: - Particle System (see MetalView+ParticleSystem.swift)

    // MARK: - Link Navigation (see MetalView+LinkNavigation.swift)

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
        let offsetDelta = -deltaY

        if event.hasPreciseScrollingDeltas {
            if event.scrollingPhase == .began {
                scrollVelocity = 0
                stopScrollAnimator()
            }

            applyDirectScroll(offsetDelta)

            if event.momentumPhase == .ended {
                scrollVelocity = 0
                stopScrollAnimator()
            }
            return
        }

        if VulpesConfig.shared.smoothScrolling {
            applyInertialImpulse(offsetDelta)
        } else {
            applyDirectScroll(offsetDelta)
        }
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
