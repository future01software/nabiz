import Foundation
import SwiftUI
import UserNotifications

// MARK: - Ayarlar

enum UyariPrefs {
    static let acik = "uyariAcik"
    static let cpuEsik = "uyariCpuEsik"          // % (100 = bir tam çekirdek)
    static let cpuDakika = "uyariCpuDakika"
    static let bellek = "uyariBellek"
    static let surecBellekGB = "uyariSurecBellekGB" // 0 = kapalı
    static let pil = "uyariPil"
    static let disk = "uyariDisk"
    static let isi = "uyariIsi"
    static let gecmis = "uyariGecmisi"
}

struct UyariAyarlari {
    var acik = true
    var cpuEsik = 80.0
    var cpuDakika = 2.0
    var bellek = true
    var surecBellekGB = 4.0
    var pil = true
    var disk = true
    var isi = true

    static func oku(_ d: UserDefaults = .standard) -> UyariAyarlari {
        var a = UyariAyarlari()
        func b(_ k: String, _ v: Bool) -> Bool { d.object(forKey: k) == nil ? v : d.bool(forKey: k) }
        func n(_ k: String, _ v: Double) -> Double { d.object(forKey: k) == nil ? v : d.double(forKey: k) }
        a.acik = b(UyariPrefs.acik, a.acik)
        a.cpuEsik = n(UyariPrefs.cpuEsik, a.cpuEsik)
        a.cpuDakika = n(UyariPrefs.cpuDakika, a.cpuDakika)
        a.bellek = b(UyariPrefs.bellek, a.bellek)
        a.surecBellekGB = n(UyariPrefs.surecBellekGB, a.surecBellekGB)
        a.pil = b(UyariPrefs.pil, a.pil)
        a.disk = b(UyariPrefs.disk, a.disk)
        a.isi = b(UyariPrefs.isi, a.isi)
        return a
    }
}

// MARK: - Uyarı

struct Uyari: Identifiable, Codable, Equatable {
    enum Tur: String, Codable { case cpu, bellek, surecBellek, pil, disk, isi }
    var id = UUID()
    var tarih = Date()
    let tur: Tur
    let baslik: String
    let metin: String

    var simge: String {
        switch tur {
        case .cpu: "flame.fill"
        case .bellek: "memorychip"
        case .surecBellek: "externaldrive.fill.badge.exclamationmark"
        case .pil: "battery.25percent"
        case .disk: "internaldrive"
        case .isi: "thermometer.high"
        }
    }

    var renk: Color {
        switch tur {
        case .cpu, .isi: .orange
        case .bellek, .surecBellek: .purple
        case .pil: .red
        case .disk: .yellow
        }
    }
}

// MARK: - Motor

/// Her ölçümde kuralları değerlendirir. Aynı uyarıyı tekrar tekrar göndermemek için
/// her uyarının bir "bekleme süresi" vardır; geçici dalgalanmalar için de payı vardır.
@MainActor
final class UyariMotoru: ObservableObject {
    @Published private(set) var gecmis: [Uyari] = []
    @Published private(set) var okunmamis = 0

    /// Bildirimi gönderen fonksiyon (testlerde değiştirilir).
    var gonderici: (Uyari) -> Void = UyariMotoru.bildirimGonder
    var ayarOkuyucu: () -> UyariAyarlari = { UyariAyarlari.oku() }
    var isiOkuyucu: () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState }
    var saat: () -> Date = { Date() }

    private var yogunSure: [String: Double] = [:]     // uygulama adı → eşik üstünde geçen saniye
    private var bellekBaskiSure = 0.0
    private var bekleme: [String: Date] = [:]          // uyarı anahtarı → bu zamana kadar tekrar gönderme
    private var pilUyarildi15 = false
    private var pilUyarildi5 = false
    private let kalici: Bool

    init(kalici: Bool = true) {
        self.kalici = kalici
        if kalici, let data = UserDefaults.standard.data(forKey: UyariPrefs.gecmis),
           let eski = try? JSONDecoder().decode([Uyari].self, from: data) {
            gecmis = eski
        }
    }

    func degerlendir(_ s: Snapshot) {
        let a = ayarOkuyucu()
        guard a.acik, s.elapsed > 0 else { return }
        let simdi = saat()

        // 1) Uzun süre yoğun çalışan uygulama (aynı adlı süreçler tek sayılır, en yoğunu alınır)
        var enYogun: [String: Double] = [:]
        for p in s.processes where !p.restricted { enYogun[p.name] = max(enYogun[p.name] ?? 0, p.cpu) }
        var yeniSure: [String: Double] = [:]
        for (ad, cpu) in enYogun {
            let onceki = yogunSure[ad] ?? 0
            if cpu >= a.cpuEsik { yeniSure[ad] = onceki + s.elapsed }
            else if cpu >= a.cpuEsik * 0.7, onceki > 0 { yeniSure[ad] = onceki }   // kısa düşüşleri affet
        }
        yogunSure = yeniSure
        for (ad, sure) in yogunSure where sure >= a.cpuDakika * 60 {
            let dk = Int((sure / 60).rounded())
            let cpu = enYogun[ad] ?? 0
            tetikle(anahtar: "cpu:\(ad)", bekleme: 15 * 60, simdi: simdi,
                    Uyari(tur: .cpu, baslik: "\(ad) \(dk) dakikadır yoğun",
                          metin: "Şu an %\(Int(cpu.rounded())) CPU kullanıyor. Gerekmiyorsa kapatabilirsiniz; Mac'iniz ısınabilir ve pil daha hızlı biter."))
        }

        // 2) Bellek baskısı 30 saniyeden uzun yüksek
        if a.bellek {
            bellekBaskiSure = s.memory.pressureLevel >= 2 ? bellekBaskiSure + s.elapsed : 0
            if bellekBaskiSure >= 30 {
                let enCok = s.processes.max { $0.memory < $1.memory }
                let kritik = s.memory.pressureLevel >= 4
                tetikle(anahtar: "bellek", bekleme: 30 * 60, simdi: simdi,
                        Uyari(tur: .bellek, baslik: kritik ? "Bellek tükeniyor" : "Bellek daraldı",
                              metin: "En çok \(enCok?.name ?? "bir uygulama") kullanıyor (\(Fmt.bytes(enCok?.memory ?? 0))). Kullanmadığınız uygulamaları kapatmak Mac'i rahatlatır."))
            }
        }

        // 3) Tek bir uygulama çok bellek kullanıyor
        if a.surecBellekGB > 0 {
            let sinir = UInt64(a.surecBellekGB * 1_073_741_824)
            for p in s.processes where p.memory >= sinir {
                tetikle(anahtar: "surecBellek:\(p.name)", bekleme: 60 * 60, simdi: simdi,
                        Uyari(tur: .surecBellek, baslik: "\(p.name) çok bellek kullanıyor",
                              metin: "\(Fmt.bytes(p.memory)) bellek kullanıyor. Uzun süredir açıksa yeniden başlatmak belleği boşaltabilir."))
            }
        }

        // 4) Pil
        if a.pil, let b = s.battery {
            if b.onAC || b.percent > 20 { pilUyarildi15 = false; pilUyarildi5 = false }
            if !b.onAC {
                if b.percent <= 5, !pilUyarildi5 {
                    pilUyarildi5 = true; pilUyarildi15 = true
                    gonder(Uyari(tur: .pil, baslik: "Pil kritik: %\(Int(b.percent))",
                                 metin: "Mac birazdan kapanabilir. Hemen şarja takın ve açık işlerinizi kaydedin."))
                } else if b.percent <= 15, !pilUyarildi15 {
                    pilUyarildi15 = true
                    gonder(Uyari(tur: .pil, baslik: "Pil azaldı: %\(Int(b.percent))",
                                 metin: b.minutesToEmpty.map { "Yaklaşık \(Fmt.minutes($0)) kaldı. Şarj aletini takmayı unutmayın." } ?? "Şarj aletini takmayı unutmayın."))
                }
            }
        }

        // 5) Disk doluyor
        if a.disk, s.disk.total > 0 {
            let az = s.disk.free < 10 * 1_000_000_000 || Double(s.disk.free) / Double(s.disk.total) < 0.05
            if az {
                tetikle(anahtar: "disk", bekleme: 6 * 60 * 60, simdi: simdi,
                        Uyari(tur: .disk, baslik: "Disk doluyor",
                              metin: "Sadece \(Fmt.bytes(s.disk.free)) boş yer kaldı. Disk dolunca Mac yavaşlar ve kayıt yapılamaz."))
            }
        }

        // 6) Isınma
        if a.isi {
            let durum = isiOkuyucu()
            if durum == .serious || durum == .critical {
                tetikle(anahtar: "isi", bekleme: 30 * 60, simdi: simdi,
                        Uyari(tur: .isi, baslik: durum == .critical ? "Mac çok ısındı" : "Mac ısındı",
                              metin: "macOS performansı düşürerek soğumaya çalışıyor. Havalandırmayı kapatmayın; yoğun uygulamaları kapatın."))
            }
        }
    }

    private func tetikle(anahtar: String, bekleme sure: TimeInterval, simdi: Date, _ u: Uyari) {
        if let kadar = bekleme[anahtar], kadar > simdi { return }
        bekleme[anahtar] = simdi.addingTimeInterval(sure)
        gonder(u)
    }

    private func gonder(_ u: Uyari) {
        var u = u
        u.tarih = saat()
        gecmis.insert(u, at: 0)
        if gecmis.count > 50 { gecmis.removeLast(gecmis.count - 50) }
        okunmamis += 1
        kaydet()
        gonderici(u)
    }

    func okunduSay() { okunmamis = 0 }

    func temizle() {
        gecmis = []
        okunmamis = 0
        kaydet()
    }

    private func kaydet() {
        guard kalici, let data = try? JSONEncoder().encode(gecmis) else { return }
        UserDefaults.standard.set(data, forKey: UyariPrefs.gecmis)
    }

    // MARK: macOS bildirimi

    nonisolated static func izinIste() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    nonisolated static func bildirimGonder(_ u: Uyari) {
        let icerik = UNMutableNotificationContent()
        icerik.title = u.baslik
        icerik.body = u.metin
        icerik.sound = .default
        icerik.userInfo = ["sekme": "uyarilar"]
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: u.id.uuidString, content: icerik, trigger: nil))
    }
}

extension Notification.Name {
    static let nabizPencereAc = Notification.Name("nabizPencereAc")
}
