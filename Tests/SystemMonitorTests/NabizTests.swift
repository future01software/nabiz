import XCTest
import SwiftUI
@testable import SystemMonitor

final class AdTespitiTests: XCTestCase {
    func testUygulamaAdi() {
        let (ad, uygulama) = ProcessList.displayName(path: "/Applications/Safari.app/Contents/MacOS/Safari", comm: "Safari")
        XCTAssertEqual(ad, "Safari")
        XCTAssertTrue(uygulama)
    }

    func testIcIceYardimciUygulama() {
        // Bir uygulamanın içindeki yardımcı uygulama kendi adını taşır ve "uygulama" sayılmaz.
        let yol = "/Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app/Contents/MacOS/Claude Helper (Renderer)"
        let (ad, uygulama) = ProcessList.displayName(path: yol, comm: "Claude Helper")
        XCTAssertEqual(ad, "Claude Helper (Renderer)")
        XCTAssertFalse(uygulama)
        XCTAssertEqual(ProcessList.topBundle(yol), "/Applications/Claude.app")
    }

    func testDuzKomut() {
        XCTAssertEqual(ProcessList.displayName(path: "/usr/sbin/cfprefsd", comm: "cfprefsd").0, "cfprefsd")
        XCTAssertEqual(ProcessList.displayName(path: "", comm: "kernel_task").0, "kernel_task")
        XCTAssertNil(ProcessList.topBundle("/usr/libexec/trustd"))
    }
}

final class BicimTests: XCTestCase {
    func testSure() {
        XCTAssertEqual(Fmt.minutes(45), "45 dk")
        XCTAssertEqual(Fmt.minutes(125), "2 sa 5 dk")
    }

    func testYuzde() {
        XCTAssertEqual(Fmt.percent(12.4), "12%")
        XCTAssertEqual(Fmt.percent(99.6), "100%")
        XCTAssertEqual(Fmt.percent(7.25, digits: 1), "7.2%")
    }

    func testRenkGidisDonus() {
        XCTAssertEqual(Color(hex: "#2FB5A8").hexString, "#2FB5A8")
        XCTAssertEqual(Color(hex: "ff7a59").hexString, "#FF7A59")
    }

    func testKorunanSurecler() {
        XCTAssertTrue(Monitor.korunanlar.contains("loginwindow"))
        XCTAssertTrue(Monitor.korunanlar.contains("WindowServer"))
    }
}

final class OlcumTests: XCTestCase {
    func testBellekMantikli() {
        let m = SystemStats.memory()
        XCTAssertGreaterThan(m.total, 1 << 30)
        XCTAssertGreaterThan(m.used, 0)
        XCTAssertLessThanOrEqual(m.used, m.total)
    }

    func testCekirdekSayisi() {
        XCTAssertEqual(SystemStats.cpuTicks().count, ProcessInfo.processInfo.processorCount)
    }

    func testKendiSurecimizGorunuyor() {
        let pidler = ProcessList.allKinfo().map { $0.kp_proc.p_pid }
        XCTAssertTrue(pidler.contains(getpid()))
        XCTAssertNotNil(ProcessList.usage(of: getpid()))
        XCTAssertGreaterThan(ProcessList.threadCount(of: getpid()), 0)
    }

    func testOlcumOraniIkinciOlcumdeHesaplanir() {
        let s = Sampler()
        let ilk = s.sample()
        XCTAssertEqual(ilk.elapsed, 0)
        Thread.sleep(forTimeInterval: 0.3)
        let ikinci = s.sample()
        XCTAssertGreaterThan(ikinci.elapsed, 0.2)
        XCTAssertGreaterThan(ikinci.processes.count, 10)
        XCTAssertGreaterThanOrEqual(ikinci.cpuTotal, 0)
        XCTAssertLessThanOrEqual(ikinci.cpuTotal, 100.5)
    }
}

final class HizTests: XCTestCase {
    /// Bir ölçüm turu (tüm işlemler dahil) yarım saniyenin altında bitmeli.
    func testOlcumHizi() {
        let s = Sampler()
        _ = s.sample()
        var sureler: [Double] = []
        for _ in 0..<5 {
            let bas = Date()
            _ = s.sample()
            sureler.append(Date().timeIntervalSince(bas))
        }
        let ortalama = sureler.reduce(0, +) / Double(sureler.count)
        print(String(format: "OLCUM_SURESI ortalama %.1f ms, en uzun %.1f ms", ortalama * 1000, (sureler.max() ?? 0) * 1000))
        XCTAssertLessThan(ortalama, 0.5)
    }
}
