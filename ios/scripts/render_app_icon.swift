import Foundation

// Compatibility entry point only. The owned SVG is rendered by the portable
// Python renderer; no AppKit, font glyphs or system-symbol artwork is used.
// Preferred cross-platform command, from the repo root:
// python3 tools/render-brand-assets.py
// Existing macOS usage: swift ios/scripts/render_app_icon.swift [output.png]
let script = URL(fileURLWithPath: #filePath).standardizedFileURL
let root = script.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let renderer = root.appendingPathComponent("tools/render-brand-assets.py")
let output = CommandLine.arguments.dropFirst().first
    ?? root.appendingPathComponent("ios/HydroCap/Assets.xcassets/AppIcon.appiconset/icon-1024.png").path
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = ["python3", renderer.path, "--ios-only", "--ios-output", output]
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
