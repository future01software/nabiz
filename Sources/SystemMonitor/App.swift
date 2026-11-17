import SwiftUI
import AppKit

@main
struct SystemMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var monitor = Monitor()
    @AppStorage(Prefs.showMenuBar) private var showMenuBar = true
    @AppStorage(Prefs.interval) private var interval = 2.0
    @AppStorage(Prefs.appearance) private var appearance = Appearance.system.rawValue

    var body: some Scene {
        Window("Nabız", id: "main") {
            ContentView()
                .environmentObject(monitor)
                .preferredColorScheme(Appearance(rawValue: appearance)?.scheme)
                .onAppear { monitor.interval = interval }
                .onChange(of: interval) { _, new in monitor.interval = new }
        }
        .defaultSize(width: 1240, height: 860)

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarView()
                .environmentObject(monitor)
        } label: {
            MenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .preferredColorScheme(Appearance(rawValue: appearance)?.scheme)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    // Keep running in the menu bar when the window is closed (if the menu bar item is on).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !UserDefaults.standard.bool(forKey: Prefs.showMenuBar, default: true)
    }
}

enum Prefs {
    static let accent = "accentHex"
    static let interval = "refreshInterval"
    static let showMenuBar = "showMenuBar"
    static let appearance = "appearance"
    static let colorful = "colorfulMetrics"
    static let menuBarStyle = "menuBarStyle"
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { self == .system ? "Sistem" : self == .light ? "Açık" : "Koyu" }
    var scheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

extension UserDefaults {
    func bool(forKey key: String, default value: Bool) -> Bool {
        object(forKey: key) == nil ? value : bool(forKey: key)
    }
}

// MARK: - Colors

extension Color {
    static let defaultAccentHex = "#2FB5A8"

    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        let v = UInt64(s, radix: 16) ?? 0x2FB5A8
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }

    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return Color.defaultAccentHex }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - Formatting

enum Fmt {
    static func bytes(_ b: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: b), countStyle: .memory)
    }

    private static let decimal: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .decimal
        f.allowsNonnumericFormatting = false   // "0 KB" instead of "Zero KB"
        return f
    }()

    static func rate(_ r: Double) -> String {
        decimal.string(fromByteCount: Int64(max(0, r))) + "/sn"
    }

    static func total(_ b: Double) -> String {
        decimal.string(fromByteCount: Int64(max(0, b)))
    }

    static func minutes(_ m: Int) -> String {
        m >= 60 ? "\(m / 60) sa \(m % 60) dk" : "\(m) dk"
    }

    static func percent(_ p: Double, digits: Int = 0) -> String {
        String(format: "%.\(digits)f%%", p)
    }
}
