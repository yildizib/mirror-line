# MirrorLine Ürün Dokümanı

**Dil / Language:** [Türkçe](#turkce) | [English](#english)

<a id="turkce"></a>

## MirrorLine Ne İşe Yarar?

MirrorLine, iki Android telefonu aynı yerel ağ üzerinden doğrudan birbirine
bağlayarak telefon görüşmelerini, SMS mesajlarını ve seçili uygulama
bildirimlerini yansıtan, sunucusuz ve gizlilik odaklı bir uygulamadır.

SIM kartın bulunduğu telefon **Source**, kullanıcının günlük olarak kullandığı
telefon ise **Main** rolündedir. Source telefon hattı arka planda taşır; Main
telefon çağrıları, SMS'leri ve yansıtılan bildirimleri tek bir arayüzde gösterir.
Veriler üçüncü parti bir sunucudan geçmez.

## Ürünün Amacı

MirrorLine'ın amacı, kullanıcının SIM kartın bulunduğu telefonu yanında
taşımadan veya sürekli kontrol etmeden o telefondaki iletişim olaylarını kendi
ana telefonundan yönetebilmesini sağlamaktır.

Ürün bunu şu prensiplerle yapar:

- İki telefon arasında doğrudan iletişim kurar.
- Çağrı, SMS ve bildirimleri tek bir deneyimde birleştirir.
- Verileri bulut veya üçüncü parti relay sunucusuna göndermez.
- Bağlantı geçici olarak kesildiğinde olayları kaybetmemeye çalışır.
- Kullanıcıya hangi uygulama bildirimlerinin yansıtılacağını seçtirebilir.
- Çağrı ve SMS gibi hassas işlemleri cihazlar arasında şifreli taşır.

## Çözdüğü Problem

Kullanıcının iki telefonu olduğunda SIM kart bir cihazda, günlük kullanım ve
ekran diğer cihazda kalabilir. Bu durumda kullanıcı gelen çağrıları, SMS'leri
ve önemli uygulama bildirimlerini kaçırabilir. MirrorLine, SIM'li telefonu
Source ve kullanıcının ana telefonunu Main olarak eşleştirerek bu iki cihazı
tek bir iletişim ekranı gibi kullanmayı sağlar.

## Temel Feature'lar

- QR kod ile iki cihazı eşleştirme.
- Main ve Source cihaz rolleri.
- Gelen çağrıların Main cihazda gösterilmesi.
- Main cihazdan Source üzerindeki çağrıyı uzaktan reddetme.
- Gelen SMS'lerin Main cihaza aktarılması.
- Main cihazdan Source SIM'i üzerinden SMS gönderme.
- Seçili uygulamaların bildirimlerini Main cihaza yansıtma.
- Çağrı, SMS ve bildirimleri ayrı listelerde ve Home akışında görüntüleme.
- Aynı kişi, numara veya uygulamaya ait olayları gruplama.
- Sayfalı listeler, detay ekranları ve çoklu seçimle silme.
- Bağlantı yokken olayları offline queue ile bekletme.
- UDP beacon, bilinen ağ önbelleği ve subnet taramasıyla cihaz keşfi.
- Wi-Fi/IP değişikliklerinde otomatik yeniden bağlanma.
- Bağlantı durumu, discovery kayıtları ve gönderim hattı için teşhis ekranı.
- Pil optimizasyonu, otomatik başlatma ve sistem izinleri için ayarlar.
- Türkçe ve İngilizce kullanıcı arayüzü.

## Hedef Kullanıcı

MirrorLine, iki Android telefon kullanan ve SIM kartı bir telefonda dururken
iletişimlerini diğer telefondan yönetmek isteyen kullanıcılar içindir. Ürün
özellikle yerel ağ dışına veri çıkarmak istemeyen, teknik farkındalığı yüksek
kullanıcıları hedefler.

## Cihaz Rolleri

### Main

- Source cihazdan gelen çağrı, SMS ve bildirimleri gösterir.
- Gelen çağrıyı uzaktan reddedebilir.
- Source telefon üzerinden SMS gönderebilir.
- Bağlantı, keşif ve senkronizasyon durumunu gösterir.

### Source

- SIM üzerinden gelen çağrı ve SMS olaylarını yakalar.
- Çağrı, SMS ve seçili uygulama bildirimlerini Main cihaza gönderir.
- Main cihazdan gelen SMS gönderme ve çağrı reddetme komutlarını uygular.
- Arka planda foreground service ile çalışır.

## Kullanıcı Akışı

### İlk Kurulum

1. Uygulama iki Android telefona kurulur.
2. Her cihazda cihaz rolü seçilir.
3. Cihazlardan biri pairing ekranında QR kod gösterir.
4. Diğer cihaz QR kodu tarar.
5. Kullanıcı karşı cihazın eşleşme isteğini onaylar.
6. İki cihaz birbirini doğrular ve peer bilgilerini kalıcı olarak kaydeder.
7. İsteğe bağlı 6 haneli doğrulama kodu karşılaştırılır.

Pairing işlemi tek taraflı kayıtla bitmez. Request, accept/reject ve ack
mesajlarıyla iki cihazın da eşleşmeyi tamamladığı doğrulanır.

### Günlük Kullanım

Bağlantı kurulduğunda Main cihazda beş ana bölüm bulunur:

- Home: Çağrı, SMS ve bildirimleri kronolojik birleşik akışta gösterir.
- Calls: Kişi/numara bazlı çağrı grupları ve çağrı detayları.
- SMS: Konuşma listesi ve mesajlaşma ekranı.
- Notifications: Uygulama bazlı yansıtılmış bildirimler ve detayları.
- Settings: Cihaz, pairing, bağlantı, izin ve teşhis işlemleri.

## Ürün Özellikleri

### Çağrı Yansıtma

- Gelen çağrı Main cihazda yerel bildirim olarak gösterilir.
- Çağrı durumu ringing, answered, missed ve ended olarak takip edilir.
- Çağrı numarası ve kişi adı sonradan çözülebilir ve mevcut kayda işlenir.
- Main cihazdan çağrı reddetme komutu Source cihaza gönderilir.
- Bağlantı koparsa çağrı olayları offline queue içinde bekletilebilir.
- Main tarafında uzun süre ringing kalan çağrılar için 90 saniyelik koruma
  mekanizması bulunur.

### SMS Yansıtma

- Source cihazdaki gelen SMS Main cihaza gönderilir ve yerel veritabanına
  kaydedilir.
- Main cihazdan yazılan SMS Source cihazdaki SIM üzerinden gönderilir.
- Giden SMS durumu pending, sent veya failed olarak güncellenir.
- SMS konuşmaları adres bazında gruplanır.
- SMS listeleri ve konuşmalar sayfalı yüklenir.
- Bağlantı yokken gelen veya giden olaylar kuyruklanır.
- Yanıt alınamayan pending SMS'ler iki dakika sonra failed durumuna geçirilir.
- Android'in parçalı SMS yayınları Source tarafında kısa süre birleştirilir.

### Bildirim Yansıtma

- Source cihazdaki seçili uygulama bildirimleri Main cihaza yansıtılır.
- Kullanıcı hangi uygulamaların izleneceğini Watched Apps ekranından seçer.
- Aynı sistem bildirimlerinin tekrarları filtrelenir.
- Bildirim özetleri ve default dialer/SMS uygulamalarının yinelenen bildirimleri
  atlanır.
- Main cihazda bildirimler uygulama bazında gruplanır.
- Yansıtılmış bildirim yerel Android bildirimi olarak gösterilir.
- Bildirim kayıtları sistem bildiriminden bağımsız olarak veritabanında tutulur.

### Bağlantı ve Yeniden Bağlanma

- Cihazlar aynı yerel ağda doğrudan TCP bağlantısı kurar.
- Source TCP sunucusu olarak dinler; Main bağlantıyı başlatır.
- UDP beacon cihazların güncel IP adreslerini duyurur.
- Bilinen ağ/IP kayıtları hızlı yeniden bağlantı için önbelleğe alınır.
- Beacon bulunamadığında yerel subnet'ler TCP probe ile taranır.
- Wi-Fi roam ve IP değişikliklerinde yeniden keşif yapılır.
- Bağlantı koptuğunda olaylar offline queue içine alınır.
- Kuyruk öğeleri bağlantı geri geldiğinde en fazla beş denemeyle gönderilir.
- Bağlantı heartbeat ve watchdog mekanizmalarıyla izlenir.
- Ekran kapalıyken bağlantıyı korumak için heartbeat aralığı seyreltilir.
- Settings içinden ilerleme kayıtları görülen manuel Force Connect işlemi
  başlatılabilir.

### Pairing ve Cihaz Yönetimi

- QR kod cihaz kimliği, IP, port, AES anahtarı, rol ve public key bilgilerini
  taşır.
- QR tarama için kamera tabanlı mobil scanner kullanılır.
- Birden fazla eşli cihaz kaydı desteklenir.
- Eşli cihaz bilgileri Settings ekranında görülebilir.
- Cihaz sıfırlama peer, çağrı, SMS, bildirim ve queue kayıtlarını temizler.
- Yeni pairing işlemi için yeni cihaz kimliği ve anahtar üretilebilir.

### Teşhis ve Ayarlar

- Bağlantı durumu ve son discovery denemeleri görüntülenir.
- Gerçek gönderim hattını kullanan çağrı, SMS ve bildirim teşhis testleri
  çalıştırılabilir.
- Bildirim listener izin durumu kontrol edilir.
- Android runtime izinleri yönetilir.
- Pil optimizasyonu, OEM otomatik başlatma ve pil tasarrufu ekranlarına
  kısayollar sağlanır.
- Uygulama Türkçe ve İngilizce yerelleştirmeyi destekler.

## Güvenlik ve Gizlilik

- Mesaj payload'ları AES-256-GCM ile şifrelenir.
- Her mesaj için 12 byte nonce ve 16 byte authentication tag kullanılır.
- Şifreleme anahtarı Android Keystore tabanlı secure storage'da saklanır.
- Cihaz kimlik doğrulaması Ed25519 challenge-response ile yapılır.
- Pairing sırasında karşı cihazın public key'i kaydedilir.
- Bağlantı kurulmadan önce auth challenge ve auth acknowledgement tamamlanır.
- Aynı canlı bağlantı içinde eski mesajların tekrar oynatılmasına karşı timestamp
  kontrolü uygulanır.
- Sunucu, relay veya bulut veri deposu kullanılmaz.
- Yerel kayıtlar cihazın SQLite veritabanında tutulur.
- Kullanıcı seçmediği uygulamaların bildirimlerini yansıtmaz.

## Teknik Ürün Sınırları

### Doğrulama Kapsamı

CI; format kontrolü, statik analiz, Flutter testleri ve debug APK derlemesini
otomatik olarak çalıştırır. İki cihazlı Android testleri pairing, reconnect,
ağ değişikliği ve arka plan yaşam döngüsü senaryoları için manuel cihaz
doğrulamasıdır; CI sonucu olarak raporlanmaz.

- Uygulama Android odaklıdır; telephony, SMS ve notification listener özellikleri
  Android native servislerine bağlıdır.
- Cihazların doğrudan haberleşebilmesi için erişilebilir bir ortak ağ veya VPN
  gerekir.
- Farklı ağlar arasında merkezi relay hizmeti bulunmaz.
- Canlı çağrı sesi taşınmaz; yalnızca çağrı olayları ve kontrol komutları
  yansıtılır.
- Varsayılan SMS uygulaması olma, MMS ve RCS yönetimi ürün kapsamına dahil
  değildir.
- Bildirim yansıtma, Android Notification Listener izni ve cihaz üreticisinin
  arka plan kısıtlamalarına bağlıdır.
- OEM pil tasarrufu ve otomatik başlatma politikaları bağlantı sürekliliğini
  etkileyebilir.

## Veri Modeli

Uygulama SQLite üzerinde aşağıdaki kayıtları tutar:

- `peer`: Eşli cihaz kimliği, rol, adres, port, AES anahtarı ve public key.
- `call_event`: Çağrı yönü, numara, kişi adı, zaman ve çağrı durumu.
- `sms_message`: Konuşma, adres, gövde, yön ve gönderim durumu.
- `notification_event`: Uygulama, başlık, metin, native bildirim kimliği ve zaman.
- `offline_queue`: Bağlantı yokken bekleyen şifreli mesaj payload'ları, deneme
  sayıları ve tekrarları önleyen `dedupe_key` değeri.
- `known_network`: Eş cihaz için daha önce başarılı olmuş ağ/IP bilgileri.

Veritabanı şema sürümü 7'dir. `peer` tablosunda birden fazla eş cihaz kaydı
tutulabilir; ancak aktif bağlantı runtime'ı aynı anda tek bir peer context'i
kullanır.

Veritabanı şema sürümü 6'dır ve eski sürümler için migration desteği bulunur.

## Uygulama Mimarisi

Ürün kodu aşağıdaki bağımlılık yönünü izler:

```text
Base services (core)
        -> Facades (features/*_facade.dart)
        -> UI services (providers/controllers)
        -> Screens and widgets
```

Core katmanı ağ, güvenlik, telephony, veritabanı ve sistem servislerini sağlar.
Facade'lar bu servisleri ürün davranışına dönüştürür. UI katmanı doğrudan socket,
DAO veya native listener erişimi yapmaz.

## Mevcut Durum

Mevcut uygulama; pairing, rol seçimi, çağrı yansıtma, SMS mirroring, seçili
bildirim yansıtma, offline queue, otomatik yeniden bağlanma, bağlantı teşhisi,
Android foreground service ve temel cihaz yönetimi özelliklerini içerir.

Test kapsamı; şifreleme, protocol, socket, beacon, subnet discovery, pairing,
DAO, migration, facade, pagination, provider ve widget testlerini içerir.

Bu belge ürünün mevcut davranışını tanımlar. Yeni özellik kararları ve sürüm
planları bu belgeye eklenmeden önce mevcut implementasyonla doğrulanmalıdır.

---

<a id="english"></a>

# MirrorLine Product Document

## What Does MirrorLine Do?

MirrorLine mirrors phone calls, SMS messages, and selected application
notifications between two Android phones over a direct local-network
connection. It is serverless and privacy-focused.

The phone containing the SIM card is the **Source** device. The phone used by
the user is the **Main** device. Source keeps the mobile line in the
background; Main displays calls, SMS messages, and mirrored notifications in a
single interface. Data does not pass through a third-party server.

## Product Purpose

MirrorLine allows users to manage communication events from their main phone
without constantly carrying or checking the phone that contains the SIM card.

The product follows these principles:

- Connects the two phones directly.
- Combines calls, SMS, and notifications into one experience.
- Does not send data to a cloud or third-party relay server.
- Attempts to prevent event loss during temporary disconnections.
- Lets users choose which application notifications are mirrored.
- Transports sensitive call and SMS data between devices in encrypted form.

## Problem Solved

When a user has two phones, the SIM card and the phone used every day may be
different devices. The user can then miss incoming calls, SMS messages, and
important application notifications. MirrorLine pairs the SIM-holding Source
phone with the user's Main phone and makes them work as one communication
interface.

## Core Features

- QR-code device pairing.
- Main and Source device roles.
- Incoming call display on Main.
- Remote call rejection from Main through Source.
- Incoming SMS mirroring to Main.
- SMS sending through the Source SIM from Main.
- Mirroring notifications from selected applications.
- Separate Calls, SMS, and Notifications sections plus a combined Home feed.
- Grouping events by person, phone number, or application.
- Paginated lists, detail screens, and multi-select deletion.
- Offline queue for events while the connection is unavailable.
- Device discovery through UDP beacon, known-network cache, and subnet scan.
- Automatic reconnection after Wi-Fi or IP changes.
- Connection diagnostics and delivery-path test screens.
- Settings for battery optimization, auto-start, and system permissions.
- Turkish and English user interface.

## Target Users

MirrorLine is intended for people who use two Android phones and want to manage
communications from one phone while the SIM card remains in the other. It is
especially suitable for technically aware users who do not want their data to
leave the local network.

## Device Roles

### Main

- Displays calls, SMS messages, and notifications received from Source.
- Can reject incoming calls remotely.
- Can send SMS messages through the Source phone.
- Displays connection, discovery, and synchronization status.

### Source

- Captures incoming call and SMS events from the SIM.
- Sends calls, SMS messages, and selected application notifications to Main.
- Executes SMS sending and call rejection commands from Main.
- Runs in the background through an Android foreground service.

## User Flow

### Initial Setup

1. Install the application on both Android phones.
2. Select a device role on each phone.
3. Show a QR code on one device from the pairing screen.
4. Scan the QR code with the other device.
5. Approve the pairing request on the receiving device.
6. Both devices authenticate each other and persist their peer records.
7. Optionally compare the six-digit verification code.

Pairing does not finish with a one-sided record. Request, accept/reject, and
acknowledgement messages verify that both devices completed the pairing.

### Daily Use

When connected, Main provides five primary sections:

- Home: A chronological feed combining calls, SMS messages, and notifications.
- Calls: Call groups by contact/number and call details.
- SMS: Conversation list and chat screen.
- Notifications: Application-based mirrored notification groups and details.
- Settings: Device, pairing, connection, permission, and diagnostics actions.

## Product Features

### Call Mirroring

- Incoming calls appear as local notifications on Main.
- Call states are tracked as ringing, answered, missed, and ended.
- The number and contact name can be resolved later and applied to the existing
  record.
- Main sends call-rejection commands to Source.
- Call events can wait in the offline queue when the connection is unavailable.
- A 90-second Main-side watchdog prevents a ringing call from remaining stuck.

### SMS Mirroring

- Incoming SMS messages from Source are sent to Main and stored locally.
- SMS messages composed on Main are sent through the Source SIM.
- Outgoing SMS status is tracked as pending, sent, or failed.
- SMS conversations are grouped by address.
- SMS lists and conversations load through pagination.
- Events are queued when the connection is unavailable.
- Pending SMS messages without a response are marked failed after two minutes.
- Multipart Android SMS broadcasts are briefly combined on Source.

### Notification Mirroring

- Selected application notifications on Source are mirrored to Main.
- Users choose watched applications from the Watched Apps screen.
- Duplicate reposts of the same system notification are filtered.
- Notification summaries and duplicate default dialer/SMS notifications are
  skipped.
- Main groups mirrored notifications by application.
- Mirrored notifications are shown as local Android notifications.
- Notification records remain in the database independently of the source
  notification lifecycle.

### Connection and Reconnection

- Devices establish a direct TCP connection on the local network.
- Source listens as the TCP server; Main initiates the connection.
- UDP beacon announces current device IP addresses.
- Known network/IP records are cached for fast reconnection.
- Local subnets are probed through TCP when beacon discovery is insufficient.
- Network discovery is repeated after Wi-Fi roaming or IP changes.
- Events are placed in the offline queue when the connection drops.
- Queued items are sent with up to five attempts after reconnection.
- Heartbeat and watchdog mechanisms monitor the connection.
- Heartbeat frequency is reduced while the screen is off.
- Settings provides a manual Force Connect action with visible progress logs.

### Pairing and Device Management

- QR data contains device identity, IP, port, AES key, role, and public key.
- Camera-based scanning is used for QR pairing.
- Multiple paired-device records can be stored.
- The current active connection runtime uses one selected peer context at a
  time; storing multiple peers does not imply simultaneous multi-peer
  connections.
- Paired-device information is visible in Settings.
- Device reset clears peer, call, SMS, notification, and queue records.
- A new device identity and key can be generated for a new pairing.

### Diagnostics and Settings

- Connection status and recent discovery attempts are visible.
- Diagnostics can run call, SMS, and notification tests through the real delivery
  path.
- Notification listener permission status can be checked.
- Android runtime permissions are managed from the application.
- Shortcuts are provided for battery optimization, OEM auto-start, and battery
  saver settings.
- The application supports Turkish and English localization.

## Security and Privacy

- Message payloads are encrypted with AES-256-GCM.
- Each message uses a 12-byte nonce and a 16-byte authentication tag.
- Encryption keys are stored in Android Keystore-backed secure storage.
- Device authentication uses an Ed25519 challenge-response handshake.
- The other device's public key is stored during pairing.
- Authentication challenge and acknowledgement complete before a connection is
  considered ready.
- Timestamp checks protect against replaying old messages within a live
  connection.
- No server, relay, or cloud data store is used.
- Local records are stored in the device's SQLite database.
- Notifications from applications not selected by the user are not mirrored.

## Product Boundaries

### Verification Scope

CI automatically runs formatting, static analysis, Flutter tests, and a debug
APK build. Two-device Android checks for pairing, reconnect, network changes,
and background lifecycle are manual device verification and must not be
reported as CI results.

- The application is Android-focused; telephony, SMS, and notification listener
  features depend on Android native services.
- The devices need an accessible shared network or VPN for direct communication.
- There is no central relay service between different networks.
- Live call audio is not transported; only call events and control commands are
  mirrored.
- Becoming the default SMS application and managing MMS/RCS are out of scope.
- Notification mirroring depends on Android Notification Listener permission and
  background restrictions imposed by the device manufacturer.
- OEM battery-saving and auto-start policies can affect connection continuity.

## Data Model

The application stores the following records in SQLite:

- `peer`: Paired device identity, role, address, port, AES key, and public key.
- `call_event`: Call direction, number, contact name, time, and call status.
- `sms_message`: Conversation, address, body, direction, and delivery status.
- `notification_event`: Application, title, text, native notification ID, and
  time.
- `offline_queue`: Encrypted message payloads waiting for a connection, retry
  counts, and the `dedupe_key` used to prevent duplicate delivery.
- `known_network`: Previously successful network/IP information for a peer.

The database schema is version 7 and includes migrations from older versions,
including the `offline_queue.dedupe_key` column migration.

## Application Architecture

The product code follows this dependency direction:

```text
Base services (core)
        -> Facades (features/*_facade.dart)
        -> UI services (providers/controllers)
        -> Screens and widgets
```

The core layer provides networking, security, telephony, database, and system
services. Facades turn those services into product behavior. The UI layer does
not access sockets, DAOs, or native listeners directly.

## Verified Security Behavior

- Sensitive SQLite fields and offline queue payloads are encrypted before
  persistence; the secure storage key is authoritative for local encryption.
- Network payloads use AES-GCM encryption. Normal messages authenticate their
  protocol version, type, message ID, and timestamp as associated data.
- Paired connections use mutual Ed25519 authentication with device IDs and
  expected public keys, then negotiate a fresh session before application data
  is accepted.
- Normal messages reject cross-session delivery, replayed IDs, reordered
  sequences, and timestamps outside the freshness window.
- QR pairing binds the request, accept, verification value, and final
  acknowledgement to one transaction. Peer ID, role, and public-key changes
  are rejected, and persistence waits for the final acknowledgement.
- Transport parsing enforces frame, JSON, and encrypted payload limits and
  closes connections that repeatedly send malformed data.

### Security Non-Goals

- The application does not protect a device that is already compromised or
  running malicious software with access to its process and secure storage.
- Local-network availability, TCP metadata, and claimed peer IP addresses are
  not treated as proof of identity.
- The product does not provide a cloud relay, remote access outside the local
  network, or protection against denial of service by the operating system or
  network infrastructure.

## Current Status

The current application includes pairing, role selection, call mirroring, SMS
mirroring, selected notification mirroring, offline queue, automatic
reconnection, connection diagnostics, Android foreground service, and basic
device management.

Tests cover raw wire confidentiality, local storage encryption and migration,
authenticated sockets, replay protection, pairing identity binding, transport
limits, beacon, subnet discovery, DAOs, facades, pagination, providers, and
widgets.

This document describes the current product behavior. New feature decisions and
release plans should be verified against the implementation before being added
here.
