import SwiftUI
import UserNotifications

/// Uyarı kurallarının ayarları (hem Ayarlar penceresinde hem Uyarılar sekmesinde kullanılır).
struct UyariKurallari: View {
    @AppStorage(UyariPrefs.acik) private var acik = true
    @AppStorage(UyariPrefs.cpuEsik) private var cpuEsik = 80.0
    @AppStorage(UyariPrefs.cpuDakika) private var cpuDakika = 2.0
    @AppStorage(UyariPrefs.bellek) private var bellek = true
    @AppStorage(UyariPrefs.surecBellekGB) private var surecBellekGB = 4.0
    @AppStorage(UyariPrefs.pil) private var pil = true
    @AppStorage(UyariPrefs.disk) private var disk = true
    @AppStorage(UyariPrefs.isi) private var isi = true
    @State private var bildirimIzni: UNAuthorizationStatus?

    var body: some View {
        Toggle("Uyarıları aç", isOn: $acik)
            .onChange(of: acik) { _, yeni in if yeni { UyariMotoru.izinIste() } }
        Group {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Label("Yoğun uygulama", systemImage: "flame.fill")
                    Spacer()
                    Text("%\(Int(cpuEsik)) üstünde \(Int(cpuDakika)) dk").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $cpuEsik, in: 30...200, step: 10) { Text("CPU eşiği") }
                    .labelsHidden()
                Picker("Süre", selection: $cpuDakika) {
                    Text("1 dakika").tag(1.0); Text("2 dakika").tag(2.0); Text("5 dakika").tag(5.0); Text("10 dakika").tag(10.0)
                }
                Text("%100 = bir işlemci çekirdeğinin tamamı. Çok çekirdekli işler %100'ü geçebilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle(isOn: $bellek) { Label("Bellek daralınca", systemImage: "memorychip") }
            Picker(selection: $surecBellekGB) {
                Text("Kapalı").tag(0.0); Text("2 GB").tag(2.0); Text("4 GB").tag(4.0); Text("8 GB").tag(8.0)
            } label: { Label("Tek uygulama şundan fazla bellek kullanırsa", systemImage: "externaldrive.fill.badge.exclamationmark") }
            Toggle(isOn: $pil) { Label("Pil %15 ve %5'e düşünce", systemImage: "battery.25percent") }
            Toggle(isOn: $disk) { Label("Diskte 10 GB'tan az yer kalınca", systemImage: "internaldrive") }
            Toggle(isOn: $isi) { Label("Mac ısınınca", systemImage: "thermometer.high") }
        }
        .disabled(!acik)
        if bildirimIzni == .denied {
            Label("Bildirimlere izin verilmemiş. Sistem Ayarları › Bildirimler › Nabız bölümünden açabilirsiniz; uyarılar yine de bu listede görünür.",
                  systemImage: "bell.slash")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        Color.clear.frame(height: 0)
            .task {
                let ayar = await UNUserNotificationCenter.current().notificationSettings()
                bildirimIzni = ayar.authorizationStatus
            }
    }
}

struct UyarilarPage: View {
    @EnvironmentObject private var monitor: Monitor
    @ObservedObject var motor: UyariMotoru

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Form { UyariKurallari() }
                .formStyle(.grouped)
                .frame(width: 360)
                .scrollContentBackground(.hidden)

            Panel {
                HStack {
                    Label("Uyarı geçmişi", systemImage: "bell.badge").font(.headline)
                    Spacer()
                    if !motor.gecmis.isEmpty {
                        Button("Geçmişi temizle", role: .destructive) { motor.temizle() }
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
                if motor.gecmis.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal").font(.system(size: 36)).foregroundStyle(.green)
                        Text("Henüz uyarı yok").font(.title3.weight(.semibold))
                        Text("Bir uygulama uzun süre yoğun çalışırsa, bellek daralırsa, pil ya da disk azalırsa burada ve bildirim olarak görürsünüz.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 380)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(motor.gecmis) { u in UyariSatiri(uyari: u) }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding(16)
        .onAppear { motor.okunduSay() }
    }
}

struct UyariSatiri: View {
    let uyari: Uyari
    var kucuk = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: uyari.simge)
                .foregroundStyle(uyari.renk)
                .frame(width: kucuk ? 22 : 30, height: kucuk ? 22 : 30)
                .background(Circle().fill(uyari.renk.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(uyari.baslik).font(kucuk ? .callout.weight(.semibold) : .body.weight(.semibold)).lineLimit(1)
                    Spacer()
                    Text(uyari.tarih, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !kucuk {
                    Text(uyari.metin).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(kucuk ? 0 : 10)
        .background(kucuk ? nil : RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
        .help(uyari.metin)
    }
}
