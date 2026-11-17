import SwiftUI
import Charts
import AppKit

// MARK: - Tabs

enum AppTab: String, CaseIterable, Identifiable {
    case overview, cpu, memory, gpu, disk, network, battery, processes
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Genel Bakış"
        case .processes: "İşlemler"
        default: metric!.title
        }
    }

    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .cpu: "cpu"
        case .memory: "memorychip"
        case .gpu: "cube.transparent"
        case .disk: "internaldrive"
        case .network: "network"
        case .battery: "battery.75percent"
        case .processes: "list.bullet.rectangle"
        }
    }

    var metric: Metric? {
        switch self {
        case .cpu: .cpu
        case .memory: .memory
        case .gpu: .gpu
        case .disk: .disk
        case .network: .network
        case .battery: .battery
        default: nil
        }
    }
}

/// Tabs that also show each section's live value.
struct LiveTabBar: View {
    @EnvironmentObject private var monitor: Monitor
    @Binding var tab: AppTab
    let palette: Palette

    var body: some View {
        let s = monitor.snapshot
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(visibleTabs(s)) { t in
                    let color = t.metric.map { palette.color($0) } ?? palette.accent
                    let selected = t == tab
                    Button { tab = t } label: {
                        HStack(spacing: 7) {
                            Image(systemName: t.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(selected ? color : .secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(t.title).font(.callout.weight(selected ? .semibold : .regular))
                                Text(value(t, s))
                                    .font(.caption2.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(selected ? color : .secondary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(selected ? color.opacity(0.16) : .clear)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(selected ? color.opacity(0.45) : .clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(shortcut(t), modifiers: .command)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func visibleTabs(_ s: Snapshot) -> [AppTab] {
        AppTab.allCases.filter { t in
            switch t {
            case .gpu: s.gpu != nil
            case .battery: s.battery != nil
            default: true
            }
        }
    }

    private func shortcut(_ t: AppTab) -> KeyEquivalent {
        let index = AppTab.allCases.firstIndex(of: t) ?? 0
        return KeyEquivalent(Character(String(index + 1)))
    }

    private func value(_ t: AppTab, _ s: Snapshot) -> String {
        switch t {
        case .overview: return s.memory.pressureLevel > 1 ? "Bellek dar" : s.cpuTotal >= 70 ? "Yoğun" : "Her şey sakin"
        case .cpu: return Fmt.percent(s.cpuTotal)
        case .memory: return Fmt.percent(s.memory.usedFraction * 100)
        case .gpu: return Fmt.percent(s.gpu?.utilization ?? 0)
        case .disk: return "\(Fmt.bytes(s.disk.free)) boş"
        case .network: return "↓ \(Fmt.rate(s.netIn))"
        case .battery:
            guard let b = s.battery else { return "—" }
            return Fmt.percent(b.percent) + (b.isCharging ? " ⚡︎" : "")
        case .processes: return "\(s.processes.count)"
        }
    }
}

// MARK: - Shared page pieces

/// Left: a big dial plus a list of numbers. Right: charts and lists.
struct DetailLayout<Header: View, Main: View>: View {
    let stats: [(String, String)]
    @ViewBuilder let header: Header
    @ViewBuilder let main: Main

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Panel {
                header
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                StatRows(rows: stats)
                Spacer(minLength: 0)
            }
            .frame(width: 290)
            .frame(maxHeight: .infinity)

            VStack(spacing: 16) { main }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(16)
    }
}

struct StatRows: View {
    let rows: [(String, String)]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                HStack {
                    Text(row.0).foregroundStyle(.secondary)
                    Spacer()
                    Text(row.1).monospacedDigit().multilineTextAlignment(.trailing)
                }
                .font(.callout)
                .padding(.vertical, 6)
                if i < rows.count - 1 { Divider().opacity(0.5) }
            }
        }
    }
}

struct BigDial: View {
    let fraction: Double
    let color: Color
    let value: String
    let caption: String

    var body: some View {
        ZStack {
            ArcGauge(fraction: fraction, color: color, size: 150, lineWidth: 14)
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(caption).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 30)
        }
        .frame(width: 160, height: 150)
    }
}

struct ChartSeries: Identifiable {
    var id: String { name }
    let name: String
    let color: Color
    let values: [Double]
}

/// Line/area chart over the history window. `stacked` stacks the areas (e.g. user + system CPU).
struct HistoryChart: View {
    @EnvironmentObject private var monitor: Monitor
    let title: String
    let series: [ChartSeries]
    var maxValue: Double? = nil
    var stacked = false
    var format: (Double) -> String = { "\(Int($0))%" }

    var body: some View {
        let length = monitor.historyLength
        let top = maxValue ?? max(1, series.flatMap(\.values).max() ?? 1) * 1.15
        Panel {
            HStack {
                Label(title, systemImage: "waveform.path.ecg").font(.headline)
                Spacer()
                ForEach(series) { s in
                    HStack(spacing: 5) {
                        Circle().fill(s.color).frame(width: 8, height: 8)
                        Text(s.name)
                        if let last = s.values.last {
                            Text(format(last)).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
            }
            Chart {
                ForEach(series) { s in
                    let shift = length - s.values.count
                    ForEach(Array(s.values.enumerated()), id: \.offset) { i, v in
                        if stacked {
                            AreaMark(x: .value("t", i + shift), y: .value("v", v), stacking: .standard)
                                .foregroundStyle(by: .value("s", s.name))
                                .interpolationMethod(.monotone)
                        } else {
                            AreaMark(x: .value("t", i + shift), yStart: .value("v", 0), yEnd: .value("v", v),
                                     series: .value("s", s.name))
                                .foregroundStyle(LinearGradient(colors: [s.color.opacity(0.35), s.color.opacity(0.02)],
                                                                startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.monotone)
                            LineMark(x: .value("t", i + shift), y: .value("v", v), series: .value("s", s.name))
                                .foregroundStyle(s.color)
                                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                                .interpolationMethod(.monotone)
                        }
                    }
                }
            }
            .chartForegroundStyleScale(domain: series.map(\.name), range: series.map { $0.color.opacity(0.75) })
            .chartLegend(.hidden)
            .chartXScale(domain: 0...max(1, length - 1))
            .chartYScale(domain: 0...top)
            .chartXAxis {
                AxisMarks(values: [0, length / 2, length - 1]) { v in
                    AxisValueLabel {
                        if let i = v.as(Int.self) {
                            let secs = Double(length - 1 - i) * monitor.interval
                            Text(secs == 0 ? "şimdi" : "\(Int(secs / 60)) dk \(Int(secs) % 60) sn önce")
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(format(d)) } }
                }
            }
            .frame(minHeight: 90, maxHeight: .infinity)
        }
    }
}

/// Bars for the last 7 days.
struct WeekBars: View {
    let title: String
    let days: [DayTotals]
    let color: Color
    let a: (DayTotals) -> Double
    let aName: String
    let b: (DayTotals) -> Double
    let bName: String

    private static let inFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f }()
    private static let outFmt: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE"; return f }()

    var body: some View {
        Panel {
            HStack {
                Label(title, systemImage: "calendar").font(.headline)
                Spacer()
                legend(color, aName)
                legend(color.opacity(0.45), bName)
            }
            Chart {
                ForEach(days.suffix(7), id: \.day) { d in
                    BarMark(x: .value("Day", label(d.day)), y: .value("v", a(d)))
                        .foregroundStyle(color)
                        .position(by: .value("k", aName))
                        .cornerRadius(4)
                    BarMark(x: .value("Day", label(d.day)), y: .value("v", b(d)))
                        .foregroundStyle(color.opacity(0.45))
                        .position(by: .value("k", bName))
                        .cornerRadius(4)
                }
            }
            .chartYAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { v in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.total(d)) } }
                }
            }
            .frame(minHeight: 90, maxHeight: .infinity)
        }
    }

    private func legend(_ c: Color, _ name: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 10, height: 10)
            Text(name)
        }
        .font(.caption)
    }

    private func label(_ day: String) -> String {
        guard let d = Self.inFmt.date(from: day) else { return day }
        return Calendar.current.isDateInToday(d) ? "Bugün" : Self.outFmt.string(from: d)
    }
}

/// The processes that used the most CPU over the last minute, with their mini graphs.
struct TopProcessesPanel: View {
    @EnvironmentObject private var monitor: Monitor
    let title: String
    let color: Color
    var count = 8
    var byMemory = false

    var body: some View {
        let procs = monitor.snapshot.processes
            .filter { !$0.restricted }
            .sorted { byMemory ? $0.memory > $1.memory : $0.avgCPU > $1.avgCPU }
            .prefix(count)
        let capacity = max(2, Int((60 / monitor.interval).rounded()))
        Panel {
            Label(title, systemImage: "list.number").font(.headline)
            VStack(spacing: 5) {
                ForEach(Array(procs)) { p in
                    HStack(spacing: 8) {
                        if let icon = monitor.icon(for: p) {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        } else {
                            Image(systemName: "gearshape").foregroundStyle(.secondary).frame(width: 16, height: 16)
                        }
                        Text(p.name).lineLimit(1)
                        Spacer()
                        if byMemory {
                            Text(Fmt.bytes(p.memory)).monospacedDigit().foregroundStyle(.secondary)
                        } else {
                            MiniGraph(values: p.cpuHistory, accent: color, capacity: capacity)
                                .frame(width: 90, height: 16)
                            Text(String(format: "%.1f%%", p.avgCPU))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 52, alignment: .trailing)
                        }
                    }
                    .font(.callout)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
}

// MARK: - CPU

struct CPUPage: View {
    @EnvironmentObject private var monitor: Monitor
    let palette: Palette

    var body: some View {
        let s = monitor.snapshot
        let info = SystemInfo.current
        let today = monitor.daily.today
        let color = palette.color(.cpu)
        DetailLayout(stats: [
            ("Kullanıcı", Fmt.percent(s.cpuUser, digits: 1)),
            ("Sistem", Fmt.percent(s.cpuSystem, digits: 1)),
            ("Boşta", Fmt.percent(max(0, 100 - s.cpuTotal), digits: 1)),
            ("Bugünkü ortalama", Fmt.percent(today.cpuAverage)),
            ("Bugünkü en yüksek", Fmt.percent(today.cpuPeak)),
            ("Çip", info.chip),
            ("Çekirdekler", "\(info.performanceCores) performans + \(info.efficiencyCores) verimlilik"),
            ("İşlemler", "\(s.processes.count)"),
            ("İş parçacığı", "\(s.processes.reduce(0) { $0 + Int($1.threads) })"),
        ]) {
            BigDial(fraction: s.cpuTotal / 100, color: color, value: Fmt.percent(s.cpuTotal), caption: "kullanımda")
        } main: {
            HistoryChart(title: "CPU", series: [
                ChartSeries(name: "Kullanıcı", color: color, values: monitor.history.map(\.cpuUser)),
                ChartSeries(name: "Sistem", color: color.opacity(0.45), values: monitor.history.map(\.cpuSystem)),
            ], maxValue: 100, stacked: true)

            Panel {
                Label("Her çekirdek", systemImage: "square.grid.3x3").font(.headline)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], spacing: 8) {
                    ForEach(Array(s.cores.enumerated()), id: \.offset) { i, v in
                        VStack(spacing: 4) {
                            GeometryReader { geo in
                                ZStack(alignment: .bottom) {
                                    RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.12))
                                    RoundedRectangle(cornerRadius: 5).fill(color)
                                        .frame(height: max(2, geo.size.height * v / 100))
                                        .animation(.easeOut(duration: 0.4), value: v)
                                }
                            }
                            .frame(height: 38)
                            Text("\(i + 1) · \(Int(v))%").font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                }
            }

            TopProcessesPanel(title: "Son 1 dakikada en yoğunlar", color: color)
        }
    }
}

// MARK: - Memory

struct MemoryPage: View {
    @EnvironmentObject private var monitor: Monitor
    let palette: Palette

    var body: some View {
        let m = monitor.snapshot.memory
        let color = palette.color(.memory)
        let free = m.total > m.used + m.cached ? m.total - m.used - m.cached : 0
        let parts: [(String, UInt64, Color)] = [
            ("Uygulama", m.app, color),
            ("Kalıcı", m.wired, color.opacity(0.7)),
            ("Sıkıştırılmış", m.compressed, color.opacity(0.45)),
            ("Önbellekteki dosyalar", m.cached, .secondary.opacity(0.45)),
            ("Boş", free, .secondary.opacity(0.15)),
        ]
        DetailLayout(stats: [
            ("Kullanılan", Fmt.bytes(m.used)),
            ("Uygulama belleği", Fmt.bytes(m.app)),
            ("Kalıcı", Fmt.bytes(m.wired)),
            ("Sıkıştırılmış", Fmt.bytes(m.compressed)),
            ("Önbellekteki dosyalar", Fmt.bytes(m.cached)),
            ("Boş", Fmt.bytes(free)),
            ("Kullanılan takas", "\(Fmt.bytes(m.swapUsed)) / \(Fmt.bytes(m.swapTotal))"),
            ("Baskı", m.pressureLevel >= 4 ? "Kritik" : m.pressureLevel >= 2 ? "Yüksek" : "Normal"),
        ]) {
            BigDial(fraction: m.usedFraction, color: m.pressureLevel > 1 ? .orange : color,
                    value: Fmt.bytes(m.used), caption: "toplam \(Fmt.bytes(m.total))")
        } main: {
            Panel {
                Label("Bellekte ne var", systemImage: "square.stack.3d.up").font(.headline)
                GeometryReader { geo in
                    HStack(spacing: 3) {
                        ForEach(parts, id: \.0) { part in
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(part.2)
                                .frame(width: max(3, (geo.size.width - 12) * Double(part.1) / Double(max(m.total, 1))))
                                .help("\(part.0): \(Fmt.bytes(part.1))")
                        }
                    }
                }
                .frame(height: 26)
                HStack(spacing: 16) {
                    ForEach(parts, id: \.0) { part in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(part.2).frame(width: 10, height: 10)
                            Text(part.0).foregroundStyle(.secondary)
                            Text(Fmt.bytes(part.1)).monospacedDigit()
                        }
                        .font(.caption)
                    }
                }
            }

            HistoryChart(title: "Kullanılan bellek", series: [
                ChartSeries(name: "Kullanılan", color: color, values: monitor.history.map(\.memory)),
            ], maxValue: 100)

            ShareBar(title: "En çok kullanan uygulamalar", icon: "memorychip", color: color,
                     shares: monitor.shares(top: 6) { Double($0.memory) },
                     format: { Fmt.bytes(UInt64($0)) }, onMore: nil)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - GPU

struct GPUPage: View {
    @EnvironmentObject private var monitor: Monitor
    let palette: Palette

    var body: some View {
        let g = monitor.snapshot.gpu
        let today = monitor.daily.today
        let color = palette.color(.gpu)
        DetailLayout(stats: [
            ("Grafik", g?.name ?? "—"),
            ("GPU çekirdekleri", g?.cores.map(String.init) ?? "—"),
            ("Kullanılan bellek", g.map { Fmt.bytes($0.memoryInUse) } ?? "—"),
            ("Bugünkü ortalama", Fmt.percent(today.gpuAverage)),
            ("Bugünkü en yüksek", Fmt.percent(today.gpuPeak)),
        ]) {
            BigDial(fraction: (g?.utilization ?? 0) / 100, color: color,
                    value: Fmt.percent(g?.utilization ?? 0), caption: "meşgul")
        } main: {
            HistoryChart(title: "GPU", series: [
                ChartSeries(name: "Yoğun", color: color, values: monitor.history.map(\.gpu)),
            ], maxValue: 100)
            Panel {
                Label("Bilmekte fayda var", systemImage: "info.circle").font(.headline)
                Text("GPU ekrandaki her şeyi çizer, video oynatır, oyunları ve yapay zekâ araçlarını çalıştırır. Kısa sıçramalar normaldir; siz bir şey yapmazken GPU meşgul kalıyorsa genelde bir uygulama arka planda animasyon çalıştırıyordur.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Uygulama başına GPU kullanımı macOS'ta yönetici izni gerektirdiği için burada gösterilmiyor.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Disk

struct DiskPage: View {
    @EnvironmentObject private var monitor: Monitor
    let palette: Palette

    var body: some View {
        let s = monitor.snapshot
        let today = monitor.daily.today
        let week = monitor.daily.lastWeek
        let color = palette.color(.disk)
        let used = s.disk.total > s.disk.free ? s.disk.total - s.disk.free : 0
        DetailLayout(stats: [
            ("Boş", Fmt.bytes(s.disk.free)),
            ("Kullanılan", Fmt.bytes(used)),
            ("Kapasite", Fmt.bytes(s.disk.total)),
            ("Şu an okunan", Fmt.rate(s.diskRead)),
            ("Şu an yazılan", Fmt.rate(s.diskWrite)),
            ("Bugün okunan", Fmt.total(today.diskRead)),
            ("Bugün yazılan", Fmt.total(today.diskWrite)),
            ("7 günde yazılan", Fmt.total(week.diskWrite)),
        ]) {
            BigDial(fraction: s.disk.total == 0 ? 0 : Double(used) / Double(s.disk.total), color: color,
                    value: Fmt.bytes(s.disk.free), caption: "boş")
        } main: {
            MirrorPanel(title: "Disk etkinliği", icon: "internaldrive", color: color,
                        upLabel: "Okuma", downLabel: "Yazma",
                        up: monitor.history.map(\.diskRead), down: monitor.history.map(\.diskWrite),
                        upNow: s.diskRead, downNow: s.diskWrite, footer: [])
            HStack(alignment: .top, spacing: 16) {
                Panel {
                    Label("Diskler", systemImage: "externaldrive").font(.headline)
                    ForEach(s.volumes) { v in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: v.isInternal ? "internaldrive" : "externaldrive")
                                    .foregroundStyle(.secondary)
                                Text(v.name).lineLimit(1)
                                Spacer()
                                Text("\(Fmt.bytes(v.free)) boş · toplam \(Fmt.bytes(v.total))")
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                            ProgressView(value: Double(v.total - min(v.free, v.total)), total: Double(v.total))
                                .tint(color)
                        }
                        .help(v.path)
                    }
                    Spacer(minLength: 0)
                }
                WeekBars(title: "Son 7 gün", days: monitor.daily.days, color: color,
                         a: \.diskWrite, aName: "Yazılan", b: \.diskRead, bName: "Okuma")
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Network

struct NetworkPage: View {
    @EnvironmentObject private var monitor: Monitor
    let palette: Palette

    var body: some View {
        let s = monitor.snapshot
        let today = monitor.daily.today
        let week = monitor.daily.lastWeek
        let color = palette.color(.network)
        DetailLayout(stats: [
            ("İndirme", Fmt.rate(s.netIn)),
            ("Yükleme", Fmt.rate(s.netOut)),
            ("Bugün indirilen", Fmt.total(today.netIn)),
            ("Bugün yüklenen", Fmt.total(today.netOut)),
            ("7 günde indirilen", Fmt.total(week.netIn)),
            ("7 günde yüklenen", Fmt.total(week.netOut)),
        ]) {
            VStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill").font(.system(size: 34)).foregroundStyle(color)
                Text(Fmt.rate(s.netIn))
                    .font(.system(size: 26, weight: .bold, design: .rounded)).monospacedDigit()
                Text("↑ \(Fmt.rate(s.netOut))").foregroundStyle(.secondary).monospacedDigit()
            }
            .frame(height: 150)
        } main: {
            MirrorPanel(title: "Trafik", icon: "arrow.up.arrow.down", color: color,
                        upLabel: "İndirme", downLabel: "Yükleme",
                        up: monitor.history.map(\.netIn), down: monitor.history.map(\.netOut),
                        upNow: s.netIn, downNow: s.netOut, footer: [])
            HStack(alignment: .top, spacing: 16) {
                Panel {
                    Label("Bağlantılar", systemImage: "point.3.connected.trianglepath.dotted").font(.headline)
                    if s.interfaces.isEmpty {
                        Text("Bağlı değil").foregroundStyle(.secondary)
                    }
                    ForEach(s.interfaces) { i in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Circle().fill(.green).frame(width: 7, height: 7)
                                Text(i.displayName)
                                Text(i.bsdName).font(.caption).foregroundStyle(.tertiary)
                            }
                            ForEach(i.addresses, id: \.self) { a in
                                Text(a).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                WeekBars(title: "Son 7 gün", days: monitor.daily.days, color: color,
                         a: \.netIn, aName: "İndirme", b: \.netOut, bName: "Yükleme")
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Battery

struct BatteryPage: View {
    @EnvironmentObject private var monitor: Monitor
    let palette: Palette

    var body: some View {
        let s = monitor.snapshot
        let color = palette.color(.battery)
        if let b = s.battery {
            DetailLayout(stats: ([
                ("Durum", b.isCharging ? "Şarj oluyor" : b.onAC ? "Prize takılı" : "Pilde"),
                ("Kalan süre", b.isCharging ? (b.minutesToFull.map { "\(Fmt.minutes($0)) sonra dolu" } ?? "—")
                                           : (b.minutesToEmpty.map(Fmt.minutes) ?? (b.onAC ? "—" : "Hesaplanıyor…"))),
                ("Mac'in güç kullanımı", b.systemWatts.map { String(format: "%.1f W", $0) } ?? "—"),
                ("Pil akışı", b.watts.map { $0 >= 0 ? String(format: "%.1f W harcıyor", $0) : String(format: "%.1f W şarj ediyor", -$0) } ?? "—"),
                ("Sağlık", b.healthPercent.map { Fmt.percent($0) } ?? "—"),
                ("Kapasite", b.maxCapacity.map { m in "\(m) / \(b.designCapacity ?? m) mAh" } ?? "—"),
                ("Döngü", b.cycleCount.map(String.init) ?? "—"),
                ("Temperature", b.temperature.map { String(format: "%.1f °C", $0) } ?? "—"),
                ("Şarj aleti", b.adapterWatts.map { "\($0) W" } ?? (b.onAC ? "Bağlı" : "Bağlı değil")),
            ] as [(String, String)]).filter { $0.1 != "—" }) {
                BigDial(fraction: b.percent / 100, color: b.percent < 15 && !b.onAC ? .red : color,
                        value: Fmt.percent(b.percent), caption: b.isCharging ? "şarj oluyor" : "şarj")
            } main: {
                HistoryChart(title: "Mac'in güç kullanımı", series: [
                    ChartSeries(name: "Watts", color: color, values: monitor.history.map { max(0, $0.watts) }),
                ], format: { String(format: "%.1f W", $0) })
                TopProcessesPanel(title: "En çok enerji harcayanlar (CPU, son 1 dk)", color: color)
            }
        } else {
            ContentUnavailableView("Pil yok", systemImage: "powerplug",
                                   description: Text("Bu Mac prizden çalışıyor."))
        }
    }
}
