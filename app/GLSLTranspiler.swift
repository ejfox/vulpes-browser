// GLSLTranspiler.swift
// vulpes-browser
//
// Converts Ghostty/Shadertoy-style GLSL shaders to Metal Shading Language
//
// Supported GLSL features:
//   - vec2, vec3, vec4 → float2, float3, float4
//   - mat2, mat3, mat4 → float2x2, float3x3, float4x4
//   - texture(sampler, uv) → sampler.sample(texSampler, uv)
//   - iResolution, iChannel0, iTime uniforms
//   - mainImage(out vec4 fragColor, in vec2 fragCoord) entry point
//   - Common functions: mod, fract, mix, clamp, step, smoothstep, etc.

import Foundation
import Metal

class GLSLTranspiler {

    // MARK: - Transpilation

    /// Transpile GLSL shader source to Metal shader source
    static func transpile(glsl: String, functionName: String = "customPostProcess") -> String {
        var source = glsl

        // Step 1: Remove GLSL version directive if present
        source = source.replacingOccurrences(of: #"#version \d+.*\n"#, with: "", options: .regularExpression)

        // Step 2: Replace GLSL types with Metal types
        source = replaceTypes(source)

        // Step 3: Replace texture sampling
        source = replaceTextureSampling(source)

        // Step 4: Replace GLSL-specific functions
        source = replaceFunctions(source)

        // Step 5: Fix Metal address space for global constants
        source = fixMetalAddressSpace(source)

        // Step 6: Fix function parameters (inout, out, in)
        source = fixFunctionParameters(source)

        // Step 7: Add missing uniform params to helper functions that use them
        source = addMissingUniformParams(source)

        // Step 8: Extract mainImage and wrap in Metal boilerplate
        let metalSource = wrapInMetalBoilerplate(source, functionName: functionName)

        return metalSource
    }

    // MARK: - Type Replacements

    private static func replaceTypes(_ source: String) -> String {
        var s = source

        // Vector types
        s = s.replacingOccurrences(of: "vec2", with: "float2")
        s = s.replacingOccurrences(of: "vec3", with: "float3")
        s = s.replacingOccurrences(of: "vec4", with: "float4")
        s = s.replacingOccurrences(of: "ivec2", with: "int2")
        s = s.replacingOccurrences(of: "ivec3", with: "int3")
        s = s.replacingOccurrences(of: "ivec4", with: "int4")
        s = s.replacingOccurrences(of: "uvec2", with: "uint2")
        s = s.replacingOccurrences(of: "uvec3", with: "uint3")
        s = s.replacingOccurrences(of: "uvec4", with: "uint4")
        s = s.replacingOccurrences(of: "bvec2", with: "bool2")
        s = s.replacingOccurrences(of: "bvec3", with: "bool3")
        s = s.replacingOccurrences(of: "bvec4", with: "bool4")

        // Matrix types
        s = s.replacingOccurrences(of: "mat2", with: "float2x2")
        s = s.replacingOccurrences(of: "mat3", with: "float3x3")
        s = s.replacingOccurrences(of: "mat4", with: "float4x4")

        // Sampler types (will be replaced in context)
        s = s.replacingOccurrences(of: "sampler2D", with: "texture2d<float>")

        return s
    }

    // MARK: - Metal Address Space Fixes

    private static func fixMetalAddressSpace(_ source: String) -> String {
        var s = source

        // Fix array declarations: "const float3[24] name" → "constant float3 name[24]"
        // Pattern: const <type>[<size>] <name>
        let arrayPattern = #"const\s+(float\d?|int\d?|uint\d?|bool\d?|float\dx\d)\[(\d+)\]\s+(\w+)"#
        if let regex = try? NSRegularExpression(pattern: arrayPattern, options: []) {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range,
                                                withTemplate: "constant $1 $3[$2]")
        }

        // Fix global const declarations: "const float NAME" → "constant float NAME"
        // Only at start of line (after newline or start of string)
        let constPattern = #"(?m)^const\s+(float|int|uint|bool)"#
        if let regex = try? NSRegularExpression(pattern: constPattern, options: []) {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range,
                                                withTemplate: "constant $1")
        }

        // Fix global non-const declarations at program scope: "float name = val;" → "constant float name = val;"
        // This matches lines that start with a type and assignment (not inside a function)
        let globalVarPattern = #"(?m)^(float\d?|int\d?|uint\d?|bool\d?)\s+(\w+)\s*="#
        if let regex = try? NSRegularExpression(pattern: globalVarPattern, options: []) {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range,
                                                withTemplate: "constant $1 $2 =")
        }

        return s
    }

    // MARK: - Fix Function Parameters

    private static func fixFunctionParameters(_ source: String) -> String {
        var s = source

        // Replace "inout float3 name" → "thread float3 &name"
        // Handles in, out, inout qualifiers
        let inoutPattern = #"inout\s+(float\d?|int\d?|uint\d?|bool\d?)\s+(\w+)"#
        if let regex = try? NSRegularExpression(pattern: inoutPattern, options: []) {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range,
                                                withTemplate: "thread $1 &$2")
        }

        // "out float4 name" → "thread float4 &name"
        let outPattern = #"\bout\s+(float\d?|int\d?|uint\d?|bool\d?)\s+(\w+)"#
        if let regex = try? NSRegularExpression(pattern: outPattern, options: []) {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range,
                                                withTemplate: "thread $1 &$2")
        }

        // "in float2 name" → just "float2 name" (in is default in Metal)
        let inPattern = #"\bin\s+(float\d?|int\d?|uint\d?|bool\d?)\s+"#
        if let regex = try? NSRegularExpression(pattern: inPattern, options: []) {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range,
                                                withTemplate: "$1 ")
        }

        return s
    }

    // MARK: - Add Missing Parameters to Helper Functions

    /// Detect functions that use iResolution/iTime/iChannel0 and add them as parameters
    /// Also updates call sites to pass these parameters
    private static func addMissingUniformParams(_ source: String) -> String {
        var s = source

        // Find all function definitions and check if they use globals
        // Pattern: type funcName(params) {body}
        let funcPattern = #"(void|float\d?|int\d?|bool)\s+(\w+)\s*\(([^)]*)\)\s*\{"#

        guard let regex = try? NSRegularExpression(pattern: funcPattern, options: []) else {
            return s
        }

        var functionsUsingResolution: Set<String> = []
        var functionsUsingTime: Set<String> = []

        // First pass: find which functions use iResolution/iTime
        let matches = regex.matches(in: s, options: [], range: NSRange(s.startIndex..., in: s))
        for match in matches {
            guard let funcNameRange = Range(match.range(at: 2), in: s) else { continue }
            let funcName = String(s[funcNameRange])

            // Skip mainImage as it's handled specially
            if funcName == "mainImage" { continue }

            // Find the function body
            let startIndex = s.index(s.startIndex, offsetBy: match.range.upperBound - 1)
            var braceCount = 1
            var endIndex = startIndex

            for i in s[s.index(after: startIndex)...].indices {
                if s[i] == "{" { braceCount += 1 }
                if s[i] == "}" { braceCount -= 1 }
                if braceCount == 0 {
                    endIndex = i
                    break
                }
            }

            let body = String(s[startIndex...endIndex])
            if body.contains("iResolution") {
                functionsUsingResolution.insert(funcName)
            }
            if body.contains("iTime") {
                functionsUsingTime.insert(funcName)
            }
        }

        // Second pass: add parameters to function definitions only (preceded by return type)
        for funcName in functionsUsingResolution {
            // Function definition pattern: "returnType funcName(params)"
            let defPattern = "(void|float\\d?|int\\d?|bool)\\s+" + funcName + "(\\s*\\()([^)]*)(\\))"
            if let defRegex = try? NSRegularExpression(pattern: defPattern, options: []) {
                let range = NSRange(s.startIndex..., in: s)
                s = defRegex.stringByReplacingMatches(in: s, options: [], range: range,
                                                       withTemplate: "$1 " + funcName + "$2$3, float2 iResolution$4")
            }
        }

        for funcName in functionsUsingTime {
            let defPattern = "(void|float\\d?|int\\d?|bool)\\s+" + funcName + "(\\s*\\()([^)]*)(\\))"
            if let defRegex = try? NSRegularExpression(pattern: defPattern, options: []) {
                let range = NSRange(s.startIndex..., in: s)
                s = defRegex.stringByReplacingMatches(in: s, options: [], range: range,
                                                       withTemplate: "$1 " + funcName + "$2$3, float iTime$4")
            }
        }

        // Third pass: update call sites to pass the parameters
        // Call sites are NOT preceded by type keywords (void, float, int, etc.)
        for funcName in functionsUsingResolution {
            // Match function calls: funcName(args) NOT preceded by type keyword
            // Use negative lookbehind to exclude function definitions
            let callPattern = "(?<!void )(?<!float )(?<!int )(?<!bool )(?<!thread )\\b" + funcName + "\\s*\\(([^)]*)\\)"
            if let callRegex = try? NSRegularExpression(pattern: callPattern, options: []) {
                var range = NSRange(s.startIndex..., in: s)
                while let match = callRegex.firstMatch(in: s, options: [], range: range) {
                    guard let argsRange = Range(match.range(at: 1), in: s) else { break }
                    let args = String(s[argsRange])

                    // Only add if not already present and args don't contain type declarations
                    if !args.contains("iResolution") && !args.contains("float2 ") {
                        let fullRange = Range(match.range, in: s)!
                        let replacement = "\(funcName)(\(args), iResolution)"
                        s.replaceSubrange(fullRange, with: replacement)
                    }

                    // Update range for next search
                    let nextStart = s.index(s.startIndex, offsetBy: min(match.range.location + 1, s.count))
                    range = NSRange(nextStart..., in: s)
                }
            }
        }

        for funcName in functionsUsingTime {
            let callPattern = "(?<!void )(?<!float )(?<!int )(?<!bool )(?<!thread )\\b" + funcName + "\\s*\\(([^)]*)\\)"
            if let callRegex = try? NSRegularExpression(pattern: callPattern, options: []) {
                var range = NSRange(s.startIndex..., in: s)
                while let match = callRegex.firstMatch(in: s, options: [], range: range) {
                    guard let argsRange = Range(match.range(at: 1), in: s) else { break }
                    let args = String(s[argsRange])

                    if !args.contains("iTime") && !args.contains("float ") {
                        let fullRange = Range(match.range, in: s)!
                        let replacement = "\(funcName)(\(args), iTime)"
                        s.replaceSubrange(fullRange, with: replacement)
                    }

                    let nextStart = s.index(s.startIndex, offsetBy: min(match.range.location + 1, s.count))
                    range = NSRange(nextStart..., in: s)
                }
            }
        }

        return s
    }

    // MARK: - Fix Early Returns

    private static func fixEarlyReturns(_ mainBody: String) -> String {
        // Replace bare "return;" with "return fragColor;" in mainImage body
        return mainBody.replacingOccurrences(of: #"return\s*;"#,
                                              with: "return fragColor;",
                                              options: .regularExpression)
    }

    // MARK: - Texture Sampling

    private static func replaceTextureSampling(_ source: String) -> String {
        var s = source

        // Replace texture(iChannel0, uv) with iChannel0.sample(texSampler, uv)
        // This regex handles texture(sampler, coords)
        let texturePattern = #"texture\s*\(\s*(\w+)\s*,\s*([^)]+)\)"#
        if let regex = try? NSRegularExpression(pattern: texturePattern, options: []) {
            let range = NSRange(s.startIndex..., in: s)
            s = regex.stringByReplacingMatches(in: s, options: [], range: range,
                                                withTemplate: "$1.sample(texSampler, $2)")
        }

        return s
    }

    // MARK: - Function Replacements

    private static func replaceFunctions(_ source: String) -> String {
        var s = source

        // mod() in GLSL is fmod() in Metal, but Metal's fmod can be negative
        // GLSL mod(x, y) = x - y * floor(x/y), same as Metal's fmod for positive values
        // For full compatibility, we'd need a helper, but fmod works for most cases
        s = s.replacingOccurrences(of: "mod(", with: "fmod(")

        // atan(y, x) is the same in both
        // Most math functions (sin, cos, tan, sqrt, pow, exp, log, abs, floor, ceil, etc.) are the same

        // dFdx/dFdy → dfdx/dfdy (if used)
        s = s.replacingOccurrences(of: "dFdx(", with: "dfdx(")
        s = s.replacingOccurrences(of: "dFdy(", with: "dfdy(")

        return s
    }

    // MARK: - Metal Boilerplate

    private static func wrapInMetalBoilerplate(_ glslSource: String, functionName: String) -> String {
        // Extract everything before mainImage (constants, helper functions)
        // and the mainImage body

        var preamble = ""
        var mainBody = ""

        // Find mainImage function
        if let mainImageRange = glslSource.range(of: #"void\s+mainImage\s*\("#, options: .regularExpression) {
            preamble = String(glslSource[..<mainImageRange.lowerBound])

            // Find the body between { and matching }
            if let bodyStart = glslSource[mainImageRange.upperBound...].firstIndex(of: "{") {
                let afterBrace = glslSource.index(after: bodyStart)
                var braceCount = 1
                var bodyEnd = afterBrace

                for i in glslSource[afterBrace...].indices {
                    let char = glslSource[i]
                    if char == "{" { braceCount += 1 }
                    if char == "}" { braceCount -= 1 }
                    if braceCount == 0 {
                        bodyEnd = i
                        break
                    }
                }

                mainBody = String(glslSource[afterBrace..<bodyEnd])
                // Fix early returns in mainImage body
                mainBody = fixEarlyReturns(mainBody)
            }
        } else {
            // No mainImage found, use entire source as preamble
            preamble = glslSource
            mainBody = "fragColor = iChannel0.sample(texSampler, uv);"
        }

        // Build Metal shader - preamble at program scope with functions that now have iResolution param
        let metalSource = """
        // Auto-transpiled from GLSL by Vulpes Browser
        #include <metal_stdlib>
        using namespace metal;

        // Uniforms for Ghostty/Shadertoy compatibility
        struct PostProcessUniforms {
            float2 iResolution;
            float iTime;
        };

        // Transpiled GLSL preamble (constants, helper functions)
        \(preamble)

        // Main fragment shader
        fragment float4 \(functionName)(
            float4 position [[position]],
            constant PostProcessUniforms &uniforms [[buffer(0)]],
            texture2d<float> iChannel0 [[texture(0)]]
        ) {
            constexpr sampler texSampler(
                mag_filter::linear,
                min_filter::linear,
                address::clamp_to_edge
            );

            // Shadertoy/Ghostty compatibility
            float2 iResolution = uniforms.iResolution;
            float iTime = uniforms.iTime;
            float2 fragCoord = position.xy;
            float4 fragColor;

            // Transpiled mainImage body
            \(mainBody)

            return fragColor;
        }
        """

        return metalSource
    }

    // MARK: - Compilation

    /// Load and compile a GLSL shader file to a Metal function
    static func loadShader(from path: String, device: MTLDevice) -> MTLFunction? {
        guard let glslSource = try? String(contentsOfFile: path, encoding: .utf8) else {
            NSLog("GLSLTranspiler: Failed to read shader file: %@", path)
            return nil
        }

        let metalSource = transpile(glsl: glslSource)

        // Debug: log transpiled source
        NSLog("GLSLTranspiler: Transpiled shader from %@", path)

        // Compile Metal shader
        do {
            let library = try device.makeLibrary(source: metalSource, options: nil)
            NSLog("GLSLTranspiler: Shader compiled successfully!")
            return library.makeFunction(name: "customPostProcess")
        } catch {
            NSLog("GLSLTranspiler: Failed to compile shader: %@", "\(error)")
            NSLog("GLSLTranspiler: Metal source:\n%@", metalSource)
            return nil
        }
    }

    /// Create a render pipeline state from a GLSL shader
    static func createPipeline(
        from path: String,
        device: MTLDevice,
        vertexFunction: MTLFunction,
        pixelFormat: MTLPixelFormat = .bgra8Unorm
    ) -> MTLRenderPipelineState? {

        guard let fragmentFunction = loadShader(from: path, device: device) else {
            return nil
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Custom GLSL Pipeline"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        do {
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("GLSLTranspiler: Failed to create pipeline: \(error)")
            return nil
        }
    }
}
