import SwiftUI

@main
struct SpacefulApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 980, minHeight: 640)
                .onAppear {
                    // Optional: open a folder straight away when a path is supplied on the
                    // command line (`Spaceful /path`) or via the SPACEFUL_OPEN env var —
                    // handy for "open with", scripting and automated captures.
                    if let url = LaunchOptions.initialFolder { model.startScan(url) }
                    if let viz = LaunchOptions.initialViz { model.vizMode = viz }
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

/// Reads an optional startup folder from the launch arguments or environment.
enum LaunchOptions {
    static var initialFolder: URL? {
        let candidate = CommandLine.arguments.dropFirst().first { !$0.hasPrefix("-") }
            ?? ProcessInfo.processInfo.environment["SPACEFUL_OPEN"]
        guard let path = candidate else { return nil }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    /// Optional initial visualization (`SPACEFUL_VIZ=treemap|sunburst`).
    static var initialViz: VizMode? {
        ProcessInfo.processInfo.environment["SPACEFUL_VIZ"].flatMap(VizMode.init(rawValueLoose:))
    }
}

private extension VizMode {
    init?(rawValueLoose s: String) {
        switch s.lowercased() {
        case "treemap": self = .treemap
        case "sunburst", "soleil": self = .sunburst
        default: return nil
        }
    }
}
