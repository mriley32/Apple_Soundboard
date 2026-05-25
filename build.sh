#!/bin/bash

# Exit immediately if any command fails
set -e

echo "=== Starting Apple Soundboard macOS Build ==="

# 1. Compile the Swift SwiftUI code
echo "Compiling Swift source files..."
swiftc -parse-as-library -O -o Apple_Soundboard_Binary main.swift

# 2. Build the native macOS .app folder structure
echo "Creating application bundle structure..."
APP_DIR="Apple_Soundboard.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

# Clean any existing bundle
rm -rf "$APP_DIR"

# Create directories
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 3. Move the compiled binary into the MacOS folder
echo "Moving binary..."
mv Apple_Soundboard_Binary "$MACOS_DIR/Apple_Soundboard"
chmod +x "$MACOS_DIR/Apple_Soundboard"

# 4. Generate the Info.plist configuration
echo "Generating Info.plist configuration..."
cat <<EOF > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Apple_Soundboard</string>
    <key>CFBundleIdentifier</key>
    <string>com.rileym.Apple-Soundboard</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Apple Soundboard</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.entertainment</string>
</dict>
</plist>
EOF

echo "=== Build and Packaging Complete! ==="
echo "Created: $APP_DIR"
echo "You can now run this native macOS application by:"
echo "1. Double-clicking $APP_DIR in Finder."
echo "2. Running 'open $APP_DIR' from the command line."
echo ""
