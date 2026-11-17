import Foundation
import Darwin
import IOKit
import IOKit.ps
import SystemConfiguration

struct GPUInfo {
    var name: String
    var utilization: Double      // 0–100
    var memoryInUse: UInt64      // bytes
    var cores: Int?
}

struct BatteryInfo {
    var percent: Double
    var isCharging: Bool
    var onAC: Bool
    var minutesToEmpty: Int?     // nil = still calculating / on AC
    var minutesToFull: Int?
    var healthPercent: Double?   // max capacity vs. design capacity
    var cycleCount: Int?
    var watts: Double?           // positive = drawing from battery
    var temperature: Double?     // °C
    var systemWatts: Double?     // whole Mac's power use
    var maxCapacity: Int?        // mAh
    var designCapacity: Int?     // mAh
    var adapterWatts: Int?
}

struct VolumeInfo: Identifiable {
    var id: String { path }
    var name: String
    var path: String
    var total: UInt64
    var free: UInt64
    var isInternal: Bool
    var isRoot: Bool
}

struct InterfaceInfo: Identifiable {
    var id: String { bsdName }
    var bsdName: String
    var displayName: String
    var addresses: [String]
}

struct DiskSpace {
    var total: UInt64 = 0
    var free: UInt64 = 0
}

struct SystemInfo {
    var chip: String
    var model: String
    var performanceCores: Int
    var efficiencyCores: Int
    var bootTime: Date?

    static let current: SystemInfo = {
        SystemInfo(chip: sysctlString("machdep.cpu.brand_string") ?? "Mac",
                   model: sysctlString("hw.model") ?? "",
                   performanceCores: sysctlInt("hw.perflevel0.logicalcpu") ?? 0,
                   efficiencyCores: sysctlInt("hw.perflevel1.logicalcpu") ?? 0,
                   bootTime: bootTime())
    }()

    private static func bootTime() -> Date? {
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1e6)
    }
}

func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
    return String(cString: buf)
}

func sysctlInt(_ name: String) -> Int? {
    var v: Int32 = 0
    var size = MemoryLayout<Int32>.size
    return sysctlbyname(name, &v, &size, nil, 0) == 0 ? Int(v) : nil
}

private func registryProperties(_ service: io_service_t) -> [String: Any]? {
    var props: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
    return dict
}

enum Hardware {
    static func gpu() -> GPUInfo? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var best: GPUInfo?
        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }
            guard let props = registryProperties(service),
                  let perf = props["PerformanceStatistics"] as? [String: Any] else { continue }
            let util = (perf["Device Utilization %"] as? NSNumber)?.doubleValue ?? 0
            let mem = (perf["In use system memory"] as? NSNumber)?.uint64Value ?? 0
            var name = props["model"] as? String
            if name == nil, let data = props["model"] as? Data {
                name = String(decoding: data.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
            let info = GPUInfo(name: name ?? SystemInfo.current.chip, utilization: util, memoryInUse: mem,
                               cores: (props["gpu-core-count"] as? NSNumber)?.intValue)
            if best == nil || util > best!.utilization { best = info }
        }
        return best
    }

    static func battery() -> BatteryInfo? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        var info: BatteryInfo?
        for source in list {
            guard let d = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = Double(d[kIOPSCurrentCapacityKey] as? Int ?? 0)
            let max = Double(d[kIOPSMaxCapacityKey] as? Int ?? 100)
            let toEmpty = d[kIOPSTimeToEmptyKey] as? Int ?? -1
            let toFull = d[kIOPSTimeToFullChargeKey] as? Int ?? -1
            info = BatteryInfo(percent: max > 0 ? current / max * 100 : current,
                               isCharging: d[kIOPSIsChargingKey] as? Bool ?? false,
                               onAC: d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                               minutesToEmpty: toEmpty > 0 ? toEmpty : nil,
                               minutesToFull: toFull > 0 ? toFull : nil)
        }
        guard var battery = info else { return nil }

        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0, var p = registryProperties(service) {
            defer { IOObjectRelease(service) }
            // Newer macOS versions keep the details inside "BatteryData".
            if let nested = p["BatteryData"] as? [String: Any] {
                p.merge(nested) { top, _ in top }
            }
            let rawMax = (p["NominalChargeCapacity"] as? NSNumber)?.doubleValue
                ?? (p["AppleRawMaxCapacity"] as? NSNumber)?.doubleValue
            if let rawMax, let design = (p["DesignCapacity"] as? NSNumber)?.doubleValue, design > 0 {
                battery.healthPercent = min(100, rawMax / design * 100)
            }
            battery.cycleCount = (p["CycleCount"] as? NSNumber)?.intValue
            battery.maxCapacity = rawMax.map { Int($0) }
            battery.designCapacity = (p["DesignCapacity"] as? NSNumber)?.intValue
            if let t = (p["Temperature"] as? NSNumber)?.doubleValue, t > 0 { battery.temperature = t / 100 }
            if let telemetry = p["PowerTelemetryData"] as? [String: Any],
               let mw = (telemetry["SystemLoad"] as? NSNumber)?.doubleValue, mw > 0 {
                battery.systemWatts = mw / 1000
            }
            if let adapter = p["AdapterDetails"] as? [String: Any] {
                battery.adapterWatts = (adapter["Watts"] as? NSNumber)?.intValue
            }
            if let mv = (p["Voltage"] as? NSNumber)?.doubleValue,
               let ma = ((p["InstantAmperage"] ?? p["Amperage"]) as? NSNumber)?.int64Value {
                battery.watts = -(mv / 1000) * (Double(ma) / 1000)
            }
        }
        return battery
    }

    static func diskSpace() -> DiskSpace {
        let url = URL(fileURLWithPath: "/")
        guard let v = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey,
                                                        .volumeAvailableCapacityForImportantUsageKey]) else {
            return DiskSpace()
        }
        return DiskSpace(total: UInt64(v.volumeTotalCapacity ?? 0),
                         free: UInt64(v.volumeAvailableCapacityForImportantUsage ?? 0))
    }

    static func volumes() -> [VolumeInfo] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey,
                                      .volumeIsInternalKey, .volumeIsRootFileSystemKey, .volumeIsBrowsableKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                               options: [.skipHiddenVolumes]) else { return [] }
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.volumeIsBrowsable != false,
                  let total = v.volumeTotalCapacity, total > 0 else { return nil }
            let free = v.volumeAvailableCapacityForImportantUsage.map { Int($0) } ?? v.volumeAvailableCapacity ?? 0
            return VolumeInfo(name: v.volumeName ?? url.lastPathComponent, path: url.path,
                              total: UInt64(total), free: UInt64(max(0, free)),
                              isInternal: v.volumeIsInternal ?? false,
                              isRoot: v.volumeIsRootFileSystem ?? false)
        }
    }

    private static let interfaceNames: [String: String] = {
        var names: [String: String] = [:]
        for i in (SCNetworkInterfaceCopyAll() as? [SCNetworkInterface]) ?? [] {
            if let bsd = SCNetworkInterfaceGetBSDName(i) as String?,
               let name = SCNetworkInterfaceGetLocalizedDisplayName(i) as String? {
                names[bsd] = name
            }
        }
        return names
    }()

    /// Active network interfaces with their IP addresses (loopback and link-local skipped).
    static func interfaces() -> [InterfaceInfo] {
        var ifap: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifap) == 0, let first = ifap else { return [] }
        defer { freeifaddrs(ifap) }
        var order: [String] = []
        var addrs: [String: [String]] = [:]
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            let flags = Int32(ifa.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0, let addr = ifa.ifa_addr else { continue }
            let family = Int32(addr.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let len = socklen_t(family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(addr, len, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: host)
            if ip.lowercased().hasPrefix("fe80") { continue }
            let name = String(cString: ifa.ifa_name)
            if addrs[name] == nil { order.append(name); addrs[name] = [] }
            addrs[name]?.append(ip)
        }
        return order.map { InterfaceInfo(bsdName: $0, displayName: interfaceNames[$0] ?? $0, addresses: addrs[$0] ?? []) }
    }
}
