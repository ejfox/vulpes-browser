// VulpesConfig.swift
// vulpes-browser
//
// Configuration system - nvim/ghostty style dotfile config
// Reads from ~/.config/vulpes/config
//
// Format:
//   # Comments start with #
//   key = value
//   shader = bloom-vulpes  (loads from ~/.config/ghostty/shaders/)
//   shader = /absolute/path/to/shader.glsl

import Foundation

class VulpesConfig {
    static let shared = VulpesConfig()

    // MARK: - Config Values

    // Appearance
    var backgroundColor: (r: Float, g: Float, b: Float, a: Float) = (0, 0, 0, 0)
    var textColor: (r: Float, g: Float, b: Float) = (0.9, 0.9, 0.9)
    var linkColor: (r: Float, g: Float, b: Float) = (0.4, 0.6, 1.0)
    var fontSize: Float = 16.0

    // Shader settings
    var shaderPath: String? = nil  // Path to custom GLSL post-process shader
    var bloomEnabled: Bool = true
    var bloomIntensity: Float = 0.12
    var bloomRadius: Float = 2.5

    // Scrolling
    var scrollSpeed: Float = 40.0
    var smoothScrolling: Bool = true

    // Particles
    var particlesEnabled: Bool = true
    var particleCount: Int = 150

    // Home page
    var homePage: String = "https://ejfox.com"

    // MARK: - Paths

    private let configDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/vulpes")
    private let configFile: URL

    // Ghostty shader directory (for shader = name shorthand)
    private let ghosttyShaderDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/ghostty/shaders")

    // MARK: - Init

    private init() {
        configFile = configDir.appendingPathComponent("config")
        ensureConfigDir()
        loadConfig()
    }

    private func ensureConfigDir() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: configDir.path) {
            try? fm.createDirectory(at: configDir, withIntermediateDirectories: true)
            createDefaultConfig()
        }
    }

    private func createDefaultConfig() {
        let defaultConfig = """
        # Vulpes Browser Configuration
        # ~/.config/vulpes/config

        # Home page
        home_page = https://ejfox.com

        # Font size (points)
        font_size = 16

        # Colors (RGB 0-1)
        # text_color = 0.9 0.9 0.9
        # link_color = 0.4 0.6 1.0
        # background_color = 0 0 0 0

        # Post-processing shader
        # Use a Ghostty shader name (looks in ~/.config/ghostty/shaders/)
        # shader = bloom-vulpes
        # Or an absolute path:
        # shader = /path/to/custom.glsl

        # Bloom settings (used if no custom shader)
        bloom_enabled = true
        bloom_intensity = 0.12
        bloom_radius = 2.5

        # Scrolling
        scroll_speed = 40
        smooth_scrolling = true

        # Particle effects on link clicks
        particles_enabled = true
        particle_count = 150
        """

        try? defaultConfig.write(to: configFile, atomically: true, encoding: .utf8)
        print("VulpesConfig: Created default config at \(configFile.path)")
    }

    // MARK: - Config Loading

    func loadConfig() {
        guard let contents = try? String(contentsOf: configFile, encoding: .utf8) else {
            print("VulpesConfig: No config file found, using defaults")
            return
        }

        print("VulpesConfig: Loading from \(configFile.path)")

        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comments and empty lines
            if trimmed.isEmpty || trimmed.hasPrefix("#") {
                continue
            }

            // Parse key = value
            guard let equalsIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = trimmed[..<equalsIndex].trimmingCharacters(in: .whitespaces).lowercased()
            let value = trimmed[trimmed.index(after: equalsIndex)...].trimmingCharacters(in: .whitespaces)

            parseConfigValue(key: key, value: value)
        }

        print("VulpesConfig: Loaded - bloom=\(bloomEnabled), shader=\(shaderPath ?? "none")")
    }

    private func parseConfigValue(key: String, value: String) {
        switch key {
        case "home_page":
            homePage = value

        case "font_size":
            fontSize = Float(value) ?? fontSize

        case "text_color":
            if let color = parseColor(value) {
                textColor = color
            }

        case "link_color":
            if let color = parseColor(value) {
                linkColor = color
            }

        case "background_color":
            if let color = parseColor4(value) {
                backgroundColor = color
            }

        case "shader":
            shaderPath = resolveShaderPath(value)

        case "bloom_enabled":
            bloomEnabled = parseBool(value)

        case "bloom_intensity":
            bloomIntensity = Float(value) ?? bloomIntensity

        case "bloom_radius":
            bloomRadius = Float(value) ?? bloomRadius

        case "scroll_speed":
            scrollSpeed = Float(value) ?? scrollSpeed

        case "smooth_scrolling":
            smoothScrolling = parseBool(value)

        case "particles_enabled":
            particlesEnabled = parseBool(value)

        case "particle_count":
            particleCount = Int(value) ?? particleCount

        default:
            print("VulpesConfig: Unknown key '\(key)'")
        }
    }

    // MARK: - Parsing Helpers

    private func parseBool(_ value: String) -> Bool {
        let v = value.lowercased()
        return v == "true" || v == "yes" || v == "1"
    }

    private func parseColor(_ value: String) -> (r: Float, g: Float, b: Float)? {
        let parts = value.split(separator: " ").compactMap { Float($0) }
        guard parts.count >= 3 else { return nil }
        return (parts[0], parts[1], parts[2])
    }

    private func parseColor4(_ value: String) -> (r: Float, g: Float, b: Float, a: Float)? {
        let parts = value.split(separator: " ").compactMap { Float($0) }
        guard parts.count >= 4 else { return nil }
        return (parts[0], parts[1], parts[2], parts[3])
    }

    private func resolveShaderPath(_ value: String) -> String? {
        // If it's an absolute path, use it directly
        if value.hasPrefix("/") {
            return value
        }

        // Otherwise, look in Ghostty shader directory
        var shaderName = value
        if !shaderName.hasSuffix(".glsl") {
            shaderName += ".glsl"
        }

        let ghosttyPath = ghosttyShaderDir.appendingPathComponent(shaderName)
        if FileManager.default.fileExists(atPath: ghosttyPath.path) {
            return ghosttyPath.path
        }

        // Also check vulpes shader directory
        let vulpesPath = configDir.appendingPathComponent("shaders/\(shaderName)")
        if FileManager.default.fileExists(atPath: vulpesPath.path) {
            return vulpesPath.path
        }

        print("VulpesConfig: Shader '\(value)' not found")
        return nil
    }

    // MARK: - Reload

    func reload() {
        loadConfig()
        NotificationCenter.default.post(name: .vulpesConfigReloaded, object: nil)
    }
}

// Notification for config reload
extension Notification.Name {
    static let vulpesConfigReloaded = Notification.Name("vulpesConfigReloaded")
}
