import {
  ArrowLeft,
  ArrowRight,
  Bell,
  BellRinging,
  CaretRight,
  Check,
  CheckCircle,
  CircleNotch,
  Clock,
  DeviceMobile,
  Devices,
  Envelope,
  Eye,
  EyeSlash,
  Gear,
  Globe,
  House,
  Info,
  Key,
  ListChecks,
  LockKey,
  MagnifyingGlass,
  Phone,
  Plus,
  QrCode,
  ShieldCheck,
  SignIn,
  SignOut,
  SlidersHorizontal,
  Trash,
  UserCircle,
  Warning,
  WifiSlash,
} from '@phosphor-icons/react';
import { useEffect, useMemo, useState, type ReactNode } from 'react';
import {
  groupLabels,
  screenById,
  screens,
  variantKey,
  type Locale,
  type LocalizedText,
  type ScreenDefinition,
} from './screens';

type Route =
  | { kind: 'gallery'; locale: Locale }
  | { kind: 'screen'; id: string; variant: string; locale: Locale; capture: boolean };

const t = (value: LocalizedText, locale: Locale): string => value[locale];

const copy = (locale: Locale, tr: string, en: string): string =>
  locale === 'tr' ? tr : en;

const parseRoute = (): Route => {
  const raw = window.location.hash.slice(1) || '/gallery';
  const [path, query = ''] = raw.split('?');
  const params = new URLSearchParams(query);
  const locale = params.get('locale') === 'en' ? 'en' : 'tr';
  const match = path.match(/^\/screen\/([A-Z]+\d{2})$/);
  if (!match) return { kind: 'gallery', locale };
  const definition = screenById.get(match[1]);
  return {
    kind: 'screen',
    id: match[1],
    variant: params.get('variant') || definition?.variants[0] || 'default',
    locale,
    capture: params.get('capture') === '1',
  };
};

const makeScreenHash = (
  id: string,
  variant: string,
  locale: Locale,
  capture = false,
): string => {
  const params = new URLSearchParams({ variant, locale });
  if (capture) params.set('capture', '1');
  return `#/screen/${id}?${params.toString()}`;
};

const useRoute = (): Route => {
  const [route, setRoute] = useState<Route>(parseRoute);
  useEffect(() => {
    const onHashChange = () => setRoute(parseRoute());
    window.addEventListener('hashchange', onHashChange);
    return () => window.removeEventListener('hashchange', onHashChange);
  }, []);
  return route;
};

export function App() {
  const route = useRoute();
  return route.kind === 'gallery' ? (
    <Gallery locale={route.locale} />
  ) : (
    <ScreenRoute route={route} />
  );
}

function Gallery({ locale }: { locale: Locale }) {
  const [query, setQuery] = useState('');
  const [group, setGroup] = useState('all');
  const filtered = useMemo(
    () =>
      screens.filter((item) => {
        const matchesQuery = `${item.id} ${t(item.title, locale)}`
          .toLocaleLowerCase(locale === 'tr' ? 'tr-TR' : 'en-US')
          .includes(query.toLocaleLowerCase(locale === 'tr' ? 'tr-TR' : 'en-US'));
        return matchesQuery && (group === 'all' || item.group === group);
      }),
    [group, locale, query],
  );

  return (
    <main className="gallery-shell">
      <header className="gallery-header">
        <div>
          <span className="eyebrow">MirrorLine</span>
          <h1>{copy(locale, 'Mobil wireframe galerisi', 'Mobile wireframe gallery')}</h1>
          <p>
            {copy(
              locale,
              '90 ekran kimliği, zorunlu durumlar ve rol bazlı akışlar.',
              '90 screen IDs, required states, and role-based flows.',
            )}
          </p>
        </div>
        <LocaleSwitch locale={locale} gallery />
      </header>
      <section className="gallery-controls" aria-label={copy(locale, 'Galeri filtreleri', 'Gallery filters')}>
        <label className="search-field">
          <MagnifyingGlass size={22} aria-hidden="true" />
          <span className="sr-only">{copy(locale, 'Ekran ara', 'Search screens')}</span>
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder={copy(locale, 'Kimlik veya ekran adı ara', 'Search ID or screen name')}
          />
        </label>
        <label className="filter-field">
          <span>{copy(locale, 'Grup', 'Group')}</span>
          <select value={group} onChange={(event) => setGroup(event.target.value)}>
            <option value="all">{copy(locale, 'Tümü', 'All')}</option>
            {Object.entries(groupLabels).map(([key, label]) => (
              <option key={key} value={key}>
                {t(label, locale)}
              </option>
            ))}
          </select>
        </label>
      </section>
      <section className="screen-grid" aria-live="polite">
        {filtered.map((item) => (
          <article className="screen-tile" key={item.id}>
            <div className="tile-meta">
              <span className="id-chip">{item.id}</span>
              <span>{t(groupLabels[item.group], locale)}</span>
            </div>
            <h2>{t(item.title, locale)}</h2>
            <p>{t(item.summary, locale)}</p>
            <div className="tile-footer">
              <span>
                {item.variants.length} {copy(locale, 'durum', 'state')}
              </span>
              <a href={makeScreenHash(item.id, item.variants[0], locale)}>
                {copy(locale, 'Ekranı aç', 'Open screen')}
                <ArrowRight size={20} aria-hidden="true" />
              </a>
            </div>
          </article>
        ))}
      </section>
    </main>
  );
}

function LocaleSwitch({ locale, gallery = false }: { locale: Locale; gallery?: boolean }) {
  const other: Locale = locale === 'tr' ? 'en' : 'tr';
  const href = gallery ? `#/gallery?locale=${other}` : undefined;
  return (
    <a className="locale-switch" href={href} aria-label={copy(locale, 'Dili değiştir', 'Change language')}>
      <Globe size={20} aria-hidden="true" />
      {other.toUpperCase()}
    </a>
  );
}

function ScreenRoute({ route }: { route: Extract<Route, { kind: 'screen' }> }) {
  const definition = screenById.get(route.id);
  if (!definition) return <NotFound locale={route.locale} />;
  const variant = definition.variants.includes(route.variant)
    ? route.variant
    : definition.variants[0];
  const change = (next: Partial<{ id: string; variant: string; locale: Locale }>) => {
    const id = next.id || definition.id;
    const nextDefinition = screenById.get(id) || definition;
    window.location.hash = makeScreenHash(
      id,
      next.variant || nextDefinition.variants[0],
      next.locale || route.locale,
      route.capture,
    ).slice(1);
  };

  return (
    <div className={route.capture ? 'capture-shell' : 'preview-shell'}>
      {!route.capture && (
        <aside className="preview-toolbar">
          <a href={`#/gallery?locale=${route.locale}`}>
            <ArrowLeft size={20} aria-hidden="true" />
            {copy(route.locale, 'Galeri', 'Gallery')}
          </a>
          <label>
            <span>{copy(route.locale, 'Ekran', 'Screen')}</span>
            <select value={definition.id} onChange={(event) => change({ id: event.target.value })}>
              {screens.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.id} · {t(item.title, route.locale)}
                </option>
              ))}
            </select>
          </label>
          <label>
            <span>{copy(route.locale, 'Durum', 'State')}</span>
            <select value={variant} onChange={(event) => change({ variant: event.target.value })}>
              {definition.variants.map((item) => (
                <option key={item} value={item}>
                  {humanizeVariant(item, route.locale)}
                </option>
              ))}
            </select>
          </label>
          <button onClick={() => change({ locale: route.locale === 'tr' ? 'en' : 'tr' })}>
            <Globe size={20} aria-hidden="true" />
            {route.locale === 'tr' ? 'EN' : 'TR'}
          </button>
        </aside>
      )}
      <div className="device-viewport" data-screen-id={definition.id} data-variant={variant}>
        <MobileScreen
          definition={definition}
          locale={route.locale}
          variant={variant}
          navigate={change}
        />
      </div>
    </div>
  );
}

function NotFound({ locale }: { locale: Locale }) {
  return (
    <main className="not-found">
      <Warning size={40} aria-hidden="true" />
      <h1>{copy(locale, 'Ekran bulunamadı', 'Screen not found')}</h1>
      <a href={`#/gallery?locale=${locale}`}>{copy(locale, 'Galeriye dön', 'Return to gallery')}</a>
    </main>
  );
}

interface MobileScreenProps {
  definition: ScreenDefinition;
  locale: Locale;
  variant: string;
  navigate: (next: Partial<{ id: string; variant: string; locale: Locale }>) => void;
}

function MobileScreen(props: MobileScreenProps) {
  const { definition, locale, variant } = props;
  const showBack = definition.id !== 'A01' && definition.id !== 'A02';
  const hasBottomNav = ['main-app', 'main-settings', 'source-app', 'source-settings'].includes(
    definition.group,
  );
  return (
    <div className="mobile-screen">
      <header className="mobile-app-bar">
        {showBack ? (
          <button
            className="icon-button"
            type="button"
            aria-label={copy(locale, 'Geri', 'Back')}
            onClick={() => window.history.back()}
          >
            <ArrowLeft size={24} aria-hidden="true" />
          </button>
        ) : (
          <BrandMark compact />
        )}
        <div className="app-bar-title">
          <strong>{t(definition.title, locale)}</strong>
          <span>{t(groupLabels[definition.group], locale)}</span>
        </div>
        <button
          className="icon-button"
          type="button"
          aria-label={copy(locale, 'Dili değiştir', 'Change language')}
          onClick={() => props.navigate({ locale: locale === 'tr' ? 'en' : 'tr' })}
        >
          <Globe size={22} aria-hidden="true" />
        </button>
      </header>
      <main className="mobile-content" tabIndex={-1}>
        <StateNotice variant={variant} locale={locale} id={definition.id} />
        <ScreenBody {...props} />
      </main>
      {hasBottomNav && <BottomNav definition={definition} locale={locale} navigate={props.navigate} />}
    </div>
  );
}

function BrandMark({ compact = false }: { compact?: boolean }) {
  return (
    <span className={compact ? 'brand-mark compact' : 'brand-mark'} aria-label="MirrorLine">
      <span className="brand-symbol" aria-hidden="true">
        <Devices size={compact ? 20 : 26} weight="bold" />
      </span>
      {!compact && <strong>MirrorLine</strong>}
    </span>
  );
}

function StateNotice({ variant, locale, id }: { variant: string; locale: Locale; id: string }) {
  if (['default', 'populated', 'active', 'Main', 'Source', 'connected', 'visible'].includes(variant)) {
    return null;
  }
  const key = variantKey(variant);
  const loading = /(loading|submitting|checking|processing|refreshing|slow-startup)/.test(key);
  const danger = /(failed|wrong|invalid|expired|rejected|timed-out|unavailable)/.test(key);
  const warning = /(offline|denied|attention|cached|quota|limited|paused|permanently)/.test(key);
  const success = /(success|verified|granted|complete|current|enabled|sent|healthy|on|exempt)/.test(key);
  const tone = danger ? 'danger' : warning ? 'warning' : success ? 'success' : 'neutral';
  return (
    <div className={`state-notice ${tone}`} role={danger ? 'alert' : 'status'} data-state={key}>
      {loading ? (
        <CircleNotch size={21} className="spin" aria-hidden="true" />
      ) : danger ? (
        <Warning size={21} aria-hidden="true" />
      ) : warning ? (
        <Info size={21} aria-hidden="true" />
      ) : (
        <CheckCircle size={21} aria-hidden="true" />
      )}
      <div>
        <strong>{humanizeVariant(variant, locale)}</strong>
        <span>{stateExplanation(id, variant, locale)}</span>
      </div>
    </div>
  );
}

function humanizeVariant(variant: string, locale: Locale): string {
  const translations: Record<string, string> = {
    default: 'Varsayılan',
    submitting: 'Gönderiliyor',
    'wrong credentials': 'Bilgiler yanlış',
    offline: 'Çevrimdışı',
    'validation errors': 'Doğrulama hataları',
    'email exists': 'E-posta kullanımda',
    pending: 'Bekliyor',
    cooldown: 'Yeniden gönderme bekliyor',
    expired: 'Süresi doldu',
    verified: 'Doğrulandı',
    'resend failed': 'Yeniden gönderilemedi',
    checking: 'Kontrol ediliyor',
    failed: 'İşlem başarısız',
    granted: 'İzin verildi',
    denied: 'İzin verilmedi',
    'permanently denied': 'Ayarlardan izin gerekli',
    loading: 'Yükleniyor',
    empty: 'İçerik yok',
    cached: 'Önceki içerik gösteriliyor',
    current: 'Güncel',
    available: 'Kullanılabilir',
    success: 'Tamamlandı',
    dismissed: 'Daha sonra',
    'needs attention': 'Dikkat gerekiyor',
    disconnected: 'Bağlantı yok',
    'processing': 'İşleniyor',
  };
  if (locale === 'tr' && translations[variant]) return translations[variant];
  return variant.charAt(0).toUpperCase() + variant.slice(1);
}

function stateExplanation(id: string, variant: string, locale: Locale): string {
  if (variant === 'offline' || variant === 'cached') {
    return copy(locale, 'Mevcut içerik korunur; bağlantı gelince tekrar denenir.', 'Existing content stays visible and retries when connected.');
  }
  if (/denied/.test(variant)) {
    return copy(locale, 'Kurulum devam eder; yalnızca ilgili özellik kısıtlanır.', 'Setup continues; only the related capability is limited.');
  }
  if (id === 'A10' && variant === 'dismissed') {
    return copy(locale, 'Bu sürüm tekrar önerilmeyecek.', 'This version will not be offered again.');
  }
  if (/loading|submitting|checking|processing|refreshing/.test(variant)) {
    return copy(locale, 'İşlem sürerken bilgiler ve önceki içerik korunur.', 'Values and existing content remain while the action continues.');
  }
  return copy(locale, 'Bu durum için açık bir sonraki adım sunulur.', 'A clear next step is provided for this state.');
}

function ScreenBody(props: MobileScreenProps) {
  const { definition } = props;
  if (definition.group === 'account') return <AccountBody {...props} />;
  if (definition.group === 'role') return <RoleBody {...props} />;
  if (definition.group === 'pairing') return <PairingBody {...props} />;
  if (definition.group === 'main-permission' || definition.group === 'source-permission') {
    return <PermissionBody {...props} />;
  }
  if (definition.group === 'main-app') return <MainAppBody {...props} />;
  if (definition.group === 'source-app') return <SourceAppBody {...props} />;
  if (definition.group === 'main-settings' || definition.group === 'source-settings') {
    return <SettingsBody {...props} />;
  }
  return <SharedBody {...props} />;
}

function Intro({ icon, title, summary }: { icon: ReactNode; title: string; summary: string }) {
  return (
    <section className="screen-intro">
      <div className="intro-icon" aria-hidden="true">{icon}</div>
      <div>
        <h1>{title}</h1>
        <p>{summary}</p>
      </div>
    </section>
  );
}

function Card({ title, children, tone = 'plain' }: { title?: string; children: ReactNode; tone?: string }) {
  return (
    <section className={`card ${tone}`}>
      {title && <h2>{title}</h2>}
      {children}
    </section>
  );
}

function Row({ icon, title, description, trailing }: { icon: ReactNode; title: string; description?: string; trailing?: ReactNode }) {
  return (
    <div className="data-row">
      <span className="row-icon" aria-hidden="true">{icon}</span>
      <span className="row-copy">
        <strong>{title}</strong>
        {description && <span>{description}</span>}
      </span>
      {trailing && <span className="row-trailing">{trailing}</span>}
    </div>
  );
}

function Button({ children, onClick, kind = 'primary', icon }: { children: ReactNode; onClick?: () => void; kind?: 'primary' | 'secondary' | 'danger' | 'ghost'; icon?: ReactNode }) {
  return (
    <button className={`button ${kind}`} type="button" onClick={onClick}>
      {icon}
      <span>{children}</span>
    </button>
  );
}

function TextField({ label, type = 'text', error, placeholder }: { label: string; type?: string; error?: string; placeholder?: string }) {
  return (
    <label className="text-field">
      <span>{label}</span>
      <span className={`input-shell ${error ? 'has-error' : ''}`}>
        <input type={type} placeholder={placeholder} aria-invalid={Boolean(error)} />
        {type === 'password' && <Eye size={22} aria-hidden="true" />}
      </span>
      {error && <small role="alert">{error}</small>}
    </label>
  );
}

function AccountBody(props: MobileScreenProps) {
  const { definition, locale, variant, navigate } = props;
  if (definition.id === 'A01') {
    return (
      <div className="center-stack launch-state">
        <BrandMark />
        <CircleNotch size={28} className="spin" aria-hidden="true" />
        <p>{t(definition.summary, locale)}</p>
      </div>
    );
  }
  if (definition.id === 'A02') {
    return (
      <>
        <Intro icon={<Devices size={32} />} title={t(definition.title, locale)} summary={t(definition.summary, locale)} />
        <Card>
          <Row icon={<House size={22} />} title={copy(locale, 'Ana Telefon', 'Main Phone')} description={copy(locale, 'Tüm Kaynaklardan gelen etkinlikleri gör.', 'See activity from all Sources.')} />
          <Row icon={<DeviceMobile size={22} />} title={copy(locale, 'Kaynak Telefon', 'Source Phone')} description={copy(locale, 'Bu telefondaki seçili etkinlikleri paylaş.', 'Share selected activity from this phone.')} />
        </Card>
        <div className="action-stack">
          <Button icon={<SignIn size={21} />} onClick={() => navigate({ id: 'A03' })}>{copy(locale, 'Giriş yap', 'Sign in')}</Button>
          <Button kind="secondary" onClick={() => navigate({ id: 'A04' })}>{copy(locale, 'Hesap oluştur', 'Create account')}</Button>
        </div>
      </>
    );
  }
  if (definition.id === 'A10') {
    return (
      <>
        <Intro icon={<BellRinging size={32} />} title={t(definition.title, locale)} summary={t(definition.summary, locale)} />
        <Card title={copy(locale, 'Sürüm 2.5.0', 'Version 2.5.0')}>
          <p>{copy(locale, 'Kararlılık ve erişilebilirlik iyileştirmeleri içerir.', 'Includes stability and accessibility improvements.')}</p>
        </Card>
        <div className="action-stack">
          <Button>{copy(locale, 'Güncelle', 'Update')}</Button>
          <Button kind="secondary" onClick={() => navigate({ variant: 'dismissed' })}>{copy(locale, 'Daha sonra', 'Later')}</Button>
        </div>
      </>
    );
  }
  if (definition.id === 'A11') {
    return (
      <>
        <Intro icon={<Bell size={32} />} title={t(definition.title, locale)} summary={t(definition.summary, locale)} />
        <Card>
          <Row icon={<Info size={22} />} title={copy(locale, 'Yüklü sürüm', 'Installed version')} trailing="2.4.1" />
          <Row icon={<CheckCircle size={22} />} title={copy(locale, 'Kullanılabilir sürüm', 'Available version')} trailing={variant === 'current' ? '2.4.1' : '2.5.0'} />
        </Card>
        <div className="action-stack">
          {variant === 'available' && <Button>{copy(locale, 'Güncelle', 'Update')}</Button>}
          <Button kind="secondary">{copy(locale, 'Daha sonra', 'Later')}</Button>
        </div>
      </>
    );
  }
  const isVerify = definition.id === 'A05' || definition.id === 'A08';
  const isPassword = ['A03', 'A04', 'A09'].includes(definition.id);
  const isForm = !isVerify;
  return (
    <>
      <Intro icon={isVerify ? <Envelope size={32} /> : isPassword ? <LockKey size={32} /> : <Key size={32} />} title={t(definition.title, locale)} summary={t(definition.summary, locale)} />
      {isForm ? (
        <form className="form-stack" onSubmit={(event) => event.preventDefault()}>
          {!['A09'].includes(definition.id) && (
            <TextField
              label={copy(locale, 'E-posta', 'Email')}
              placeholder="ornek@alanadi.com"
              error={/invalid|wrong/.test(variant) ? copy(locale, 'Geçerli bilgileri kontrol et.', 'Check the entered information.') : undefined}
            />
          )}
          {isPassword && <TextField label={copy(locale, 'Parola', 'Password')} type="password" />}
          {['A04', 'A09'].includes(definition.id) && <TextField label={copy(locale, 'Parolayı doğrula', 'Confirm password')} type="password" />}
          {['A04', 'A09'].includes(definition.id) && (
            <ul className="requirements">
              <li><Check size={18} />{copy(locale, 'En az 8 karakter', 'At least 8 characters')}</li>
              <li><Check size={18} />{copy(locale, 'Bir harf ve bir rakam', 'One letter and one number')}</li>
            </ul>
          )}
          <Button onClick={() => navigate({ id: definition.id === 'A04' ? 'A05' : definition.id === 'A03' ? 'R01' : definition.id === 'A09' ? 'A03' : 'A08' })}>
            {copy(locale, 'Devam et', 'Continue')}
          </Button>
        </form>
      ) : (
        <>
          <Card>
            <Row icon={<Envelope size={22} />} title="ahmet.yilmaz@example.com" description={copy(locale, 'Doğrulama mesajı gönderildi', 'Verification message sent')} />
          </Card>
          <div className="action-stack">
            <Button onClick={() => navigate({ id: 'R01' })}>{copy(locale, 'Tekrar kontrol et', 'Check again')}</Button>
            <Button kind="secondary" onClick={() => navigate({ id: 'A06' })}>{copy(locale, 'E-postayı değiştir', 'Change email')}</Button>
          </div>
        </>
      )}
    </>
  );
}

function RoleBody({ definition, locale, variant, navigate }: MobileScreenProps) {
  if (definition.id === 'R01') {
    return (
      <>
        <Intro icon={<Devices size={32} />} title={t(definition.title, locale)} summary={t(definition.summary, locale)} />
        <button className="choice-card" onClick={() => navigate({ id: 'R02', variant: 'Main' })}>
          <House size={28} aria-hidden="true" />
          <span><strong>{copy(locale, 'Ana Telefon', 'Main Phone')}</strong><small>{copy(locale, 'Hesapta yalnızca bir tane olabilir.', 'Only one can be active on the account.')}</small></span>
          <CaretRight size={22} aria-hidden="true" />
        </button>
        <button className="choice-card" onClick={() => navigate({ id: 'R02', variant: 'Source' })}>
          <DeviceMobile size={28} aria-hidden="true" />
          <span><strong>{copy(locale, 'Kaynak Telefon', 'Source Phone')}</strong><small>{copy(locale, 'En fazla beş Kaynak bağlanabilir.', 'Up to five Sources can be connected.')}</small></span>
          <CaretRight size={22} aria-hidden="true" />
        </button>
      </>
    );
  }
  const destructive = ['R04', 'R06'].includes(definition.id);
  return (
    <>
      <Intro icon={destructive ? <Warning size={32} /> : <ShieldCheck size={32} />} title={t(definition.title, locale)} summary={t(definition.summary, locale)} />
      {definition.id === 'R05' ? (
        <TextField label={copy(locale, 'Hesap parolası', 'Account password')} type="password" error={variant === 'failed' ? copy(locale, 'Parola doğrulanamadı.', 'Password could not be verified.') : undefined} />
      ) : (
        <Card tone={destructive ? 'warning' : 'plain'}>
          <Row icon={<SignOut size={22} />} title={copy(locale, 'Eski Ana Telefon erişimini kaybeder', 'The old Main Phone loses access')} />
          <Row icon={<Devices size={22} />} title={copy(locale, 'Kaynak bağlantıları kaldırılır', 'Source connections are removed')} />
          <Row icon={<QrCode size={22} />} title={copy(locale, 'Kaynaklar yeniden eşleştirilir', 'Sources must be paired again')} />
        </Card>
      )}
      <div className="action-stack">
        <Button kind={destructive ? 'danger' : 'primary'} onClick={() => navigate({ id: nextRoleScreen(definition.id, variant) })}>
          {definition.id === 'R07' ? copy(locale, 'Kaynak Telefon ekle', 'Add Source Phone') : copy(locale, 'Devam et', 'Continue')}
        </Button>
        {destructive && <Button kind="secondary">{copy(locale, 'Vazgeç', 'Cancel')}</Button>}
      </div>
    </>
  );
}

function nextRoleScreen(id: string, variant: string): string {
  const map: Record<string, string> = { R02: variant === 'Source' ? 'SP01' : 'MP01', R03: 'R04', R04: 'R05', R05: 'R06', R06: 'R07', R07: 'P02' };
  return map[id] || 'R03';
}

function PairingBody({ definition, locale, variant, navigate }: MobileScreenProps) {
  const codeScreen = ['P05', 'P07', 'P09'].includes(definition.id);
  const dangerScreen = ['P03', 'P12', 'P13', 'P14', 'P15'].includes(definition.id);
  return (
    <>
      <Intro icon={codeScreen ? <QrCode size={32} /> : dangerScreen ? <Warning size={32} /> : <Devices size={32} />} title={t(definition.title, locale)} summary={t(definition.summary, locale)} />
      {definition.id === 'P01' || definition.id === 'P03' ? (
        <>
          <Capacity current={variant === '5 of 5' || definition.id === 'P03' ? 5 : variant === '0' ? 0 : 2} locale={locale} />
          <Card>
            <Row icon={<DeviceMobile size={22} />} title="Pixel 7" description={copy(locale, 'Kişisel', 'Personal')} trailing={copy(locale, 'Etkin', 'Active')} />
            <Row icon={<DeviceMobile size={22} />} title="Galaxy A54" description={copy(locale, 'İş', 'Work')} trailing={copy(locale, 'Etkin', 'Active')} />
          </Card>
        </>
      ) : codeScreen ? (
        <Card>
          {definition.id === 'P05' && <div className="qr-placeholder"><QrCode size={146} weight="thin" aria-label={copy(locale, 'Eşleştirme QR kodu', 'Pairing QR code')} /></div>}
          <div className="verification-code" aria-label={copy(locale, 'Doğrulama kodu', 'Verification code')}>749&nbsp;–&nbsp;281</div>
          <p className="center-text">{copy(locale, 'Kod her iki telefonda aynı olmalı.', 'The code must match on both phones.')}</p>
        </Card>
      ) : definition.id === 'P06' ? (
        <div className="scanner-frame" aria-label={copy(locale, 'QR tarama alanı', 'QR scanning area')}>
          <QrCode size={88} aria-hidden="true" />
          <span>{copy(locale, 'QR kodu çerçeveye hizala', 'Align the QR code in the frame')}</span>
        </div>
      ) : definition.id === 'P15' ? (
        <TextField label={copy(locale, 'Hesap parolası', 'Account password')} type="password" />
      ) : (
        <Card tone={dangerScreen ? 'warning' : 'plain'}>
          <Row icon={<DeviceMobile size={22} />} title={copy(locale, 'Kaynak Telefon', 'Source Phone')} description="Galaxy A54 · Android 14" trailing={copy(locale, 'Hazır', 'Ready')} />
          <Row icon={<House size={22} />} title={copy(locale, 'Ana Telefon', 'Main Phone')} description="Pixel 8 Pro" trailing={copy(locale, 'Etkin', 'Active')} />
        </Card>
      )}
      <div className="action-stack">
        <Button kind={dangerScreen && definition.id !== 'P03' ? 'danger' : 'primary'} onClick={() => navigate({ id: nextPairingScreen(definition.id) })}>
          {pairingAction(definition.id, locale)}
        </Button>
        {['P05', 'P06'].includes(definition.id) && <Button kind="secondary" onClick={() => navigate({ id: 'P07' })}>{copy(locale, 'Kısa kod kullan', 'Use short code')}</Button>}
      </div>
    </>
  );
}

function Capacity({ current, locale }: { current: number; locale: Locale }) {
  return (
    <Card title={copy(locale, 'Kaynak kapasitesi', 'Source capacity')}>
      <div className="capacity-line"><strong>{current} / 5</strong><span>{copy(locale, 'Kaynak Telefon', 'Source Phones')}</span></div>
      <div className="capacity-meter" aria-label={`${current} / 5`}><span style={{ width: `${current * 20}%` }} /></div>
      <p>{copy(locale, 'Bu değer hesabın güncel durumundan alınmıştır.', 'This value comes from the current account status.')}</p>
    </Card>
  );
}

function pairingAction(id: string, locale: Locale): string {
  const values: Record<string, LocalizedText> = {
    P03: { tr: 'Cihazları yönet', en: 'Manage devices' }, P05: { tr: 'Kodu yenile', en: 'Refresh code' }, P06: { tr: 'Taramayı başlat', en: 'Start scanning' }, P09: { tr: 'Kodlar eşleşiyor', en: 'Codes match' }, P10: { tr: 'Eşleştirmeyi onayla', en: 'Confirm pairing' }, P13: { tr: 'Mevcut bağlantıyı kaldır', en: 'Remove current connection' }, P14: { tr: 'Bağlantıyı kaldır', en: 'Remove connection' }, P15: { tr: 'Kimliğini doğrula', en: 'Verify identity' }, P16: { tr: 'Yeni eşleştirme başlat', en: 'Start new pairing' },
  };
  return t(values[id] || { tr: 'Devam et', en: 'Continue' }, locale);
}

function nextPairingScreen(id: string): string {
  const map: Record<string, string> = { P01: 'P02', P02: 'P04', P03: 'M09', P04: 'P05', P05: 'P09', P06: 'P09', P07: 'P09', P08: 'P05', P09: 'P10', P10: 'P11', P11: 'SP01', P12: 'P04', P13: 'P14', P14: 'P15', P15: 'P16', P16: 'P06' };
  return map[id] || 'P01';
}

function PermissionBody({ definition, locale, variant, navigate }: MobileScreenProps) {
  const isMain = definition.group === 'main-permission';
  const permissionRows = isMain
    ? [{ title: copy(locale, 'Bildirimler', 'Notifications'), description: copy(locale, 'Yeni etkinliklerden haberdar ol.', 'Stay informed about new activity.') }]
    : [
        { title: copy(locale, 'Arama izleme', 'Call monitoring'), description: copy(locale, 'Arama etkinliklerini gösterir.', 'Shows call activity.') },
        { title: copy(locale, 'SMS', 'SMS'), description: copy(locale, 'Mesajları gösterir ve yanıtlar.', 'Shows messages and supports replies.') },
        { title: copy(locale, 'Uygulama bildirimleri', 'App notifications'), description: copy(locale, 'Yalnız seçilen uygulamaları takip eder.', 'Follows selected apps only.') },
        { title: copy(locale, 'Çalışma bildirimi', 'Service notification'), description: copy(locale, 'Çalışma durumunu görünür tutar.', 'Keeps operation visible.') },
        { title: copy(locale, 'Kişi adları', 'Contact names'), description: copy(locale, 'İsteğe bağlıdır.', 'Optional.') },
      ];
  return (
    <>
      <Intro icon={<Bell size={32} />} title={t(definition.title, locale)} summary={t(definition.summary, locale)} />
      <Card>
        {permissionRows.map((row, index) => (
          <Row key={row.title} icon={index === 0 ? <Phone size={22} /> : <CheckCircle size={22} />} title={row.title} description={row.description} trailing={permissionStatus(variant, index, locale)} />
        ))}
      </Card>
      {!isMain && definition.id === 'SP01' && <p className="support-copy">{copy(locale, 'İzin verilmemesi eşleştirmeyi bozmaz; yalnızca ilgili özellik kapanır.', 'Declining access does not break pairing; only that capability turns off.')}</p>}
      <div className="action-stack">
        <Button onClick={() => navigate({ id: nextPermissionScreen(definition.id) })}>{permissionAction(definition.id, locale)}</Button>
        {!isMain && <Button kind="secondary">{copy(locale, 'Şimdilik atla', 'Skip for now')}</Button>}
      </div>
    </>
  );
}

function permissionStatus(variant: string, index: number, locale: Locale): string {
  if (variant === 'partially complete') {
    return index < 2 ? copy(locale, 'Etkin', 'Active') : copy(locale, 'Bekliyor', 'Pending');
  }
  if (variant.includes('denied')) return copy(locale, 'Kapalı', 'Off');
  if (variant.includes('needs settings')) return copy(locale, 'Ayarlardan aç', 'Open Settings');
  if (variant.includes('unavailable')) return copy(locale, 'Kullanılamıyor', 'Unavailable');
  if (variant.includes('granted') || variant === 'complete') return copy(locale, 'Etkin', 'Active');
  return copy(locale, 'Bekliyor', 'Pending');
}

function nextPermissionScreen(id: string): string {
  const source = ['SP01', 'SP02', 'SP03', 'SP04', 'SP05', 'SP06', 'SP07', 'SP08', 'SP09'];
  const index = source.indexOf(id);
  if (index >= 0) return index === source.length - 1 ? 'S01' : source[index + 1];
  return id === 'MP01' ? 'MP02' : 'M01';
}

function permissionAction(id: string, locale: Locale): string {
  if (['SP04', 'SP07', 'SP08'].includes(id)) return copy(locale, 'Ayarları aç', 'Open Settings');
  if (id === 'SP09' || id === 'MP02') return copy(locale, 'Kurulumu tamamla', 'Finish setup');
  return copy(locale, 'İzin ver ve devam et', 'Allow and continue');
}

function MainAppBody({ definition, locale, variant, navigate }: MobileScreenProps) {
  if (definition.id === 'M09') {
    const current = variant === '0' ? 0 : variant === '5 of 5' ? 5 : 2;
    return (
      <>
        <Capacity current={current} locale={locale} />
        <Card>
          {current === 0 ? <EmptyBlock locale={locale} /> : <DeviceRows locale={locale} />}
        </Card>
        <Button onClick={() => navigate({ id: current === 5 ? 'P03' : 'P02' })} icon={<Plus size={21} />}>{copy(locale, 'Kaynak Telefon ekle', 'Add Source Phone')}</Button>
      </>
    );
  }
  if (definition.id === 'M10') {
    return (
      <>
        <Intro icon={<DeviceMobile size={32} />} title="Pixel 7 · Kişisel" summary={t(definition.summary, locale)} />
        <Card title={copy(locale, 'Özellik durumu', 'Capability status')}><FeatureRows locale={locale} variant={variant === 'healthy' ? 'active' : 'needs attention'} /></Card>
        <Button kind="danger" onClick={() => navigate({ id: 'M11' })}>{copy(locale, 'Bağlantıyı kaldır', 'Remove connection')}</Button>
      </>
    );
  }
  if (definition.id === 'M11') {
    return <ConfirmationContent locale={locale} title={t(definition.title, locale)} onConfirm={() => navigate({ id: 'M09', variant: '0' })} />;
  }
  if (['M04', 'M08'].includes(definition.id)) {
    return (
      <>
        <Intro icon={definition.id === 'M04' ? <Phone size={32} /> : <Bell size={32} />} title={t(definition.title, locale)} summary={t(definition.summary, locale)} />
        <Card>
          <Row icon={<DeviceMobile size={22} />} title={copy(locale, 'Kaynak', 'Source')} trailing="Pixel 7" />
          <Row icon={<Clock size={22} />} title={copy(locale, 'Zaman', 'Time')} trailing="12:45" />
          <Row icon={<Info size={22} />} title={definition.id === 'M04' ? copy(locale, 'Durum', 'Status') : copy(locale, 'Uygulama', 'App')} trailing={definition.id === 'M04' ? humanizeVariant(variant, locale) : 'WhatsApp'} />
        </Card>
        <Button>{definition.id === 'M04' ? copy(locale, 'Bu numarayı ara', 'Call this number') : copy(locale, 'Yanıtla', 'Reply')}</Button>
      </>
    );
  }
  if (definition.id === 'M06' || definition.id === 'M07') {
    return <Conversation locale={locale} variant={variant} />;
  }
  if (definition.id === 'M02') {
    return (
      <Card title={copy(locale, 'Kaynak filtresi', 'Source filter')}>
        <label className="radio-row"><input type="radio" name="source" defaultChecked />{copy(locale, 'Tüm Kaynaklar', 'All Sources')}</label>
        <label className="radio-row"><input type="radio" name="source" />Pixel 7 · {copy(locale, 'Kişisel', 'Personal')}</label>
        <label className="radio-row"><input type="radio" name="source" />Galaxy A54 · {copy(locale, 'İş', 'Work')}</label>
        <Button>{copy(locale, 'Filtreyi uygula', 'Apply filter')}</Button>
      </Card>
    );
  }
  return <Inbox locale={locale} variant={variant} pagination={definition.id === 'M03'} />;
}

function Inbox({ locale, variant, pagination = false }: { locale: Locale; variant: string; pagination?: boolean }) {
  if (variant === 'loading') return <SkeletonRows />;
  if (variant === 'empty') return <EmptyBlock locale={locale} />;
  return (
    <>
      <div className="segmented" role="tablist" aria-label={copy(locale, 'Etkinlik türü', 'Activity type')}>
        <button role="tab" aria-selected="true">{copy(locale, 'Tümü', 'All')}</button>
        <button role="tab">{copy(locale, 'Aramalar', 'Calls')}</button>
        <button role="tab">SMS</button>
      </div>
      <Card>
        <EventRow locale={locale} icon={<Phone size={22} />} title="Ahmet Yılmaz" detail={copy(locale, 'Cevapsız arama', 'Missed call')} source="Pixel 7" />
        <EventRow locale={locale} icon={<Envelope size={22} />} title="Garanti BBVA" detail={copy(locale, 'Doğrulama mesajı', 'Verification message')} source="Galaxy A54" />
        <EventRow locale={locale} icon={<Bell size={22} />} title="WhatsApp" detail={copy(locale, 'Yeni bildirim', 'New notification')} source="Pixel 7" />
      </Card>
      {pagination && <div className="pagination-row">{variant === 'retry' ? <Button kind="secondary">{copy(locale, 'Tekrar dene', 'Retry')}</Button> : variant === 'end' ? copy(locale, 'Listenin sonu', 'End of list') : <><CircleNotch className="spin" size={20} />{copy(locale, 'Daha fazlası yükleniyor', 'Loading more')}</>}</div>}
    </>
  );
}

function EventRow({ icon, title, detail, source, locale }: { icon: ReactNode; title: string; detail: string; source: string; locale: Locale }) {
  return <Row icon={icon} title={title} description={detail} trailing={<span className="source-badge"><DeviceMobile size={16} />{source}<span className="sr-only">{copy(locale, 'Kaynak Telefon', 'Source Phone')}</span></span>} />;
}

function Conversation({ locale, variant }: { locale: Locale; variant: string }) {
  return (
    <>
      <div className="source-context"><DeviceMobile size={20} />Galaxy A54 · {copy(locale, 'İş', 'Work')}</div>
      <div className="conversation">
        <div className="bubble incoming">{copy(locale, 'Merhaba, yarınki toplantı saatini doğrular mısın?', 'Hi, can you confirm tomorrow’s meeting time?')}<time>11:14</time></div>
        <div className="bubble outgoing">{copy(locale, 'Elbette, toplantı saat 14.00’te.', 'Of course, the meeting is at 14:00.')}<time>11:18 · {humanizeVariant(variant, locale)}</time></div>
      </div>
      <label className="composer"><span className="sr-only">{copy(locale, 'SMS yanıtı', 'SMS reply')}</span><input placeholder={copy(locale, 'Yanıt yaz', 'Write a reply')} /><button aria-label={copy(locale, 'Gönder', 'Send')}><ArrowRight size={22} /></button></label>
      <p className="support-copy">{copy(locale, 'Yanıt Galaxy A54 hattı üzerinden gönderilir.', 'The reply is sent through the Galaxy A54 line.')}</p>
    </>
  );
}

function SourceAppBody({ definition, locale, variant, navigate }: MobileScreenProps) {
  if (definition.id === 'S05') {
    return (
      <>
        <label className="search-field"><MagnifyingGlass size={22} /><input placeholder={copy(locale, 'Uygulamalarda ara', 'Search apps')} /></label>
        <Card><ToggleRow title="WhatsApp" checked /><ToggleRow title="Telegram" checked /><ToggleRow title="Gmail" /><ToggleRow title="Slack" checked /></Card>
        <Button>{copy(locale, 'Seçimleri kaydet', 'Save selections')}</Button>
      </>
    );
  }
  if (definition.id === 'S07') {
    return (
      <Card title={t(definition.title, locale)}>
        <label className="radio-row"><input type="radio" name="pause" defaultChecked />{copy(locale, '1 saat', '1 hour')}</label>
        <label className="radio-row"><input type="radio" name="pause" />{copy(locale, '4 saat', '4 hours')}</label>
        <label className="radio-row"><input type="radio" name="pause" />{copy(locale, 'Sabaha kadar', 'Until morning')}</label>
        <Button>{variant === 'resume' ? copy(locale, 'İletimi sürdür', 'Resume forwarding') : copy(locale, 'İletimi duraklat', 'Pause forwarding')}</Button>
      </Card>
    );
  }
  if (definition.id === 'S08') {
    return (
      <>
        <Intro icon={<House size={32} />} title="Pixel 8 Pro" summary={t(definition.summary, locale)} />
        <Card><Row icon={<CheckCircle size={22} />} title={copy(locale, 'Bağlantı durumu', 'Connection status')} trailing={variant === 'unavailable' ? copy(locale, 'Kullanılamıyor', 'Unavailable') : copy(locale, 'Bağlı', 'Connected')} /><Row icon={<Clock size={22} />} title={copy(locale, 'Son bağlantı', 'Last connection')} trailing={copy(locale, 'Az önce', 'Just now')} /></Card>
        <Button kind="danger" onClick={() => navigate({ id: 'SS08' })}>{copy(locale, 'Bağlantıyı kaldır', 'Remove connection')}</Button>
      </>
    );
  }
  if (definition.id === 'S06') {
    return <Card title={t(definition.title, locale)}><ToggleRow title={copy(locale, 'Bildirim önizlemelerini gizle', 'Hide notification previews')} checked /><ToggleRow title={copy(locale, 'Bilinmeyen numaraları maskele', 'Mask unknown numbers')} /></Card>;
  }
  return (
    <>
      <Intro icon={<ShieldCheck size={32} />} title={t(definition.title, locale)} summary={t(definition.summary, locale)} />
      <Card title={copy(locale, 'Özellikler', 'Capabilities')}><FeatureRows locale={locale} variant={variant} /></Card>
      {definition.id === 'S03' && <Button onClick={() => navigate({ id: 'SS02' })}>{copy(locale, 'Eksik izinleri tamamla', 'Complete missing permissions')}</Button>}
    </>
  );
}

function FeatureRows({ locale, variant }: { locale: Locale; variant: string }) {
  const disconnected = variant === 'disconnected' || variant === 'unavailable';
  const paused = variant === 'paused';
  const limited = ['mixed', 'needs attention', 'several'].includes(variant);
  const active = copy(locale, 'Etkin', 'Active');
  const unavailable = copy(locale, 'Kullanılamıyor', 'Unavailable');
  const pausedLabel = copy(locale, 'Duraklatıldı', 'Paused');
  const status = disconnected ? unavailable : paused ? pausedLabel : active;
  return (
    <>
      <Row icon={<Phone size={22} />} title={copy(locale, 'Arama izleme', 'Call monitoring')} trailing={status} />
      <Row icon={<Envelope size={22} />} title="SMS" trailing={limited ? copy(locale, 'Kapalı', 'Off') : status} />
      <Row icon={<Bell size={22} />} title={copy(locale, 'Uygulama bildirimleri', 'App notifications')} trailing={status} />
      <Row icon={<UserCircle size={22} />} title={copy(locale, 'Kişi adları', 'Contact names')} trailing={copy(locale, 'İsteğe bağlı', 'Optional')} />
    </>
  );
}

function SettingsBody({ definition, locale, navigate }: MobileScreenProps) {
  if (definition.id === 'MS01' || definition.id === 'SS01') {
    const isMain = definition.id === 'MS01';
    const rows = isMain
      ? [['MS02', 'Bildirim tercihleri', 'Notification preferences'], ['MS03', 'Gizlilik ve görünüm', 'Privacy and appearance'], ['MS04', 'Depolama ve geçmiş', 'Storage and history'], ['MS06', 'Dil', 'Language'], ['MS07', 'Güncellemeler', 'Updates'], ['MS08', 'Gelişmiş tanılama', 'Advanced diagnostics'], ['MS05', 'Hesap ve güvenlik', 'Account and security'], ['R04', 'Ana Telefonu değiştir', 'Change Main Phone']]
      : [['S08', 'Ana Telefon bilgisi', 'Main Phone information'], ['SS02', 'Android izinleri', 'Android permissions'], ['SS03', 'Güvenilirlik ayarları', 'Reliability settings'], ['S05', 'Seçili uygulamalar', 'Selected apps'], ['SS04', 'Depolama ve geçmiş', 'Storage and history'], ['SS05', 'Dil', 'Language'], ['SS06', 'Güncellemeler', 'Updates'], ['SS07', 'Gelişmiş tanılama', 'Advanced diagnostics']];
    return (
      <>
        <Card>{rows.map(([id, tr, en]) => <button className="settings-row" key={id} onClick={() => navigate({ id })}><span>{copy(locale, tr, en)}</span><CaretRight size={21} /></button>)}</Card>
        <Button kind="danger" onClick={() => navigate({ id: isMain ? 'MS09' : 'SS08' })}>{copy(locale, isMain ? 'Çıkış yap' : 'Bağlantıyı kaldır', isMain ? 'Sign out' : 'Remove connection')}</Button>
        {!isMain && <Button kind="secondary" onClick={() => navigate({ id: 'SS09' })}>{copy(locale, 'Çıkış yap', 'Sign out')}</Button>}
      </>
    );
  }
  if (['MS09', 'SS08', 'SS09'].includes(definition.id)) {
    return <ConfirmationContent locale={locale} title={t(definition.title, locale)} onConfirm={() => navigate({ id: 'A02' })} />;
  }
  if (definition.id === 'MS06' || definition.id === 'SS05') {
    return <Card title={t(definition.title, locale)}><label className="radio-row"><input type="radio" name="language" defaultChecked={locale === 'tr'} />Türkçe</label><label className="radio-row"><input type="radio" name="language" defaultChecked={locale === 'en'} />English</label></Card>;
  }
  if (definition.id === 'MS07' || definition.id === 'SS06') {
    return <AccountBody definition={{ ...definition, id: 'A11' }} locale={locale} variant="current" navigate={navigate} />;
  }
  if (definition.id === 'MS08' || definition.id === 'SS07') {
    return (
      <>
        <Intro icon={<ListChecks size={32} />} title={t(definition.title, locale)} summary={t(definition.summary, locale)} />
        <Card><Row icon={<CheckCircle size={22} />} title={copy(locale, 'Uygulama durumu', 'App status')} trailing={copy(locale, 'Çalışıyor', 'Running')} /><Row icon={<Clock size={22} />} title={copy(locale, 'Son bağlantı', 'Last connection')} trailing={copy(locale, 'Az önce', 'Just now')} /><Row icon={<Bell size={22} />} title={copy(locale, 'Bildirim izni', 'Notification permission')} trailing={copy(locale, 'Etkin', 'Active')} /></Card>
        <Button kind="secondary">{copy(locale, 'Raporu kopyala', 'Copy report')}</Button>
      </>
    );
  }
  return (
    <>
      <Intro icon={<Gear size={32} />} title={t(definition.title, locale)} summary={t(definition.summary, locale)} />
      <Card><ToggleRow title={copy(locale, 'Önizlemeleri göster', 'Show previews')} checked /><ToggleRow title={copy(locale, 'Etkinlik geçmişini koru', 'Keep activity history')} checked /><Row icon={<Info size={22} />} title={copy(locale, 'Yerel kullanım', 'Local usage')} trailing="18.4 MB" /></Card>
      <Button>{copy(locale, 'Değişiklikleri kaydet', 'Save changes')}</Button>
    </>
  );
}

function SharedBody({ definition, locale, variant }: MobileScreenProps) {
  if (definition.id === 'X08') return <SkeletonRows />;
  if (definition.id === 'X04') return <EmptyBlock locale={locale} />;
  if (definition.id === 'X06') return <ConfirmationContent locale={locale} title={t(definition.title, locale)} />;
  if (definition.id === 'X07') return <><Intro icon={<Key size={32} />} title={t(definition.title, locale)} summary={t(definition.summary, locale)} /><TextField label={copy(locale, 'Hesap parolası', 'Account password')} type="password" /><Button>{copy(locale, 'Doğrula', 'Verify')}</Button></>;
  return (
    <>
      <Intro icon={variant.includes('error') ? <Warning size={32} /> : <Info size={32} />} title={t(definition.title, locale)} summary={t(definition.summary, locale)} />
      <Card><Row icon={<Info size={22} />} title={humanizeVariant(variant, locale)} description={stateExplanation(definition.id, variant, locale)} trailing={variant.includes('action') ? <Button kind="ghost">{copy(locale, 'Aç', 'Open')}</Button> : undefined} /></Card>
    </>
  );
}

function ConfirmationContent({ locale, title, onConfirm }: { locale: Locale; title: string; onConfirm?: () => void }) {
  return (
    <div className="dialog-card" role="dialog" aria-labelledby="confirmation-title" aria-modal="true">
      <span className="danger-icon"><Trash size={30} aria-hidden="true" /></span>
      <h1 id="confirmation-title">{title}</h1>
      <p>{copy(locale, 'Bu işlem mevcut bağlantıyı ve bu telefondaki erişimi sonlandırır. Daha sonra yeniden bağlantı kurulabilir.', 'This ends the current connection and access on this phone. A new connection can be created later.')}</p>
      <Button kind="danger" onClick={onConfirm}>{copy(locale, 'Onayla', 'Confirm')}</Button>
      <Button kind="secondary">{copy(locale, 'Vazgeç', 'Cancel')}</Button>
    </div>
  );
}

function DeviceRows({ locale }: { locale: Locale }) {
  return <><Row icon={<DeviceMobile size={22} />} title="Pixel 7" description={copy(locale, 'Kişisel', 'Personal')} trailing={copy(locale, 'Etkin', 'Active')} /><Row icon={<DeviceMobile size={22} />} title="Galaxy A54" description={copy(locale, 'İş', 'Work')} trailing={copy(locale, 'Etkin', 'Active')} /></>;
}

function ToggleRow({ title, checked = false }: { title: string; checked?: boolean }) {
  return <label className="toggle-row"><span>{title}</span><input type="checkbox" defaultChecked={checked} /><span className="toggle" aria-hidden="true" /></label>;
}

function EmptyBlock({ locale }: { locale: Locale }) {
  return <div className="empty-block"><span className="empty-icon"><Info size={30} /></span><h2>{copy(locale, 'Henüz içerik yok', 'Nothing here yet')}</h2><p>{copy(locale, 'İlgili etkinlikler burada görünecek.', 'Relevant activity will appear here.')}</p><Button kind="secondary">{copy(locale, 'Yeniden kontrol et', 'Check again')}</Button></div>;
}

function SkeletonRows() {
  return <div className="skeleton-list" role="status" aria-label="Yükleniyor"><span /><span /><span /><span /></div>;
}

function BottomNav({ definition, locale, navigate }: { definition: ScreenDefinition; locale: Locale; navigate: (next: Partial<{ id: string }>) => void }) {
  const main = definition.group.startsWith('main');
  const items = main
    ? [{ id: 'M01', label: copy(locale, 'Gelen Kutusu', 'Inbox'), icon: <Envelope size={22} /> }, { id: 'M09', label: copy(locale, 'Cihazlar', 'Devices'), icon: <Devices size={22} /> }, { id: 'MS01', label: copy(locale, 'Ayarlar', 'Settings'), icon: <Gear size={22} /> }]
    : [{ id: 'S01', label: copy(locale, 'Durum', 'Status'), icon: <ShieldCheck size={22} /> }, { id: 'S04', label: copy(locale, 'Gizlilik', 'Privacy'), icon: <EyeSlash size={22} /> }, { id: 'SS01', label: copy(locale, 'Ayarlar', 'Settings'), icon: <Gear size={22} /> }];
  return <nav className="bottom-nav" aria-label={copy(locale, 'Ana navigasyon', 'Primary navigation')}>{items.map((item) => <button key={item.id} className={definition.id === item.id ? 'selected' : ''} onClick={() => navigate({ id: item.id })}>{item.icon}<span>{item.label}</span></button>)}</nav>;
}
