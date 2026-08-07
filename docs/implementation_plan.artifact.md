# MirrorLine - Faz 0 Implementation Plan

## Goal
Projeyi `test_app` isminden `mirrorline` haline getirmek ve MVP (Faz 0) özelliklerini tamamen Flutter içinde geliştirmek.

## User Review Required
- Proje dizin adı `test_app` → `mirrorline` şeklinde değişecek. Kullanıcının Finder/terminal ile fiziksel klasör adını elle değiştirmesi gerekiyor; sandbox buna izin vermiyor.
- Paket adı `com.example.test_app` → `com.thinksolve.mirrorline` olacak.
- Uygulama başlığı/adı `test_app` → `MirrorLine` olacak.

## Open Questions
- Yeni paket adı `com.thinksolve.mirrorline` uygun mu? (Think & Solve Different Solutions FZE bağlamında)
- `telephony` paketi yetersiz kalırsa minimal `MethodChannel` Kotlin köprüsü eklenebilir; şimdilik planlanan tüm işlevler Flutter paketleriyle çözülecek.

## Proposed Changes

### Project Rename & Configuration
#### [MODIFY] pubspec.yaml
- `name: test_app` → `name: mirrorline`
- Yeni bağımlılıkları ekle (Riverpod, sqflite, cryptography, flutter_secure_storage, multicast_dns, web_socket_channel, qr_flutter, mobile_scanner, flutter_local_notifications, telephony, android_intent_plus, connectivity_plus, logger, uuid, json_annotation, path_provider, shared_preferences).

#### [MODIFY] README.md
- `test_app` → `MirrorLine` ve uygulama açıklaması ekle.

#### [MODIFY] android/app/build.gradle.kts
- `namespace` ve `applicationId` → `com.thinksolve.mirrorline`.

#### [MODIFY] android/app/src/main/AndroidManifest.xml
- `android:label` → `MirrorLine`.

#### [MODIFY] android/app/src/main/kotlin/com/example/test_app/MainActivity.kt
- Paket yolu ve dosya konumu → `com.thinksolve.mirrorline`.

#### [MODIFY] linux/CMakeLists.txt
- `BINARY_NAME` ve `APPLICATION_ID` → `mirrorline`.

#### [MODIFY] windows/CMakeLists.txt
- `project(...)` ve `BINARY_NAME` → `mirrorline`.

#### [MODIFY] windows/runner/Runner.rc, windows/runner/main.cpp
- Uygulama başlık/metin alanları → `MirrorLine`.

#### [MODIFY] web/index.html, web/manifest.json
- `test_app` referansları → `MirrorLine`.

#### [MODIFY] macos/Runner/Configs/AppInfo.xcconfig
- `PRODUCT_NAME` → `MirrorLine`.

#### [MODIFY] ios/Runner/Info.plist
- `CFBundleName` değeri → `MirrorLine`.

### Code Structure (lib/)
#### [NEW] lib/main.dart
- Yeni Material 3 uygulama girişi, Riverpod ProviderScope ile sarmalanmış.

#### [NEW] lib/app.dart
- MirrorLineApp widget'ı (theme, home).

#### [NEW] lib/ui/screens/home_screen.dart
- Bottom navigation ile HomeScreen.

#### [NEW] lib/ui/screens/calls_screen.dart
- Gelen arama listesi ve reddetme butonu.

#### [NEW] lib/ui/screens/sms_screen.dart
- SMS listesi ve yanıtla modalı.

#### [NEW] lib/ui/screens/settings_screen.dart
- QR, peer info, pil optimizasyonu, reset.

#### [NEW] lib/ui/screens/pairing_screen.dart
- QR oluşturma ve tarama.

#### [NEW] lib/ui/screens/role_selection_screen.dart
- Main / Source rol seçimi.

#### [NEW] lib/ui/widgets/
- call_card.dart, sms_card.dart, empty_state.dart, qr_display.dart, connection_banner.dart

#### [NEW] lib/data/
- database.dart, models/peer.dart, models/call_event.dart, models/sms_message.dart, models/queue_item.dart

#### [NEW] lib/data/daos/
- peer_dao.dart, call_event_dao.dart, sms_message_dao.dart, queue_dao.dart

#### [NEW] lib/security/
- crypto_manager.dart, key_store.dart

#### [NEW] lib/network/
- peer_discovery.dart, socket_manager.dart, message_protocol.dart

#### [NEW] lib/telephony/
- call_handler.dart, sms_handler.dart

#### [NEW] lib/providers/
- peer_provider.dart, call_list_provider.dart, sms_list_provider.dart, connection_provider.dart

#### [NEW] lib/services/
- queue_service.dart, notification_service.dart, connectivity_service.dart, permission_service.dart

#### [DELETE] Mevcut lib/main.dart (todo uygulaması)
- Yerine yeni yapı geçecek.

### Tests
#### [NEW] test/widget_test.dart
- Proje adı güncellemesi ve basit smoke test.

## Verification Plan

### Automated Tests
- `flutter pub get` başarıyla tamamlanmalı.
- `flutter analyze lib/main.dart` hatasız çıkmalı.
- `flutter test` çalışmalı.

### Manual Verification
- Kullanıcı dizin adını `mirrorline` olarak değiştirdikten sonra Android Studio'da projeyi yeniden açmalı.
- `flutter run` ile uygulama başlatılmalı ve temel UI (Home, Calls, SMS, Settings) görülebilmeli.
- (Opsiyonel) İki Android cihazda kurulum ve QR eşleştirme testi.
