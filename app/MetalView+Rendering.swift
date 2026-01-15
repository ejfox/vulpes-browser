// MetalView+Rendering.swift
// vulpes-browser
//
// Core Metal rendering loop with two-pass bloom/shader pipeline.

import AppKit
import Metal
import simd

// MARK: - Rendering Extension

extension MetalView {

    /// Ensure offscreen texture exists and matches drawable size
    func ensureOffscreenTexture(size: CGSize) {
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

    /// Main render function - called every frame
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

        // Draw images from image atlas (optimized with batching)
        if let imageAtlas = imageAtlas, !imagePlacements.isEmpty {
            sceneEncoder.setRenderPipelineState(imagePipelineState)
            sceneEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)

            // Group images by texture for batched rendering
            var atlasImages: [Vertex] = []
            var individualImages: [(texture: MTLTexture, vertices: [Vertex])] = []

            for placement in imagePlacements {
                // Check if image is loaded
                guard placement.imageIndex < extractedImages.count else { continue }
                let imageURL = extractedImages[placement.imageIndex]
                guard let entry = imageAtlas.entry(for: imageURL) else { continue }

                // Calculate actual image size preserving aspect ratio
                let aspectRatio = entry.size.width / entry.size.height
                let width = placement.width * Float(metalLayer.contentsScale)
                let height = width / Float(aspectRatio)

                // Build vertices for image quad
                let x = placement.x * Float(metalLayer.contentsScale)
                let y = (placement.y - scrollOffset) * Float(metalLayer.contentsScale)

                let minX = Float(entry.uvRect.minX)
                let maxX = Float(entry.uvRect.maxX)
                let minY = Float(entry.uvRect.minY)
                let maxY = Float(entry.uvRect.maxY)

                let vertices: [Vertex] = [
                    Vertex(position: SIMD2<Float>(x, y), texCoord: SIMD2<Float>(minX, maxY), color: SIMD4<Float>(1, 1, 1, 1)),
                    Vertex(position: SIMD2<Float>(x + width, y), texCoord: SIMD2<Float>(maxX, maxY), color: SIMD4<Float>(1, 1, 1, 1)),
                    Vertex(position: SIMD2<Float>(x, y + height), texCoord: SIMD2<Float>(minX, minY), color: SIMD4<Float>(1, 1, 1, 1)),
                    Vertex(position: SIMD2<Float>(x + width, y), texCoord: SIMD2<Float>(maxX, maxY), color: SIMD4<Float>(1, 1, 1, 1)),
                    Vertex(position: SIMD2<Float>(x + width, y + height), texCoord: SIMD2<Float>(maxX, minY), color: SIMD4<Float>(1, 1, 1, 1)),
                    Vertex(position: SIMD2<Float>(x, y + height), texCoord: SIMD2<Float>(minX, minY), color: SIMD4<Float>(1, 1, 1, 1)),
                ]

                // Group by texture
                if let individualTexture = entry.texture {
                    individualImages.append((texture: individualTexture, vertices: vertices))
                } else {
                    atlasImages.append(contentsOf: vertices)
                }
            }

            // Batch draw all atlas images in a single call
            if !atlasImages.isEmpty, let atlasTexture = imageAtlas.getAtlasTexture() {
                guard let batchBuffer = device.makeBuffer(
                    bytes: atlasImages,
                    length: MemoryLayout<Vertex>.stride * atlasImages.count,
                    options: .storageModeShared
                ) else {
                    print("MetalView: Failed to create batch buffer for atlas images")
                    return
                }

                sceneEncoder.setVertexBuffer(batchBuffer, offset: 0, index: 0)
                sceneEncoder.setFragmentTexture(atlasTexture, index: 0)
                sceneEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: atlasImages.count)
            }

            // Draw individual textures (one call per texture)
            for (texture, vertices) in individualImages {
                guard let imageBuffer = device.makeBuffer(
                    bytes: vertices,
                    length: MemoryLayout<Vertex>.stride * vertices.count,
                    options: .storageModeShared
                ) else { continue }

                sceneEncoder.setVertexBuffer(imageBuffer, offset: 0, index: 0)
                sceneEncoder.setFragmentTexture(texture, index: 0)
                sceneEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            }
        }

        // Draw particles ON TOP of text (additive blending for glow)
        let (particleBuffer, particleCount) = buildParticleVertices()
        if let particleBuffer = particleBuffer, particleCount > 0 {
            sceneEncoder.setRenderPipelineState(particlePipelineState)
            sceneEncoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
            sceneEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
            sceneEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: particleCount)
        }

        // Draw hint mode labels ON TOP of everything
        if hintModeActive {
            // Draw hint backgrounds (solid rectangles)
            let (hintBgBuffer, hintBgCount) = buildHintVertices()
            if let hintBgBuffer = hintBgBuffer, hintBgCount > 0 {
                sceneEncoder.setRenderPipelineState(solidPipelineState)
                sceneEncoder.setVertexBuffer(hintBgBuffer, offset: 0, index: 0)
                sceneEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
                sceneEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: hintBgCount)
            }

            // Draw hint text (using glyph atlas)
            if let atlas = glyphAtlas {
                let (hintTextBuffer, hintTextCount) = buildHintTextVertices()
                if let hintTextBuffer = hintTextBuffer, hintTextCount > 0 {
                    sceneEncoder.setRenderPipelineState(glyphPipelineState)
                    sceneEncoder.setVertexBuffer(hintTextBuffer, offset: 0, index: 0)
                    sceneEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
                    sceneEncoder.setFragmentTexture(atlas.texture, index: 0)
                    sceneEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: hintTextCount)
                }
            }
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
                memcpy(self.uniformBuffer.contents(), &errorUniforms, MemoryLayout<PostProcessUniforms>.stride)
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
}
