import Foundation

/// Totals for one calendar day, kept for the last 8 days.
struct DayTotals: Codable {
    var day: String
    var netIn: Double = 0
    var netOut: Double = 0
    var diskRead: Double = 0
    var diskWrite: Double = 0
    var cpuSum: Double = 0
    var gpuSum: Double = 0
    var samples: Int = 0
    var cpuPeak: Double = 0
    var gpuPeak: Double = 0

    var cpuAverage: Double { samples == 0 ? 0 : cpuSum / Double(samples) }
    var gpuAverage: Double { samples == 0 ? 0 : gpuSum / Double(samples) }

    /// Byte totals above this are impossible for one day (1 PB): they come from a counter that
    /// wrapped around before `Sampler.counterDelta` existed, and would crash formatting.
    static let maxPlausibleBytes = 1e15

    /// Same day with corrupt byte totals reset to 0 (the real value can't be recovered).
    var sanitized: DayTotals {
        func clean(_ v: Double) -> Double { v.isFinite && v >= 0 && v <= Self.maxPlausibleBytes ? v : 0 }
        var d = self
        d.netIn = clean(netIn); d.netOut = clean(netOut)
        d.diskRead = clean(diskRead); d.diskWrite = clean(diskWrite)
        return d
    }
}

@MainActor
final class DailyTracker: ObservableObject {
    @Published private(set) var days: [DayTotals] = []
    private let key = "dailyTotals.v1"
    private var unsaved = 0
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([DayTotals].self, from: data) {
            days = saved.map(\.sanitized)
        }
    }

    var today: DayTotals {
        let id = Self.formatter.string(from: Date())
        return days.last(where: { $0.day == id }) ?? DayTotals(day: id)
    }

    /// Sum of the last 7 days, today included.
    var lastWeek: DayTotals {
        days.suffix(7).reduce(into: DayTotals(day: "week")) { acc, d in
            acc.netIn += d.netIn; acc.netOut += d.netOut
            acc.diskRead += d.diskRead; acc.diskWrite += d.diskWrite
        }
    }

    func record(_ snap: Snapshot) {
        guard snap.elapsed > 0 else { return }
        let id = Self.formatter.string(from: Date())
        if days.last?.day != id {
            days.append(DayTotals(day: id))
            if days.count > 8 { days.removeFirst(days.count - 8) }
        }
        var d = days[days.count - 1]
        d.netIn += snap.netIn * snap.elapsed
        d.netOut += snap.netOut * snap.elapsed
        d.diskRead += snap.diskRead * snap.elapsed
        d.diskWrite += snap.diskWrite * snap.elapsed
        d.cpuSum += snap.cpuTotal
        d.gpuSum += snap.gpu?.utilization ?? 0
        d.samples += 1
        d.cpuPeak = max(d.cpuPeak, snap.cpuTotal)
        d.gpuPeak = max(d.gpuPeak, snap.gpu?.utilization ?? 0)
        days[days.count - 1] = d

        unsaved += 1
        if unsaved >= 15 { save() }
    }

    func save() {
        unsaved = 0
        if let data = try? JSONEncoder().encode(days) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
