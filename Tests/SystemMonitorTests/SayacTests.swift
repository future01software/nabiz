import XCTest
@testable import SystemMonitor

/// Sayaç geriye düştüğünde (VPN kapandı, uyku/uyanma, disk çıkarıldı) oluşan ~2^64'lük sahte değerler
/// günlük toplamlara girip uygulamayı açılışta çökertiyordu.
final class SayacTests: XCTestCase {
    func testSayacArtisi() {
        XCTAssertEqual(Sampler.counterDelta(1_500, 1_000), 500)
    }

    func testSayacGeriyeDusunceSifir() {
        XCTAssertEqual(Sampler.counterDelta(10, 1_000), 0)
    }

    func testBozukToplamlarTemizlenir() {
        var d = DayTotals(day: "2026-11-21")
        d.netIn = 1.84e19; d.netOut = .infinity; d.diskRead = .nan; d.diskWrite = 49_194_602_496
        let temiz = d.sanitized
        XCTAssertEqual(temiz.netIn, 0)
        XCTAssertEqual(temiz.netOut, 0)
        XCTAssertEqual(temiz.diskRead, 0)
        XCTAssertEqual(temiz.diskWrite, 49_194_602_496)
    }

    func testBicimlendiriciCokmez() {
        XCTAssertEqual(Fmt.byteCount(2.03e20), Int64.max)
        XCTAssertEqual(Fmt.byteCount(.infinity), 0)
        XCTAssertEqual(Fmt.byteCount(.nan), 0)
        XCTAssertEqual(Fmt.byteCount(-5), 0)
        XCTAssertEqual(Fmt.byteCount(1_000), 1_000)
        XCTAssertFalse(Fmt.total(2.03e20).isEmpty)
    }
}
