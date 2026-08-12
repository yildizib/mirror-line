// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get appTitle => 'MirrorLine';

  @override
  String get splashTagline => 'İki telefon, uçtan uca şifreli bağlantı';

  @override
  String get navCalls => 'Aramalar';

  @override
  String get navSms => 'SMS';

  @override
  String get navSettings => 'Ayarlar';

  @override
  String get roleTitle => 'Rol Seçimi';

  @override
  String get rolePrompt => 'Bu telefon hangi rolde çalışsın?';

  @override
  String get roleHint => 'Rolü daha sonra ayarlardan değiştirebilirsiniz.';

  @override
  String get roleMain => 'Asıl Telefon';

  @override
  String get roleMainDesc =>
      'Bildirimleri görür, aramaları reddedebilir, SMS’lere yanıt yazarsınız.';

  @override
  String get roleSource => 'Diğer Telefon';

  @override
  String get roleSourceDesc =>
      'SIM’in bulunduğu, arka planda arama ve SMS eventlerini yakalayan cihaz.';

  @override
  String get roleMainSelected => 'Asıl Telefon seçildi';

  @override
  String get roleSourceSelected => 'Diğer Telefon seçildi';

  @override
  String get batteryDialogTitle => 'Arka planda güvenilir çalışma';

  @override
  String get batteryDialogBody =>
      'Bu cihaz \"Diğer Telefon\" olduğu için arama/SMS eventlerini yakalayabilmesi adına ekran kapalıyken de sürekli çalışmalı. Bunun için Android\'in pil optimizasyonundan bu uygulamayı hariç tutmanız gerekiyor.\n\nNot: bu, normalden biraz daha fazla pil tüketimi anlamına gelir -- bağlantıyı canlı tutmanın bilinçli bir bedeli. İstemezseniz daha sonra Ayarlar\'dan da açabilirsiniz.';

  @override
  String get later => 'Daha Sonra';

  @override
  String get setupNow => 'Şimdi Ayarla';

  @override
  String get pairingTitle => 'Cihaz Eşleştir';

  @override
  String get pairingShowQr => 'QR Göster';

  @override
  String get pairingScanQr => 'QR Tara';

  @override
  String get pairingSelectRoleFirst => 'Önce rol seçimi yapmalısınız.';

  @override
  String get pairingSelectRoleButton => 'Rol Seç';

  @override
  String get pairingOtherScanHint => 'Diğer telefon bu QR kodu taratsın.';

  @override
  String get pairingRequestReceived => 'Eşleşme isteği alındı!';

  @override
  String get verificationCodeLabel => 'DOĞRULAMA KODU';

  @override
  String get pairingCodeMatch => 'Kod her iki cihazda aynı olmalı.';

  @override
  String pairingWaiting(String device) {
    return '$device ile eşleşme bekleniyor...';
  }

  @override
  String get pairingCancel => 'İptal';

  @override
  String get pairingRetry => 'Tekrar Dene';

  @override
  String get pairingScanPrompt => 'Diğer cihazın QR kodunu tarayın';

  @override
  String get pairingStartScan => 'Taramayı Başlat';

  @override
  String get pairingRequestTitle => 'Eşleşme İsteği';

  @override
  String pairingRequestFrom(String device) {
    return '$device cihazı ile eşleşmek istiyor.';
  }

  @override
  String get pairingReject => 'Reddet';

  @override
  String get pairingConfirm => 'Onayla';

  @override
  String get pairingConfirmTitle => 'Eşleşmeyi Onayla';

  @override
  String pairingConfirmBody(String device) {
    return '$device cihazı ile eşleşeceksiniz.';
  }

  @override
  String pairingPairedWith(String device) {
    return '$device ile eşleştirildi!';
  }

  @override
  String get pairingInvalidQr => 'Geçersiz QR kod formatı';

  @override
  String get pairingUnknownDevice => 'Bilinmeyen Cihaz';

  @override
  String get pairingErrorConnectionFailed => 'Bağlantı kurulamadı.';

  @override
  String get pairingErrorRejectedOrTimedOut =>
      'Eşleşme reddedildi veya zaman aşımına uğradı.';

  @override
  String get pairingErrorHandshake => 'Eşleşme hatası';

  @override
  String get pairingErrorRejected => 'Eşleşme reddedildi.';

  @override
  String get pairingErrorAckTimeout =>
      'Eşleşme tamamlanamadı (karşı taraftan onay gelmedi). Tekrar deneyin.';

  @override
  String get settingsThisDevice => 'Bu Cihaz';

  @override
  String get settingsNoDeviceInfo =>
      'Henüz cihaz bilgisi oluşturulmadı. Rol seçin.';

  @override
  String get settingsPairedDevice => 'Bağlı Cihaz';

  @override
  String get settingsNotPairedHint =>
      'Henüz eşleşmediniz. Karşı cihaza taratmak için:';

  @override
  String get settingsConnectionDiag => 'Bağlantı Teşhisi';

  @override
  String get settingsLocalIp => 'Bu cihaz IP';

  @override
  String get settingsPeerIp => 'Eş cihaz IP';

  @override
  String get settingsServer => 'Sunucu';

  @override
  String settingsServerRunning(int port) {
    return 'çalışıyor (port $port)';
  }

  @override
  String get settingsServerStopped => 'kapalı';

  @override
  String get settingsLastBeacon => 'Son beacon';

  @override
  String get settingsNoBeacon => 'henüz yok';

  @override
  String get settingsConnectAttempts => 'Deneme sayısı';

  @override
  String get settingsPairedDevices => 'Eşleşmiş Cihazlar';

  @override
  String get settingsNoPairedDevices => 'Henüz eşleşmiş cihaz yok.';

  @override
  String get settingsPort => 'Port';

  @override
  String get settingsIpLabel => 'IP';

  @override
  String get settingsPublicKeyLabel => 'Public Key';

  @override
  String get settingsRoleLabel => 'Rol';

  @override
  String get settingsCounterpartSuffix => ' (karşı)';

  @override
  String get settingsIpUnknown => 'belirlenemedi';

  @override
  String get settingsForceReconnect => 'Yeniden Bağlan';

  @override
  String get settingsForceConnectTitle => 'Bağlanıyor...';

  @override
  String get settingsForceConnectNoPeer => 'Eşleştirilmiş cihaz yok';

  @override
  String get settingsForceConnectDone => 'Bağlandı';

  @override
  String get settingsForceConnectFailed => 'Bağlanamadı';

  @override
  String get settingsForceConnectClose => 'Kapat';

  @override
  String get settingsPairDevice => 'Cihaz Eşleştir';

  @override
  String get settingsChangeRole => 'Rol Değiştir';

  @override
  String get settingsSystem => 'Sistem';

  @override
  String get settingsRemoveBatteryOpt => 'Pil optimizasyonunu kaldır';

  @override
  String get settingsRemoveBatteryOptDesc =>
      'Uygulamanın arka planda güvenilir çalışması için';

  @override
  String get settingsBatteryOpened => 'Pil ayarları açıldı';

  @override
  String get settingsNotifAccess => 'Bildirim erişimi';

  @override
  String get settingsNotifAccessDesc =>
      'Diğer telefondan bildirimleri yansıtmak için gerekli';

  @override
  String get settingsKeepPermissions => 'Kullanılmıyorsa izinleri kaldırma';

  @override
  String get settingsKeepPermissionsDesc =>
      'Uygulama Bilgisi\'nde \"Kullanılmıyorsa izinleri kaldır\" (HyperOS\'ta \"Uygulama kullanılmıyorsa\") seçeneğini kapatın — açık kalırsa Android birkaç ay sonra SMS/arama izinlerini geri alabilir';

  @override
  String get settingsAutoStart => 'Arka planda otomatik başlatma izni';

  @override
  String get settingsAutoStartKnown =>
      'Bu cihazın üreticisi (Xiaomi/Huawei/OPPO/Vivo/Samsung vb.) kendi ek arka plan kısıtlamasını uygulayabilir — uygulamayı buradan izinli listesine ekleyin';

  @override
  String get settingsAutoStartFallback =>
      'Üretici ayarları bulunamadıysa Uygulama Bilgisi açılır';

  @override
  String get settingsBatterySaver => 'Pil tasarrufu istisnası';

  @override
  String get settingsBatterySaverDesc =>
      'Bu cihazın üreticisi (HyperOS/MIUI) ayrı bir pil tasarrufu listesi kullanır — bağlantının ekran kapalıyken kopmaması için burada da \"Kısıtlama yok\" seçin';

  @override
  String get settingsResetDevice => 'Cihazı sıfırla';

  @override
  String get settingsResetDesc => 'Tüm verileri sil ve yeni QR oluştur';

  @override
  String get settingsResetConfirmTitle => 'Cihazı sıfırla';

  @override
  String get settingsResetConfirmBody =>
      'Tüm eşleştirme bilgileri, arama ve SMS geçmişi silinecek. Yeni QR oluşturulacak.';

  @override
  String get settingsResetDone => 'Cihaz sıfırlandı';

  @override
  String get settingsLanguage => 'Dil';

  @override
  String get settingsLanguageSystem => 'Sistem dili';

  @override
  String get connStatusConnected => 'Bağlı';

  @override
  String get connStatusDisconnected => 'Bağlı değil';

  @override
  String get connStatusConnecting => 'Bağlanıyor...';

  @override
  String get connBannerOffline =>
      'Bağlantı yok. Eş cihaz aranıyor; aynı WiFi ağında olduğunuzdan emin olun.';

  @override
  String get connErrorServerStartFailed => 'Sunucu başlatılamadı';

  @override
  String get connErrorPeerIpUnknown =>
      'Eş cihaz IP bilinmiyor (beacon bekleniyor)';

  @override
  String get connErrorConnectFailed =>
      'Bağlantı başarısız (sunucu kapalı veya ulaşılamıyor)';

  @override
  String get callStatusRinging => 'Çalıyor';

  @override
  String get callStatusAnswered => 'Cevaplandı';

  @override
  String get callStatusMissed => 'Cevapsız';

  @override
  String get callStatusRejected => 'Reddedildi';

  @override
  String get callStatusEnded => 'Sonlandı';

  @override
  String get callStatusFailed => 'Gönderilemedi';

  @override
  String get callUnknownNumber => 'Bilinmeyen numara';

  @override
  String get callsEmpty => 'Henüz gelen arama yok';

  @override
  String callsSelectedCount(int count) {
    return '$count seçili';
  }

  @override
  String get callsDeleteSelected => 'Seçilen aramaları sil';

  @override
  String callsDeleteConfirmBody(int groups, int count) {
    return '$groups kişiye ait $count arama kalıcı olarak silinecek.';
  }

  @override
  String get callsDeleted => 'Seçilen aramalar silindi';

  @override
  String callsCallCount(int count) {
    return '$count arama';
  }

  @override
  String get callsRejected => 'Arama reddedildi';

  @override
  String get callsSelectMode => 'Aramaları seç';

  @override
  String callsDeleteOne(int count) {
    return '$count arama kalıcı olarak silinecek.';
  }

  @override
  String get smsStatusReceived => 'Alındı';

  @override
  String get smsStatusSent => 'Gönderildi';

  @override
  String get smsStatusDelivered => 'İletildi';

  @override
  String get smsStatusSending => 'Gönderiliyor';

  @override
  String get smsStatusFailed => 'Gönderilemedi';

  @override
  String get smsUnknownSender => 'Bilinmeyen gönderen';

  @override
  String get smsEmpty => 'Henüz mesaj yok';

  @override
  String smsSelectedCount(int count) {
    return '$count seçili';
  }

  @override
  String get smsDeleteSelected => 'Seçilen konuşmaları sil';

  @override
  String smsDeleteConfirmBody(int count) {
    return '$count konuşma ve tüm mesajları kalıcı olarak silinecek.';
  }

  @override
  String get smsDeleted => 'Seçilen konuşmalar silindi';

  @override
  String get smsSelectMode => 'Mesajları seç';

  @override
  String get smsReplyHint => 'Yanıtınızı yazın...';

  @override
  String get notificationsEmpty => 'Henüz bildirim yok';

  @override
  String notificationsSelectedCount(int count) {
    return '$count seçili';
  }

  @override
  String get notificationsDeleteSelected => 'Seçilen bildirimleri sil';

  @override
  String notificationsDeleteConfirmBody(int count) {
    return '$count bildirim kalıcı olarak silinecek.';
  }

  @override
  String get notificationsDeleted => 'Seçilen bildirimler silindi';

  @override
  String notificationsEventCount(int count) {
    return '$count bildirim';
  }

  @override
  String get notificationsSelectMode => 'Bildirimleri seç';

  @override
  String notificationsDeleteOne(int count) {
    return '$count bildirim kalıcı olarak silinecek.';
  }

  @override
  String get commonDelete => 'Sil';

  @override
  String get commonReset => 'Sıfırla';

  @override
  String get commonCancel => 'İptal';

  @override
  String commonError(String error) {
    return 'Hata: $error';
  }

  @override
  String get commonSelect => 'Seç';

  @override
  String get commonDeleteSelected => 'Seçilenleri sil';

  @override
  String get commonToday => 'Bugün';
}
