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
                case .processes:
                    VStack(spacing: 0) {
                        processTable
                        Divider()
                        statusBar
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 740)
        .tint(accent)
        .searchable(text: $search, placement: .toolbar, prompt: "Ad, PID veya kullanıcı ara")
        .onChange(of: search) { _, new in if !new.isEmpty { tab = .processes } }
        .toolbar {
            if tab == .processes {
                ToolbarItem(placement: .navigation) {
                    Picker("Göster", selection: $filter) {
                        ForEach(ProcessFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }
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

    private var processTable: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
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

    private var statusBar: some View {
        let procs = monitor.snapshot.processes
        let threads = procs.reduce(0) { $0 + Int($1.threads) }
        return HStack {
            Text("\(procs.count) işlem · \(threads) iş parçacığı")
            Spacer()
            if rows.count != procs.count { Text("\(rows.count) gösteriliyor") }
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

// MARK: - Summary cards

struct SummaryCards: View {
    @EnvironmentObject private var monitor: Monitor
    let accent: Color

    var body: some View {
        let s = monitor.snapshot
        let h = monitor.history
        HStack(alignment: .top, spacing: 12) {
            MetricCard(title: "CPU", icon: "cpu", value: Fmt.percent(s.cpuTotal),
                       detail: "Kullanıcı \(Fmt.percent(s.cpuUser)) · Sistem \(Fmt.percent(s.cpuSystem))") {
                VStack(spacing: 6) {
                    Sparkline(values: h.map(\.cpu), accent: accent, maxValue: 100)
                    CoreBars(cores: s.cores, accent: accent)
                }
            }
            MetricCard(title: "Bellek", icon: "memorychip",
                       value: "\(Fmt.bytes(s.memory.used)) / \(Fmt.bytes(s.memory.total))",
                       detail: memoryDetail(s.memory)) {
                VStack(alignment: .leading, spacing: 6) {
                    Sparkline(values: h.map(\.memory), accent: accent, maxValue: 100)
                    PressureBadge(level: s.memory.pressureLevel)
                }
            }
            MetricCard(title: "Ağ", icon: "arrow.up.arrow.down",
                       value: "↓ \(Fmt.rate(s.netIn))",
                       detail: "↑ \(Fmt.rate(s.netOut))") {
                DualSparkline(a: h.map(\.netIn), b: h.map(\.netOut), accent: accent)
            }
            MetricCard(title: "Disk", icon: "internaldrive",
                       value: "R \(Fmt.rate(s.diskRead))",
                       detail: "W \(Fmt.rate(s.diskWrite))") {
                DualSparkline(a: h.map(\.diskRead), b: h.map(\.diskWrite), accent: accent)
            }
        }
    }

    private func memoryDetail(_ m: MemoryInfo) -> String {
        var parts = ["App \(Fmt.bytes(m.app))", "Wired \(Fmt.bytes(m.wired))", "Compressed \(Fmt.bytes(m.compressed))"]
        if m.swapUsed > 0 { parts.append("Swap \(Fmt.bytes(m.swapUsed))") }
        return parts.joined(separator: " · ")
    }
}

struct MetricCard<Content: View>: View {
    let title: String
    let icon: String
    let value: String
    let detail: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct Sparkline: View {
    let values: [Double]
    let accent: Color
    var maxValue: Double? = nil

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { i, v in
            AreaMark(x: .value("t", i), y: .value("v", v))
                .foregroundStyle(accent.opacity(0.25).gradient)
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", i), y: .value("v", v))
                .foregroundStyle(accent)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
                .interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...max(1, values.count - 1))
        .chartYScale(domain: 0...(maxValue ?? max(1, values.max() ?? 1)))
        .frame(height: 44)
    }
}

struct DualSparkline: View {
    let a: [Double]
    let b: [Double]
    let accent: Color

    var body: some View {
        let top = max(1, (a + b).max() ?? 1)
        Chart {
            ForEach(Array(a.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("t", i), y: .value("v", v), series: .value("s", "a"))
                    .foregroundStyle(accent)
                    .interpolationMethod(.monotone)
            }
            ForEach(Array(b.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("t", i), y: .value("v", v), series: .value("s", "b"))
                    .foregroundStyle(accent.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                    .interpolationMethod(.monotone)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: 0...max(1, a.count - 1))
        .chartYScale(domain: 0...top)
        .frame(height: 44)
    }
}

struct CoreBars: View {
    let cores: [Double]
    let accent: Color

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(cores.enumerated()), id: \.offset) { _, v in
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(accent)
                            .frame(height: max(1, geo.size.height * v / 100))
                    }
                }
                .background(RoundedRectangle(cornerRadius: 1.5).fill(.quaternary))
            }
        }
        .frame(height: 18)
        .help("Her çubuk bir CPU çekirdeği")
    }
}

struct PressureBadge: View {
    let level: Int

    var body: some View {
        let (text, color): (String, Color) = switch level {
        case 4: ("Bellek baskısı: kritik", .red)
        case 2: ("Bellek baskısı: yüksek", .orange)
        default: ("Bellek baskısı: normal", .green)
        }
        Label {
            Text(text).font(.caption2).foregroundStyle(.secondary)
        } icon: {
            Circle().fill(color).frame(width: 7, height: 7)
        }
    }
}
