import XCTest
@testable import SystemMonitor

@MainActor
final class UyariTests: XCTestCase {
    var motor: UyariMotoru!
    var gonderilen: [Uyari] = []
    var zaman = Date(timeIntervalSince1970: 1_000_000)
    var ayar = UyariAyarlari()
    var isi: ProcessInfo.ThermalState = .nominal

    override func setUp() async throws {
        gonderilen = []
        motor = UyariMotoru(kalici: false)
        motor.gonderici = { [unowned self] u in self.gonderilen.append(u) }
        motor.saat = { [unowned self] in self.zaman }
        motor.ayarOkuyucu = { [unowned self] in self.ayar }
        motor.isiOkuyucu = { [unowned self] in self.isi }
    }

    private func surec(_ ad: String, cpu: Double, bellek: UInt64 = 100_000_000) -> ProcInfo {
        ProcInfo(id: Int32(abs(ad.hashValue % 30000) + 2), name: ad, path: "/x/\(ad)", user: "u", isApp: false,
                 cpu: cpu, memory: bellek, threads: 1, restricted: false)
    }

    /// `saniye` boyunca 2 saniyelik ölçümler gönderir.
    private func calistir(saniye: Double, _ yap: () -> Snapshot) {
        var g = 0.0
        while g < saniye {
            var s = yap(); s.elapsed = 2
            motor.degerlendir(s)
            zaman = zaman.addingTimeInterval(2)
            g += 2
        }
    }

    private func anlik(_ surecler: [ProcInfo]) -> Snapshot {
        var s = Snapshot(); s.processes = surecler
        s.memory.total = 16 << 30
        s.disk = DiskSpace(total: 500_000_000_000, free: 200_000_000_000)
        return s
    }

    func testYogunUygulamaIkiDakikadaBirKezUyarilir() {
        calistir(saniye: 110) { anlik([surec("Chrome", cpu: 95)]) }
        XCTAssertTrue(gonderilen.isEmpty, "2 dakika dolmadan uyarmamalı")
        calistir(saniye: 20) { anlik([surec("Chrome", cpu: 95)]) }
        XCTAssertEqual(gonderilen.count, 1)
        XCTAssertEqual(gonderilen.first?.tur, .cpu)
        XCTAssertTrue(gonderilen.first?.baslik.contains("Chrome") == true)
        calistir(saniye: 300) { anlik([surec("Chrome", cpu: 95)]) }
        XCTAssertEqual(gonderilen.count, 1, "15 dakika dolmadan tekrar uyarmamalı")
        calistir(saniye: 700) { anlik([surec("Chrome", cpu: 95)]) }
        XCTAssertEqual(gonderilen.count, 2, "15 dakika sonra tekrar hatırlatmalı")
    }

    func testKisaSicramaUyarmaz() {
        // 1 dk yoğun, 30 sn sakin, tekrar 1 dk yoğun: kesintisiz 2 dk olmadığı için uyarı yok
        calistir(saniye: 60) { anlik([surec("Xcode", cpu: 120)]) }
        calistir(saniye: 30) { anlik([surec("Xcode", cpu: 5)]) }
        calistir(saniye: 60) { anlik([surec("Xcode", cpu: 120)]) }
        XCTAssertTrue(gonderilen.isEmpty)
    }

    func testKucukDususlerAffedilir() {
        // Eşiğin hemen altına inip çıkması sayacı sıfırlamaz
        for _ in 0..<10 {   // 10 × 14 sn yoğun = 140 sn (düşüşler süreye eklenmez ama sayacı da sıfırlamaz)
            calistir(saniye: 14) { anlik([surec("Safari", cpu: 90)]) }
            calistir(saniye: 2) { anlik([surec("Safari", cpu: 65)]) }
        }
        XCTAssertEqual(gonderilen.map(\.tur), [.cpu])
    }

    func testUyarilarKapaliykenSessiz() {
        ayar.acik = false
        calistir(saniye: 300) { anlik([surec("Chrome", cpu: 150)]) }
        XCTAssertTrue(gonderilen.isEmpty)
    }

    func testBellekDarligi() {
        calistir(saniye: 40) {
            var s = anlik([surec("Chrome", cpu: 1, bellek: 3 << 30)])
            s.memory.pressureLevel = 2
            return s
        }
        XCTAssertEqual(gonderilen.map(\.tur), [.bellek])
        XCTAssertTrue(gonderilen[0].metin.contains("Chrome"))
    }

    func testTekUygulamaCokBellek() {
        calistir(saniye: 4) { anlik([surec("Xcode", cpu: 1, bellek: 5 << 30)]) }
        XCTAssertEqual(gonderilen.map(\.tur), [.surecBellek])
    }

    func testPilYuzde15ve5BirerKez() {
        func pil(_ y: Double, prizde: Bool = false) -> Snapshot {
            var s = anlik([]); s.battery = BatteryInfo(percent: y, isCharging: false, onAC: prizde, minutesToEmpty: 30, minutesToFull: nil); return s
        }
        calistir(saniye: 10) { pil(16) }
        XCTAssertTrue(gonderilen.isEmpty)
        calistir(saniye: 10) { pil(14) }
        calistir(saniye: 10) { pil(12) }
        XCTAssertEqual(gonderilen.count, 1)
        calistir(saniye: 4) { pil(4) }
        XCTAssertEqual(gonderilen.count, 2)
        XCTAssertTrue(gonderilen[1].baslik.contains("kritik"))
        calistir(saniye: 4) { pil(4, prizde: true) }
        XCTAssertEqual(gonderilen.count, 2, "prize takılıyken uyarmamalı")
    }

    func testDiskDoluyor() {
        calistir(saniye: 4) {
            var s = anlik([]); s.disk = DiskSpace(total: 500_000_000_000, free: 6_000_000_000); return s
        }
        XCTAssertEqual(gonderilen.map(\.tur), [.disk])
    }

    func testIsinma() {
        isi = .serious
        calistir(saniye: 10) { anlik([]) }
        XCTAssertEqual(gonderilen.map(\.tur), [.isi])
    }

    func testGecmisVeOkunmamis() {
        calistir(saniye: 4) { anlik([surec("Xcode", cpu: 1, bellek: 5 << 30)]) }
        XCTAssertEqual(motor.gecmis.count, 1)
        XCTAssertEqual(motor.okunmamis, 1)
        motor.okunduSay()
        XCTAssertEqual(motor.okunmamis, 0)
        motor.temizle()
        XCTAssertTrue(motor.gecmis.isEmpty)
    }
}
