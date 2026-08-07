# MirrorLine - Ürün Gereksinim Dokümanı

## 1. Ürün Vizyonu
MirrorLine, iki Android telefonu arasında sunucusuz, uçtan uca şifreli (AES‑256‑GCM) arama ve SMS senkronizasyonu sağlayan bir mobil uygulamadır. Cihazlar aynı yerel ağda (Wi‑Fi veya hotspot) doğrudan birbirine bağlanır; veri hiçbir üçüncü parti sunucudan geçmez.

## 2. Problem Tanımı
Birden fazla aktif hattı olan kullanıcılar, ikinci telefonu sürekli takip etmek zorunda kalır ya da önemli aramaları/SMS'leri kaçırır. Mevcut çözümler ya OEM ekosisteme bağımlıdır, ya kapalı kaynaktır, ya da bulut üzerinden veri taşır.

## 3. Hedef Kullanıcı
- Birincil: İki Android telefonu aktif kullanan, veri gizliliğine önem veren, teknik farkındalığı yüksek bireysel kullanıcı.
- İkincil: Açık kaynak / doğrulanabilir gizlilik arayan genel Android kullanıcı kitlesi.

## 4. MVP Kapsamı (v0.1)

### 4.1 Cihaz Rolleri
- **Asıl Telefon (Main):** Bildirimleri görür, aramaları reddedebilir, SMS'leri okur/yanıtlar.
- **Diğer Telefon (Source):** SIM'in bulunduğu, arka planda arama/SMS event'lerini yakalayan cihaz.

### 4.2 Özellik Listesi
- QR kod ile cihaz eşleştirme (256‑bit simetrik anahtar + IP).
- Rol seçimi (Main / Source).
- Gelen arama bildirimi + uzaktan reddetme.
- Çift yönlü SMS mirroring (gelen + giden).
- Çevrimdışı / farklı ağ senaryosunda yerel kuyruk.
- Ayarlar: pil optimizasyonunu kaldırma, cihaz sıfırlama & yeni QR.

## 5. Kapsam Dışı (v0.1)
- Canlı arama sesinin taşınması.
- Farklı ağlardaki cihazlar arası senkronizasyon (relay/VPN yok).
- iOS desteği.
- Varsayılan SMS uygulaması olma / tam MMS/RCS yönetimi.
- Çoklu ikincil cihaz desteği (Faz 1).

## 6. Kullanıcı Akışları

### 6.1 Eşleştirme
1. Uygulama her iki cihaza kurulur.
2. Bir cihaz "Eşleştir" seçer; 256‑bit anahtar + IP bilgisini QR kod olarak gösterir.
3. Diğer cihaz QR kodu tarar; anahtar güvenli depolamaya kaydedilir.
4. Her iki cihazda rol seçimi yapılır.

### 6.2 Gelen Arama
1. Source cihazda arama gelir → PhoneStateReceiver yakalar.
2. Arayan numara AES‑256‑GCM ile şifrelenip Main cihaza gönderilir.
3. Main cihazda heads‑up bildirim gösterilir.
4. Kullanıcı "Reddet"e basarsa komut şifrelenip Source cihaza iletilir ve arama sonlandırılır.

### 6.3 SMS (Çift Yönlü)
- Gelen SMS: Source → şifrele → Main → UI listesi + bildirim.
- Giden SMS: Main → şifrele → Source → SmsManager.sendTextMessage() → durum geri bildirimi.

### 6.4 Çevrimdışı Senaryo
- Cihazlar aynı ağda değilse "Senkronizasyon duraklatıldı" mesajı gösterilir.
- Event'ler yerel kuyruğa yazılır.
- Tekrar aynı ağa dönüldüğünde kuyruk senkronize edilir.

## 7. Sistem Mimarisi

### 7.1 Genel Yapı
- **Source:** PhoneStateReceiver, SmsReceiver → şifrele → TCP socket üzerinden Main cihaza gönder.
- **Main:** Socket dinleyici → deşifre → bildirim/UI güncelleme → komutları geri gönder.

### 7.2 Ağ Katmanı
- mDNS/NSD keşfi.
- TCP socket üzerinden şifreli paket iletimi.
- BLE ve relay katmanları Faz 2'de değerlendirilecek.

### 7.3 Güvenlik Modeli
- Anahtar yalnızca fiziksel QR ile değiş tokuş edilir.
- Anahtar Android Keystore / iOS Keychain benzeri güvenli depolamada saklanır.
- Her paket AES‑256‑GCM ile şifrelenir; her mesajda yeni nonce.
- Yerel veri (call/sms/queue) SQLite'da tutulur; bulut senkronizasyonu yok.

## 8. Veri Modeli

### 8.1 Tablolar
- `peer`: id, role, ip, port, key, created_at
- `call_event`: id, direction, number, timestamp, encrypted, status, created_at
- `sms_message`: id, thread_id, address, body, encrypted, direction, status, timestamp, created_at
- `offline_queue`: id, type, payload, retry_count, created_at

## 9. Teknoloji Yığını
- Flutter (UI, state management, ağ, veri katmanı).
- sqflite + path_provider (SQLite).
- cryptography + flutter_secure_storage (şifreleme & anahtar).
- multicast_dns (cihaz keşfi).
- socket_io_client / web_socket_channel (TCP socket).
- qr_flutter + mobile_scanner (QR).
- flutter_local_notifications (bildirimler).
- telephony (SMS/arama eventleri için Android native köprü).
- android_intent (pil optimizasyonu kaldırma).
- connectivity_plus (ağ durumu).
- Riverpod (state management).

## 10. Gerekli İzinler
- READ_PHONE_STATE
- READ_CALL_LOG (opsiyonel)
- ANSWER_PHONE_CALLS
- RECEIVE_SMS, SEND_SMS
- FOREGROUND_SERVICE

## 11. Riskler
- Runtime izin reddi.
- Ağ değişikliği / bağlantı kopması.
- OEM pil optimizasyonları.
- Android versiyon farklılıkları (notification, permissions).

## 12. Yol Haritası
- **Faz 0 (MVP):** Eşleştirme, arama bildirimi + reddetme, SMS mirror, çevrimdışı kuyruk.
- **Faz 1:** Güvenilirlik, çoklu cihaz, OEM pil optimizasyonu yönetimi.
- **Faz 2:** BLE yedek bağlantı, bildirim mirroring (WhatsApp vb.).
