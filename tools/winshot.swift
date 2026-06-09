#!/usr/bin/env swift
import AppKit
import Foundation

// Captures the main on-screen window of a given app to a PNG, using screencapture -l.
// Usage: swift tools/winshot.swift <AppOwnerName> <output.png>

let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Spaceful"
let out = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "shot.png"

guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
    FileHandle.standardError.write("no window list\n".data(using: .utf8)!); exit(1)
}

// Pick the largest layer-0 window owned by `owner`.
let candidates = infos.filter {
    ($0[kCGWindowOwnerName as String] as? String) == owner &&
    ($0[kCGWindowLayer as String] as? Int) == 0
}
func area(_ w: [String: Any]) -> CGFloat {
    guard let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { return 0 }
    return (b["Width"] ?? 0) * (b["Height"] ?? 0)
}
guard let win = candidates.max(by: { area($0) < area($1) }),
      let id = win[kCGWindowNumber as String] as? Int else {
    FileHandle.standardError.write("window for \(owner) not found\n".data(using: .utf8)!); exit(2)
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
p.arguments = ["-l\(id)", "-o", "-x", out]   // window only, no shadow, no sound
try? p.run(); p.waitUntilExit()
print("captured window \(id) → \(out)")
