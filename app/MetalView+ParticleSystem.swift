// MetalView+ParticleSystem.swift
// vulpes-browser
//
// Particle system for link click effects

import AppKit
import Metal
import simd

// MARK: - Particle System Extension

extension MetalView {

    /// Spawn burst of particles across a rectangular area (link explosion effect)
    func spawnParticles(at point: CGPoint, color: SIMD3<Float>? = nil) {
        spawnParticlesInArea(
            minX: Float(point.x) - 5,
            minY: Float(point.y) - 5,
            maxX: Float(point.x) + 5,
            maxY: Float(point.y) + 5,
            color: color
        )
    }

    /// Spawn particles across a link's bounding box - letters explode into particles
    func spawnParticlesFromLink(hitBox: LinkHitBox, color: SIMD3<Float>? = nil) {
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
    func spawnParticlesInArea(minX: Float, minY: Float, maxX: Float, maxY: Float, color: SIMD3<Float>? = nil) {
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
    func updateParticles(deltaTime: Float) {
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
    func updateGlowAnimation(deltaTime: Float) {
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
    func buildParticleVertices() -> (MTLBuffer?, Int) {
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
    func buildGlowVertices() -> (MTLBuffer?, Int) {
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
}
