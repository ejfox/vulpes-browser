#!/bin/bash
set -e

VERSION="0.1.0-beta.1"
BUILD_DIR="build"
APP_NAME="Vulpes Browser"

echo "Building Vulpes $VERSION..."

# Clean previous builds
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Build Zig library
echo "Building Zig library..."
zig build -Doptimize=ReleaseFast

# Generate Xcode project
echo "Generating Xcode project..."
xcodegen generate

# Build macOS app
echo "Building macOS app..."
xcodebuild -project Vulpes.xcodeproj \
    -scheme Vulpes \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    build

# Find and copy the built app
APP_PATH=$(find "$BUILD_DIR/DerivedData" -name "Vulpes Browser.app" -type d | head -1)

if [ -z "$APP_PATH" ]; then
    echo "Error: Could not find built app"
    exit 1
fi

echo "Copying app to build directory..."
cp -R "$APP_PATH" "$BUILD_DIR/"

# Create zip for distribution
echo "Creating distribution zip..."
cd "$BUILD_DIR"
zip -r "Vulpes-Browser-${VERSION}-macOS.zip" "Vulpes Browser.app"
cd ..

echo ""
echo "Build complete!"
echo "App: $BUILD_DIR/Vulpes Browser.app"
echo "Zip: $BUILD_DIR/Vulpes-Browser-${VERSION}-macOS.zip"
