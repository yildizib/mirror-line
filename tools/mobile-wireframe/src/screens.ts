export type Locale = 'tr' | 'en';

export type ScreenGroup =
  | 'account'
  | 'role'
  | 'pairing'
  | 'main-permission'
  | 'source-permission'
  | 'main-app'
  | 'source-app'
  | 'main-settings'
  | 'source-settings'
  | 'shared';

export interface LocalizedText {
  tr: string;
  en: string;
}

export interface ScreenDefinition {
  id: string;
  group: ScreenGroup;
  title: LocalizedText;
  summary: LocalizedText;
  variants: string[];
}

const screen = (
  id: string,
  group: ScreenGroup,
  trTitle: string,
  enTitle: string,
  trSummary: string,
  enSummary: string,
  variants: string[] = ['default'],
): ScreenDefinition => ({
  id,
  group,
  title: { tr: trTitle, en: enTitle },
  summary: { tr: trSummary, en: enSummary },
  variants,
});

export const screens: ScreenDefinition[] = [
  screen('A01', 'account', 'MirrorLine açılıyor', 'Opening MirrorLine', 'Oturum ve cihaz rolü güvenli biçimde okunuyor.', 'Reading your session and device role.', ['default', 'slow startup']),
  screen('A02', 'account', 'Hoş geldin', 'Welcome', 'Telefonlarındaki önemli etkinlikleri tek yerde gör.', 'See important activity from your phones in one place.'),
  screen('A03', 'account', 'Giriş yap', 'Sign in', 'MirrorLine hesabınla devam et.', 'Continue with your MirrorLine account.', ['default', 'submitting', 'wrong credentials', 'offline']),
  screen('A04', 'account', 'Hesap oluştur', 'Create account', 'Doğrulanmış e-posta ve parola ile hesabını hazırla.', 'Set up your account with a verified email and password.', ['default', 'validation errors', 'submitting', 'email exists', 'offline']),
  screen('A05', 'account', 'E-postanı doğrula', 'Verify your email', 'Gönderdiğimiz bağlantıyı açtıktan sonra tekrar kontrol et.', 'Open the link we sent, then check again.', ['pending', 'cooldown', 'expired', 'verified', 'resend failed']),
  screen('A06', 'account', 'Kayıt e-postasını değiştir', 'Change registration email', 'Doğrulama mesajını yeni adresine gönder.', 'Send the verification message to a new address.', ['default', 'invalid', 'already used', 'submitting']),
  screen('A07', 'account', 'Parolamı unuttum', 'Forgot password', 'Parola sıfırlama bağlantısı iste.', 'Request a password reset link.', ['default', 'invalid', 'submitting', 'accepted', 'failed']),
  screen('A08', 'account', 'E-postanı kontrol et', 'Check your email', 'Hesap varlığına ilişkin bilgi vermeden yönlendirme yapar.', 'Provides neutral guidance without revealing account status.'),
  screen('A09', 'account', 'Yeni parola oluştur', 'Create a new password', 'Yeni parolanı belirle ve hesabına dön.', 'Set a new password and return to your account.', ['default', 'invalid', 'expired link', 'success']),
  screen('A10', 'account', 'Yeni sürüm var', 'A new version is available', 'Güncelleme uygulamayı kullanmanı engellemez.', 'The update never blocks app use.', ['visible', 'dismissed']),
  screen('A11', 'account', 'Güncellemeleri kontrol et', 'Check for updates', 'Yüklü sürümü ve kullanılabilir sürümü karşılaştır.', 'Compare the installed and available versions.', ['available', 'check failed', 'current']),

  screen('R01', 'role', 'Bu telefonun rolünü seç', 'Choose this phone’s role', 'Telefonu Ana veya Kaynak olarak kur.', 'Set up this phone as Main or Source.'),
  screen('R02', 'role', 'Rolü onayla', 'Confirm role', 'Seçilen rolün bu telefonda ne yapacağını incele.', 'Review what the selected role does on this phone.', ['Main', 'Source']),
  screen('R03', 'role', 'Ana Telefon zaten mevcut', 'A Main Phone already exists', 'Hesabında aynı anda yalnızca bir Ana Telefon bulunabilir.', 'Your account can have only one Main Phone at a time.'),
  screen('R04', 'role', 'Değişiklik sonuçları', 'Replacement consequences', 'Eski oturum ve mevcut Kaynak bağlantıları kaldırılır.', 'The old session and current Source connections are removed.'),
  screen('R05', 'role', 'Kimliğini doğrula', 'Verify your identity', 'Ana Telefonu değiştirmeden önce parolanı doğrula.', 'Confirm your password before replacing the Main Phone.', ['default', 'failed', 'submitting']),
  screen('R06', 'role', 'Ana Telefonu değiştir', 'Replace Main Phone', 'Geri alınamayan sonuçları son kez onayla.', 'Confirm the irreversible consequences one final time.', ['default', 'processing', 'failed']),
  screen('R07', 'role', 'Ana Telefon hazır', 'Main Phone is ready', 'Kaynak Telefon ekleyebilir veya ana ekrana geçebilirsin.', 'Add a Source Phone or continue to the home screen.', ['zero Sources', 'returning Main']),

  screen('P01', 'pairing', 'Kaynak Telefonlar', 'Source Phones', 'Hesabından alınan mevcut ve azami cihaz durumunu gösterir.', 'Shows the current and maximum device count received for your account.', ['0', '1–4', '5 of 5', 'unavailable']),
  screen('P02', 'pairing', 'Eşleştirme kontrol ediliyor', 'Checking pairing eligibility', 'Yeni eşleştirmenin başlatılıp başlatılamayacağını kontrol et.', 'Check whether a new pairing can begin.', ['checking', 'failed']),
  screen('P03', 'pairing', 'Cihaz sınırına ulaşıldı', 'Device limit reached', 'Yeni Kaynak eklemek için önce mevcut bir bağlantıyı kaldır.', 'Remove an existing connection before adding another Source.'),
  screen('P04', 'pairing', 'Eşleştirmeye hazırlan', 'Prepare to pair', 'İki telefonu yanında tut ve adımları incele.', 'Keep both phones nearby and review the steps.'),
  screen('P05', 'pairing', 'Eşleştirme kodu', 'Pairing code', 'QR veya kısa kodu Kaynak Telefonda kullan.', 'Use the QR or short code on the Source Phone.', ['active', 'expiring', 'expired', 'refreshing']),
  screen('P06', 'pairing', 'QR kodu tara', 'Scan QR code', 'Ana Telefonda gösterilen kodu çerçeveye hizala.', 'Align the code shown on the Main Phone.', ['default', 'permission denied', 'unavailable']),
  screen('P07', 'pairing', 'Kısa kodu gir', 'Enter short code', 'Ana Telefonda görünen kısa kodu yaz.', 'Enter the short code shown on the Main Phone.', ['default', 'invalid', 'expired', 'submitting']),
  screen('P08', 'pairing', 'Kod kullanılamıyor', 'Code unavailable', 'Yeni kod oluştur ve tekrar dene.', 'Create a new code and try again.', ['invalid', 'expired']),
  screen('P09', 'pairing', 'Kodları karşılaştır', 'Compare codes', 'Her iki telefonda da aynı kodun göründüğünü doğrula.', 'Confirm that both phones show the same code.', ['Main', 'Source']),
  screen('P10', 'pairing', 'Kaynak Telefonu incele', 'Review Source Phone', 'Cihaz adını kontrol edip eşleştirmeyi onayla.', 'Check the device name and confirm pairing.', ['default', 'submitting']),
  screen('P11', 'pairing', 'Kaynak Telefon eklendi', 'Source Phone added', 'Bağlantı tamamlandı; sıradaki adıma geç.', 'The connection is complete; continue to the next step.', ['Main', 'Source']),
  screen('P12', 'pairing', 'Eşleştirme tamamlanamadı', 'Pairing could not be completed', 'Nedeni incele, tekrar dene veya işlemi iptal et.', 'Review the reason, retry, or cancel.', ['generic', 'rejected', 'timed out', 'quota changed']),
  screen('P13', 'pairing', 'Kaynak Telefon zaten bağlı', 'Source Phone already connected', 'Yeni eşleştirmeden önce mevcut Ana bağlantısını kaldır.', 'Remove the current Main connection before pairing again.', ['connected', 'Main unavailable']),
  screen('P14', 'pairing', 'Mevcut bağlantıyı kaldır', 'Remove current connection', 'Aktarım durur ve yeniden eşleştirme gerekir.', 'Forwarding stops and pairing will be required again.'),
  screen('P15', 'pairing', 'Bağlantıyı kaldırmak için doğrula', 'Verify before removing connection', 'Kritik işlem için hesap parolanı doğrula.', 'Confirm your account password for this critical action.', ['default', 'failed', 'processing']),
  screen('P16', 'pairing', 'Bağlantı kaldırıldı', 'Connection removed', 'Bu telefonu yeni bir Ana Telefonla eşleştirebilirsin.', 'You can pair this phone with a new Main Phone.'),

  screen('MP01', 'main-permission', 'Ana Telefon bildirimleri', 'Main Phone notifications', 'Ana Telefon yalnızca bildirim izni ister.', 'The Main Phone only requests notification permission.'),
  screen('MP02', 'main-permission', 'Bildirim izni sonucu', 'Notification permission result', 'İzin durumu kurulumu engellemeden açıklanır.', 'The permission status is explained without blocking setup.', ['granted', 'denied', 'permanently denied']),

  screen('SP01', 'source-permission', 'Kaynak izinleri', 'Source permissions', 'Her özellik ayrı ayrı kurulabilir ve daha sonra tamamlanabilir.', 'Each capability can be configured separately and completed later.', ['fresh', 'partially complete', 'complete']),
  screen('SP02', 'source-permission', 'Arama izleme', 'Call monitoring', 'Arama etkinliklerini Ana Telefonda göstermek için izin iste.', 'Request access to show call activity on the Main Phone.', ['not requested', 'granted', 'denied', 'unavailable']),
  screen('SP03', 'source-permission', 'SMS erişimi', 'SMS access', 'SMS görüntüleme ve bu hat üzerinden yanıtlama iznini açıkla.', 'Explain SMS viewing and replies sent through this line.', ['not requested', 'granted', 'denied', 'unavailable']),
  screen('SP04', 'source-permission', 'Uygulama bildirim erişimi', 'App notification access', 'Seçilen uygulamaların bildirimlerini takip etmek için Ayarları aç.', 'Open Settings to follow notifications from selected apps.', ['off', 'checking', 'on', 'unavailable']),
  screen('SP05', 'source-permission', 'Çalışma durumu bildirimi', 'Service status notification', 'Kaynak özelliklerinin çalıştığını görünür tutar.', 'Keeps Source operation visible.', ['not requested', 'granted', 'denied']),
  screen('SP06', 'source-permission', 'Kişi adları', 'Contact names', 'İstersen numaralar yerine kişi adlarını göster.', 'Optionally show contact names instead of numbers.', ['not requested', 'granted', 'skipped', 'denied']),
  screen('SP07', 'source-permission', 'Pil ayarı önerisi', 'Battery setting recommendation', 'Arka plan güvenilirliği için sistem ayarını incele.', 'Review the system setting for background reliability.', ['unknown', 'optimized', 'exempt', 'unavailable']),
  screen('SP08', 'source-permission', 'Otomatik başlatma önerisi', 'Auto-start recommendation', 'Desteklenen cihazlarda yeniden başlatma sonrası çalışmayı iyileştir.', 'Improve operation after restart on supported devices.', ['available', 'enabled', 'unavailable']),
  screen('SP09', 'source-permission', 'İzin özeti', 'Permission summary', 'Her özelliğin etkin, kısıtlı veya kapalı durumunu gör.', 'See whether each capability is active, limited, or off.', ['all active', 'partial', 'needs attention']),

  screen('M01', 'main-app', 'Gelen Kutusu', 'Inbox', 'Tüm Kaynaklardan gelen birleşik etkinlik akışı.', 'A combined activity feed from all Sources.', ['loading', 'populated', 'empty', 'cached', 'failed']),
  screen('M02', 'main-app', 'Gelen Kutusu filtreleri', 'Inbox filters', 'Etkinlik türüne veya Kaynak Telefona göre filtrele.', 'Filter by event type or Source Phone.', ['all', 'one Source', 'no Sources']),
  screen('M03', 'main-app', 'Gelen Kutusu sayfalama', 'Inbox pagination', 'Listenin altındaki yükleme, hata ve son durumları.', 'Loading, retry, and end states at the bottom of the list.', ['loading more', 'retry', 'end']),
  screen('M04', 'main-app', 'Arama ayrıntısı', 'Call details', 'Kaynak, kişi, zaman, süre ve geçerli eylemleri göster.', 'Show Source, identity, time, duration, and valid actions.', ['ringing', 'answered', 'missed', 'ended', 'stale action']),
  screen('M05', 'main-app', 'SMS konuşmaları', 'SMS conversations', 'Kaynak Telefonlara göre konuşma listesini göster.', 'Show conversations scoped to Source Phones.', ['loading', 'populated', 'empty', 'failed']),
  screen('M06', 'main-app', 'SMS konuşması', 'SMS conversation', 'Mesajları görüntüle, eski içerikleri yükle ve yanıtla.', 'View messages, load older content, and reply.', ['populated', 'loading older', 'retry', 'new-message chip']),
  screen('M07', 'main-app', 'Mesaj gönderim durumu', 'Message delivery state', 'Her mesajın gönderim sonucunu açıkça göster.', 'Clearly show each message delivery result.', ['sending', 'queued', 'sent', 'failed', 'expired']),
  screen('M08', 'main-app', 'Bildirim ayrıntısı', 'Notification details', 'Kaynak, uygulama, zaman, içerik ve yanıt durumunu göster.', 'Show Source, app, time, content, and reply state.', ['reply supported', 'view only', 'hidden content']),
  screen('M09', 'main-app', 'Cihazlar', 'Devices', 'Bağlı Kaynak Telefonları ve alınan kapasite durumunu göster.', 'Show connected Source Phones and received capacity status.', ['0', '1–4', '5 of 5', 'unavailable']),
  screen('M10', 'main-app', 'Kaynak Telefon ayrıntısı', 'Source Phone details', 'Özellik durumu, son etkinlik ve bağlantı yönetimi.', 'Capability status, last activity, and connection management.', ['healthy', 'limited', 'inactive']),
  screen('M11', 'main-app', 'Kaynak bağlantısını kaldır', 'Remove Source connection', 'Bağlantıyı kaldırmadan önce sonuçları onayla.', 'Confirm consequences before removing the connection.', ['default', 'processing', 'failed']),

  screen('S01', 'source-app', 'Kaynak durumu', 'Source status', 'Koruma özetini ve Ana Telefon bağlantısını göster.', 'Show the protection summary and Main Phone connection.', ['active', 'needs attention', 'paused', 'disconnected']),
  screen('S02', 'source-app', 'Özellik durumları', 'Capability status', 'Arama, SMS, uygulama, servis ve kişi durumlarını göster.', 'Show call, SMS, app, service, and contact status.', ['all active', 'mixed', 'unavailable']),
  screen('S03', 'source-app', 'Dikkat gerekiyor', 'Attention needed', 'Eksik özellikleri ve çözüm eylemlerini listele.', 'List missing capabilities and recovery actions.', ['one', 'several']),
  screen('S04', 'source-app', 'Gizlilik', 'Privacy', 'Paylaşım kategorilerini ve geçerli seçimleri göster.', 'Show sharing categories and current choices.', ['default', 'paused']),
  screen('S05', 'source-app', 'Seçili uygulamalar', 'Selected apps', 'Takip edilecek uygulamaları ara ve seç.', 'Search and select apps to follow.', ['loading', 'populated', 'empty search', 'failed']),
  screen('S06', 'source-app', 'İçerik gizliliği', 'Content privacy', 'Bildirim önizlemelerini ve hassas içeriği yönet.', 'Manage notification previews and sensitive content.'),
  screen('S07', 'source-app', 'İletimi duraklat', 'Pause forwarding', 'Eşleştirmeyi bozmadan geçici olarak duraklat.', 'Pause temporarily without breaking the connection.', ['select duration', 'active pause', 'resume']),
  screen('S08', 'source-app', 'Ana Telefon bilgisi', 'Main Phone information', 'Bağlı Ana Telefonu ve bağlantı kaldırma eylemini göster.', 'Show the connected Main Phone and removal action.', ['connected', 'unavailable']),

  screen('MS01', 'main-settings', 'Ana Telefon ayarları', 'Main Phone settings', 'Ana Telefona ait tercih ve hesap işlemleri.', 'Preferences and account actions for the Main Phone.'),
  screen('MS02', 'main-settings', 'Bildirim tercihleri', 'Notification preferences', 'Etkinlik türü bildirimlerini ve sistem iznini yönet.', 'Manage event notifications and system permission.'),
  screen('MS03', 'main-settings', 'Gizlilik ve görünüm', 'Privacy and appearance', 'Önizleme görünürlüğünü ve desteklenen görünüm tercihlerini seç.', 'Choose preview visibility and supported appearance preferences.'),
  screen('MS04', 'main-settings', 'Depolama ve geçmiş', 'Storage and history', 'Yerel geçmiş özetini gör ve güvenle temizle.', 'Review local history and clear it safely.'),
  screen('MS05', 'main-settings', 'Hesap ve güvenlik', 'Account and security', 'Doğrulanmış e-posta, oturumlar, parola ve Ana değişimi.', 'Verified email, sessions, password, and Main replacement.'),
  screen('MS06', 'main-settings', 'Dil', 'Language', 'Türkçe veya İngilizce seç.', 'Choose Turkish or English.'),
  screen('MS07', 'main-settings', 'Güncellemeleri kontrol et', 'Check for updates', 'Mevcut sürüm durumunu isteğe bağlı olarak kontrol et.', 'Check the current version status without blocking use.'),
  screen('MS08', 'main-settings', 'Gelişmiş tanılama', 'Advanced diagnostics', 'Okunabilir mobil durum ve kopyalanabilir rapor.', 'Readable mobile status and a copyable report.'),
  screen('MS09', 'main-settings', 'Çıkış yap', 'Sign out', 'Bu telefondaki yerel sonuçları açıklayıp onay iste.', 'Explain local consequences on this phone and confirm.'),

  screen('SS01', 'source-settings', 'Kaynak Telefon ayarları', 'Source Phone settings', 'Kaynak Telefona ait bağlantı, izin ve uygulama tercihleri.', 'Connection, permission, and app preferences for the Source Phone.'),
  screen('SS02', 'source-settings', 'Android izinleri', 'Android permissions', 'Özellik gruplarının durumunu ve Ayarlar eylemlerini göster.', 'Show feature-group status and Settings actions.'),
  screen('SS03', 'source-settings', 'Güvenilirlik ayarları', 'Reliability settings', 'Pil ve otomatik başlatma durumlarını birlikte yönet.', 'Manage battery and auto-start status together.'),
  screen('SS04', 'source-settings', 'Depolama ve geçmiş', 'Storage and history', 'Yerel depolama özetini gör ve güvenle temizle.', 'Review local storage and clear it safely.'),
  screen('SS05', 'source-settings', 'Dil', 'Language', 'Türkçe veya İngilizce seç.', 'Choose Turkish or English.'),
  screen('SS06', 'source-settings', 'Güncellemeleri kontrol et', 'Check for updates', 'Mevcut sürüm durumunu isteğe bağlı olarak kontrol et.', 'Check the current version status without blocking use.'),
  screen('SS07', 'source-settings', 'Gelişmiş tanılama', 'Advanced diagnostics', 'Kaynak özellikleri ve izinler için okunabilir durum raporu.', 'A readable status report for Source capabilities and permissions.'),
  screen('SS08', 'source-settings', 'Bağlantıyı kaldır', 'Remove connection', 'Güvenlik uyarısını ve yeniden doğrulama yolunu göster.', 'Show the security warning and reauthentication path.'),
  screen('SS09', 'source-settings', 'Çıkış yap', 'Sign out', 'Çıkışın Kaynak çalışmasına etkisini açıklayıp onay iste.', 'Explain the effect on Source operation and confirm.'),

  screen('X01', 'shared', 'Kısa bildirim', 'Snackbar', 'Başarı, bilgi ve eylemli uyarı örnekleri.', 'Success, neutral, and actionable warning examples.', ['success', 'neutral', 'warning with action']),
  screen('X02', 'shared', 'Kalıcı uyarı', 'Persistent banner', 'İçeriği koruyan çevrimdışı, dikkat ve güncelleme uyarıları.', 'Offline, attention, and update banners that preserve content.', ['offline/cached', 'needs attention', 'update available']),
  screen('X03', 'shared', 'Satır içi hata', 'Inline error row', 'Tekrar dene, Ayarları aç ve kullanılamıyor durumları.', 'Retry, open Settings, and unavailable states.', ['retry', 'settings action', 'unavailable']),
  screen('X04', 'shared', 'Boş durum', 'Empty state', 'Veri olmadığında anlamlı açıklama ve tek sonraki eylem.', 'A useful explanation and one next action when data is empty.', ['no events', 'no Sources', 'no selected apps', 'no search results']),
  screen('X05', 'shared', 'Tam sayfa hata', 'Full-page error', 'Devam edilemeyen durumlarda açık çözüm yolu.', 'A clear recovery path when progress is blocked.', ['authentication required', 'content unavailable', 'unsupported capability']),
  screen('X06', 'shared', 'Onay iletişim kutusu', 'Confirmation dialog', 'Normal, yıkıcı ve güvenlik hassasiyetli onay örnekleri.', 'Normal, destructive, and security-sensitive confirmations.', ['normal', 'destructive', 'security-sensitive']),
  screen('X07', 'shared', 'Yeniden doğrulama', 'Reauthentication sheet', 'Kritik işlem için parola doğrulama alt sayfası.', 'Password confirmation sheet for a critical action.', ['default', 'submitting', 'failed']),
  screen('X08', 'shared', 'Yükleme iskeletleri', 'Skeleton set', 'Form, etkinlik, cihaz ve konuşma iskeletleri.', 'Form, event, device, and conversation skeletons.', ['form', 'event rows', 'device rows', 'conversation rows']),
];

export const screenById = new Map(screens.map((item) => [item.id, item]));

export const groupLabels: Record<ScreenGroup, LocalizedText> = {
  account: { tr: 'Hesap ve başlangıç', en: 'Account and startup' },
  role: { tr: 'Rol ve Ana güvenliği', en: 'Role and Main security' },
  pairing: { tr: 'Eşleştirme', en: 'Pairing' },
  'main-permission': { tr: 'Ana Telefon izinleri', en: 'Main Phone permissions' },
  'source-permission': { tr: 'Kaynak Telefon izinleri', en: 'Source Phone permissions' },
  'main-app': { tr: 'Ana Telefon uygulaması', en: 'Main Phone app' },
  'source-app': { tr: 'Kaynak Telefon uygulaması', en: 'Source Phone app' },
  'main-settings': { tr: 'Ana Telefon ayarları', en: 'Main Phone settings' },
  'source-settings': { tr: 'Kaynak Telefon ayarları', en: 'Source Phone settings' },
  shared: { tr: 'Ortak durum bileşenleri', en: 'Shared state components' },
};

export const variantKey = (variant: string): string =>
  variant
    .normalize('NFKD')
    .replace(/[–—]/g, '-')
    .replace(/[^a-zA-Z0-9]+/g, '-')
    .replace(/^-|-$/g, '')
    .toLowerCase();
