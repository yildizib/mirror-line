# MirrorLine - Teknik Plan

## Paket Listesi (pubspec.yaml)

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8

  # State management
  flutter_riverpod: ^2.5.1

  # Local storage
  sqflite: ^2.3.3+1
  path_provider: ^2.1.3
  shared_preferences: ^2.2.3
  path: ^1.9.0

  # Security
  cryptography: ^2.7.0
  flutter_secure_storage: ^11.0.0

  # Network / discovery
  multicast_dns: ^0.3.2+7
  web_socket_channel: ^3.0.3

  # QR
  qr_flutter: ^4.1.0
  mobile_scanner: ^7.4.0

  # Notifications
  flutter_local_notifications: ^22.2.0

  # Telephony bridge (SMS/call events)
  # telephony paketi AGP namespace uyumsuzluğu nedeniyle kaldırıldı.
  # Yerine MethodChannel tabanlı telephony_channel.dart kullanılıyor.

  # Battery optimization opt-out
  android_intent_plus: ^6.1.0

  # Connectivity
  connectivity_plus: ^7.3.1

  # Logging
  logger: ^2.3.0

  # JSON serialization
  json_annotation: ^4.9.0

  # Permissions
  permission_handler: ^13.0.0

  # UUID
  uuid: ^4.4.2

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  build_runner: ^2.4.11
  json_serializable: ^6.8.1
  mockito: ^5.4.4
```

## Katmanlar

### 1. Data Layer
- `lib/data/database.dart`: sqflite açma/kapama, tablo oluşturma, migrasyon.
- `lib/data/models/`: `Peer`, `CallEvent`, `SmsMessage`, `QueueItem` modelleri.
- `lib/data/daos/`: CRUD işlemleri (peer_dao, call_event_dao, sms_message_dao, queue_dao).

### 2. Security Layer
- `lib/security/crypto_manager.dart`: AES‑256‑GCM şifreleme/çözme.
- `lib/security/key_store.dart`: flutter_secure_storage ile anahtar saklama.

### 3. Network Layer
- `lib/network/peer_discovery.dart`: mDNS keşfi (placeholder; manuel IP fallback ile sınırlı).
- `lib/network/socket_manager.dart`: TCP socket kurulumu, dinleme, gönderme.
- `lib/network/message_protocol.dart`: Mesaj tipleri, encoding/decoding, ACK/NAK.

### 4. Telephony Layer
- `lib/telephony/telephony_channel.dart`: MethodChannel tabanlı native köprü.
- `lib/telephony/call_handler.dart`: Gelen arama eventleri, reddetme komutu.
- `lib/telephony/sms_handler.dart`: Gelen/giden SMS eventleri ve gönderim.
- **Not:** `telephony` paketi AGP namespace uyumsuzluğu nedeniyle kaldırıldı. Yerine `MethodChannel` ile minimal Kotlin köprü (`MainActivity.kt`) kullanılıyor.

### 5. State Layer (Riverpod)
- `lib/providers/peer_provider.dart`
- `lib/providers/call_list_provider.dart`
- `lib/providers/sms_list_provider.dart`
- `lib/providers/connection_provider.dart`

### 6. UI Layer
- `lib/ui/screens/`: Home, Calls, Sms, Settings, Pairing, RoleSelection.
- `lib/ui/widgets/`: CallCard, SmsCard, EmptyState, QrDisplay, ConnectionBanner.

### 7. Services
- `lib/services/queue_service.dart`: Çevrimdışı kuyruk yönetimi.
- `lib/services/notification_service.dart`: Yerel bildirimler.
- `lib/services/connectivity_service.dart`: Ağ durumu izleme.
- `lib/services/permission_service.dart`: İzin kontrolü ve isteme (permission_handler).

## Mesaj Protokolü

```json
{
  "type": "call_incoming" | "call_rejected" | "sms_incoming" | "sms_outgoing" | "sms_status" | "ack" | "ping",
  "id": "uuid",
  "timestamp": 1712345678,
  "payload": "<base64 encrypted json>"
}
```

- Her mesaj şifrelenmeden önce JSON olarak hazırlanır.
- AES‑256‑GCM ile şifrelenir; nonce 12 byte, tag 16 byte.
- Alıcı: deşifre → type'a göre işlem.
- ACK: başarılı işlem sonrası gönderilir; NAK durumunda retry.

## Retry Policy
- Exponential back‑off: 2s, 4s, 8s, 16s, 32s.
- Max 5 deneme.
- Başarısız kuyruk öğeleri UI'da "Gönderilemedi" olarak işaretlenir.

## İzin Akışı
1. Uygulama açılır.
2. `PermissionService.areAllGranted()` ile izinler kontrol edilir.
3. Eksik izin varsa `PermissionService.requestAll()` ile istenir.
4. Kullanıcı izin verirse devam eder; reddederse kısıtlı mod bilgisi gösterilir.
5. Pil optimizasyonu kaldırma: `PermissionService.requestIgnoreBatteryOptimizations()`.

## Android Build Yapılandırması
- `compileSdk = 37`, `targetSdk = 37`
- AGP 9.1.0, Gradle 9.6.1
- Core library desugaring açık (`desugar_jdk_libs:2.1.5`)
- Paket adı: `com.thinksolve.mirrorline`

## Test Stratejisi
- Unit testler: crypto, queue retry, DAO'lar.
- Widget testler: empty state, buton tıklamaları.
- Integration testler: eşleştirme → rol → mesaj gönderme (tek cihazda mock socket).

## Notlar
- Android native modüller yerine mümkün olan her şey Flutter paketleri ile çözülecek.
- `telephony` paketi yerine `MethodChannel` ile minimal Kotlin köprü kullanılıyor.
- iOS build'ı sadece UI testleri için kullanılabilir; çekirdek özellikler Android‑only.