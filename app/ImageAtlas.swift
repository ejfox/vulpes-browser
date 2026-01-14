// ImageAtlas.swift
// vulpes-browser
//
// GPU-accelerated image atlas for performant image rendering.
// Similar to GlyphAtlas but optimized for images with dynamic loading.
//
// Architecture:
// - Texture atlas packing for efficient GPU memory usage
// - Async image downloading and decoding
// - Metal texture creation for zero-copy rendering
// - LRU cache for memory management
// - Support for various image formats (PNG, JPEG, WebP)

import AppKit
import Metal
import CoreGraphics

final class ImageAtlas {
    
    // MARK: - Data Structures
    
    struct ImageKey: Hashable {
        let url: String
    }
    
    struct ImageEntry {
        let uvRect: CGRect        // UV coordinates in atlas (0-1)
        let size: CGSize          // Original image size in pixels
        let texture: MTLTexture?  // Individual texture if too large for atlas
        var lastUsed: Date        // For LRU eviction
    }
    
    // MARK: - Configuration
    
    private let maxAtlasSize: Int = 4096  // 4K atlas texture
    private let maxIndividualSize: Int = 2048  // Images larger than this get individual textures
    private let maxCacheSize: Int = 100   // Max number of cached images
    private let maxConcurrentDownloads: Int = 4  // Limit concurrent downloads
    
    // MARK: - State
    
    private let device: MTLDevice
    private var atlasTexture: MTLTexture?
    private var entries: [ImageKey: ImageEntry] = [:]
    
    // Atlas packing state (simple row-based packing)
    private var nextX: Int = 0
    private var nextY: Int = 0
    private var rowHeight: Int = 0
    private let padding: Int = 2
    
    // Download queue for async image loading
    private let downloadQueue = DispatchQueue(label: "com.vulpes.imagedownload", qos: .userInitiated, attributes: .concurrent)
    private var pendingDownloads: Set<String> = []
    
    // Thread-safe access to pendingDownloads
    private let pendingDownloadsQueue = DispatchQueue(label: "com.vulpes.pendingDownloads")
    
    // Reusable command queue for better performance
    private let uploadQueue: MTLCommandQueue?
    
    // MARK: - Initialization
    
    init?(device: MTLDevice) {
        self.device = device
        
        // Create reusable command queue for uploads
        self.uploadQueue = device.makeCommandQueue()
        guard uploadQueue != nil else {
            print("ImageAtlas: Failed to create command queue")
            return nil
        }
        
        // Create initial atlas texture
        guard let texture = createAtlasTexture() else {
            return nil
        }
        self.atlasTexture = texture
        
        print("ImageAtlas: Initialized with \(maxAtlasSize)x\(maxAtlasSize) atlas")
    }
    
    private func createAtlasTexture() -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,  // Full color with alpha
            width: maxAtlasSize,
            height: maxAtlasSize,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .private  // GPU-only for best performance
        
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = "Image Atlas"
        return texture
    }
    
    // MARK: - Public API
    
    /// Get cached image entry if available, otherwise returns nil and triggers async download
    func entry(for url: String) -> ImageEntry? {
        let key = ImageKey(url: url)
        
        // Check cache
        if var entry = entries[key] {
            // Update LRU timestamp
            entry.lastUsed = Date()
            entries[key] = entry
            return entry
        }
        
        // Not cached - trigger async download if not already pending
        var shouldDownload = false
        pendingDownloadsQueue.sync {
            // Limit concurrent downloads to prevent resource exhaustion
            if !pendingDownloads.contains(url) && pendingDownloads.count < maxConcurrentDownloads {
                pendingDownloads.insert(url)
                shouldDownload = true
            }
        }
        
        if shouldDownload {
            downloadImage(url: url)
        }
        
        return nil
    }
    
    /// Check if image is cached
    func isCached(_ url: String) -> Bool {
        return entries[ImageKey(url: url)] != nil
    }
    
    /// Get the main atlas texture for batch rendering
    func getAtlasTexture() -> MTLTexture? {
        return atlasTexture
    }
    
    /// Clear all cached images
    func clearCache() {
        entries.removeAll()
        pendingDownloadsQueue.sync {
            pendingDownloads.removeAll()
        }
        nextX = 0
        nextY = 0
        rowHeight = 0
        print("ImageAtlas: Cache cleared")
    }
    
    /// Cleanup resources
    deinit {
        clearCache()
    }
    
    // MARK: - Image Loading
    
    private func downloadImage(url: String) {
        downloadQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Handle relative URLs by checking if it starts with http
            guard let imageURL = self.resolveURL(url) else {
                print("ImageAtlas: Invalid URL: \(url)")
                self.pendingDownloadsQueue.async {
                    self.pendingDownloads.remove(url)
                }
                return
            }
            
            print("ImageAtlas: Downloading \(imageURL)")
            
            // Download image data with timeout
            var urlRequest = URLRequest(url: imageURL)
            urlRequest.timeoutInterval = 10.0  // 10 second timeout
            
            let semaphore = DispatchSemaphore(value: 0)
            var downloadedData: Data?
            var downloadError: Error?
            
            let task = URLSession.shared.dataTask(with: urlRequest) { data, response, error in
                downloadedData = data
                downloadError = error
                semaphore.signal()
            }
            task.resume()
            semaphore.wait()
            
            if let error = downloadError {
                print("ImageAtlas: Download error for \(url): \(error.localizedDescription)")
                self.pendingDownloadsQueue.async {
                    self.pendingDownloads.remove(url)
                }
                return
            }
            
            guard let data = downloadedData else {
                print("ImageAtlas: No data received for: \(url)")
                self.pendingDownloadsQueue.async {
                    self.pendingDownloads.remove(url)
                }
                return
            }
            
            // Decode image
            guard let nsImage = NSImage(data: data) else {
                print("ImageAtlas: Failed to decode image: \(url)")
                self.pendingDownloadsQueue.async {
                    self.pendingDownloads.remove(url)
                }
                return
            }
            
            // Convert to CGImage
            guard let cgImage = self.cgImage(from: nsImage) else {
                print("ImageAtlas: Failed to convert image: \(url)")
                self.pendingDownloadsQueue.async {
                    self.pendingDownloads.remove(url)
                }
                return
            }
            
            // Add to atlas on main queue
            DispatchQueue.main.async {
                self.addToAtlas(url: url, image: cgImage)
                self.pendingDownloadsQueue.async {
                    self.pendingDownloads.remove(url)
                }
                
                // Notify that image is ready (trigger redraw)
                NotificationCenter.default.post(name: .imageLoaded, object: url)
            }
        }
    }
    
    private func resolveURL(_ url: String) -> URL? {
        // Check if it's a full URL
        if url.hasPrefix("http://") || url.hasPrefix("https://") {
            return URL(string: url)
        }
        
        // For relative URLs, we'd need the base URL from the page
        // For now, just return nil for relative URLs
        // This will be improved when we pass base URL context
        return nil
    }
    
    private func cgImage(from nsImage: NSImage) -> CGImage? {
        var imageRect = CGRect(origin: .zero, size: nsImage.size)
        return nsImage.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
    }
    
    private func addToAtlas(url: String, image: CGImage) {
        let width = image.width
        let height = image.height
        
        // Check if image is too large for atlas
        if width > maxIndividualSize || height > maxIndividualSize {
            // Create individual texture
            if let texture = createIndividualTexture(image: image) {
                let entry = ImageEntry(
                    uvRect: CGRect(x: 0, y: 0, width: 1, height: 1),  // Full texture
                    size: CGSize(width: width, height: height),
                    texture: texture,
                    lastUsed: Date()
                )
                entries[ImageKey(url: url)] = entry
                print("ImageAtlas: Added large image as individual texture: \(width)x\(height)")
            }
            return
        }
        
        // Try to pack into atlas
        if nextX + width + padding > maxAtlasSize {
            // Move to next row
            nextX = 0
            nextY += rowHeight + padding
            rowHeight = 0
        }
        
        // Check if we have vertical space
        if nextY + height + padding > maxAtlasSize {
            print("ImageAtlas: Atlas full, evicting old images")
            evictLRU()
            // After eviction, try again
            addToAtlas(url: url, image: image)
            return
        }
        
        // Upload image data to atlas
        guard let atlasTexture = atlasTexture else { return }
        
        let region = MTLRegion(
            origin: MTLOrigin(x: nextX, y: nextY, z: 0),
            size: MTLSize(width: width, height: height, depth: 1)
        )
        
        // Convert CGImage to raw RGBA data
        guard let rawData = imageToRGBA(image) else {
            print("ImageAtlas: Failed to convert image to RGBA")
            return
        }
        
        // Use blit encoder for GPU-side copy (more efficient)
        guard let commandQueue = uploadQueue,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            print("ImageAtlas: Failed to create command buffer for atlas upload")
            return
        }
        
        // Create staging texture
        let stagingDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        stagingDescriptor.usage = [.shaderRead]
        stagingDescriptor.storageMode = .shared  // CPU-accessible
        
        guard let stagingTexture = device.makeTexture(descriptor: stagingDescriptor) else {
            return
        }
        
        // Upload to staging texture
        stagingTexture.replace(
            region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                            size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0,
            withBytes: rawData,
            bytesPerRow: width * 4
        )
        
        // Blit to atlas
        guard let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            return
        }
        
        blitEncoder.copy(
            from: stagingTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: atlasTexture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: nextX, y: nextY, z: 0)
        )
        
        blitEncoder.endEncoding()
        commandBuffer.commit()
        
        // Calculate UV rect
        let uvRect = CGRect(
            x: CGFloat(nextX) / CGFloat(maxAtlasSize),
            y: CGFloat(nextY) / CGFloat(maxAtlasSize),
            width: CGFloat(width) / CGFloat(maxAtlasSize),
            height: CGFloat(height) / CGFloat(maxAtlasSize)
        )
        
        let entry = ImageEntry(
            uvRect: uvRect,
            size: CGSize(width: width, height: height),
            texture: nil,  // Using atlas, not individual texture
            lastUsed: Date()
        )
        
        entries[ImageKey(url: url)] = entry
        
        // Update packing state
        nextX += width + padding
        rowHeight = max(rowHeight, height)
        
        print("ImageAtlas: Added image \(width)x\(height) at (\(nextX), \(nextY))")
    }
    
    private func createIndividualTexture(image: CGImage) -> MTLTexture? {
        let width = image.width
        let height = image.height
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .private
        
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }
        
        // Upload image data
        guard let rawData = imageToRGBA(image) else {
            return nil
        }
        
        // Use staging texture for private storage
        let stagingDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        stagingDescriptor.storageMode = .shared
        
        guard let stagingTexture = device.makeTexture(descriptor: stagingDescriptor) else {
            return nil
        }
        
        stagingTexture.replace(
            region: MTLRegion(origin: MTLOrigin(x: 0, y: 0, z: 0),
                            size: MTLSize(width: width, height: height, depth: 1)),
            mipmapLevel: 0,
            withBytes: rawData,
            bytesPerRow: width * 4
        )
        
        // Blit to private texture
        guard let commandQueue = uploadQueue,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let blitEncoder = commandBuffer.makeBlitCommandEncoder() else {
            print("ImageAtlas: Failed to create command buffer for individual texture")
            return nil
        }
        
        blitEncoder.copy(
            from: stagingTexture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: width, height: height, depth: 1),
            to: texture,
            destinationSlice: 0,
            destinationLevel: 0,
            destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
        )
        
        blitEncoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()  // Sync for individual textures
        
        return texture
    }
    
    private func imageToRGBA(_ image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }
        
        // Flip coordinate system to match Metal (Y-down)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        return rawData
    }
    
    private func evictLRU() {
        // Remove oldest images until we have space
        let sorted = entries.sorted { $0.value.lastUsed < $1.value.lastUsed }
        let toRemove = min(10, sorted.count / 4)  // Remove 25% or 10 images
        
        for i in 0..<toRemove {
            entries.removeValue(forKey: sorted[i].key)
        }
        
        // Reset packing (rebuild atlas)
        // In a production system, we'd do smarter repacking
        // For now, just clear and let images reload
        nextX = 0
        nextY = 0
        rowHeight = 0
        
        print("ImageAtlas: Evicted \(toRemove) images")
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let imageLoaded = Notification.Name("imageLoaded")
}
