# Nabız

macOS için sade, Türkçe bir sistem izleyici. Activity Monitor'ün yaptığını daha okunur bir şekilde gösterir; Vitals'tan aldığı fikirle her işlemin **son 1 dakikalık** CPU grafiğini de tutar.

## Neler var
- **Genel Bakış:** CPU, bellek, GPU, disk ve pil kadranları; son dakikaların zaman çizelgesi; ağ ve disk etkinliği; "kim ne kullanıyor" çubukları; tek cümlelik durum ("Her şey sakin", "Bellek daraldı"…).
- **Canlı sekmeler:** her sekmenin altında o anki değer (CPU 30%, Bellek 70%…). ⌘1–⌘8 ile geçiş.
- **Detay sayfaları:** CPU (çekirdekler, en yoğunlar), Bellek (dağılım, uygulamalar), GPU, Disk (diskler, 7 gün), Ağ (bağlantılar, 7 gün), Pil (sağlık, döngü, güç).
- **İşlemler:** arama, Tümü/Benim/Uygulamalar filtresi, son 1 dakika grafiği; sağ tıkla Kapat / Zorla Kapat / Finder'da Göster / PID kopyala. Oturumu kapatabilecek sistem işlemleri (loginwindow, WindowServer…) korunur.
- **Menü çubuğu:** Çubuklar / Halkalar / Yazı stilleri; tıklayınca mini kadranlar ve en yoğun uygulamalar.
- **Ayarlar (⌘,):** görünüm, renk, yenileme sıklığı, menü çubuğu.

## Derleme
```bash
./build-app.sh      # Nabız.app oluşturur
swift test          # testleri çalıştırır
swift Tools/make-icon.swift "$PWD"   # simgeyi yeniden çizer
```

Yönetici izni gerektirmez; başka kullanıcılara ait işlemlerin CPU/bellek değerleri macOS tarafından gizlenir ("—").
