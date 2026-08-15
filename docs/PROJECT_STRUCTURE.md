# MirrorLine — Proje Yapısı ve Mimari

Bu doküman projenin yapısını, katmanlı mimarisini ve "ne nerede, ne işe yarar" haritasını özetler.

## Proje Özeti

**MirrorLine** (`package: mirrorline`, v0.3.0) — Sunucusuz, uçtan uca şifreli (AES-256-GCM + Ed25519) iki Android telefon arası arama/SMS/bildirim yansıtma uygulaması. Türkiye IMEI kayıt sorununa çözüm: kayıtlı telefon (Source) hattı taşır, ana telefon (Main) her şeyi görür. İki telefon aynı WiFi üzerinden doğrudan bağlanır, veri hiçbir üçüncü parti sunucudan geçmez.

Teknolojiler: Flutter + Riverpod (state) + sqflite (SQLite, şema v6) + cryptography/crypto (şifreleme) + web_socket_channel (TCP) + Kotlin native köprü (tek MethodChannel) + l10n (TR/EN).

## Mimari Katmanlar (AGENTS.md kuralı)

```
Base services (core/)  →  Facade (features/*_facade.dart)  →  UI service (controllers/providers)  →  UI (screens/widgets)
```

Bağımlılık tek yönlü: `core → l10n + harici paketler`, `features → core`. Core asla features/shared'a import etmez.

## lib/ Yapısı

### `core/` — Base services (27 dosya)

| Bölüm | Dosyalar | Görev |
|---|---|---|
| **data/** | `database.dart` | sqflite şema sahibi (şema v6, migration v1→v6, testler için açık `createTables`/`upgradeTables`) |
| | `models/` | `Peer`, `CallEvent`, `SmsMessage`, `NotificationEvent`, `QueueItem` — saf Dart veri sözleşmeleri, `groupKey`/`displayName` gibi görüntü mantığı |
| | `daos/` | 6 tablo için ince CRUD + pagination: `PeerDao` (`.replaceId` pairing'de phantom duplicate önler), `CallEventDao`, `SmsMessageDao`, `NotificationEventDao`, `KnownNetworkDao` (reconnect fast-path cache), `QueueDao` |
| **network/** | `socket_manager.dart` | Şifreli TCP bağlantısı, length-framed transport, AES-GCM payload, heartbeat/watchdog, Ed25519 challenge-response auth, background throttle. En kritik base service |
| | `message_protocol.dart` | Wire format: `MirrorMessage` (type/id/timestamp/base64 ciphertext) + `MessageTypes` sabitleri (call, sms, notification, ack, pairing, auth). Saf veri sözleşmesi |
| | `lan_beacon.dart` | UDP beacon (port 45679): IP/port kimliğini yayınlar, eşin beacon'ını dinler. 3s hızlı / 15s yavaş kadans |
| | `subnet_scanner.dart` | AP isolation fallback: local /24(ler)i aktif TCP probe ile tarar. Sonuçlar yalnızca ipucudur, auth hep şifreli handshake ile doğrulanır. `subnetPrefixOf()` helper'ı `KnownNetworkDao` tarafından da kullanılır |
| | `peer_discovery.dart` | Cihazın kendi yerel IPv4 adreslerini çözer (WiFi + VPN TUN, TUN öncelikli) |
| **security/** | `crypto_manager.dart` | AES-GCM şifreleme/çözme, Ed25519 imza/doğrulama, 6 haneli deterministik pairing kodu |
| | `key_store.dart` | flutter_secure_storage (Android Keystore) üzerinden kimlik, AES anahtar, Ed25519 keypair kalıcılığı |
| **telephony/** | `telephony_channel.dart` | Native `MethodChannel('io.github.yildizib.mirrorline/telephony')` köprüsü. Dinleyiciler (`setEventHandler`: onCall/onSms/onNotification/onNotificationRemoved/onNetworkChanged) facade'larca tüketilir |
| | `installed_apps_channel.dart` | Yüklü uygulama listesi + ikonlar; aynı tek MethodChannel'ı yeniden kullanır |
| **services/** | `queue_service.dart` | Offline outbox: bağlantısızken çağrı/SMS tamponlar, 5 denemeden sonra bırakır |
| | `connectivity_service.dart` | connectivity_plus üzerinden çevrimiçi/çevrimdışı gözlemi, `connection_facade`'ın reconnect mantığını besler |
| | `notification_service.dart` | OS bildirimi gösterimi + `NotificationRouter` (arka plan tap → widget ağacına deep-link köprüsü) |
| | `watched_apps_service.dart` | Hangi uygulamaların bildirimlerinin yansıtılacağı (SharedPreferences, ilk çalıştırmada hepsiyle tohumlanır). Riverpod provider — core'da barındırılan "UI service" istisnası |
| | `locale_service.dart` | Dil state + widget ağacı dışında localized string çözümleme (`appL10n(ref)` helper). Aynı istisna |
| | `permission_service.dart` | Merkezi runtime izin yönetimi (bildirim/telefon/SMS/kişiler, pil optimizasyonu) |
| **theme/** | `theme.dart` | Material 3 tema + `AppSpacing`/`AppRadius`/`AppStatusColors` (ThemeExtension) |

### `features/` — Facade + UI (7 özellik, 3 dosya türü)

Katman kuralı:
- **Facade** (`*_facade.dart`): Riverpod `StateNotifier`, core'a erişir (DAO/Soket/KeyStore/Crypto/Telephony). Core'a erişen tek özellik katmanı.
- **Provider / Notifier** (`*_provider.dart`): Türetilmiş state, gruplama, pagination. Facade'leri okur.
- **Controller** (`*_controller.dart`): UI service; yalnızca facade'leri orkestrasyonlar.
- **Screen / Widget**: UI; yalnızca stateless one-shot yardımcılara dokunur.

| Özellik | Dosyalar | Görev |
|---|---|---|
| **connection/** | `connection_facade.dart` (1265 satır) | Sistemin merkezi: rol tabanlı başlangıç (Source=server+beacon, Main=client), auth, discovery, offline queue flush, replay koruması, reconnect, health timer. `sendOrQueue`/`notify` callback'lerini diğer facade'lara enjekte eder |
| | `reconnect_scheduler.dart`, `peer_discovery_coordinator.dart`, `force_connect_strategy.dart` | Provider DEĞİL, enjekte edilebilir plain Dart helper'lar |
| | `connection_status_provider.dart` | Canlı teşhis: `ConnectionStatus`, hata kodları, discovery log (50 kayıt) |
| | `widgets/connection_banner.dart` | Bağlantısızken app bar altında animasyonlu offline şeridi |
| **pairing/** | `pairing_facade.dart` | İki yönlü QR eşleştirme: istek→kabul/red (30s)→peer kalıcılığı→ack (15s, asimetrik durumu önler) |
| | `peer_facade.dart` | Tüm özelliklerin ortak düşük seviye peer kaydı: `createPeer`, `createPeerFromQr`, `applyPairedPeer`, `applyUpdate`, 6 haneli kod üretimi |
| | `pairing_controller.dart`, `role_selection_controller.dart` | UI service (facade zincirini orkestrasyonlar) |
| | `pairing_screen.dart` (776 satır), `role_selection_screen.dart`, `widgets/qr_display.dart` | QR göster/tara, rol seçimi (Main/Source) |
| **home/** | `home_screen.dart` | 5 sekmeli shell (Home/Calls/SMS/Notifications/Settings), canlı bağlantı noktası, deep-link router |
| | `home_feed_provider.dart` | 3 olay türünü (call/sms/notification) birleştiren chronological feed, 3'lü pagination |
| | `splash_screen.dart`, `home_feed_screen.dart` | Açılış animasyonu, birleşik feed listesi |
| **sms/** | `sms_facade.dart` | SMS state + native/peer olay yönetimi. Native threadId yok → address'e göre gruplama. Source tarafında `smsOutgoing` aslında SMS gönderir (`TelephonyChannel.sendSms`) |
| | `sms_thread_provider.dart` | Konuşma gruplama + pagination (`SmsThread` = address anahtarlı) |
| | `sms_screen.dart`, `sms_thread_screen.dart` | Konuşma listesi (swipe + çoklu seçim), chat görünümü + compose |
| | `widgets/sms_bubble.dart`, `widgets/sms_thread_tile.dart` | Chat balonu, konuşma satırı |
| **calls/** | `call_facade.dart` | Çağrı state + native event queue serialization (re-entrant sıralama hatalarını önler), 90s ringing watchdog, `_pendingCallStatuses` tamponu |
| | `call_group_provider.dart` | Kişi bazlı gruplama + pagination (`CallGroup`, `hasActive` ringing) |
| | `calls_screen.dart`, `call_group_detail_screen.dart`, `widgets/call_card.dart` | Gruplu çağrı listesi, grup detayı, çağrı kartı |
| **notifications/** | `notification_facade.dart` | Yansıtılan bildirim state. Source'ta watched-apps filtresi, Main'de yerel OS bildirimi. `notificationRemoved` bilinçli no-op (DB'de kalır, #59) |
| | `notification_group_provider.dart` | Paket bazlı gruplama + pagination |
| | `notifications_screen.dart`, `notification_group_detail_screen.dart` | Uygulama bazlı liste, detay |
| **settings/** | `settings_screen.dart` (1052 satır) | Bölüm bazlı ayarlar: Bu Cihaz, Eşli Cihaz, Bağlantı Teşhisi, Eşli Cihazlar, Pairing Aksiyonları, Sistem, Danger Zone. `_ForceConnectDialog` canlı progress |
| | `settings_controller.dart` | `deletePeer`, `resetDevice` orkestrasyonu |
| | `diagnostics_facade.dart` | "Run Tests": gerçek gönderim hattından sahte çağrı/SMS/bildirim, test logu |
| | `diagnostics_screen.dart`, `watched_apps_screen.dart` | Test sonuçları, aranabilir yüklü-uygulama toggle listesi |

### `shared/`

| Dosya | Görev |
|---|---|
| `pagination/paginated_list_state.dart` | `PaginatedListState<T>`, `kDefaultPageSize=25`, `dedupeById`, `yesterdayStart()` (bugün+dün penceresi) |
| `pagination/grouped_paginated_notifier.dart` | Gruplu liste pagination base (calls/notifications/sms threads): loadInitial→loadMore→refresh akışı |
| `widgets/selectable_list_scaffold.dart` | Yeniden kullanılabilir çoklu-seçim liste iskeleti (silme onayı, DateHeader, sonsuz kaydırma) |
| `widgets/empty_state.dart`, `date_header.dart`, `date_grouped_list.dart` | Boş durum, tarih başlığı, tarih gruplama yardımcıları |

## Android Native (Kotlin, 13 dosya)

| Dosya | Görev |
|---|---|
| `MainActivity.kt` | Launcher; paylaşılan `MirrorLineEngine` kullanır, Activity yok olsa da bağlantı sürer |
| `MirrorLineEngine.kt` | Tek process-wide FlutterEngine, `FlutterEngineCache`'te saklanır |
| `MirrorLineChannel.kt` | Tek `io.github.yildizib.mirrorline/telephony` MethodChannel: startListening/stopListening, rejectCall, sendSms, getLocalIp, izin/auto-start/battery-saver ekranları, resolveContactName, getInstalledApps/getAppIcon. Dart'a onNetworkChanged (300ms debounce) |
| `MirrorLineService.kt` (617 satır) | SMS + telefon durumu broadcast receiver'ları (dynamic), RINGING→ANSWERED→MISSED→ENDED durum makinesi, wake + Wi-Fi kilitleri, START_STICKY, call-log zenginleştirme retry |
| `MirrorLineNotificationListener.kt` | 3. parti bildirim yansıtma (sbn.key dedup, GROUP_SUMMARY atlar, default dialer/SMS hariç) |
| `BootReceiver.kt` | Reboot sonrası headless servis restartı |
| `Watchdog.kt` / `WatchdogReceiver.kt` | 5 dk AlarmManager watchdog (OEM process kill'e karşı) |
| `OemAutoStart.kt` | Xiaomi/Huawei/Oppo/Vivo/Samsung vb. otomatik başlatma + pil tasarrufu ekranları |
| `CallLogResolver.kt`, `ContactResolver.kt`, `InstalledAppsResolver.kt` | Çağrı kaydı, kişi adı, yüklü uygulama çözümleyicileri |

Manifest izinleri: READ_PHONE_STATE, READ_CALL_LOG, ANSWER_PHONE_CALLS, RECEIVE_SMS, SEND_SMS, READ_SMS, READ_CONTACTS, FOREGROUND_SERVICE(+PHONE_CALL), POST_NOTIFICATIONS, REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, SCHEDULE_EXACT_ALARM, WAKE_LOCK, CAMERA, RECEIVE_BOOT_COMPLETED vb.

## Test & CI

- **33 test dosyası**: core network/security (beacon e2e, şifreli wire doğrulama), DAO (gerçek in-memory SQLite, migration), facade pagination, provider/grouped-pagination, widget smoke.
- **`ci.yml`**: `dart analyze --fatal-infos` + `flutter test --test-randomize-ordering-seed random` + `flutter build apk --debug` (main/develop push+PR).
- **`android-release.yml`**: `v*` tag veya manual dispatch → pubspec versiyon bump → release APK → GitHub Release.

## l10n

- `l10n.yaml`: ARB dir `lib/l10n`, template `app_tr.arb`, output `AppLocalizations`.
- TR (template, ~342 key) + EN (~172). Türkçe-öncelikli.

## Öne Çıkan Tasarım Noktaları

1. **`ConnectionFacade` hub**: `sendOrQueue`/`notify` callback'lerini `CallFacade`/`SmsFacade`/`NotificationFacade`'a enjekte eder — onlar sokete hiç dokunmaz.
2. **Üçlü discovery**: UDP beacon + `KnownNetworkDao` fast-path cache + subnet scan, öncelik sıralı.
3. **Tek MethodChannel + shared FlutterEngine**: bağlantı izolatı Activity/servis restartlarında yaşar.
4. **Auth ack handshake**: iki taraf da premature "connected" ilan etmez; generation guard stale bağlantı denemelerini ayıklar.
5. **Türkçe-öncelikli**: ARB template, dökümanlar ve servis bildirim stringleri TR.