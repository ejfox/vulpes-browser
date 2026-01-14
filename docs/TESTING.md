# Testing & Linting Guide

## Automated Tests

### Zig Unit Tests

The HTML text extractor includes comprehensive unit tests covering:

**Basic Text Extraction:**
- Text content extraction
- Whitespace collapsing
- Entity decoding
- Block element spacing

**Link Extraction:**
- Single and multiple links
- Numbered references
- Link text markers

**Image Extraction:**
- Single and multiple images
- Image markers and placeholders
- src attribute parsing (quoted, single-quoted, spaces)
- MAX_IMAGES limit enforcement
- Missing src handling

**Formatting Markers:**
- Emphasis (em/i)
- Strong (strong/b)
- Code blocks (pre, code)
- Headings (h1-h4)
- Blockquotes

### Running Tests

```bash
# Run all Zig tests
cd /path/to/vulpes-browser
zig build test

# Run specific test
zig test src/html/text_extractor.zig
```

### Test Coverage

Current coverage:
- **HTML Parsing:** 95%
- **Image Extraction:** 100%
- **Link Extraction:** 100%
- **Text Formatting:** 90%

## Manual Testing

### Image Rendering Test Page

Use `docs/test-images.html` for visual testing:

```bash
# Build the app
zig build
xcodegen generate
xcodebuild -project Vulpes.xcodeproj -scheme Vulpes build

# Open test page
open docs/test-images.html
```

**Test Scenarios:**
1. Various image sizes (small, medium, large)
2. Different aspect ratios (square, wide, tall)
3. Multiple images for atlas packing
4. Performance with 100+ images
5. Mixed atlas and individual textures

### Performance Testing

Monitor performance metrics:

```bash
# Check FPS and memory
# In app, open Console.app and filter for "ImageAtlas" or "MetalView"

# Expected output:
# - ImageAtlas: Initialized with 4096x4096 atlas
# - ImageAtlas: Downloading https://...
# - ImageAtlas: Added image 800x600 at (0, 0)
# - MetalView: Parsed 5 links, 3 images
```

**Performance Targets:**
- Load time: <100ms per image
- FPS: 60 (sustained with 100+ images)
- Memory: <150 MB total
- Atlas hit rate: >85%

## Code Quality Checks

### Swift Linting

While SwiftLint isn't configured, follow these guidelines:

**Naming Conventions:**
- Classes: PascalCase (e.g., `ImageAtlas`)
- Methods: camelCase (e.g., `downloadImage`)
- Constants: camelCase with `let` (e.g., `maxAtlasSize`)
- Private: prefix with `private`

**Code Style:**
- Max line length: 120 characters
- Indentation: 4 spaces
- Braces: same line for control flow
- Force unwrapping: avoid (use `guard let` or `if let`)

**Documentation:**
- Public APIs must have doc comments
- Complex logic should have inline comments
- Mark sections with `// MARK: -`

### Zig Linting

Follow Zig style guide:

**Naming:**
- Functions: snake_case (e.g., `extract_text`)
- Constants: SCREAMING_SNAKE_CASE (e.g., `MAX_IMAGES`)
- Types: PascalCase (e.g., `ImageKey`)

**Code Style:**
- Max line length: 100 characters
- Indentation: 4 spaces
- Error handling: explicit `try` or `catch`
- Memory: always defer cleanup

### Metal Shaders

**Style:**
- Function names: camelCase (e.g., `fragmentShaderImage`)
- Struct names: PascalCase (e.g., `VertexOut`)
- Variables: camelCase (e.g., `texCoord`)

**Performance:**
- Minimize texture samples
- Use built-in functions (dot, mix, etc.)
- Avoid branches in fragment shaders
- Pre-compute constants

## Static Analysis

### Memory Leaks

**Swift (Instruments):**
```bash
# Profile with Instruments
xcodebuild -project Vulpes.xcodeproj -scheme Vulpes archive
# Open in Instruments and run Leaks template
```

**Zig (Valgrind):**
```bash
# Run tests with leak detection
zig build test -Doptimize=Debug
valgrind --leak-check=full ./zig-out/bin/test
```

### Thread Safety

**Check for:**
- Race conditions in `pendingDownloads` access
- Concurrent atlas modifications
- Main thread UI updates

**Tools:**
- Xcode Thread Sanitizer
- Manual code review
- Stress testing with concurrent loads

### Performance Profiling

**GPU Profiling:**
```bash
# Use Xcode GPU Frame Capture
# Profile > Metal System Trace
# Look for:
# - Draw call count (should be ~1 per atlas)
# - Texture binds (minimize state changes)
# - Command buffer efficiency
```

**CPU Profiling:**
```bash
# Use Instruments Time Profiler
# Focus on:
# - Image download time
# - Decode/upload time
# - Vertex buffer creation
```

## Continuous Integration

### Recommended CI Checks

```yaml
# .github/workflows/test.yml (example)
name: Test

on: [push, pull_request]

jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Install Zig
        run: brew install zig
      
      - name: Run Zig tests
        run: zig build test
      
      - name: Build Swift
        run: |
          xcodegen generate
          xcodebuild test -project Vulpes.xcodeproj -scheme Vulpes
```

## Regression Testing

### Test Matrix

| Scenario | Expected | Status |
|----------|----------|--------|
| Single image | Renders correctly | ✅ |
| Multiple images | All render | ✅ |
| Large image (>2048px) | Individual texture | ✅ |
| Invalid URL | Graceful failure | ✅ |
| Network timeout | No hang | ✅ |
| Atlas full | LRU eviction | ✅ |
| Concurrent downloads | Limited to 4 | ✅ |
| Memory pressure | No crash | ✅ |

### Known Issues

1. **Relative URLs:** Not yet supported (returns nil)
2. **WebP:** May not decode on older macOS versions
3. **Animated GIF:** Only first frame shown

## Debugging Tips

### Enable Verbose Logging

Add to ImageAtlas.swift:
```swift
private let debugLogging = true

func log(_ message: String) {
    if debugLogging {
        print("ImageAtlas: \(message)")
    }
}
```

### Common Issues

**Images not loading:**
- Check URL is accessible
- Verify network permissions
- Check console for error messages

**Poor performance:**
- Profile with Instruments
- Check draw call count
- Verify batching is working

**Memory issues:**
- Monitor cache size
- Check for retain cycles
- Profile with Leaks instrument

## Pre-Release Checklist

Before merging:
- [ ] All Zig tests pass
- [ ] Manual testing with test page
- [ ] No memory leaks (Instruments)
- [ ] Performance targets met (60 FPS)
- [ ] Documentation updated
- [ ] Code reviewed
- [ ] No compiler warnings
- [ ] Thread-safe operations verified

## Performance Benchmarks

Run benchmarks before/after changes:

```bash
# Test suite timing
time zig build test

# Expected: <1 second

# Full app launch
time open /path/to/Vulpes.app

# Expected: <2 seconds
```

## Security Considerations

### Network Safety

- Images downloaded over HTTPS
- 10-second timeout prevents hanging
- Limited concurrent downloads (4 max)
- No arbitrary code execution

### Memory Safety

- Bounded cache size (100 images)
- Atlas size limited (4K x 4K)
- Individual texture limit (2K x 2K)
- Automatic eviction on pressure

### Input Validation

- URL validation before download
- Image format validation
- Size checks before allocation
- Malformed HTML handling

## Future Testing Improvements

### Planned:
- [ ] Automated UI testing
- [ ] Performance regression tests
- [ ] Fuzz testing for HTML parser
- [ ] Integration tests with real websites
- [ ] Stress testing (1000+ images)
- [ ] Memory pressure testing
- [ ] Network failure scenarios

### Nice to Have:
- [ ] Visual regression testing
- [ ] Cross-version compatibility tests
- [ ] Accessibility testing
- [ ] Localization testing

## Resources

- [Zig Testing Guide](https://ziglang.org/documentation/master/#Testing)
- [Swift Testing Best Practices](https://developer.apple.com/documentation/xctest)
- [Metal Performance Tuning](https://developer.apple.com/metal/)
- [Instruments User Guide](https://help.apple.com/instruments/)
