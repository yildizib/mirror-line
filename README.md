# MirrorLine

*Serverless, end-to-end encrypted call & SMS mirroring between two Android phones.*

Sunucusuz, uçtan uca şifreli iki Android telefon arası arama ve SMS senkronizasyonu.
Veri hiçbir zaman üçüncü parti bir sunucudan geçmez — iki telefon aynı yerel ağda
doğrudan birbirine bağlanır.

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
telefonunuzdan (Main) görürsünüz — aramalar, mesajlar, bildirimler. İnternete ya
da sunucuya gerek yok, iki telefon aynı WiFi'a bağlı olunca doğrudan konuşur.

## Lisans

[Apache License 2.0](LICENSE).

---

*Bu proje geliştirilirken Ollama Cloud, OpenCode ve Claude Code kullanılmıştır.*

<br>

---

<a id="english"></a>

# MirrorLine (English)

**Languages:** [Türkçe](#mirrorline) · English (this section)

Serverless, end-to-end encrypted call and SMS mirroring between two Android phones.
Data never passes through a third-party server — the two phones connect to each
other directly over the local network.

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
see everything on your own phone (Main) — calls, messages, notifications. No
internet, no server; the two phones talk to each other directly over the same
Wi-Fi network.

## License

[Apache License 2.0](LICENSE).

---

*This project was built with the help of Ollama Cloud, OpenCode, and Claude Code.*
