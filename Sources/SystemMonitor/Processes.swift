import Foundation
import Darwin

struct ProcInfo: Identifiable, Hashable {
    let id: pid_t
    var name: String
    var path: String
    var user: String
    var isApp: Bool
    /// Percent of one core (like Activity Monitor: 100% = one full core).
    var cpu: Double
    /// Memory footprint in bytes.
    var memory: UInt64
    var threads: Int32
    /// True when macOS doesn't let us read this process's stats (other users / system).
    var restricted: Bool
    /// Path of the top-level .app this process belongs to (helpers included).
    var bundle: String? = nil
    /// CPU % samples covering roughly the last minute (oldest first).
    var cpuHistory: [Double] = []
    /// Average CPU % over the last minute — catches apps that spike now and then.
    var avgCPU: Double = 0

    var pid: Int32 { id }
}

enum ProcessList {
    static func allKinfo() -> [kinfo_proc] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0 else { return [] }
        size += size / 4 // headroom for processes that start meanwhile
        let stride = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: size / stride)
        guard sysctl(&mib, UInt32(mib.count), &procs, &size, nil, 0) == 0 else { return [] }
        return Array(procs.prefix(size / stride))
    }

    static func comm(_ kp: kinfo_proc) -> String {
        withUnsafeBytes(of: kp.kp_proc.p_comm) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }

    static func path(of pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 4096)
        let n = proc_pidpath(pid, &buf, UInt32(buf.count))
        return n > 0 ? String(cString: buf) : ""
    }

    /// Cumulative CPU time (mach units) and memory footprint, or nil if not permitted.
    static func usage(of pid: pid_t) -> (cpuTime: UInt64, footprint: UInt64)? {
        var ru = rusage_info_v4()
        let ok = withUnsafeMutablePointer(to: &ru) { ptr in
            ptr.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        } == 0
        guard ok else { return nil }
        return (ru.ri_user_time &+ ru.ri_system_time, ru.ri_phys_footprint)
    }

    static func threadCount(of pid: pid_t) -> Int32 {
        var ti = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, size) == size ? ti.pti_threadnum : 0
    }

    static func topBundle(_ path: String) -> String? {
        guard let r = path.range(of: ".app/") else { return nil }
        return String(path[..<r.lowerBound]) + ".app"
    }

    /// Nice display name: app bundle name for apps, otherwise the executable name.
    static func displayName(path: String, comm: String) -> (String, Bool) {
        if let range = path.range(of: ".app/Contents/MacOS/", options: .backwards) {
            let bundlePrefix = path[..<range.lowerBound]          // ".../Safari"
            let exe = String(path[range.upperBound...])
            // A top-level app (not a helper app nested inside another app bundle).
            if !bundlePrefix.contains(".app/") {
                let appName = bundlePrefix.split(separator: "/").last.map(String.init) ?? exe
                return (appName, true)
            }
            return (exe, false)
        }
        if !path.isEmpty { return ((path as NSString).lastPathComponent, false) }
        return (comm, false)
    }
}
