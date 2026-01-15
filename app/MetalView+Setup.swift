// MetalView+Setup.swift
// vulpes-browser
//
// Metal pipeline setup and initialization.
// Creates vertex descriptors, render pipelines, and uniform buffers.

import AppKit
import Metal
import simd

// MARK: - Metal Setup Extension

extension MetalView {

    /// Configure vertex attribute layout for all shaders
    func setupVertexDescriptor() {
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

    /// Create all render pipeline states
    func setupRenderPipelines() {
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

        // Create image pipeline (for rendering images from atlas)
        guard let fragmentImage = library.makeFunction(name: "fragmentShaderImage") else {
            fatalError("MetalView: Failed to load fragmentShaderImage function")
        }

        let imageDescriptor = MTLRenderPipelineDescriptor()
        imageDescriptor.label = "Image Pipeline"
        imageDescriptor.vertexFunction = vertexFunction
        imageDescriptor.fragmentFunction = fragmentImage
        imageDescriptor.vertexDescriptor = vertexDescriptor
        imageDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        // Alpha blending for images
        imageDescriptor.colorAttachments[0].isBlendingEnabled = true
        imageDescriptor.colorAttachments[0].rgbBlendOperation = .add
        imageDescriptor.colorAttachments[0].alphaBlendOperation = .add
        imageDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        imageDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        imageDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        imageDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha

        do {
            imagePipelineState = try device.makeRenderPipelineState(descriptor: imageDescriptor)
        } catch {
            fatalError("MetalView: Failed to create image pipeline state: \(error)")
        }

        print("MetalView: Render pipelines created")
    }

    /// Allocate uniform buffer for shader constants
    func setupUniformBuffer() {
        // Allocate buffer for uniforms
        uniformBuffer = device.makeBuffer(
            length: MemoryLayout<Uniforms>.stride,
            options: .storageModeShared
        )
        uniformBuffer.label = "Uniforms"

        // Initialize with current size
        updateUniforms()
    }

    /// Update uniform buffer with current viewport size
    func updateUniforms() {
        var uniforms = Uniforms(
            viewportSize: SIMD2<Float>(Float(bounds.width), Float(bounds.height))
        )
        memcpy(uniformBuffer.contents(), &uniforms, MemoryLayout<Uniforms>.stride)
    }

    /// Create test geometry for debugging
    func setupTestGeometry() {
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
}
