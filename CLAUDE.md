# Nabız — proje kuralları

macOS sistem izleyici (SwiftUI, Swift Package). Arayüz **Türkçe**, tasarım **özgün** (başka uygulamaları birebir kopyalama).

## Komutlar (tek tek, sade yaz)
- Derle: `swift build`
- Test: `swift test`
- Uygulama paketi: `./build-app.sh` → `build.noindex/Nabız.app`; `./build-app.sh --install` → `/Applications/Nabız.app`'a kurar ve açar

## Yapı
- `Sources/SystemMonitor/SystemStats.swift` — CPU, bellek, ağ, disk sayaçları (Mach/sysctl/IOKit)
- `Processes.swift` — işlem listesi ve ad tespiti
- `Hardware.swift` — GPU, pil, diskler, ağ bağlantıları
- `Monitor.swift` — ölçüm döngüsü (arka planda), geçmiş, işlem kapatma
- `DailyTracker.swift` — günlük/7 günlük toplamlar (UserDefaults)
- `Dashboard.swift`, `Pages.swift`, `ContentView.swift` — pencere; `MenuBarView.swift` — menü çubuğu ve ayarlar
- `Tests/SystemMonitorTests` — testler

## Dikkat
- Ölçüm her turda ~15 ms; ekran çizimi pahalıdır. Grafiklerde Swift Charts yerine `Canvas` tercih et (Sparkline, AynaGrafik). Canvas içine `ctx.draw(Text)` ile yazı yazma.
- Ağ bağlantısı yok; uygulama hiçbir veriyi dışarı göndermez.
- Yeni metinler Türkçe olmalı.
