import SwiftUI
import Charts
import AppKit

enum ProcessFilter: String, CaseIterable, Identifiable {
    case all = "Tümü"
    case mine = "Benim"
    case apps = "Uygulamalar"
    var id: String { rawValue }
}

struct ContentView: View {
    @EnvironmentObject private var monitor: Monitor
    @AppStorage(Prefs.accent) private var accentHex = Color.defaultAccentHex

    @State private var search = ""
    @State private var filter: ProcessFilter = .all
    @State private var sortOrder = [KeyPathComparator(\ProcInfo.cpu, order: .reverse)]
    @State private var selection = Set<ProcInfo.ID>()
    @State private var confirmForce: [ProcInfo] = []
    @State private var errorMessage: String?

    private var accent: Color { Color(hex: accentHex) }

    private var rows: [ProcInfo] {
        let me = NSUserName()
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return monitor.snapshot.processes
            .filter { p in
                switch filter {
                case .all: true
                case .mine: p.user == me
                case .apps: p.isApp
                }
            }
            .filter { q.isEmpty || $0.name.lowercased().contains(q) || String($0.id) == q || $0.user.lowercased() == q }
            .sorted(using: sortOrder)
    }

    private var selected: [ProcInfo] {
        monitor.snapshot.processes.filter { selection.contains($0.id) }
    }

    @AppStorage(Prefs.colorful) private var colorful = true
    @AppStorage("selectedTab.v2") private var tab = AppTab.overview

    var body: some View {
        let palette = Palette(colorful: colorful, accent: accent)
        VStack(spacing: 0) {
            LiveTabBar(tab: $tab, palette: palette)
            Divider()
            Group {
                switch tab {
                case .overview:
                    DashboardView(palette: palette, openTab: { tab = $0 }) { order in
                        sortOrder = [order]
                        tab = .processes
                    }
                case .cpu: CPUPage(palette: palette)
                case .memory: MemoryPage(palette: palette)
                case .gpu: GPUPage(palette: palette)
                case .disk: DiskPage(palette: palette)
                case .network: NetworkPage(palette: palette)
                case .battery: BatteryPage(palette: palette)
                case .uyarilar: UyarilarPage(motor: monitor.uyarilar)
                case .processes:
                    let satirlar = rows   // her yenilemede bir kez hesapla
                    VStack(spacing: 0) {
                        HStack {
                            Picker("Göster", selection: $filter) {
                                ForEach(ProcessFilter.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            Spacer()
                            Text("Seçip sağ tıklayın: Kapat, Zorla Kapat, Finder'da Göster")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        Divider()
                        processTable(satirlar)
                        Divider()
                        statusBar(gosterilen: satirlar.count)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 740)
        // Pencere açıkken Dock'ta görün; kapanınca Dock'tan kalk, sadece üst barda kal.
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            if UserDefaults.standard.bool(forKey: Prefs.showMenuBar, default: true) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
        .tint(accent)
        .searchable(text: $search, placement: .toolbar, prompt: "Ad, PID veya kullanıcı ara")
        .onChange(of: search) { _, new in if !new.isEmpty { tab = .processes } }
        .toolbar {
            if tab == .processes { ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    stop(selected, force: false)
                } label: {
                    Label("Kapat", systemImage: "xmark.circle")
                }
                .help("Seçili işlemden kapanmasını iste")
                .disabled(selection.isEmpty)

                Button {
                    confirmForce = selected
                } label: {
                    Label("Zorla Kapat", systemImage: "bolt.circle")
                }
                .help("Seçili işlemi hemen durdur")
                .disabled(selection.isEmpty)
            } }
        }
        .confirmationDialog(forceTitle, isPresented: Binding(get: { !confirmForce.isEmpty },
                                                             set: { if !$0 { confirmForce = [] } })) {
            Button("Zorla Kapat", role: .destructive) { stop(confirmForce, force: true) }
        } message: {
            Text("Kaydedilmemiş değişiklikler kaybolur.")
        }
        .alert("Kapatılamadı", isPresented: Binding(get: { errorMessage != nil },
                                                     set: { if !$0 { errorMessage = nil } })) {
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var forceTitle: String {
        confirmForce.count == 1 ? "“\(confirmForce[0].name)” zorla kapatılsın mı?" : "\(confirmForce.count) işlem zorla kapatılsın mı?"
    }

    private func processTable(_ satirlar: [ProcInfo]) -> some View {
        Table(satirlar, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Ad", value: \.name) { p in
                HStack(spacing: 6) {
                    if let icon = monitor.icon(for: p) {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "gearshape")
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    Text(p.name).lineLimit(1)
                }
                .help(p.path)
            }
            .width(min: 180, ideal: 280)

            TableColumn("CPU %", value: \.cpu) { p in
                CPUCell(value: p.cpu, restricted: p.restricted, accent: accent)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Son 1 dakika", value: \.avgCPU) { p in
                HStack(spacing: 6) {
                    MiniGraph(values: p.cpuHistory, accent: accent)
                        .frame(width: 70, height: 16)
                    Text(p.restricted ? "—" : String(format: "%.1f", p.avgCPU))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .help("Son 1 dakikadaki CPU · ortalama \(String(format: "%.1f", p.avgCPU))%")
            }
            .width(min: 110, ideal: 130)

            TableColumn("Bellek", value: \.memory) { p in
                Text(p.restricted ? "—" : Fmt.bytes(p.memory))
                    .monospacedDigit()
                    .foregroundStyle(p.restricted ? .tertiary : .primary)
            }
            .width(min: 70, ideal: 90)

            TableColumn("İş parçacığı", value: \.threads) { p in
                Text(p.restricted ? "—" : "\(p.threads)")
                    .monospacedDigit()
                    .foregroundStyle(p.restricted ? .tertiary : .primary)
            }
            .width(min: 50, ideal: 60)

            TableColumn("PID", value: \.pid) { p in
                Text(String(p.id)).monospacedDigit().foregroundStyle(.secondary)
            }
            .width(min: 50, ideal: 60)

            TableColumn("Kullanıcı", value: \.user) { p in
                Text(p.user).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 60, ideal: 100)
        }
        .contextMenu(forSelectionType: ProcInfo.ID.self) { ids in
            let procs = monitor.snapshot.processes.filter { ids.contains($0.id) }
            Button("Kapat") { stop(procs, force: false) }
            Button("Zorla Kapat…") { confirmForce = procs }
            Divider()
            if procs.count == 1, let p = procs.first, !p.path.isEmpty {
                Button("Finder'da Göster") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p.path)])
                }
            }
            Button("PID'yi Kopyala") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(procs.map { String($0.id) }.joined(separator: " "), forType: .string)
            }
        }
    }

    private func statusBar(gosterilen: Int) -> some View {
        let procs = monitor.snapshot.processes
        let threads = procs.reduce(0) { $0 + Int($1.threads) }
        return HStack {
            Text("\(procs.count) işlem · \(threads) iş parçacığı")
            Spacer()
            if gosterilen != procs.count { Text("\(gosterilen) gösteriliyor") }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func stop(_ procs: [ProcInfo], force: Bool) {
        var errors: [String] = []
        for p in procs {
            do { try monitor.quit(p, force: force) } catch { errors.append(error.localizedDescription) }
        }
        if !errors.isEmpty { errorMessage = errors.joined(separator: "\n") }
        selection.removeAll()
    }
}

/// Lightweight per-row graph (drawn with Canvas so hundreds of rows stay fast).
/// Scale: 0–100% (one core), grows if a process uses more than one core.
struct MiniGraph: View {
    let values: [Double]
    let accent: Color
    var capacity = 30

    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 3),
                     with: .color(.secondary.opacity(0.12)))
            guard values.count > 1 else { return }
            let top = max(100, values.max() ?? 100)
            let step = size.width / CGFloat(max(capacity, values.count) - 1)
            let startX = size.width - step * CGFloat(values.count - 1)
            var line = Path()
            for (i, v) in values.enumerated() {
                let pt = CGPoint(x: startX + step * CGFloat(i),
                                 y: size.height - size.height * CGFloat(v / top))
                i == 0 ? line.move(to: pt) : line.addLine(to: pt)
            }
            var area = line
            area.addLine(to: CGPoint(x: size.width, y: size.height))
            area.addLine(to: CGPoint(x: startX, y: size.height))
            area.closeSubpath()
            ctx.fill(area, with: .color(accent.opacity(0.3)))
            ctx.stroke(line, with: .color(accent), lineWidth: 1.2)
        }
    }
}

struct CPUCell: View {
    let value: Double
    let restricted: Bool
    let accent: Color

    var body: some View {
        if restricted {
            Text("—").foregroundStyle(.tertiary)
        } else {
            Text(String(format: "%.1f", value))
                .monospacedDigit()
                .fontWeight(value >= 50 ? .semibold : .regular)
                .foregroundStyle(value >= 80 ? Color.orange : .primary)
        }
    }
}

// MARK: - Hafif grafikler (Canvas: Swift Charts'tan çok daha az işlemci harcar)

/// Değerleri sağa yaslı çizer (en yeni değer en sağda). `kapasite` kadar noktaya yer ayırır.
private func cizgiYolu(_ degerler: [Double], tepe: Double, boyut: CGSize, kapasite: Int, ters: Bool = false, orta: CGFloat? = nil) -> (cizgi: Path, alan: Path)? {
    guard degerler.count > 1, tepe > 0 else { return nil }
    let n = max(kapasite, degerler.count)
    let adim = boyut.width / CGFloat(n - 1)
    let x0 = boyut.width - adim * CGFloat(degerler.count - 1)
    let taban = orta ?? boyut.height
    let yukseklik = orta ?? boyut.height
    var cizgi = Path()
    for (i, v) in degerler.enumerated() {
        let oran = CGFloat(min(max(v / tepe, 0), 1))
        let y = ters ? taban + (boyut.height - taban) * oran : taban - yukseklik * oran
        let p = CGPoint(x: x0 + adim * CGFloat(i), y: y)
        i == 0 ? cizgi.move(to: p) : cizgi.addLine(to: p)
    }
    var alan = cizgi
    alan.addLine(to: CGPoint(x: boyut.width, y: taban))
    alan.addLine(to: CGPoint(x: x0, y: taban))
    alan.closeSubpath()
    return (cizgi, alan)
}

struct Sparkline: View {
    let values: [Double]
    let accent: Color
    var maxValue: Double? = nil
    var kapasite = 90

    var body: some View {
        Canvas { ctx, size in
            let tepe = maxValue ?? max(1, values.max() ?? 1)
            guard let y = cizgiYolu(values, tepe: tepe, boyut: size, kapasite: kapasite) else { return }
            ctx.fill(y.alan, with: .linearGradient(Gradient(colors: [accent.opacity(0.35), accent.opacity(0.03)]),
                                                   startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.stroke(y.cizgi, with: .color(accent), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        }
    }
}

struct DualSparkline: View {
    let a: [Double]
    let b: [Double]
    let accent: Color
    var kapasite = 90

    var body: some View {
        Canvas { ctx, size in
            let tepe = max(1, (a + b).max() ?? 1)
            if let y = cizgiYolu(a, tepe: tepe, boyut: size, kapasite: kapasite) {
                ctx.stroke(y.cizgi, with: .color(accent), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
            if let y = cizgiYolu(b, tepe: tepe, boyut: size, kapasite: kapasite) {
                ctx.stroke(y.cizgi, with: .color(accent.opacity(0.5)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, dash: [3, 2]))
            }
        }
    }
}

/// Üstte bir seri (ör. indirme), altta aynalanmış ikinci seri (ör. yükleme).
struct AynaGrafik: View {
    let ust: [Double]
    let alt: [Double]
    let renk: Color
    var kapasite = 90

    var body: some View {
        Canvas { ctx, size in
            let tepe = max(1024, (ust + alt).max() ?? 1)
            let orta = size.height / 2
            if let y = cizgiYolu(ust, tepe: tepe, boyut: size, kapasite: kapasite, orta: orta) {
                ctx.fill(y.alan, with: .linearGradient(Gradient(colors: [renk.opacity(0.7), renk.opacity(0.1)]),
                                                       startPoint: .zero, endPoint: CGPoint(x: 0, y: orta)))
            }
            if let y = cizgiYolu(alt, tepe: tepe, boyut: size, kapasite: kapasite, ters: true, orta: orta) {
                ctx.fill(y.alan, with: .linearGradient(Gradient(colors: [renk.opacity(0.05), renk.opacity(0.4)]),
                                                       startPoint: CGPoint(x: 0, y: orta), endPoint: CGPoint(x: 0, y: size.height)))
            }
            var cizgi = Path(); cizgi.move(to: CGPoint(x: 0, y: orta)); cizgi.addLine(to: CGPoint(x: size.width, y: orta))
            ctx.stroke(cizgi, with: .color(.secondary.opacity(0.4)), lineWidth: 0.5)
        }
    }
}
