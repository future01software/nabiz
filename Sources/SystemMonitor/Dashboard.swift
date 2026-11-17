import SwiftUI
import Charts
import AppKit

// MARK: - Palette

enum Metric: String, CaseIterable {
    case cpu, memory, gpu, disk, network, battery

    var title: String {
        switch self {
        case .cpu: "CPU"
        case .memory: "Bellek"
        case .gpu: "GPU"
        case .disk: "Disk"
        case .network: "Ağ"
        case .battery: "Pil"
        }
    }

    var defaultHex: String {
        switch self {
        case .cpu: "#FF7A59"      // coral
        case .memory: "#2FB5A8"   // teal
        case .gpu: "#8B6CF6"      // violet
        case .disk: "#E0B04B"     // sand
        case .network: "#3BA7F0"  // sky
        case .battery: "#7CC74A"  // lime
        }
    }
}

struct Palette {
    var colorful: Bool
    var accent: Color

    func color(_ m: Metric) -> Color { colorful ? Color(hex: m.defaultHex) : accent }
}

// MARK: - Grouping processes by app

struct AppShare: Identifiable {
    let id: String
    let name: String
    let value: Double
    let bundle: String?
}

extension Monitor {
    /// Groups processes by their app (helpers counted with their app) and returns the top ones plus "Diğer".
    func shares(top: Int = 5, _ value: (ProcInfo) -> Double) -> [AppShare] {
        var totals: [String: Double] = [:]
        for p in snapshot.processes {
            let v = value(p)
            guard v > 0 else { continue }
            totals[p.bundle ?? "", default: 0] += v
        }
        let sorted = totals.sorted { $0.value > $1.value }
        var result: [AppShare] = sorted.prefix(top).map { key, v in
            key.isEmpty
                ? AppShare(id: "system", name: "Sistem ve araçlar", value: v, bundle: nil)
                : AppShare(id: key, name: ((key as NSString).lastPathComponent as NSString).deletingPathExtension,
                           value: v, bundle: key)
        }
        let rest = sorted.dropFirst(top).reduce(0) { $0 + $1.value }
        if rest > 0 { result.append(AppShare(id: "other", name: "Diğer", value: rest, bundle: nil)) }
        return result
    }
}

// MARK: - Overview

struct DashboardView: View {
    @EnvironmentObject private var monitor: Monitor
    let palette: Palette
    var openTab: (AppTab) -> Void
    var openProcesses: (KeyPathComparator<ProcInfo>) -> Void

    @State private var hidden: Set<Metric> = []

    var body: some View {
        let s = monitor.snapshot
        VStack(alignment: .leading, spacing: 14) {
                StatusLine(palette: palette)

                gauges(s)

                HStack(alignment: .top, spacing: 14) {
                    timeline
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    VStack(spacing: 14) {
                    MirrorPanel(title: "Ağ", icon: "network", color: palette.color(.network),
                                upLabel: "İndirme", downLabel: "Yükleme",
                                up: monitor.history.map(\.netIn), down: monitor.history.map(\.netOut),
                                upNow: s.netIn, downNow: s.netOut,
                                footer: [("Bugün", "↓ \(Fmt.total(monitor.daily.today.netIn))  ↑ \(Fmt.total(monitor.daily.today.netOut))"),
                                         ("7 gün", "↓ \(Fmt.total(monitor.daily.lastWeek.netIn))  ↑ \(Fmt.total(monitor.daily.lastWeek.netOut))")])
                    MirrorPanel(title: "Disk etkinliği", icon: "internaldrive", color: palette.color(.disk),
                                upLabel: "Okuma", downLabel: "Yazma",
                                up: monitor.history.map(\.diskRead), down: monitor.history.map(\.diskWrite),
                                upNow: s.diskRead, downNow: s.diskWrite,
                                footer: [("Bugün yazılan", Fmt.total(monitor.daily.today.diskWrite)),
                                         ("Bugün okunan", Fmt.total(monitor.daily.today.diskRead))])
                    }
                    .frame(minWidth: 300, idealWidth: 400, maxWidth: 440)
                }
                .frame(maxHeight: .infinity)

                HStack(alignment: .top, spacing: 14) {
                    ShareBar(title: "Belleği kim kullanıyor", icon: "memorychip", color: palette.color(.memory),
                             shares: monitor.shares(top: 3) { Double($0.memory) },
                             format: { Fmt.bytes(UInt64($0)) },
                             onMore: { openProcesses(KeyPathComparator(\ProcInfo.memory, order: .reverse)) })
                    ShareBar(title: "CPU'yu kim kullanıyor · son 1 dk", icon: "cpu", color: palette.color(.cpu),
                             shares: monitor.shares(top: 3) { $0.avgCPU },
                             format: { String(format: "%.1f%%", $0) },
                             onMore: { openProcesses(KeyPathComparator(\ProcInfo.avgCPU, order: .reverse)) })
                }
        }
        .padding(16)
    }

    // Gauge tiles

    @ViewBuilder
    private func gauges(_ s: Snapshot) -> some View {
        let today = monitor.daily.today
        HStack(spacing: 12) {
            GaugeTile(metric: .cpu, color: palette.color(.cpu), fraction: s.cpuTotal / 100,
                      value: Fmt.percent(s.cpuTotal),
                      lines: ["Kullanıcı \(Fmt.percent(s.cpuUser)) · Sistem \(Fmt.percent(s.cpuSystem))",
                              "Bugün ort. \(Fmt.percent(today.cpuAverage)) · en yüksek \(Fmt.percent(today.cpuPeak))"])
                .onTapGesture { openTab(.cpu) }

            GaugeTile(metric: .memory, color: palette.color(.memory), fraction: s.memory.usedFraction,
                      value: Fmt.bytes(s.memory.used),
                      lines: ["toplam \(Fmt.bytes(s.memory.total))", pressureText(s.memory.pressureLevel)],
                      warning: s.memory.pressureLevel > 1)
                .onTapGesture { openTab(.memory) }

            if let g = s.gpu {
                GaugeTile(metric: .gpu, color: palette.color(.gpu), fraction: g.utilization / 100,
                          value: Fmt.percent(g.utilization),
                          lines: [g.name, "Bugün en yüksek \(Fmt.percent(today.gpuPeak))"])
                    .onTapGesture { openTab(.gpu) }
            }

            let used = s.disk.total > s.disk.free ? s.disk.total - s.disk.free : 0
            GaugeTile(metric: .disk, color: palette.color(.disk),
                      fraction: s.disk.total == 0 ? 0 : Double(used) / Double(s.disk.total),
                      value: Fmt.bytes(s.disk.free),
                      lines: ["boş · toplam \(Fmt.bytes(s.disk.total))", "Başlangıç diski"])
                .onTapGesture { openTab(.disk) }

            if let b = s.battery {
                GaugeTile(metric: .battery, color: palette.color(.battery), fraction: b.percent / 100,
                          value: Fmt.percent(b.percent),
                          lines: [batteryLine(b), batteryHealth(b)],
                          warning: b.percent < 15 && !b.onAC)
                    .onTapGesture { openTab(.battery) }
            }
        }
    }

    private var timeline: some View {
        let h = monitor.history
        let series: [(Metric, [Double])] = [
            (.cpu, h.map(\.cpu)),
            (.memory, h.map(\.memory)),
            (.gpu, h.map(\.gpu)),
        ].filter { !hidden.contains($0.0) }

        return Panel {
            HStack {
                Label("Son \(Int(Double(monitor.historyLength) * monitor.interval / 60)) dakika",
                      systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                ForEach([Metric.cpu, .memory, .gpu], id: \.self) { m in
                    Button {
                        if hidden.contains(m) { hidden.remove(m) } else { hidden.insert(m) }
                    } label: {
                        HStack(spacing: 5) {
                            Circle().fill(palette.color(m)).frame(width: 8, height: 8)
                            Text(m.title)
                        }
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(.quaternary.opacity(hidden.contains(m) ? 0.2 : 0.8)))
                        .opacity(hidden.contains(m) ? 0.4 : 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            let renkler = series.map { m, _ in palette.colorful ? palette.color(m) : palette.accent.opacity(m == .cpu ? 1 : m == .memory ? 0.6 : 0.35) }
            let uzunluk = monitor.historyLength
            HStack(spacing: 6) {
            Canvas { ctx, size in
                // Izgara: %0, %50, %100 (etiketler sağda, normal yazı olarak)
                let alan = CGSize(width: size.width, height: size.height - 8)
                for oran in [0.0, 0.5, 1.0] {
                    let y = 4 + alan.height * (1 - oran)
                    var c = Path(); c.move(to: CGPoint(x: 0, y: y)); c.addLine(to: CGPoint(x: alan.width, y: y))
                    ctx.stroke(c, with: .color(.secondary.opacity(0.3)), style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                }
                // Seriler
                for (i, (_, degerler)) in series.enumerated() where degerler.count > 1 {
                    let adim = alan.width / CGFloat(max(uzunluk, degerler.count) - 1)
                    let x0 = alan.width - adim * CGFloat(degerler.count - 1)
                    var yol = Path()
                    for (j, v) in degerler.enumerated() {
                        let p = CGPoint(x: x0 + adim * CGFloat(j), y: 4 + alan.height * (1 - CGFloat(min(max(v / 100, 0), 1))))
                        j == 0 ? yol.move(to: p) : yol.addLine(to: p)
                    }
                    ctx.stroke(yol, with: .color(renkler[i]), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            }
            VStack(alignment: .leading) {
                Text("100%"); Spacer(); Text("50%"); Spacer(); Text("0%")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.vertical, -2)
            }
            .frame(minHeight: 90, maxHeight: .infinity)
        }
    }

    private func pressureText(_ level: Int) -> String {
        switch level {
        case 4: "Baskı: kritik"
        case 2: "Baskı: yüksek"
        default: "Baskı: normal"
        }
    }

    private func batteryLine(_ b: BatteryInfo) -> String {
        if b.isCharging { return b.minutesToFull.map { "Şarj oluyor · \(Fmt.minutes($0)) sonra dolu" } ?? "Şarj oluyor" }
        if b.onAC { return "Prize takılı" }
        var s = b.minutesToEmpty.map { "\(Fmt.minutes($0)) kaldı" } ?? "Pilde"
        if let w = b.watts, w > 0 { s += String(format: " · %.1f W", w) }
        return s
    }

    private func batteryHealth(_ b: BatteryInfo) -> String {
        var parts: [String] = []
        if let h = b.healthPercent { parts.append("Sağlık \(Fmt.percent(h))") }
        if let c = b.cycleCount { parts.append("\(c) döngü") }
        return parts.isEmpty ? " " : parts.joined(separator: " · ")
    }
}

// MARK: - Status line

struct StatusLine: View {
    @EnvironmentObject private var monitor: Monitor
    let palette: Palette

    var body: some View {
        let s = monitor.snapshot
        let busiest = monitor.shares(top: 6) { $0.avgCPU }.first { $0.bundle != nil }
        let (mood, color, text) = summary(s, busiest: busiest)
        let info = SystemInfo.current

        HStack(spacing: 12) {
            Image(systemName: mood)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(Circle().fill(color.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(text).font(.title3.weight(.semibold))
                Text("\(info.chip) · \(info.performanceCores)P + \(info.efficiencyCores)E çekirdek · \(uptime(info.bootTime)) açık · \(thermal)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func summary(_ s: Snapshot, busiest: AppShare?) -> (String, Color, String) {
        let name = busiest?.name ?? "Hiçbir şey"
        if s.memory.pressureLevel >= 4 {
            return ("exclamationmark.triangle.fill", .red, "Bellek tükeniyor")
        }
        if s.memory.pressureLevel >= 2 {
            let top = monitor.shares(top: 6) { Double($0.memory) }.first { $0.bundle != nil }?.name ?? "Bir uygulama"
            return ("exclamationmark.circle.fill", .orange, "Bellek daraldı — en çok \(top) kullanıyor")
        }
        if s.cpuTotal >= 70 {
            return ("flame.fill", .orange, "Mac çok çalışıyor — en yoğun: \(name)")
        }
        if s.cpuTotal >= 30 {
            return ("bolt.fill", palette.color(.cpu), "Yoğun — çoğunlukla \(name)")
        }
        return ("leaf.fill", .green, "Her şey sakin" + (busiest.map { " — en aktif: \($0.name)" } ?? ""))
    }

    private var thermal: String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: "serin"
        case .fair: "ılık"
        case .serious: "sıcak"
        case .critical: "çok sıcak"
        @unknown default: "—"
        }
    }

    private func uptime(_ boot: Date?) -> String {
        guard let boot else { return "—" }
        let mins = Int(Date().timeIntervalSince(boot) / 60)
        let d = mins / 1440, h = (mins % 1440) / 60, m = mins % 60
        return d > 0 ? "\(d) gün \(h) sa" : h > 0 ? "\(h) sa \(m) dk" : "\(m) dk"
    }
}

// MARK: - Building blocks

struct Panel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(.background.secondary))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator.opacity(0.5)))
    }
}

struct GaugeTile: View {
    let metric: Metric
    let color: Color
    let fraction: Double
    let value: String
    let lines: [String]
    var warning = false

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                ArcGauge(fraction: fraction, color: warning ? .orange : color, size: 84, lineWidth: 9)
                VStack(spacing: 0) {
                    Text(value)
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(metric.title.uppercased(with: Locale(identifier: "tr_TR")))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                }
                .padding(.horizontal, 16)
            }
            .frame(width: 100, height: 86)

            VStack(spacing: 2) {
                ForEach(lines, id: \.self) { Text($0) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.background.secondary)
                .overlay(
                    RadialGradient(colors: [color.opacity(0.16), .clear], center: .top,
                                   startRadius: 0, endRadius: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                )
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.separator.opacity(0.5)))
        .contentShape(Rectangle())
    }
}

/// A 270° dial with tick marks.
struct ArcGauge: View {
    let fraction: Double
    let color: Color
    var size: CGFloat = 96
    var lineWidth: CGFloat = 10
    private let sweep = 0.75

    var body: some View {
        let f = min(max(fraction, 0), 1)
        ZStack {
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(color.opacity(0.14), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: sweep * f)
                .stroke(
                    AngularGradient(colors: [color.opacity(0.55), color], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360 * sweep * max(f, 0.01))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            // ticks
            ForEach(0..<11) { i in
                Capsule()
                    .fill(.secondary.opacity(0.35))
                    .frame(width: 1.5, height: i % 5 == 0 ? 7 : 4)
                    .offset(y: -(size / 2 - lineWidth - 6))
                    .rotationEffect(.degrees(-135 + Double(i) * 27))
            }
        }
        .rotationEffect(.degrees(135))
        .frame(width: size, height: size)
    }
}

/// Two-sided chart: one series above the line, the other mirrored below.
struct MirrorPanel: View {
    let title: String
    let icon: String
    let color: Color
    let upLabel: String
    let downLabel: String
    let up: [Double]
    let down: [Double]
    let upNow: Double
    let downNow: Double
    let footer: [(String, String)]

    var body: some View {
        Panel {
            HStack(alignment: .firstTextBaseline) {
                Label(title, systemImage: icon).font(.headline)
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(upLabel) \(Fmt.rate(upNow))").foregroundStyle(color)
                    Text("\(downLabel) \(Fmt.rate(downNow))").foregroundStyle(color.opacity(0.6))
                }
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            }
            AynaGrafik(ust: up, alt: down, renk: color)
                .frame(minHeight: 40, maxHeight: .infinity)

            if !footer.isEmpty {
                HStack {
                    ForEach(footer, id: \.0) { item in
                        HStack(spacing: 5) {
                            Text(item.0).foregroundStyle(.secondary)
                            Text(item.1).fontWeight(.medium).monospacedDigit()
                        }
                        .font(.caption)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }
}

/// One long bar split by app, plus a legend.
struct ShareBar: View {
    @EnvironmentObject private var monitor: Monitor
    let title: String
    let icon: String
    let color: Color
    let shares: [AppShare]
    let format: (Double) -> String
    let onMore: (() -> Void)?

    var body: some View {
        let total = max(shares.reduce(0) { $0 + $1.value }, 0.0001)
        Panel {
            HStack {
                Label(title, systemImage: icon).font(.headline)
                Spacer()
                if let onMore {
                    Button("Tüm işlemler", action: onMore)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
            GeometryReader { geo in
                let gaps = CGFloat(max(shares.count - 1, 0)) * 3
                HStack(spacing: 3) {
                    ForEach(Array(shares.enumerated()), id: \.element.id) { i, share in
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(shade(i))
                            .frame(width: max(4, (geo.size.width - gaps) * share.value / total))
                            .help("\(share.name): \(format(share.value))")
                    }
                }
            }
            .frame(height: 22)

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible())], spacing: 6) {
                ForEach(Array(shares.enumerated()), id: \.element.id) { i, share in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(shade(i)).frame(width: 10, height: 10)
                        appIcon(share)
                        Text(share.name).lineLimit(1)
                        Spacer()
                        Text(format(share.value)).monospacedDigit().foregroundStyle(.secondary)
                        Text(Fmt.percent(share.value / total * 100))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .frame(width: 38, alignment: .trailing)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func shade(_ i: Int) -> Color {
        if shares.indices.contains(i), shares[i].id == "other" { return .secondary.opacity(0.35) }
        return color.opacity(max(0.3, 1 - Double(i) * 0.15))
    }

    @ViewBuilder
    private func appIcon(_ share: AppShare) -> some View {
        if let bundle = share.bundle {
            Image(nsImage: monitor.icon(forBundle: bundle)).resizable().frame(width: 16, height: 16)
        } else {
            Image(systemName: share.id == "other" ? "ellipsis.circle" : "gearshape.2")
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
        }
    }
}
