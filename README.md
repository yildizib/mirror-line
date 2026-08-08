# MirrorLine

*Serverless, end-to-end encrypted call & SMS mirroring between two Android phones.*

Sunucusuz, uçtan uca şifreli iki Android telefon arası arama ve SMS senkronizasyonu.
Veri hiçbir zaman üçüncü parti bir sunucudan geçmez — iki telefon aynı yerel ağda
doğrudan birbirine bağlanır.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

## Neden?

Birden fazla aktif hattı olan (ör. iş + kişisel) kullanıcılar, ikinci telefonu sürekli
takip etmek zorunda kalır ya da önemli aramaları/SMS'leri kaçırır. MirrorLine, SIM'in
takılı olduğu telefonu ("Diğer Telefon") asıl kullandığınız telefona ("Asıl Telefon")
LAN üzerinden uçtan uca şifreli olarak yansıtır — bulut yok, hesap yok, üçüncü parti
sunucu yok.

## Özellikler

- **QR kod ile cihaz eşleştirme** — kim kimin QR'ını tararsa tarasın çalışır, roller
  önceden seçilmiş olduğu sürece yön fark etmez.
- **Karşılıklı kimlik doğrulama** — Ed25519 challenge-response ile üçüncü bir cihazın
  bağlantıya sızması engellenir (3 yönlü el sıkışma: challenge → response → ack).
- **UDP beacon ile otomatik cihaz keşfi** — IP adresi değişse bile (DHCP yenileme,
  ağ değişimi) cihazlar birbirini yeniden bulur.
- **Kendi kendine toparlanan bağlantı** — bağlantı sessizce koparsa (WiFi güç
  tasarrufu, ağ dalgalanması vb.) uygulama periyodik olarak kendini yeniden
  başlatmadan otomatik toparlanır; öldürülüp yeniden açılmasına gerek yoktur.
- **Gelen arama bildirimi + uzaktan reddetme** — arama durumu (çalıyor/cevaplandı/
  cevapsız/reddedildi/sonlandı) iki cihaz arasında gerçek zamanlı senkronize edilir.
- **Çift yönlü SMS mirroring** — gelen SMS'ler yansıtılır, Asıl Telefon'dan yazılan
  yanıtlar Diğer Telefon üzerinden gönderilir.
- **Rehber adı çözümlemesi** — bildirimlerde çıplak numara yerine (varsa) rehberdeki
  isim gösterilir (izin opsiyonel, reddedilirse numaraya döner).
- **Bildirim aynalama** (opsiyonel) — seçtiğiniz uygulamaların bildirimlerini de
  (uygulama adı + mesaj ile, mükerrer göstermeden) yansıtabilir.
- **Çevrimdışı kuyruk** — bağlantı yokken oluşan olaylar yerelde kuyruğa alınır,
  bağlantı geri gelince otomatik gönderilir.
- **AES-256-GCM uçtan uca şifreleme** — her mesaj kendi nonce'u ile şifrelenir;
  anahtar sadece fiziksel QR ile değiş tokuş edilir, hiçbir sunucudan geçmez.

## Mimari

- **Source (Diğer Telefon):** SIM'in takılı olduğu cihaz. TCP sunucusu (port 45678)
  açar ve LAN'e periyodik UDP beacon (port 45679) yayar. Gelen arama/SMS/bildirim
  eventlerini native (Kotlin) tarafta yakalayıp şifreli olarak karşı cihaza gönderir.
- **Main (Asıl Telefon):** Beacon'ları dinler, Source'u bulur ve TCP ile bağlanır.
  Bildirimleri gösterir, aramayı reddedebilir, SMS'e yanıt yazabilir.
- **Eşleştirme öncesi:** Her iki cihaz da (rol fark etmeksizin) kendi portunda dinler,
  böylece QR eşleştirme kim tarafından başlatılırsa başlatılsın çalışır. Eşleşme
  tamamlanınca sadece Source kalıcı sunucu olarak çalışmaya devam eder.
- **Bağlantı sağlığı:** 15 sn'de bir heartbeat (karşılıklı ack ile), 45 sn veri
  gelmezse veya bir yazma başarısız olursa bağlantı düşürülür; ardından periyodik
  (10 sn) bir öz-iyileştirme döngüsü tam bir yeniden başlatma (`refresh()`) dener —
  bu döngü hem Main hem Source rolünde çalışır.
- **Android arka plan çalışması:** Uygulama süreci boyunca yaşayan paylaşımlı bir
  `FlutterEngine` (Activity yaşam döngüsünden bağımsız) + foreground service +
  wake lock/WiFi lock kombinasyonu, ekran kilitlense veya Activity öldürülse bile
  bağlantının canlı kalmasını sağlar.

## Teknoloji Yığını

- **Flutter / Dart** — UI, state management ([Riverpod](https://riverpod.dev)), ağ, veri katmanı
- **sqflite** — yerel SQLite veritabanı (peer, call_event, sms_message, offline_queue)
- **cryptography** — AES-256-GCM + Ed25519
- **flutter_secure_storage** — anahtarların güvenli saklanması (Android Keystore destekli)
- **mobile_scanner / qr_flutter** — QR eşleştirme
- **flutter_local_notifications** — yerel bildirimler
- **Kotlin (native)** — telefon durumu/SMS/bildirim dinleyicileri, rehber sorgusu,
  foreground service, paylaşımlı `FlutterEngine` yönetimi (`telephony` paketi yerine
  minimal bir `MethodChannel` köprüsü kullanılıyor — AGP namespace uyumsuzluğu nedeniyle)

Kod tabanı **feature-first** olarak organize edilmiştir: `lib/core/` (network,
security, data, services, telephony, tema) katman-bağımsız altyapıyı; `lib/features/`
(connection, pairing, calls, sms, settings, home) her özelliğin kendi provider ve
ekranlarını bir arada tutar.

## Başlangıç

```bash
flutter pub get
flutter run
```

Android tarafında gerekli izinler (telefon durumu, SMS, arama, bildirim, opsiyonel
rehber) ilk kullanımda istenir; ayrıntılar için `docs/` klasörüne bakın.

## İki Cihazda Test Prosedürü

1. **Hazırlık:** İki telefonu da aynı WiFi ağına bağlayın. (Ağda "AP isolation" /
   "client isolation" kapalı olmalı; misafir ağlarında cihazlar birbirini göremeyebilir.)
2. **Source cihaz:** Uygulamayı açın → Ayarlar → Rol Seç → **Diğer Telefon**.
   İzinler istendiğinde tamamını verin.
3. **Main cihaz:** Uygulamayı açın → Ayarlar → Rol Seç → **Asıl Telefon**.
4. **Eşleştirme:** İki cihazdan hangisinde QR gösterilip hangisinde tarandığı önemli
   değildir. Bir cihazda Ayarlar → **Cihaz Eşleştir** → "QR Göster"; diğerinde aynı
   ekranın "QR Tara" sekmesinden okutun.
5. **Doğrulama:** Birkaç saniye içinde üst banner kaybolmalı ve Ayarlar'da "Bağlı"
   görünmeli. Bağlanmazsa Ayarlar → "Yeniden Dene" veya manuel IP ile bağlanmayı
   deneyin (Source IP'si, Source cihazın Ayarlar ekranında yazar).
6. **SMS testi:** Source cihaza başka bir telefondan SMS gönderin. Main cihazda
   rehber adıyla (varsa) bildirim gelmeli ve SMS sekmesinde mesaj görünmeli.
   Main'den "Yanıtla" ile yazılan mesaj Source üzerinden gönderilir.
7. **Arama testi:** Source cihazı başka bir telefondan arayın. Main'de bildirim ve
   Aramalar sekmesinde kayıt görünmeli; reddet butonu sadece arama çalarken görünür
   ve basıldığında Source'taki aramayı sonlandırır. Arama cevaplanır/kapanırsa
   durum (Cevaplandı/Cevapsız/Sonlandı) her iki cihazda da otomatik güncellenir.
8. **Arka plan:** Source cihazda Ayarlar → "Pil optimizasyonunu kaldır" ve
   "Kullanılmıyorsa izinleri kaldırma" seçeneklerini kullanın; uygulama foreground
   service + wake lock ile arka planda ve ekran kapalıyken de çalışmaya devam eder.

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
  edin; açıkken "Yeniden Dene"ye basın. Bağlantı birkaç saniye içinde kendiliğinden de
  toparlanmalıdır (bkz. Mimari → Bağlantı sağlığı).
- Her durumda Ayarlar'dan **manuel IP** ile bağlanmayı deneyebilirsiniz
  (IP'yi Source cihazın "Bu Cihaz" bölümünden okuyun).

## Güvenlik Modeli

- Paylaşılan simetrik anahtar (AES-256-GCM) yalnızca fiziksel QR kod ile değiş
  tokuş edilir; hiçbir ağ üzerinden taşınmaz.
- Her cihazın kendi Ed25519 kimlik anahtar çifti vardır; eşleştirme sırasında genel
  anahtarlar karşılıklı değiştirilir ve sonraki her bağlantı challenge-response ile
  doğrulanır (bkz. `core/network/socket_manager.dart`).
- Anahtarlar `flutter_secure_storage` ile (Android Keystore destekli) saklanır.
- Tüm mesaj gövdeleri AES-256-GCM ile şifrelenir; her mesajda yeni bir nonce üretilir.
- Yerel veri (arama/SMS geçmişi, kuyruk) yalnızca cihaz üzerindeki SQLite'ta tutulur;
  hiçbir bulut senkronizasyonu yoktur.

Bir güvenlik açığı bulduysanız lütfen bir issue açmadan önce doğrudan iletişime geçin.

## Katkıda Bulunma

Issue ve PR'lara açığız. Değişiklik göndermeden önce:

```bash
flutter analyze
flutter test
```

komutlarının temiz geçtiğinden emin olun.

## Lisans

[Apache License 2.0](LICENSE).

---

*Bu proje geliştirilirken Ollama Cloud, OpenCode ve Claude Code kullanılmıştır.*
