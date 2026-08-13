import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('tr'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In tr, this message translates to:
  /// **'MirrorLine'**
  String get appTitle;

  /// No description provided for @splashTagline.
  ///
  /// In tr, this message translates to:
  /// **'İki telefon, uçtan uca şifreli bağlantı'**
  String get splashTagline;

  /// No description provided for @navHome.
  ///
  /// In tr, this message translates to:
  /// **'Akış'**
  String get navHome;

  /// No description provided for @navCalls.
  ///
  /// In tr, this message translates to:
  /// **'Aramalar'**
  String get navCalls;

  /// No description provided for @navSms.
  ///
  /// In tr, this message translates to:
  /// **'SMS'**
  String get navSms;

  /// No description provided for @navNotifications.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimler'**
  String get navNotifications;

  /// No description provided for @navSettings.
  ///
  /// In tr, this message translates to:
  /// **'Ayarlar'**
  String get navSettings;

  /// No description provided for @homeFeedEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Henüz etkinlik yok'**
  String get homeFeedEmpty;

  /// No description provided for @roleTitle.
  ///
  /// In tr, this message translates to:
  /// **'Rol Seçimi'**
  String get roleTitle;

  /// No description provided for @rolePrompt.
  ///
  /// In tr, this message translates to:
  /// **'Bu telefon hangi rolde çalışsın?'**
  String get rolePrompt;

  /// No description provided for @roleHint.
  ///
  /// In tr, this message translates to:
  /// **'Rolü daha sonra ayarlardan değiştirebilirsiniz.'**
  String get roleHint;

  /// No description provided for @roleMain.
  ///
  /// In tr, this message translates to:
  /// **'Asıl Telefon'**
  String get roleMain;

  /// No description provided for @roleMainDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimleri görür, aramaları reddedebilir, SMS’lere yanıt yazarsınız.'**
  String get roleMainDesc;

  /// No description provided for @roleSource.
  ///
  /// In tr, this message translates to:
  /// **'Diğer Telefon'**
  String get roleSource;

  /// No description provided for @roleSourceDesc.
  ///
  /// In tr, this message translates to:
  /// **'SIM’in bulunduğu, arka planda arama ve SMS eventlerini yakalayan cihaz.'**
  String get roleSourceDesc;

  /// No description provided for @roleMainSelected.
  ///
  /// In tr, this message translates to:
  /// **'Asıl Telefon seçildi'**
  String get roleMainSelected;

  /// No description provided for @roleSourceSelected.
  ///
  /// In tr, this message translates to:
  /// **'Diğer Telefon seçildi'**
  String get roleSourceSelected;

  /// No description provided for @batteryDialogTitle.
  ///
  /// In tr, this message translates to:
  /// **'Arka planda güvenilir çalışma'**
  String get batteryDialogTitle;

  /// No description provided for @batteryDialogBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu cihaz \"Diğer Telefon\" olduğu için arama/SMS eventlerini yakalayabilmesi adına ekran kapalıyken de sürekli çalışmalı. Bunun için Android\'in pil optimizasyonundan bu uygulamayı hariç tutmanız gerekiyor.\n\nNot: bu, normalden biraz daha fazla pil tüketimi anlamına gelir -- bağlantıyı canlı tutmanın bilinçli bir bedeli. İstemezseniz daha sonra Ayarlar\'dan da açabilirsiniz.'**
  String get batteryDialogBody;

  /// No description provided for @later.
  ///
  /// In tr, this message translates to:
  /// **'Daha Sonra'**
  String get later;

  /// No description provided for @setupNow.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi Ayarla'**
  String get setupNow;

  /// No description provided for @pairingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Cihaz Eşleştir'**
  String get pairingTitle;

  /// No description provided for @pairingShowQr.
  ///
  /// In tr, this message translates to:
  /// **'QR Göster'**
  String get pairingShowQr;

  /// No description provided for @pairingScanQr.
  ///
  /// In tr, this message translates to:
  /// **'QR Tara'**
  String get pairingScanQr;

  /// No description provided for @pairingSelectRoleFirst.
  ///
  /// In tr, this message translates to:
  /// **'Önce rol seçimi yapmalısınız.'**
  String get pairingSelectRoleFirst;

  /// No description provided for @pairingSelectRoleButton.
  ///
  /// In tr, this message translates to:
  /// **'Rol Seç'**
  String get pairingSelectRoleButton;

  /// No description provided for @pairingOtherScanHint.
  ///
  /// In tr, this message translates to:
  /// **'Diğer telefon bu QR kodu taratsın.'**
  String get pairingOtherScanHint;

  /// No description provided for @pairingRequestReceived.
  ///
  /// In tr, this message translates to:
  /// **'Eşleşme isteği alındı!'**
  String get pairingRequestReceived;

  /// No description provided for @verificationCodeLabel.
  ///
  /// In tr, this message translates to:
  /// **'DOĞRULAMA KODU'**
  String get verificationCodeLabel;

  /// No description provided for @pairingCodeMatch.
  ///
  /// In tr, this message translates to:
  /// **'Kod her iki cihazda aynı olmalı.'**
  String get pairingCodeMatch;

  /// No description provided for @pairingWaiting.
  ///
  /// In tr, this message translates to:
  /// **'{device} ile eşleşme bekleniyor...'**
  String pairingWaiting(String device);

  /// No description provided for @pairingCancel.
  ///
  /// In tr, this message translates to:
  /// **'İptal'**
  String get pairingCancel;

  /// No description provided for @pairingRetry.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar Dene'**
  String get pairingRetry;

  /// No description provided for @pairingScanPrompt.
  ///
  /// In tr, this message translates to:
  /// **'Diğer cihazın QR kodunu tarayın'**
  String get pairingScanPrompt;

  /// No description provided for @pairingStartScan.
  ///
  /// In tr, this message translates to:
  /// **'Taramayı Başlat'**
  String get pairingStartScan;

  /// No description provided for @pairingRequestTitle.
  ///
  /// In tr, this message translates to:
  /// **'Eşleşme İsteği'**
  String get pairingRequestTitle;

  /// No description provided for @pairingRequestFrom.
  ///
  /// In tr, this message translates to:
  /// **'{device} cihazı ile eşleşmek istiyor.'**
  String pairingRequestFrom(String device);

  /// No description provided for @pairingReject.
  ///
  /// In tr, this message translates to:
  /// **'Reddet'**
  String get pairingReject;

  /// No description provided for @pairingConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Onayla'**
  String get pairingConfirm;

  /// No description provided for @pairingConfirmTitle.
  ///
  /// In tr, this message translates to:
  /// **'Eşleşmeyi Onayla'**
  String get pairingConfirmTitle;

  /// No description provided for @pairingConfirmBody.
  ///
  /// In tr, this message translates to:
  /// **'{device} cihazı ile eşleşeceksiniz.'**
  String pairingConfirmBody(String device);

  /// No description provided for @pairingPairedWith.
  ///
  /// In tr, this message translates to:
  /// **'{device} ile eşleştirildi!'**
  String pairingPairedWith(String device);

  /// No description provided for @pairingInvalidQr.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz QR kod formatı'**
  String get pairingInvalidQr;

  /// No description provided for @pairingUnknownDevice.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen Cihaz'**
  String get pairingUnknownDevice;

  /// No description provided for @pairingErrorConnectionFailed.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı kurulamadı.'**
  String get pairingErrorConnectionFailed;

  /// No description provided for @pairingErrorRejectedOrTimedOut.
  ///
  /// In tr, this message translates to:
  /// **'Eşleşme reddedildi veya zaman aşımına uğradı.'**
  String get pairingErrorRejectedOrTimedOut;

  /// No description provided for @pairingErrorHandshake.
  ///
  /// In tr, this message translates to:
  /// **'Eşleşme hatası'**
  String get pairingErrorHandshake;

  /// No description provided for @pairingErrorRejected.
  ///
  /// In tr, this message translates to:
  /// **'Eşleşme reddedildi.'**
  String get pairingErrorRejected;

  /// No description provided for @pairingErrorAckTimeout.
  ///
  /// In tr, this message translates to:
  /// **'Eşleşme tamamlanamadı (karşı taraftan onay gelmedi). Tekrar deneyin.'**
  String get pairingErrorAckTimeout;

  /// No description provided for @settingsThisDevice.
  ///
  /// In tr, this message translates to:
  /// **'Bu Cihaz'**
  String get settingsThisDevice;

  /// No description provided for @settingsNoDeviceInfo.
  ///
  /// In tr, this message translates to:
  /// **'Henüz cihaz bilgisi oluşturulmadı. Rol seçin.'**
  String get settingsNoDeviceInfo;

  /// No description provided for @settingsPairedDevice.
  ///
  /// In tr, this message translates to:
  /// **'Bağlı Cihaz'**
  String get settingsPairedDevice;

  /// No description provided for @settingsNotPairedHint.
  ///
  /// In tr, this message translates to:
  /// **'Henüz eşleşmediniz. Karşı cihaza taratmak için:'**
  String get settingsNotPairedHint;

  /// No description provided for @settingsConnectionDiag.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı Teşhisi'**
  String get settingsConnectionDiag;

  /// No description provided for @settingsLocalIp.
  ///
  /// In tr, this message translates to:
  /// **'Bu cihaz IP'**
  String get settingsLocalIp;

  /// No description provided for @settingsPeerIp.
  ///
  /// In tr, this message translates to:
  /// **'Eş cihaz IP'**
  String get settingsPeerIp;

  /// No description provided for @settingsServer.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu'**
  String get settingsServer;

  /// No description provided for @settingsServerRunning.
  ///
  /// In tr, this message translates to:
  /// **'çalışıyor (port {port})'**
  String settingsServerRunning(int port);

  /// No description provided for @settingsServerStopped.
  ///
  /// In tr, this message translates to:
  /// **'kapalı'**
  String get settingsServerStopped;

  /// No description provided for @settingsLastBeacon.
  ///
  /// In tr, this message translates to:
  /// **'Son beacon'**
  String get settingsLastBeacon;

  /// No description provided for @settingsNoBeacon.
  ///
  /// In tr, this message translates to:
  /// **'henüz yok'**
  String get settingsNoBeacon;

  /// No description provided for @settingsConnectAttempts.
  ///
  /// In tr, this message translates to:
  /// **'Deneme sayısı'**
  String get settingsConnectAttempts;

  /// No description provided for @settingsPairedDevices.
  ///
  /// In tr, this message translates to:
  /// **'Eşleşmiş Cihazlar'**
  String get settingsPairedDevices;

  /// No description provided for @settingsNoPairedDevices.
  ///
  /// In tr, this message translates to:
  /// **'Henüz eşleşmiş cihaz yok.'**
  String get settingsNoPairedDevices;

  /// No description provided for @settingsPort.
  ///
  /// In tr, this message translates to:
  /// **'Port'**
  String get settingsPort;

  /// No description provided for @settingsIpLabel.
  ///
  /// In tr, this message translates to:
  /// **'IP'**
  String get settingsIpLabel;

  /// No description provided for @settingsPublicKeyLabel.
  ///
  /// In tr, this message translates to:
  /// **'Public Key'**
  String get settingsPublicKeyLabel;

  /// No description provided for @settingsRoleLabel.
  ///
  /// In tr, this message translates to:
  /// **'Rol'**
  String get settingsRoleLabel;

  /// No description provided for @settingsCounterpartSuffix.
  ///
  /// In tr, this message translates to:
  /// **' (karşı)'**
  String get settingsCounterpartSuffix;

  /// No description provided for @settingsIpUnknown.
  ///
  /// In tr, this message translates to:
  /// **'belirlenemedi'**
  String get settingsIpUnknown;

  /// No description provided for @settingsForceReconnect.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden Bağlan'**
  String get settingsForceReconnect;

  /// No description provided for @settingsForceConnectTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bağlanıyor...'**
  String get settingsForceConnectTitle;

  /// No description provided for @settingsForceConnectNoPeer.
  ///
  /// In tr, this message translates to:
  /// **'Eşleştirilmiş cihaz yok'**
  String get settingsForceConnectNoPeer;

  /// No description provided for @settingsForceConnectDone.
  ///
  /// In tr, this message translates to:
  /// **'Bağlandı'**
  String get settingsForceConnectDone;

  /// No description provided for @settingsForceConnectFailed.
  ///
  /// In tr, this message translates to:
  /// **'Bağlanamadı'**
  String get settingsForceConnectFailed;

  /// No description provided for @settingsForceConnectClose.
  ///
  /// In tr, this message translates to:
  /// **'Kapat'**
  String get settingsForceConnectClose;

  /// No description provided for @settingsPairDevice.
  ///
  /// In tr, this message translates to:
  /// **'Cihaz Eşleştir'**
  String get settingsPairDevice;

  /// No description provided for @settingsChangeRole.
  ///
  /// In tr, this message translates to:
  /// **'Rol Değiştir'**
  String get settingsChangeRole;

  /// No description provided for @settingsSystem.
  ///
  /// In tr, this message translates to:
  /// **'Sistem'**
  String get settingsSystem;

  /// No description provided for @settingsRemoveBatteryOpt.
  ///
  /// In tr, this message translates to:
  /// **'Pil optimizasyonunu kaldır'**
  String get settingsRemoveBatteryOpt;

  /// No description provided for @settingsRemoveBatteryOptDesc.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamanın arka planda güvenilir çalışması için'**
  String get settingsRemoveBatteryOptDesc;

  /// No description provided for @settingsBatteryOpened.
  ///
  /// In tr, this message translates to:
  /// **'Pil ayarları açıldı'**
  String get settingsBatteryOpened;

  /// No description provided for @settingsNotifAccess.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim erişimi'**
  String get settingsNotifAccess;

  /// No description provided for @settingsNotifAccessDesc.
  ///
  /// In tr, this message translates to:
  /// **'Diğer telefondan bildirimleri yansıtmak için gerekli'**
  String get settingsNotifAccessDesc;

  /// No description provided for @settingsWatchedApps.
  ///
  /// In tr, this message translates to:
  /// **'İzlenen uygulamalar'**
  String get settingsWatchedApps;

  /// No description provided for @settingsWatchedAppsDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimleri yansıtılacak uygulamaları seç'**
  String get settingsWatchedAppsDesc;

  /// No description provided for @watchedAppsTitle.
  ///
  /// In tr, this message translates to:
  /// **'İzlenen uygulamalar'**
  String get watchedAppsTitle;

  /// No description provided for @watchedAppsSearchHint.
  ///
  /// In tr, this message translates to:
  /// **'Uygulama ara...'**
  String get watchedAppsSearchHint;

  /// No description provided for @settingsRunTests.
  ///
  /// In tr, this message translates to:
  /// **'Testleri çalıştır'**
  String get settingsRunTests;

  /// No description provided for @settingsRunTestsDesc.
  ///
  /// In tr, this message translates to:
  /// **'Eşleşen cihaza sahte arama, SMS ve bildirim gönder'**
  String get settingsRunTestsDesc;

  /// No description provided for @runTestsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Testleri çalıştır'**
  String get runTestsTitle;

  /// No description provided for @runTestsButton.
  ///
  /// In tr, this message translates to:
  /// **'Testleri çalıştır'**
  String get runTestsButton;

  /// No description provided for @runTestsEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Henüz test çalıştırılmadı'**
  String get runTestsEmpty;

  /// No description provided for @runTestsSent.
  ///
  /// In tr, this message translates to:
  /// **'Gönderildi'**
  String get runTestsSent;

  /// No description provided for @runTestsQueued.
  ///
  /// In tr, this message translates to:
  /// **'Sıraya alındı'**
  String get runTestsQueued;

  /// No description provided for @runTestsCallType.
  ///
  /// In tr, this message translates to:
  /// **'Test araması'**
  String get runTestsCallType;

  /// No description provided for @runTestsSmsType.
  ///
  /// In tr, this message translates to:
  /// **'Test SMS\'i'**
  String get runTestsSmsType;

  /// No description provided for @runTestsNotificationType.
  ///
  /// In tr, this message translates to:
  /// **'Test bildirimi'**
  String get runTestsNotificationType;

  /// No description provided for @runTestsNotConnected.
  ///
  /// In tr, this message translates to:
  /// **'Testleri çalıştırmak için eşleşmiş bir cihaza bağlı olmalısınız'**
  String get runTestsNotConnected;

  /// No description provided for @settingsKeepPermissions.
  ///
  /// In tr, this message translates to:
  /// **'Kullanılmıyorsa izinleri kaldırma'**
  String get settingsKeepPermissions;

  /// No description provided for @settingsKeepPermissionsDesc.
  ///
  /// In tr, this message translates to:
  /// **'Uygulama Bilgisi\'nde \"Kullanılmıyorsa izinleri kaldır\" (HyperOS\'ta \"Uygulama kullanılmıyorsa\") seçeneğini kapatın — açık kalırsa Android birkaç ay sonra SMS/arama izinlerini geri alabilir'**
  String get settingsKeepPermissionsDesc;

  /// No description provided for @settingsAutoStart.
  ///
  /// In tr, this message translates to:
  /// **'Arka planda otomatik başlatma izni'**
  String get settingsAutoStart;

  /// No description provided for @settingsAutoStartKnown.
  ///
  /// In tr, this message translates to:
  /// **'Bu cihazın üreticisi (Xiaomi/Huawei/OPPO/Vivo/Samsung vb.) kendi ek arka plan kısıtlamasını uygulayabilir — uygulamayı buradan izinli listesine ekleyin'**
  String get settingsAutoStartKnown;

  /// No description provided for @settingsAutoStartFallback.
  ///
  /// In tr, this message translates to:
  /// **'Üretici ayarları bulunamadıysa Uygulama Bilgisi açılır'**
  String get settingsAutoStartFallback;

  /// No description provided for @settingsBatterySaver.
  ///
  /// In tr, this message translates to:
  /// **'Pil tasarrufu istisnası'**
  String get settingsBatterySaver;

  /// No description provided for @settingsBatterySaverDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bu cihazın üreticisi (HyperOS/MIUI) ayrı bir pil tasarrufu listesi kullanır — bağlantının ekran kapalıyken kopmaması için burada da \"Kısıtlama yok\" seçin'**
  String get settingsBatterySaverDesc;

  /// No description provided for @settingsResetDevice.
  ///
  /// In tr, this message translates to:
  /// **'Cihazı sıfırla'**
  String get settingsResetDevice;

  /// No description provided for @settingsResetDesc.
  ///
  /// In tr, this message translates to:
  /// **'Tüm verileri sil ve yeni QR oluştur'**
  String get settingsResetDesc;

  /// No description provided for @settingsResetConfirmTitle.
  ///
  /// In tr, this message translates to:
  /// **'Cihazı sıfırla'**
  String get settingsResetConfirmTitle;

  /// No description provided for @settingsResetConfirmBody.
  ///
  /// In tr, this message translates to:
  /// **'Tüm eşleştirme bilgileri, arama ve SMS geçmişi silinecek. Yeni QR oluşturulacak.'**
  String get settingsResetConfirmBody;

  /// No description provided for @settingsResetDone.
  ///
  /// In tr, this message translates to:
  /// **'Cihaz sıfırlandı'**
  String get settingsResetDone;

  /// No description provided for @settingsDangerZone.
  ///
  /// In tr, this message translates to:
  /// **'Tehlikeli Bölge'**
  String get settingsDangerZone;

  /// No description provided for @settingsLanguage.
  ///
  /// In tr, this message translates to:
  /// **'Dil'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSystem.
  ///
  /// In tr, this message translates to:
  /// **'Sistem dili'**
  String get settingsLanguageSystem;

  /// No description provided for @connStatusConnected.
  ///
  /// In tr, this message translates to:
  /// **'Bağlı'**
  String get connStatusConnected;

  /// No description provided for @connStatusDisconnected.
  ///
  /// In tr, this message translates to:
  /// **'Bağlı değil'**
  String get connStatusDisconnected;

  /// No description provided for @connStatusConnecting.
  ///
  /// In tr, this message translates to:
  /// **'Bağlanıyor...'**
  String get connStatusConnecting;

  /// No description provided for @connBannerOffline.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı yok. Eş cihaz aranıyor; aynı WiFi ağında olduğunuzdan emin olun.'**
  String get connBannerOffline;

  /// No description provided for @connErrorServerStartFailed.
  ///
  /// In tr, this message translates to:
  /// **'Sunucu başlatılamadı'**
  String get connErrorServerStartFailed;

  /// No description provided for @connErrorPeerIpUnknown.
  ///
  /// In tr, this message translates to:
  /// **'Eş cihaz IP bilinmiyor (beacon bekleniyor)'**
  String get connErrorPeerIpUnknown;

  /// No description provided for @connErrorConnectFailed.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı başarısız (sunucu kapalı veya ulaşılamıyor)'**
  String get connErrorConnectFailed;

  /// No description provided for @callStatusRinging.
  ///
  /// In tr, this message translates to:
  /// **'Çalıyor'**
  String get callStatusRinging;

  /// No description provided for @callStatusAnswered.
  ///
  /// In tr, this message translates to:
  /// **'Cevaplandı'**
  String get callStatusAnswered;

  /// No description provided for @callStatusMissed.
  ///
  /// In tr, this message translates to:
  /// **'Cevapsız'**
  String get callStatusMissed;

  /// No description provided for @callStatusRejected.
  ///
  /// In tr, this message translates to:
  /// **'Reddedildi'**
  String get callStatusRejected;

  /// No description provided for @callStatusEnded.
  ///
  /// In tr, this message translates to:
  /// **'Sonlandı'**
  String get callStatusEnded;

  /// No description provided for @callStatusFailed.
  ///
  /// In tr, this message translates to:
  /// **'Gönderilemedi'**
  String get callStatusFailed;

  /// No description provided for @callUnknownNumber.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen numara'**
  String get callUnknownNumber;

  /// No description provided for @callsEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Henüz gelen arama yok'**
  String get callsEmpty;

  /// No description provided for @callsSelectedCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} seçili'**
  String callsSelectedCount(int count);

  /// No description provided for @callsDeleteSelected.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen aramaları sil'**
  String get callsDeleteSelected;

  /// No description provided for @callsDeleteConfirmBody.
  ///
  /// In tr, this message translates to:
  /// **'{groups} kişiye ait {count} arama kalıcı olarak silinecek.'**
  String callsDeleteConfirmBody(int groups, int count);

  /// No description provided for @callsDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen aramalar silindi'**
  String get callsDeleted;

  /// No description provided for @callsCallCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} arama'**
  String callsCallCount(int count);

  /// No description provided for @callsRejected.
  ///
  /// In tr, this message translates to:
  /// **'Arama reddedildi'**
  String get callsRejected;

  /// No description provided for @callsSelectMode.
  ///
  /// In tr, this message translates to:
  /// **'Aramaları seç'**
  String get callsSelectMode;

  /// No description provided for @callsDeleteOne.
  ///
  /// In tr, this message translates to:
  /// **'{count} arama kalıcı olarak silinecek.'**
  String callsDeleteOne(int count);

  /// No description provided for @smsStatusReceived.
  ///
  /// In tr, this message translates to:
  /// **'Alındı'**
  String get smsStatusReceived;

  /// No description provided for @smsStatusSent.
  ///
  /// In tr, this message translates to:
  /// **'Gönderildi'**
  String get smsStatusSent;

  /// No description provided for @smsStatusDelivered.
  ///
  /// In tr, this message translates to:
  /// **'İletildi'**
  String get smsStatusDelivered;

  /// No description provided for @smsStatusSending.
  ///
  /// In tr, this message translates to:
  /// **'Gönderiliyor'**
  String get smsStatusSending;

  /// No description provided for @smsStatusFailed.
  ///
  /// In tr, this message translates to:
  /// **'Gönderilemedi'**
  String get smsStatusFailed;

  /// No description provided for @smsUnknownSender.
  ///
  /// In tr, this message translates to:
  /// **'Bilinmeyen gönderen'**
  String get smsUnknownSender;

  /// No description provided for @smsEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Henüz mesaj yok'**
  String get smsEmpty;

  /// No description provided for @smsSelectedCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} seçili'**
  String smsSelectedCount(int count);

  /// No description provided for @smsDeleteSelected.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen konuşmaları sil'**
  String get smsDeleteSelected;

  /// No description provided for @smsDeleteConfirmBody.
  ///
  /// In tr, this message translates to:
  /// **'{count} konuşma ve tüm mesajları kalıcı olarak silinecek.'**
  String smsDeleteConfirmBody(int count);

  /// No description provided for @smsDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen konuşmalar silindi'**
  String get smsDeleted;

  /// No description provided for @smsSelectMode.
  ///
  /// In tr, this message translates to:
  /// **'Mesajları seç'**
  String get smsSelectMode;

  /// No description provided for @smsReplyHint.
  ///
  /// In tr, this message translates to:
  /// **'Yanıtınızı yazın...'**
  String get smsReplyHint;

  /// No description provided for @runTestsCallLabel.
  ///
  /// In tr, this message translates to:
  /// **'MirrorLine Test Araması'**
  String get runTestsCallLabel;

  /// No description provided for @runTestsSmsBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu, MirrorLine tanılamasından gelen bir test SMS\'idir.'**
  String get runTestsSmsBody;

  /// No description provided for @runTestsNotificationApp.
  ///
  /// In tr, this message translates to:
  /// **'MirrorLine Testi'**
  String get runTestsNotificationApp;

  /// No description provided for @runTestsNotificationTitle.
  ///
  /// In tr, this message translates to:
  /// **'Test Bildirimi'**
  String get runTestsNotificationTitle;

  /// No description provided for @runTestsNotificationBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu, MirrorLine tanılamasından gelen bir test bildirimidir.'**
  String get runTestsNotificationBody;

  /// No description provided for @notificationsEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Henüz bildirim yok'**
  String get notificationsEmpty;

  /// No description provided for @notificationsSelectedCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} seçili'**
  String notificationsSelectedCount(int count);

  /// No description provided for @notificationsDeleteSelected.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen bildirimleri sil'**
  String get notificationsDeleteSelected;

  /// No description provided for @notificationsDeleteConfirmBody.
  ///
  /// In tr, this message translates to:
  /// **'{count} bildirim kalıcı olarak silinecek.'**
  String notificationsDeleteConfirmBody(int count);

  /// No description provided for @notificationsDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Seçilen bildirimler silindi'**
  String get notificationsDeleted;

  /// No description provided for @notificationsEventCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} bildirim'**
  String notificationsEventCount(int count);

  /// No description provided for @notificationsSelectMode.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimleri seç'**
  String get notificationsSelectMode;

  /// No description provided for @notificationsDeleteOne.
  ///
  /// In tr, this message translates to:
  /// **'{count} bildirim kalıcı olarak silinecek.'**
  String notificationsDeleteOne(int count);

  /// No description provided for @commonDelete.
  ///
  /// In tr, this message translates to:
  /// **'Sil'**
  String get commonDelete;

  /// No description provided for @commonReset.
  ///
  /// In tr, this message translates to:
  /// **'Sıfırla'**
  String get commonReset;

  /// No description provided for @commonCancel.
  ///
  /// In tr, this message translates to:
  /// **'İptal'**
  String get commonCancel;

  /// No description provided for @commonError.
  ///
  /// In tr, this message translates to:
  /// **'Hata: {error}'**
  String commonError(String error);

  /// No description provided for @commonSelect.
  ///
  /// In tr, this message translates to:
  /// **'Seç'**
  String get commonSelect;

  /// No description provided for @commonDeleteSelected.
  ///
  /// In tr, this message translates to:
  /// **'Seçilenleri sil'**
  String get commonDeleteSelected;

  /// No description provided for @commonToday.
  ///
  /// In tr, this message translates to:
  /// **'Bugün'**
  String get commonToday;

  /// No description provided for @commonYesterday.
  ///
  /// In tr, this message translates to:
  /// **'Dün'**
  String get commonYesterday;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
