import SwiftUI
import AppKit

enum MenuBarStyle: String, CaseIterable, Identifiable {
    case meters, rings, text
    var id: String { rawValue }
    var title: String {
        switch self {
        case .meters: "Çubuklar"
        case .rings: "Halkalar"
        case .text: "Yazı"
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var monitor: Monitor
    @AppStorage(Prefs.menuBarStyle) private var style = MenuBarStyle.meters

    var body: some View {
        let s = monitor.snapshot
        let cpu = min(max(s.cpuTotal / 100, 0), 1)
        let ram = min(max(s.memory.usedFraction, 0), 1)
        switch style {
        case .text:
            Text("CPU \(Int((cpu * 100).rounded()))%  RAM \(Int((ram * 100).rounded()))%")
                .monospacedDigit()
        case .meters:
            Image(nsImage: Self.render(MenuMeters(cpu: cpu, ram: ram)))
        case .rings:
            Image(nsImage: Self.render(MenuRings(cpu: cpu, ram: ram)))
        }
    }

    /// Renders a small SwiftUI drawing into a template image, so macOS tints it
    /// to match a light or dark menu bar automatically.
    @MainActor
    static func render<V: View>(_ view: V) -> NSImage {
        let renderer = ImageRenderer(content: view.foregroundStyle(.black))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }
}

/// Two stacked rows: label · bar · percent.
struct MenuMeters: View {
    let cpu: Double
    let ram: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            row("CPU", cpu)
            row("RAM", ram)
        }
        .padding(.vertical, 1)
    }

    private func row(_ label: String, _ f: Double) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .heavy))
                .fixedSize()
                .frame(width: 19, alignment: .leading)
            ZStack(alignment: .leading) {
                Capsule().opacity(0.28)
                Capsule().frame(width: max(2.5, 26 * f))
            }
            .frame(width: 26, height: 4)
            Text("\(Int((f * 100).rounded()))%")
                .font(.system(size: 8, weight: .semibold).monospacedDigit())
                .frame(width: 22, alignment: .trailing)
        }
        .frame(height: 8)
    }
}

/// Two little dials with the value next to each.
struct MenuRings: View {
    let cpu: Double
    let ram: Double

    var body: some View {
        HStack(spacing: 6) {
            ring("C", cpu)
            ring("R", ram)
        }
        .frame(height: 18)
    }

    private func ring(_ letter: String, _ f: Double) -> some View {
        HStack(spacing: 3) {
            ZStack {
                Circle().trim(from: 0, to: 0.75)
                    .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    .opacity(0.3)
                Circle().trim(from: 0, to: 0.75 * max(f, 0.02))
                    .stroke(style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
            .rotationEffect(.degrees(135))
            .overlay(Text(letter).font(.system(size: 6.5, weight: .heavy)))
            .frame(width: 14, height: 14)
            Text("\(Int((f * 100).rounded()))%")
                .font(.system(size: 11, weight: .medium).monospacedDigit())
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var monitor: Monitor
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Prefs.accent) private var accentHex = Color.defaultAccentHex

    var body: some View {
        let accent = Color(hex: accentHex)
        let s = monitor.snapshot
        let h = monitor.history
        let top = s.processes.sorted { $0.avgCPU > $1.avgCPU }.prefix(6)
        let capacity = max(2, Int((60 / monitor.interval).rounded()))

        VStack(alignment: .leading, spacing: 12) {
            row("CPU", Fmt.percent(s.cpuTotal)) {
                Sparkline(values: h.map(\.cpu), accent: accent, maxValue: 100)
            }
            row("Bellek", "\(Fmt.bytes(s.memory.used)) / \(Fmt.bytes(s.memory.total))") {
                Sparkline(values: h.map(\.memory), accent: accent, maxValue: 100)
            }
            row("Ağ", "↓ \(Fmt.rate(s.netIn))  ↑ \(Fmt.rate(s.netOut))") {
                DualSparkline(a: h.map(\.netIn), b: h.map(\.netOut), accent: accent)
            }

            Divider()
            Text("Son 1 dakikada en yoğunlar").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(top)) { p in
                HStack(spacing: 8) {
                    if let icon = monitor.icon(for: p) {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "gearshape").foregroundStyle(.secondary).frame(width: 16, height: 16)
                    }
                    Text(p.name).lineLimit(1)
                    Spacer(minLength: 4)
                    MiniGraph(values: p.cpuHistory, accent: accent, capacity: capacity)
                        .frame(width: 80, height: 18)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(String(format: "%.1f%%", p.cpu)).monospacedDigit()
                        Text("ort. \(String(format: "%.1f", p.avgCPU))").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .frame(width: 54, alignment: .trailing)
                }
                .font(.callout)
                .help(p.path)
            }

            Divider()
            HStack {
                Button("Nabız'ı Aç") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
                    .help("Ayarlar")
                Button("Kapat") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 360)
        .tint(accent)
    }

    private func row<C: View>(_ title: String, _ value: String, @ViewBuilder chart: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Text(value).font(.callout.weight(.medium)).monospacedDigit()
            }
            chart().frame(height: 32)
        }
    }
}

struct SettingsView: View {
    @AppStorage(Prefs.accent) private var accentHex = Color.defaultAccentHex
    @AppStorage(Prefs.interval) private var interval = 2.0
    @AppStorage(Prefs.showMenuBar) private var showMenuBar = true
    @AppStorage(Prefs.colorful) private var colorful = true
    @AppStorage(Prefs.menuBarStyle) private var menuBarStyle = MenuBarStyle.meters
    @AppStorage(Prefs.appearance) private var appearance = Appearance.system.rawValue

    private let presets = ["#2FB5A8", "#3B82F6", "#8B5CF6", "#EC4899", "#F97316", "#22C55E"]

    var body: some View {
        Form {
            Section("Görünüş") {
                Picker("Görünüm", selection: $appearance) {
                    ForEach(Appearance.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Renk")
                    Spacer()
                    ForEach(presets, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 18, height: 18)
                            .overlay(Circle().stroke(.primary, lineWidth: hex == accentHex ? 2 : 0).padding(-3))
                            .onTapGesture { accentHex = hex }
                    }
                    ColorPicker("", selection: Binding(get: { Color(hex: accentHex) },
                                                       set: { accentHex = $0.hexString }),
                                supportsOpacity: false)
                        .labelsHidden()
                }
            }
            Section("Davranış") {
                Picker("Yenileme sıklığı", selection: $interval) {
                    Text("1 saniye").tag(1.0)
                    Text("2 saniye").tag(2.0)
                    Text("5 saniye").tag(5.0)
                }
                Toggle("Menü çubuğunda göster", isOn: $showMenuBar)
                Picker("Menü çubuğu stili", selection: $menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!showMenuBar)
                Toggle("Her gösterge için ayrı renk", isOn: $colorful)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
