# MirrorLine

*Serverless, end-to-end encrypted call & SMS mirroring between two Android phones.*

Sunucusuz, uçtan uca şifreli iki Android telefon arası arama ve SMS senkronizasyonu.
Veri hiçbir zaman üçüncü parti bir sunucudan geçmez — iki telefon aynı yerel ağda
doğrudan birbirine bağlanır.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

**Diller:** Türkçe (bu bölüm) · [English](#english)

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
- **Bağlantı sağlığı:** 30 sn'de bir heartbeat (uygulama arka plandayken 60 sn),
  90 sn veri gelmezse veya bir yazma başarısız olursa bağlantı düşürülür; ardından
  periyodik (30 sn) bir öz-iyileştirme döngüsü tam bir yeniden başlatma (`refresh()`)
  dener — bu döngü hem Main hem Source rolünde çalışır.
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

<br>

---

<a id="english"></a>

# MirrorLine (English)

**Languages:** [Türkçe](#mirrorline) · English (this section)

Serverless, end-to-end encrypted call and SMS mirroring between two Android phones.
Data never passes through a third-party server — the two phones connect to each
other directly over the local network.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

## Why?

People who carry two active lines (e.g. work + personal) either have to keep
checking a second phone constantly, or they miss important calls and texts.
MirrorLine mirrors the phone that holds the SIM (the "Source" phone) to the one
you actually use day to day (the "Main" phone) over LAN, end-to-end encrypted —
no cloud, no account, no third-party server.

## Features

- **QR-code pairing** — works no matter which device scans which; only the order
  of *who shows the QR* is irrelevant once both roles are chosen.
- **Mutual authentication** — Ed25519 challenge-response prevents a third device
  from joining the connection (3-way handshake: challenge → response → ack).
- **Automatic discovery via UDP beacon** — devices find each other again even if
  an IP address changes (DHCP renewal, network switch).
- **Self-healing connection** — if the connection silently drops (Wi-Fi power
  saving, network hiccup, etc.), the app periodically recovers on its own without
  needing to be killed and reopened.
- **Incoming call notification + remote reject** — call state (ringing/answered/
  missed/rejected/ended) is synced live between both devices.
- **Two-way SMS mirroring** — incoming texts are mirrored; replies typed on the
  Main phone are sent out through the Source phone.
- **Contact name resolution** — notifications show the address-book name instead
  of a bare number when available (permission is optional; falls back to the
  number if declined).
- **Notification mirroring** (optional) — mirrors notifications from apps you
  choose, shown with the app's name and message, without duplicating reposts.
- **Offline queue** — events that occur while disconnected are queued locally and
  delivered automatically once the connection returns.
- **AES-256-GCM end-to-end encryption** — every message is encrypted with its own
  nonce; the key is exchanged only via the physical QR code, never over a server.

## Architecture

- **Source (the SIM phone):** opens a TCP server (port 45678) and periodically
  broadcasts a UDP beacon (port 45679) on the LAN. Captures incoming call/SMS/
  notification events natively (Kotlin) and forwards them encrypted to the peer.
- **Main (the phone you use):** listens for beacons, discovers the Source device,
  and connects over TCP. Shows notifications, can reject calls, can reply to SMS.
- **Before pairing:** both devices listen on their own port regardless of role, so
  QR pairing works no matter who initiates the scan. Once paired, only the Source
  device keeps running a persistent server.
- **Connection health:** a heartbeat every 30s (60s while the app is backgrounded),
  a 90s receive-timeout, or a failed write all bring the connection down; a
  periodic (30s) self-healing loop then retries a full reinitialization
  (`refresh()`) — this runs for both the Main and Source roles.
- **Android background execution:** a single `FlutterEngine` shared for the whole
  app process lifetime (independent of the Activity lifecycle), combined with a
  foreground service and a wake lock/Wi-Fi lock, keeps the connection alive even
  when the screen is locked or the Activity is destroyed.

## Tech Stack

- **Flutter / Dart** — UI, state management ([Riverpod](https://riverpod.dev)), networking, data layer
- **sqflite** — local SQLite database (peer, call_event, sms_message, offline_queue)
- **cryptography** — AES-256-GCM + Ed25519
- **flutter_secure_storage** — secure key storage (backed by the Android Keystore)
- **mobile_scanner / qr_flutter** — QR pairing
- **flutter_local_notifications** — local notifications
- **Kotlin (native)** — phone state/SMS/notification listeners, contacts lookup,
  foreground service, shared `FlutterEngine` management (a minimal `MethodChannel`
  bridge is used instead of the `telephony` package, due to an AGP namespace
  incompatibility)

The codebase is organized **feature-first**: `lib/core/` holds layer-agnostic
infrastructure (network, security, data, services, telephony, theme); `lib/features/`
(connection, pairing, calls, sms, settings, home) keeps each feature's providers
and screens together.

## Getting Started

```bash
flutter pub get
flutter run
```

The required Android permissions (phone state, SMS, calls, notifications,
optional contacts) are requested on first use; see the `docs/` folder for details.

## Two-Device Test Procedure

1. **Setup:** connect both phones to the same Wi-Fi network. (AP/client isolation
   must be off on the router; devices on a guest network may not see each other.)
2. **Source device:** open the app → Settings → Select Role → **Other Phone**.
   Grant all permissions when prompted.
3. **Main device:** open the app → Settings → Select Role → **Main Phone**.
4. **Pairing:** it doesn't matter which device shows the QR and which scans it.
   On one device: Settings → **Pair Device** → "Show QR" tab; on the other, scan
   it from the "Scan QR" tab of the same screen.
5. **Verify:** within a few seconds the banner at the top should disappear and
   Settings should show "Connected". If not, try Settings → "Retry", or connect
   manually by IP (the Source device's IP is shown on its own Settings screen).
6. **Test SMS:** send an SMS to the Source device from another phone. The Main
   device should show a notification with the contact's name (if known) and the
   message should appear in the SMS tab. A reply typed on Main is sent via Source.
7. **Test calls:** call the Source device from another phone. Main should show a
   notification and an entry in the Calls tab; the reject button only appears
   while the call is ringing and ends the call on Source when pressed. Once the
   call is answered or ends, its status (Answered/Missed/Ended) updates
   automatically on both devices.
8. **Background:** on the Source device, use Settings → "Remove battery
   optimization" and "Remove permissions if unused"; the app keeps running in the
   background and with the screen off thanks to the foreground service + wake lock.

## Troubleshooting

Check the **Connection Diagnostics** card under Settings:

| Row | Meaning |
|---|---|
| This device's IP | The device's real Wi-Fi IP. **"undetermined"** means Wi-Fi is off |
| Peer IP | The paired device's IP. **"unknown"** means the QR carried no IP |
| Server | Should say **"running"** on the Source device (port 45678) |
| Last beacon | Shows the Source's beacon once received (IP + time). Staying **"none yet"** means discovery isn't working |
| Attempt count / error | Connection attempts and the last error message |

Common cases:
- **"This device's IP: undetermined"** → check the Wi-Fi connection.
- **"Last beacon: none yet"** → check whether the Source device says "Server:
  running"; if it does, the router may have **AP/client isolation** enabled
  (avoid guest networks).
- **"Connection failed: IP:port (server down...)"** → check that the Source app
  is open, then tap "Retry". The connection should also recover on its own within
  a few seconds (see Architecture → Connection health).
- You can always fall back to a **manual IP** connection from Settings (read the
  IP from the Source device's "This Device" section).

## Security Model

- The shared symmetric key (AES-256-GCM) is exchanged only via the physical QR
  code; it never travels over any network.
- Each device has its own Ed25519 identity key pair; public keys are exchanged
  during pairing, and every subsequent connection is verified with a
  challenge-response handshake (see `core/network/socket_manager.dart`).
- Keys are stored with `flutter_secure_storage` (backed by the Android Keystore
  where available).
- Every message body is encrypted with AES-256-GCM, with a fresh nonce per message.
- Local data (call/SMS history, the offline queue) lives only in on-device
  SQLite; there is no cloud sync.

If you find a security vulnerability, please reach out directly before opening
a public issue.

## Contributing

Issues and PRs are welcome. Before submitting a change, make sure these pass cleanly:

```bash
flutter analyze
flutter test
```

## License

[Apache License 2.0](LICENSE).

---

*This project was built with the help of Ollama Cloud, OpenCode, and Claude Code.*
