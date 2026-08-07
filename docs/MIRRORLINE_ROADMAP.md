# MirrorLine - Yol Haritası

## Faz 0 - MVP (Mevcut Hedef)
1. Proje setup ve bağımlılıklar.
2. SQLite veri katmanı (DAO, modeller).
3. Şifreleme ve anahtar yönetimi.
4. mDNS keşif ve TCP socket.
5. QR eşleştirme ve rol seçimi UI.
6. Gelen arama bildirimi + uzaktan reddetme.
7. Çift yönlü SMS mirroring.
8. Çevrimdışı kuyruk.
9. Pil optimizasyonu kaldırma ayarı.
10. Temel testler.

## Faz 1 - Güvenilirlik
- OEM'e özel pil optimizasyonu istisnaları.
- Bağlantı kopma / tekrar bağlanma dayanıklılığı.
- Çoklu cihaz eşleştirme (birden fazla Asıl telefon).
- Room benzeri migration desteği.
- Hata raporlama (yerel log dosyası, privacy‑first).

## Faz 2 - Genişletilmiş Bağlantı ve Bildirim Aynalama
- BLE (GATT) yedek taşıma yolu.
- Uzun SMS parçalama / birleştirme.
- NotificationListenerService ile seçili uygulama bildirimlerinin aynalanması.
- Mümkünse RemoteInput ile inline yanıt desteği.

## Faz 3 - Yayın ve Geri Bildirim
- Google Play Console hazırlığı.
- Gizlilik politikası.
- Kullanıcı geri bildirim kanalı.
- Açık kaynak repo hazırlığı (opsiyonel).
