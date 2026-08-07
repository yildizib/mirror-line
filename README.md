# MirrorLine

Sunucusuz, uçtan uca şifreli iki Android telefon arası arama ve SMS senkronizasyonu.

## Özellikler
- QR kod ile cihaz eşleştirme
- UDP beacon ile otomatik cihaz keşfi (IP değişse bile yeniden bulur)
- Gelen arama bildirimi ve uzaktan reddetme
- Çift yönlü SMS mirroring
- Çevrimdışı kuyruk ve otomatik senkronizasyon
- AES‑256‑GCM şifreleme, hiçbir üçüncü parti sunucu yok

## Başlangıç

```bash
flutter pub get
flutter run
```

## Mimari (kısa)

- **Source (Diğer Telefon):** SIM'in takılı olduğu cihaz. TCP sunucusu (port 45678) açar ve
  LAN'e periyodik UDP beacon (port 45679) yayar. Gelen arama/SMS eventlerini yakalayıp
  şifreli olarak karşı cihaza gönderir.
- **Main (Asıl Telefon):** Beacon'ları dinler, Source'u bulur ve TCP ile bağlanır.
  Bildirimleri gösterir, aramayı reddedebilir, SMS'e yanıt yazabilir.
- Bağlantı koparsa otomatik yeniden bağlanma (10 sn aralıklı deneme + uygulama öne
  gelince tekrar), 15 sn'de bir heartbeat ile kopukluk tespiti vardır.

## İki Cihazda Test Prosedürü

1. **Hazırlık:** İki telefonu da aynı WiFi ağına bağlayın. (Ağda "AP isolation" /
   "client isolation" kapalı olmalı; misafir ağlarında cihazlar birbirini göremeyebilir.)
2. **Source cihaz:** Uygulamayı açın → Ayarlar → Rol Seç → **Diğer Telefon**.
   İzinler istendiğinde tamamını verin.
3. **Main cihaz:** Uygulamayı açın → Ayarlar → Rol Seç → **Asıl Telefon**.
4. **Eşleştirme:** Source cihazda Ayarlar → **Cihaz Eşleştir** → "QR Göster" sekmesi.
   Main cihazda aynı ekranın "QR Tara" sekmesinden QR'ı okutun.
5. **Doğrulama:** Birkaç saniye içinde üst banner kaybolmalı ve Ayarlar'da "Bağlı"
   görünmeli. Bağlanmazsa Ayarlar → "Yeniden Dene" veya manuel IP ile bağlanmayı deneyin
   (Source IP'si, Source cihazın Ayarlar ekranında yazar).
6. **SMS testi:** Source cihaza başka bir telefondan SMS gönderin. Main cihazda
   bildirim gelmeli ve SMS sekmesinde mesaj görünmeli. Main'den "Yanıtla" ile yazılan
   mesaj Source üzerinden gönderilir.
7. **Arama testi:** Source cihazı başka bir telefondan arayın. Main'de "Gelen Arama"
   bildirimi ve Aramalar sekmesinde kayıt görünmeli; reddet butonu Source'taki aramayı
   sonlandırır.
8. **Arka plan:** Source cihazda Ayarlar → "Pil optimizasyonunu kaldır" seçeneğini
   kullanın; uygulama foreground servisle arka planda çalışmaya devam eder.
   **Not:** Source cihazda uygulamayı son uygulamalar listesinden kaydırarak tamamen
   kapatmayın; servis çalışmaya devam eder ancak Flutter motoru kapandığı için
   eventler iletilemez. Uygulamayı arka planda bırakmanız yeterli.

## Sorun Giderme

Ayarlar → **Bağlantı Teşhisi** kartında şunları kontrol edin:

| Satır | Anlamı |
|---|---|
| Bu cihaz IP | Cihazın WiFi'daki gerçek IP'si. **"belirlenemedi"** ise WiFi kapalıdır |
| Eş cihaz IP | Eşleştirilen cihazın IP'si. **"unknown"** ise QR'daki IP boş gelmiş |
| Sunucu | Source cihazda **"çalışıyor"** olmalı (port 45678) |
| Son beacon | Source'un beacon'ı alınıyorsa burada görünür (IP + saat). **"henüz yok"** kalıyorsa keşif çalışmıyor |
| Deneme sayısı / hata | Bağlanma denemeleri ve son hata mesajı |

Yaygın durumlar:
- **"Bu cihaz IP: belirlenemedi"** → WiFi bağlantısını kontrol edin.
- **"Son beacon: henüz yok"** → Source cihazda "Sunucu: çalışıyor" mu bakın; çalışıyorsa
  yönlendiricide **AP/client isolation** açık olabilir (misafir ağı kullanmayın).
- **"Bağlantı başarısız: IP:port (sunucu kapalı...)"** → Source uygulaması açık mı kontrol
  edin; açıkken "Yeniden Dene"ye basın.
- Her durumda Ayarlar'dan **manuel IP** ile bağlanmayı deneyebilirsiniz
  (IP'yi Source cihazın "Bu Cihaz" bölümünden okuyun).
