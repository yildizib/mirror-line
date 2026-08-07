# MirrorLine - UI Planı

## Genel Prensipler
- Material 3 tasarım dili.
- Tek renk tonu: `Color(0xFF6C63FF)`.
- Düşük elevation, yuvarlatılmış köşeler, geniş boşluklar.
- Riverpod ile state management; UI provider'ları dinler.
- Bottom navigation: Aramalar, SMS, Ayarlar.

## Ekranlar

### 1. Launch & İzin Ekranı
- Logo + uygulama adı.
- Gerekli izinler listesi ve "İzin Ver" butonu.
- Eksiz izin varsa ayarlara yönlendirme.

### 2. HomeScreen
- `AppBar`: MirrorLine başlığı.
- `NavigationBar` ile 3 sekme:
  - Aramalar
  - SMS
  - Ayarlar
- Her sekme ayrı bir `Scaffold` body olarak değişir.

### 3. Aramalar Sekmesi
- Liste (`ListView.separated`) gelen aramaları gösterir.
- Her öğe kart şeklinde:
  - İkon: telefon
  - Başlık: arayan numara / isim
  - Alt metin: zaman
  - Sağda "Reddet" butonu (kırmızı ikon).
- Boş durum: "Henüz gelen arama yok".

### 4. SMS Sekmesi
- Liste gelen/giden mesajları gösterir.
- Her öğe kart şeklinde:
  - İkon: mesaj
  - Başlık: gönderen/alıcı
  - Alt metin: mesaj gövdesi (max 2 satır) + zaman
  - Sağda "Yanıtla" butonu.
- FAB: "Yeni SMS" (opsiyonel).
- Boş durum: "Henüz mesaj yok".

### 5. Yanıtla Modalı
- `AlertDialog` içinde:
  - Alıcı bilgisi
  - `TextField` (çok satırlı)
  - "Gönder" ve "İptal" butonları.

### 6. Ayarlar Sekmesi
- Peer Info kartı:
  - QR kod (200x200)
  - IP adresi
  - Rol (Main / Source)
- "Pil Optimizasyonunu Kaldır" butonu.
- "Cihazı Sıfırla & Yeni QR Oluştur" butonu.
- "Uygulama Hakkında" bölümü.

### 7. Eşleştirme Akışı
- "Eşleştir" seçildiğinde:
  - QR kod ekranı (anahtar + IP).
  - Alternatif: manuel IP + anahtar girişi.
- QR tarama ekranı:
  - Kamera önizlemesi + tarama alanı.
  - Başarılı olunca rol seçimine geç.

### 8. Rol Seçimi Ekranı
- İki seçenek:
  - Asıl Telefon (Main)
  - Diğer Telefon (Source)
- Açıklama metni ile her rolün ne yaptığı belirtilir.
- "Devam" butonu.

## Renk & Tipografi
- Primary: `#6C63FF`
- Surface: beyaz / koyu mod otomatik.
- Error: `Colors.redAccent`
- Success: `Colors.green`
- Başlık: `headlineMedium`
- Alt başlık: `titleMedium`
- Liste metni: `bodyLarge`
- Buton etiketi: `labelLarge`

## Boş Durumlar
- Aramalar ve SMS listeleri boşken merkezde ikon + kısa metin gösterilir.
- "Senkronizasyon duraklatıldı" bannerı ağ yokken gösterilir.
