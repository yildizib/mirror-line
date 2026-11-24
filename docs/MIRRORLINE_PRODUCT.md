# MirrorLine Ürün Dokümanı

**Dil / Language:** [Türkçe](#turkce) | [English](#english)

<a id="turkce"></a>

## Onaylanmış hedef ürün

MirrorLine, iki Android telefon arasındaki çağrı olaylarını, SMS'leri ve
seçili uygulama bildirimlerini **sunucu aracılı uçtan uca şifreli** olarak
eşitler. SIM kartın bulunduğu telefon **Kaynak (Source)**, kullanıcının günlük
kullandığı telefon **Ana (Main)** rolündedir. Ana ve Kaynak farklı ağlarda
olabilir; hedef üründe LAN, VPN, IP adresi, UDP beacon, subnet taraması veya
doğrudan cihaz soketi gerekmez.

Sunucu hesap, cihaz, eşleştirme, anahtar meta verisi, şifreli posta kutusu ve
güvenlik denetimini yönetir. Sunucu çağrı/SMS/bildirim içeriğini veya uçtan uca
özel anahtarları görmez ya da saklamaz.

## Amaç ve roller

MirrorLine, kullanıcının SIM kartlı telefonu yanında değilken iletişim
olaylarını Ana Telefonda güvenle takip etmesini ve uygun uzaktan eylemleri
yapmasını sağlar.

- **Ana Telefon:** Birleştirilmiş akışı gösterir, Kaynakları yönetir, geçerli
  çağrı reddetme ve SMS gönderme eylemlerini başlatır.
- **Kaynak Telefon:** SIM çağrı/SMS olaylarını ve seçili uygulama
  bildirimlerini yakalar; geçerli komutları uygular.
- Her hesapta en fazla **bir Ana**, en fazla **beş Kaynak** vardır.
- Sunucu `userId` ve `deviceId` değerlerini UUIDv4 olarak üretir; cihazın
  kanonik kimliği `(userId, deviceId)` çiftidir.

## Eşleştirme ve cihaz yönetimi

Eşleştirme sunucunun yönettiği bir işlemdir. Ana Telefon beş dakika geçerli,
yalnızca bir kez kullanılabilen bir QR/kısa kod açar; Kaynak kodu sunucu
üzerinden kullanır. İki cihaz kendi Ed25519 anahtarlarıyla aynı işlem kaydını
imzalar ve her iki ekranda görünen karşılaştırma değerini onaylar. Kanıtlar ve
onaylar tamamlanmadan eşleştirme kaydı oluşmaz.

Kodlar işlem sonrası, süre dolduğunda veya iptal edildiğinde yeniden kullanılamaz.
QR/kısa kod özel anahtar, ortak AES anahtarı, IP, port ya da doğrudan bağlanma
gizlisi taşımaz. Ana değişimi eski Ana oturumunu ve mevcut Kaynak eşleşmelerini
geçersiz kılar; cihaz güvenliği ekranları bu sonucu açıkça gösterir.

## Şifreleme, relay ve replay koruması

Her cihaz Ed25519 imzalama ve X25519 anahtar anlaşması özel anahtarlarını
yalnızca cihazda saklar. Sunucuya yalnızca açık anahtarlar, sürümleri ve gizli
olmayan yaşam döngüsü meta verisi gider.

- X25519 + HKDF-SHA256 her zarf için anahtar üretir.
- AES-256-GCM içerik şifrelemesini sağlar.
- RFC 8785 canonical JSON, imzalanan yapılandırılmış alanları sabitler.
- Ed25519 imzası protokol sürümünü, zarfı, gönderici/alıcı kullanıcı ve cihaz
  kimliklerini, anahtar sürümlerini, türü, zamanları, nonce'u ve şifreli metin
  bağını kapsar.
- Alıcı, imza/kimlik/sürüm/zaman/sequence doğrulamasından ve GCM doğrulamasından
  önce içerik işlemez.
- Cihazlar kabul edilmiş replay kayıtlarını sekiz gün tutar; aynı zarf tekrar
  işlenmez.

Sunucu yalnızca şifreli zarfı en fazla yedi gün saklar. Push bildirimi içerik
taşımaz; sadece senkronizasyon gerektiğini uyandıran opak bir sinyaldir.

## Anahtar yaşam döngüsü

Anahtar döndürme 90 günde bir planlanır; kullanıcı manuel veya acil döndürme
başlatabilir. Yeni açık anahtar sürümü eski ve yeni Ed25519 anahtarlarıyla
bağlılık kanıtı sunar. Eşlerden ACK alınır; tüm ACK'ler geldiğinde ya da en geç
24 saatte yeni sürüm etkinleşir. Eski/yeni doğrulama 14 gün örtüşür. Özel
anahtarların sunucuya yüklenmesi veya bulut yedeği yoktur.

## Geçmiş, oturum ve güvenlik denetimi

Yerel geçmiş için 7, 30, 90 veya 180 gün seçilir; varsayılan 30 gündür.
Sunucu posta kutusu süresi yedi gün, cihaz replay kaydı süresi sekiz gündür.

Başarılı giriş cihaz-bağlı bir oturum yaratır. Oturum çıkış, süre dolumu,
güvenlik geçersizleştirmesi veya cihaz iptaliyle biter. Son giriş; en son
başarılı oturum oluşturmayı gösterir, başarısız giriş bunu değiştirmez.

Güvenlik denetimi; giriş, oturum, cihaz, eşleştirme, anahtar yaşam döngüsü ve
relay güvenlik kararları için eklemeli kayıttır. Parola, token, özel anahtar,
eşleştirme kodu, düz metin, şifreli metin, mesaj içeriği ve ham IP kaydı
tutulmaz. Denetim olayları bir yıl saklanır, sonra silinir veya geri döndürülemez
biçimde anonimleştirilir.

## Kullanıcı deneyimi

Ana Telefon; birleşik gelen kutusu, çağrı ayrıntıları, SMS konuşmaları,
bildirim ayrıntıları ve Kaynak yönetimi sunar. Kaynak Telefon; koruma/izin
durumunu, paylaşım seçimlerini, duraklatmayı ve Ana bağlantısı bilgisini sunar.
Uygulama Türkçe ve İngilizce çalışır. Canlı çağrı sesi aktarılmaz; yalnızca çağrı
olayları ve geçerli kontrol komutları eşitlenir. MMS/RCS ve varsayılan SMS
uygulaması olma kapsam dışıdır.

## Teknik ve uygulama durumu

Mobil kod `base -> facade -> ui_service -> ui` sınırını korur; UI ve UI service
katmanları taban servislerine doğrudan erişmez. Hedef ürün API'leri `/v1`
altında kimlik/oturum, cihaz, eşleştirme, anahtar yaşam döngüsü, posta kutusu,
güvenlik denetimi ve iç push gruplarına ayrılır; istemciler metin yerine sabit
hata kodlarını kullanır.

**Uygulama durumu (Kasım 2026):** Bu belge onaylanmış hedef ürün sözleşmesini
tanımlar. Mevcut depo henüz bu sunucu aracılı hesap, cihaz kaydı, eşleştirme,
relay, anahtar döndürme, audit veya 97 ekranın tamamını uygulamamaktadır. Mevcut
mobil yol hâlâ geçişteki eski LAN/VPN mekanizmalarını içerebilir; bu, hedef
ürünün ağ gereksinimi olduğu anlamına gelmez. Eski yol ancak eşdeğerlik ve
migrasyon kanıtından sonra kaldırılacaktır.

---

<a id="english"></a>

# MirrorLine Product Document

## Approved target product

MirrorLine synchronizes phone-call events, SMS messages, and selected app
notifications between two Android phones through a **server-mediated,
end-to-end encrypted** service. The SIM-holding phone is the **Source**; the
day-to-day phone is the **Main**. Main and Source may use independent networks:
the target product requires no LAN, VPN, IP address, UDP beacon, subnet scan,
or direct device socket.

The service coordinates accounts, devices, pairing, public-key metadata,
encrypted mailboxes, and security audit. It neither sees nor retains call/SMS/
notification content or end-to-end private keys.

## Purpose and roles

MirrorLine lets a user safely follow communication events, and perform valid
remote actions, from Main while the SIM phone is elsewhere.

- **Main:** Shows the combined feed, manages Sources, and initiates valid
  call-rejection and SMS-send actions.
- **Source:** Captures SIM call/SMS events and selected app notifications, and
  performs valid commands.
- An account has at most **one Main** and **five Sources**.
- The service generates UUIDv4 `userId` and `deviceId`; `(userId, deviceId)`
  is the canonical device identity.

## Pairing and device management

Pairing is a server-managed transaction. Main opens a one-use QR/short code
valid for five minutes; Source redeems it through the service. Both devices
sign the same transaction with their Ed25519 keys and confirm a human-comparable
value shown on both screens. No pairing membership exists until both proofs and
confirmations pass.

Codes cannot be reused after redemption, expiry, cancellation, or failure. A
QR/short code carries no private key, shared AES key, IP, port, or direct
connection secret. Replacing Main invalidates the old Main session and current
Source pairings; device-security screens make that consequence explicit.

## Encryption, relay, and replay protection

Each device keeps its Ed25519 signing and X25519 key-agreement private keys
locally. The service receives only public keys, versions, and non-secret
lifecycle metadata.

- X25519 plus HKDF-SHA256 derives an envelope key.
- AES-256-GCM encrypts content.
- RFC 8785 canonical JSON fixes the signed structured representation.
- An Ed25519 signature covers protocol/version, envelope, sender and recipient
  users/devices, key versions, type, timestamps, nonce, and ciphertext binding.
- A recipient verifies signature, identity, version, time, sequence, and GCM
  authentication before dispatching content.
- Devices retain accepted replay records for eight days and never dispatch a
  duplicate envelope twice.

The service retains opaque encrypted mailbox envelopes for at most seven days.
Push has no product content; it is only an opaque wake signal that sync is
required.

## Key lifecycle

Key rotation is scheduled every 90 days and also supports manual and emergency
paths. A new public-key version provides a continuity proof signed by both old
and new Ed25519 keys. Peers acknowledge it; the new version activates at all
ACKs or after at most 24 hours. Old/new verification overlaps for 14 days.
Private keys are never uploaded or cloud-backed up.

## History, sessions, and security audit

Local history choices are 7, 30, 90, or 180 days, with 30 days by default.
Server mailbox retention is seven days and device replay-record retention is
eight days.

A successful login creates a device-bound session. A session ends through
sign-out, expiry, security invalidation, or device revocation. Last login is
the most recent successful session creation; a failed attempt never replaces it.

Security audit is append-only for authentication, sessions, devices, pairing,
key lifecycle, and relay-security decisions. It never stores passwords, tokens,
private keys, pairing codes, plaintext, ciphertext, message content, or raw IP
addresses. Audit events are retained for one year, then deleted or irreversibly
anonymized.

## User experience

Main provides a combined inbox, call details, SMS conversations, notification
details, and Source management. Source provides protection/permission status,
sharing choices, pause controls, and Main-connection information. The app is
available in Turkish and English. Live call audio is not transported; only call
events and valid control commands are synchronized. MMS/RCS and becoming the
default SMS app are out of scope.

## Technical and implementation status

Mobile code preserves the `base -> facade -> ui_service -> ui` boundary; UI
and UI services do not access base services directly. Target APIs live under
`/v1` in authentication/session, device, pairing, key lifecycle, mailbox,
security-audit, and internal-push groups; clients use stable error codes rather
than response text.

**Implementation status (November 2026):** This document describes the
approved target product contract. The current repository does not yet implement
the server-mediated accounts, device registration, pairing, relay, key rotation,
audit, or all 97 screens. The current mobile path may still contain transitional
legacy LAN/VPN mechanisms; that is not a target-product network requirement.
The legacy path will be removed only after parity and migration evidence.
