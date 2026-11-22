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

/// Menü çubuğunda ne kadar yer kaplanacağı.
enum MenuBarMode: String, CaseIterable, Identifiable {
    case compact, detailed
    var id: String { rawValue }
    var title: String { self == .compact ? "Kompakt" : "Ayrıntılı" }
}

struct MenuBarLabel: View {
    @ObservedObject var monitor: Monitor
    @AppStorage(Prefs.menuBarStyle) private var style = MenuBarStyle.meters
    @AppStorage(Prefs.menuBarMode) private var mode = MenuBarMode.compact
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        etiket
            .onReceive(NotificationCenter.default.publisher(for: .nabizPencereAc)) { _ in openWindow(id: "main") }
    }

    @ViewBuilder private var etiket: some View {
        let s = monitor.snapshot
        let cpu = min(max(s.cpuTotal / 100, 0), 1)
        let ram = min(max(s.memory.usedFraction, 0), 1)
        if mode == .compact {
            Image(nsImage: Self.render(MenuCompact(cpu: cpu, ram: ram)))
        } else {
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

/// Kompakt: yan yana iki dikey çubuk (sol CPU, sağ bellek) ve ikisinden yüksek olanın yüzdesi.
/// Ayrıntılar menü açılınca görünür.
struct MenuCompact: View {
    let cpu: Double
    let ram: Double

    var body: some View {
        HStack(spacing: 3) {
            HStack(alignment: .bottom, spacing: 1.5) {
                bar(cpu)
                bar(ram)
            }
            Text("\(Int((max(cpu, ram) * 100).rounded()))")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .fixedSize()
        }
        .frame(height: 18)
    }

    private func bar(_ f: Double) -> some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 1.2).opacity(0.28)
            RoundedRectangle(cornerRadius: 1.2).frame(height: max(1.5, 13 * f))
        }
        .frame(width: 3.5, height: 13)
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
    @Environment(\.openSettings) private var openSettings

    /// Ayarlar penceresini (SwiftUI `Settings` sahnesi) öne getirir.
    @MainActor static func ayarlariOneGetir() {
        NSApp.activate(ignoringOtherApps: true)
        guard let pencere = NSApp.windows.first(where: { $0.identifier?.rawValue.contains("Settings") == true }) else { return }
        pencere.makeKeyAndOrderFront(nil)
        pencere.orderFrontRegardless()
    }
    @AppStorage(Prefs.accent) private var accentHex = Color.defaultAccentHex
    @AppStorage(Prefs.colorful) private var colorful = true

    var body: some View {
        let palette = Palette(colorful: colorful, accent: Color(hex: accentHex))
        let s = monitor.snapshot
        let h = monitor.history
        let enYogun = s.processes.sorted { $0.avgCPU > $1.avgCPU }.prefix(5)
        let kapasite = max(2, Int((60 / monitor.interval).rounded()))
        let (durumSimge, durumRenk, durumYazi) = durum(s)

        VStack(alignment: .leading, spacing: 12) {
            // Başlık ve tek cümlelik durum
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Nabız").font(.headline)
                    Label(durumYazi, systemImage: durumSimge)
                        .font(.caption)
                        .foregroundStyle(durumRenk)
                }
                Spacer()
            }

            // Son 15 dakikadaki uyarı
            if let u = monitor.uyarilar.gecmis.first, u.tarih > Date().addingTimeInterval(-15 * 60) {
                Button {
                    AppDelegate.uyarilariGoster()
                } label: {
                    UyariSatiri(uyari: u, kucuk: true)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(u.renk.opacity(0.12)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Uyarılar sekmesinde aç")
            }

            // Mini kadranlar
            HStack(spacing: 4) {
                MiniKadran(baslik: "CPU", deger: Fmt.percent(s.cpuTotal), oran: s.cpuTotal / 100, renk: palette.color(.cpu))
                MiniKadran(baslik: "Bellek", deger: Fmt.percent(s.memory.usedFraction * 100), oran: s.memory.usedFraction,
                           renk: s.memory.pressureLevel > 1 ? .orange : palette.color(.memory))
                if let g = s.gpu {
                    MiniKadran(baslik: "GPU", deger: Fmt.percent(g.utilization), oran: g.utilization / 100, renk: palette.color(.gpu))
                }
                if let b = s.battery {
                    MiniKadran(baslik: b.isCharging ? "Pil ⚡︎" : "Pil", deger: Fmt.percent(b.percent), oran: b.percent / 100,
                               renk: b.percent < 15 && !b.onAC ? .red : palette.color(.battery))
                } else {
                    let dolu = s.disk.total == 0 ? 0 : 1 - Double(s.disk.free) / Double(s.disk.total)
                    MiniKadran(baslik: "Disk", deger: Fmt.percent(dolu * 100), oran: dolu, renk: palette.color(.disk))
                }
            }

            // Son 3 dakika: CPU ve bellek üst üste
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text("Son \(Int(Double(monitor.historyLength) * monitor.interval / 60)) dakika").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    nokta("CPU", palette.color(.cpu)); nokta("Bellek", palette.color(.memory))
                }
                ZStack {
                    Sparkline(values: h.map(\.memory), accent: palette.color(.memory), maxValue: 100, kapasite: monitor.historyLength)
                    Sparkline(values: h.map(\.cpu), accent: palette.color(.cpu), maxValue: 100, kapasite: monitor.historyLength)
                }
                .frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 6).fill(.quaternary.opacity(0.35)))
            }

            // Ağ
            HStack(spacing: 8) {
                Image(systemName: "network").foregroundStyle(palette.color(.network))
                Text("↓ \(Fmt.rate(s.netIn))").monospacedDigit()
                Text("↑ \(Fmt.rate(s.netOut))").monospacedDigit().foregroundStyle(.secondary)
                Spacer()
                AynaGrafik(ust: h.map(\.netIn), alt: h.map(\.netOut), renk: palette.color(.network), kapasite: monitor.historyLength)
                    .frame(width: 110, height: 24)
            }
            .font(.callout)

            Divider()
            Text("Son 1 dakikada en yoğunlar").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(enYogun)) { p in
                HStack(spacing: 8) {
                    if let icon = monitor.icon(for: p) {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "gearshape").foregroundStyle(.secondary).frame(width: 16, height: 16)
                    }
                    Text(p.name).lineLimit(1)
                    Spacer(minLength: 4)
                    MiniGraph(values: p.cpuHistory, accent: palette.color(.cpu), capacity: kapasite)
                        .frame(width: 70, height: 16)
                    Text(String(format: "%.0f%%", p.avgCPU))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                }
                .font(.callout)
                .help("\(p.path)\nŞu an %\(String(format: "%.1f", p.cpu)) · son 1 dakika ortalaması %\(String(format: "%.1f", p.avgCPU))")
            }

            Divider()
            HStack {
                Button("Nabız'ı Aç") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
                Spacer()
                // SettingsLink pencereyi açar ama Nabız sadece üst bardayken (Dock'ta değilken)
                // uygulamayı öne almaz; Ayarlar o an öndeki uygulamanın arkasında kalıyordu.
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                    DispatchQueue.main.async { Self.ayarlariOneGetir() }
                } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
                    .help("Ayarlar")
                Button("Nabız'dan Çık") { NSApp.terminate(nil) }
                    .help("Nabız'ı tamamen kapatır; menü çubuğundan da kalkar")
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func nokta(_ ad: String, _ renk: Color) -> some View {
        HStack(spacing: 4) { Circle().fill(renk).frame(width: 7, height: 7); Text(ad) }
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func durum(_ s: Snapshot) -> (String, Color, String) {
        if s.memory.pressureLevel >= 4 { return ("exclamationmark.triangle.fill", .red, "Bellek tükeniyor") }
        if s.memory.pressureLevel >= 2 { return ("exclamationmark.circle.fill", .orange, "Bellek daraldı") }
        if s.cpuTotal >= 70 { return ("flame.fill", .orange, "Mac çok çalışıyor") }
        if s.cpuTotal >= 30 { return ("bolt.fill", .yellow, "Yoğun") }
        return ("leaf.fill", .green, "Her şey sakin")
    }
}

/// Menü çubuğu penceresindeki küçük kadran.
struct MiniKadran: View {
    let baslik: String
    let deger: String
    let oran: Double
    let renk: Color

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                ArcGauge(fraction: oran, color: renk, size: 56, lineWidth: 6)
                Text(deger)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 10)
            }
            .frame(width: 60, height: 56)
            Text(baslik)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(renk)
        }
        .frame(maxWidth: .infinity)
    }
}

struct SettingsView: View {
    @AppStorage(Prefs.accent) private var accentHex = Color.defaultAccentHex
    @AppStorage(Prefs.interval) private var interval = 2.0
    @AppStorage(Prefs.showMenuBar) private var showMenuBar = true
    @AppStorage(Prefs.colorful) private var colorful = true
    @AppStorage(Prefs.menuBarStyle) private var menuBarStyle = MenuBarStyle.meters
    @AppStorage(Prefs.menuBarMode) private var menuBarMode = MenuBarMode.compact
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
            Section("Uyarılar") {
                UyariKurallari()
            }
            Section("Davranış") {
                Picker("Yenileme sıklığı", selection: $interval) {
                    Text("1 saniye").tag(1.0)
                    Text("2 saniye").tag(2.0)
                    Text("5 saniye").tag(5.0)
                }
                Toggle("Menü çubuğunda göster", isOn: $showMenuBar)
                    .onChange(of: showMenuBar) { _, acik in
                        // Üst bardan kaldırılırsa Nabız'a ulaşılabilsin diye Dock'a geri gelsin.
                        if !acik { NSApp.setActivationPolicy(.regular) }
                    }
                Text("Pencere kapalıyken Nabız Dock'ta görünmez, sadece üst barda durur.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Menü çubuğu görünümü", selection: $menuBarMode) {
                    ForEach(MenuBarMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .disabled(!showMenuBar)
                Text(menuBarMode == .compact
                     ? "Az yer kaplar: iki küçük çubuk (CPU, bellek) ve yüksek olanın değeri. Ayrıntılar menüyü açınca görünür."
                     : "CPU ve bellek ayrı ayrı yazılır; menü çubuğunda daha çok yer kaplar.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Menü çubuğu stili", selection: $menuBarStyle) {
                    ForEach(MenuBarStyle.allCases) { Text($0.title).tag($0) }
                }
                .disabled(!showMenuBar || menuBarMode == .compact)
                Toggle("Her gösterge için ayrı renk", isOn: $colorful)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}
