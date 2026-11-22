import Foundation
import AppKit
import Darwin

struct Snapshot {
    var cpuUser: Double = 0
    var cpuSystem: Double = 0
    var cores: [Double] = []
    var memory = MemoryInfo()
    var netIn: Double = 0      // bytes / second
    var netOut: Double = 0
    var diskRead: Double = 0
    var diskWrite: Double = 0
    var processes: [ProcInfo] = []
    var gpu: GPUInfo?
    var battery: BatteryInfo?
    var disk = DiskSpace()
    var volumes: [VolumeInfo] = []
    var interfaces: [InterfaceInfo] = []
    var elapsed: Double = 0

    var cpuTotal: Double { cpuUser + cpuSystem }
}

struct Sample: Identifiable {
    let id: Int
    let cpu: Double
    let memory: Double
    let netIn: Double
    let netOut: Double
    let diskRead: Double
    let diskWrite: Double
    let gpu: Double
    let battery: Double
    let cpuUser: Double
    let cpuSystem: Double
    let watts: Double
}

/// Does all the measuring. Lives on a background queue and remembers the previous
/// readings so it can turn counters into rates.
final class Sampler {
    private var prevCPU: [CPUTicks] = []
    private var prevProcTime: [pid_t: UInt64] = [:]
    private var prevStamp: UInt64 = 0
    private var prevNet: (UInt64, UInt64)?
    private var prevDisk: (UInt64, UInt64)?

    /// Bytes counted since the previous sample. Counters drop when an interface goes away (VPN off,
    /// sleep/wake) or a disk is ejected; `&-` would then wrap to ~2^64 and poison the daily totals.
    static func counterDelta(_ now: UInt64, _ before: UInt64) -> UInt64 {
        now >= before ? now - before : 0
    }
    private var identity: [pid_t: (start: timeval, name: String, path: String, isApp: Bool, bundle: String?)] = [:]
    private var users: [uid_t: String] = [:]
    private var sayac = 0
    private var onbellekDiskler: [VolumeInfo] = []
    private var onbellekBaglantilar: [InterfaceInfo] = []
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return (UInt64(tb.numer), UInt64(tb.denom))
    }()

    func sample() -> Snapshot {
        var snap = Snapshot()
        let now = DispatchTime.now().uptimeNanoseconds
        let elapsed = prevStamp == 0 ? 0 : Double(now - prevStamp) / 1e9
        prevStamp = now
        snap.elapsed = elapsed

        // CPU
        let ticks = SystemStats.cpuTicks()
        if ticks.count == prevCPU.count {
            var totalUser = 0.0, totalSys = 0.0, totalAll = 0.0
            for (a, b) in zip(prevCPU, ticks) {
                let u = Double(b.user &- a.user) + Double(b.nice &- a.nice)
                let s = Double(b.system &- a.system)
                let i = Double(b.idle &- a.idle)
                let all = u + s + i
                snap.cores.append(all > 0 ? (u + s) / all * 100 : 0)
                totalUser += u; totalSys += s; totalAll += all
            }
            if totalAll > 0 {
                snap.cpuUser = totalUser / totalAll * 100
                snap.cpuSystem = totalSys / totalAll * 100
            }
        } else {
            snap.cores = Array(repeating: 0, count: ticks.count)
        }
        prevCPU = ticks

        // Memory
        snap.memory = SystemStats.memory()

        // Network & disk rates
        let net = SystemStats.networkBytes()
        if let p = prevNet, elapsed > 0 {
            snap.netIn = Double(Self.counterDelta(net.received, p.0)) / elapsed
            snap.netOut = Double(Self.counterDelta(net.sent, p.1)) / elapsed
        }
        prevNet = (net.received, net.sent)

        let disk = SystemStats.diskBytes()
        if let p = prevDisk, elapsed > 0 {
            snap.diskRead = Double(Self.counterDelta(disk.read, p.0)) / elapsed
            snap.diskWrite = Double(Self.counterDelta(disk.written, p.1)) / elapsed
        }
        prevDisk = (disk.read, disk.written)

        // GPU, battery, disk space
        snap.gpu = Hardware.gpu()
        snap.battery = Hardware.battery()
        snap.disk = Hardware.diskSpace()
        // Bağlı diskler ve ağ bağlantıları nadiren değişir: ~20 saniyede bir yenile.
        if sayac % 10 == 0 || onbellekDiskler.isEmpty {
            onbellekDiskler = Hardware.volumes()
            onbellekBaglantilar = Hardware.interfaces()
        }
        sayac += 1
        snap.volumes = onbellekDiskler
        snap.interfaces = onbellekBaglantilar

        // Processes
        snap.processes = sampleProcesses(elapsed: elapsed)
        return snap
    }

    private func sampleProcesses(elapsed: Double) -> [ProcInfo] {
        let kinfos = ProcessList.allKinfo()
        var result: [ProcInfo] = []
        result.reserveCapacity(kinfos.count)
        var newTimes: [pid_t: UInt64] = [:]
        var seen = Set<pid_t>()

        for kp in kinfos {
            let pid = kp.kp_proc.p_pid
            if pid == 0 { continue }
            seen.insert(pid)

            // Name/path never change for a process, so look them up once.
            let start = kp.kp_proc.p_starttime
            let ident: (start: timeval, name: String, path: String, isApp: Bool, bundle: String?)
            if let cached = identity[pid], cached.start.tv_sec == start.tv_sec, cached.start.tv_usec == start.tv_usec {
                ident = cached
            } else {
                let path = ProcessList.path(of: pid)
                let (name, isApp) = ProcessList.displayName(path: path, comm: ProcessList.comm(kp))
                ident = (start, name, path, isApp, ProcessList.topBundle(path))
                identity[pid] = ident
                prevProcTime[pid] = nil
            }

            let uid = kp.kp_eproc.e_ucred.cr_uid
            let user = users[uid] ?? {
                let name = getpwuid(uid).map { String(cString: $0.pointee.pw_name) } ?? "\(uid)"
                users[uid] = name
                return name
            }()

            var cpu = 0.0, mem: UInt64 = 0, restricted = true
            if let usage = ProcessList.usage(of: pid) {
                restricted = false
                mem = usage.footprint
                newTimes[pid] = usage.cpuTime
                if let prev = prevProcTime[pid], elapsed > 0, usage.cpuTime >= prev {
                    let ns = Double((usage.cpuTime - prev) * timebase.numer / timebase.denom)
                    cpu = ns / (elapsed * 1e9) * 100
                }
            }

            result.append(ProcInfo(id: pid, name: ident.name, path: ident.path, user: user,
                                   isApp: ident.isApp, cpu: cpu, memory: mem,
                                   threads: restricted ? 0 : ProcessList.threadCount(of: pid),
                                   restricted: restricted, bundle: ident.bundle))
        }
        prevProcTime = newTimes
        identity = identity.filter { seen.contains($0.key) }
        return result
    }
}

@MainActor
final class Monitor: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var history: [Sample] = []
    let historyLength = 90

    var interval: Double = 2 {
        didSet { if interval != oldValue { restartTimer() } }
    }

    let daily = DailyTracker()
    let uyarilar = UyariMotoru()
    private let sampler = Sampler()
    private let queue = DispatchQueue(label: "SystemMonitor.sampler", qos: .utility)
    private var timer: Timer?
    private var counter = 0
    private var iconCache: [pid_t: NSImage] = [:]

    private var olcuyor = false
    private var gozlemciler: [NSObjectProtocol] = []

    init() {
        let kayitli = UserDefaults.standard.double(forKey: Prefs.interval)
        if kayitli > 0 { interval = kayitli }
        tick()
        restartTimer()
        // Ayarlar penceresinde yenileme sıklığı değişince (ana pencere kapalı olsa bile) hemen uygula.
        gozlemciler.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                let yeni = UserDefaults.standard.double(forKey: Prefs.interval)
                if yeni > 0, let self, self.interval != yeni { self.interval = yeni }
            }
        })
        // Kapanırken bugünkü toplamları diske yaz.
        gozlemciler.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.daily.save() }
        })
    }

    private func restartTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common: tablo kaydırılırken ya da menü açıkken de saymaya devam etsin.
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func tick() {
        // Önceki ölçüm bitmeden yenisini başlatma (yoğun anlarda istekler üst üste binmesin).
        guard !olcuyor else { return }
        olcuyor = true
        let sampler = self.sampler
        queue.async {
            let snap = sampler.sample()
            DispatchQueue.main.async { [weak self] in
                self?.olcuyor = false
                self?.apply(snap)
            }
        }
    }

    private var procHistory: [pid_t: [Double]] = [:]

    private func apply(_ snap: Snapshot) {
        var snap = snap
        // Per-process CPU history for the last ~60 seconds.
        let window = max(2, Int((60 / interval).rounded()))
        var newHistory: [pid_t: [Double]] = [:]
        for i in snap.processes.indices {
            let p = snap.processes[i]
            var h = procHistory[p.id] ?? []
            h.append(p.cpu)
            if h.count > window { h.removeFirst(h.count - window) }
            newHistory[p.id] = h
            snap.processes[i].cpuHistory = h
            snap.processes[i].avgCPU = h.reduce(0, +) / Double(h.count)
        }
        procHistory = newHistory
        snapshot = snap
        counter += 1
        history.append(Sample(id: counter, cpu: snap.cpuTotal, memory: snap.memory.usedFraction * 100,
                              netIn: snap.netIn, netOut: snap.netOut,
                              diskRead: snap.diskRead, diskWrite: snap.diskWrite,
                              gpu: snap.gpu?.utilization ?? 0, battery: snap.battery?.percent ?? 0,
                              cpuUser: snap.cpuUser, cpuSystem: snap.cpuSystem,
                              watts: snap.battery?.systemWatts ?? snap.battery?.watts ?? 0))
        daily.record(snap)
        uyarilar.degerlendir(snap)
        if history.count > historyLength { history.removeFirst(history.count - historyLength) }
        let alive = Set(snap.processes.map(\.id))
        iconCache = iconCache.filter { alive.contains($0.key) }
    }

    private var bundleIcons: [String: NSImage] = [:]

    func icon(forBundle bundle: String) -> NSImage {
        if let cached = bundleIcons[bundle] { return cached }
        let img = NSWorkspace.shared.icon(forFile: bundle)
        bundleIcons[bundle] = img
        return img
    }

    func icon(for proc: ProcInfo) -> NSImage? {
        guard proc.isApp else { return nil }
        if let cached = iconCache[proc.id] { return cached }
        let path = proc.path
        guard let range = path.range(of: ".app/", options: .backwards) else { return nil }
        let bundle = String(path[..<range.lowerBound]) + ".app"
        let img = NSWorkspace.shared.icon(forFile: bundle)
        iconCache[proc.id] = img
        return img
    }

    // MARK: Actions

    enum QuitError: LocalizedError {
        case notPermitted(String)
        case failed(String)
        case korunan(String)
        var errorDescription: String? {
            switch self {
            case .korunan(let n): return "“\(n)” macOS'un çalışması için gerekli bir sistem işlemi. Kapatılırsa oturumunuz kapanabilir ve kaydedilmemiş işleriniz kaybolabilir; Nabız bunu kapatmaz."
            case .notPermitted(let n): return "macOS “\(n)” işlemini durdurmaya izin vermiyor. Başka bir kullanıcıya ya da sisteme ait."
            case .failed(let n): return "“\(n)” durdurulamadı."
            }
        }
    }

    /// Kapatılınca oturumu kapatan ya da Mac'i kilitleyen süreçler.
    nonisolated static let korunanlar: Set<String> = ["loginwindow", "WindowServer", "kernel_task", "launchd", "logd", "opendirectoryd", "securityd", "coreservicesd"]

    func quit(_ proc: ProcInfo, force: Bool) throws {
        if Self.korunanlar.contains(proc.name) || proc.id <= 1 { throw QuitError.korunan(proc.name) }
        if let app = NSRunningApplication(processIdentifier: proc.id) {
            let ok = force ? app.forceTerminate() : app.terminate()
            if ok { scheduleRefresh(); return }
        }
        if kill(proc.id, force ? SIGKILL : SIGTERM) != 0 {
            throw errno == EPERM ? QuitError.notPermitted(proc.name) : QuitError.failed(proc.name)
        }
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.tick() }
    }
}
