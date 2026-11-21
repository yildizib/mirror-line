# MirrorLine

*End-to-end encrypted call, SMS, and notification mirroring between Android phones.*

Mevcut uygulama iki telefonu yerel ağ veya VPN üzerinden doğrudan bağlar. Repo,
bu davranışı koruyan mobil uygulama ile gelecekteki güvenilir relay altyapısının
sunucu iskeletini birlikte barındırır; relay ürün API'leri henüz uygulanmamıştır.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

**Diller:** Türkçe (bu bölüm) · [English](#english)

## Kullanım Senaryosu

Türkiye'de yurt dışından getirilen telefonlar, IMEI kaydı yapılmadan yalnızca
sınırlı bir süre (takvim yılı içinde 120 gün) mobil şebekeye bağlanabilir; süre
dolduğunda cihazın arama, SMS ve mobil veri erişimi kesilir — yalnızca Wi-Fi
çalışmaya devam eder. Yaygın çözüm: SIM'leri yurt içi (kayıtlı) pahalı olmayan
ikinci bir telefona takmak. Ama bu kez de asıl telefonunuz aramaları, SMS'leri
ve bildirimleri kaçırır.

MirrorLine bu iki telefonu tek bir kullanıcı deneyiminde birleştirir: SIM'li
kayıtlı telefon (Source) sadece arka planda hattı taşır; siz her şeyi kendi
telefonunuzdan (Main) görürsünüz — aramalar, mesajlar, bildirimler. Mevcut LAN
transportu ile iki telefon aynı WiFi'a bağlıyken doğrudan konuşabilir.

## Repo Yapısı

- `apps/mobile`: Main ve Source rollerini içeren Flutter uygulaması
- `apps/server`: Kotlin/Spring Boot operasyonel sunucu iskeleti
- `packages/contracts`: Paylaşılan protokol sözleşmeleri için alan
- `infra/vps`: Docker Compose ve Caddy tabanlı VPS çalışma modeli

## Lisans

[Apache License 2.0](LICENSE).

---

*Bu proje geliştirilirken Ollama Cloud, OpenCode ve Claude Code kullanılmıştır.*

<br>

---

<a id="english"></a>

# MirrorLine (English)

**Languages:** [Türkçe](#mirrorline) · English (this section)

The current application provides end-to-end encrypted call, SMS, and
notification mirroring over direct LAN or VPN connections. This repository also
contains the operational skeleton for a future reliable relay; relay product
APIs are not implemented yet.

[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)

## Use Case

In Turkey, phones brought from abroad can only connect to the mobile network
for a limited period (120 days within a calendar year) without an IMEI
registration; once that expires, the device loses calls, SMS, and mobile data —
only Wi-Fi keeps working. A common workaround is putting the SIMs into a cheap,
locally-registered second phone — but then your main phone misses the calls,
texts, and notifications.

MirrorLine fuses those two phones into one experience: the SIM-holding,
registered phone (Source) simply carries the line in the background, while you
see everything on your own phone (Main) — calls, messages, notifications. The
current LAN transport lets the two phones talk directly over the same Wi-Fi
network.

## Repository layout

- `apps/mobile`: Flutter application containing both Main and Source roles
- `apps/server`: Kotlin/Spring Boot operational server skeleton
- `packages/contracts`: home for shared protocol contracts
- `infra/vps`: Docker Compose and Caddy VPS runtime model

## License

[Apache License 2.0](LICENSE).

---

*This project was built with the help of Ollama Cloud, OpenCode, and Claude Code.*
