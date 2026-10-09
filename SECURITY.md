# Güvenlik Notları

## Token (PAT) saklama

| Platform | Yöntem |
|---|---|
| Android (Flutter) | `flutter_secure_storage` (Android Keystore + EncryptedSharedPreferences). Çıkışta token, yazar bilgileri, geçmiş ve son repo/dal bilgisi tamamen silinir. |
| Web (React) | **Varsayılan: yalnızca bellek.** Hiçbir Web Storage alanına yazılmaz. İsteğe bağlı kalıcı kayıt yalnızca parola ile **AES-256-GCM** (PBKDF2-SHA256, 600.000 iterasyon) şifreli yapılır. Eski sürümlerin düz metin kayıtları açılışta silinir. |

Token yalnızca `https://api.github.com` adresine gönderilir (istemcide zorlanır).

## GitHub ile giriş (Device Flow, yalnızca Android)

Token yapıştırmaya alternatif olarak OAuth Device Flow kullanılabilir; PAT girişi yedek olarak durur.

- Uygulamaya yalnızca herkese açık `client_id` gömülür (`--dart-define=GITHUB_CLIENT_ID=...`). `client_secret` gerekmez ve asla istemciye konmamalıdır.
- Doğrulama adresi yalnızca `https://github.com` olabilir; aksi halde reddedilir.
- İstenen izinler `repo workflow`. Elde edilen token, PAT ile aynı doğrulama ve Keystore saklama yolundan geçer; çıkışta silinir.
- Çıkış yapmak token'ı GitHub'da iptal etmez. Tamamen iptal için GitHub → Settings → Applications → Authorized OAuth Apps.
- Client ID tanımlı değilse "GitHub ile Giriş Yap" butonu görünmez.
- Web (React) sürümünde kullanılamaz: GitHub'ın OAuth uç noktaları tarayıcıdan çağrılamaz (CORS), bir sunucu gerekir.

## Yapılan sertleştirmeler

- **Uygulama kilidi (v1.1):** İsteğe bağlı 6 haneli PIN. PIN düz metin saklanmaz; rastgele tuz + 20.000 tur SHA-256 karması Keystore destekli secure storage'da durur, karşılaştırma sabit zamanlıdır. 5 hatalı denemeden sonra bekleme süresi (30 sn → 32 dk) artar ve uygulama kapansa da korunur. "PIN'i unuttum" yolu oturumu kapatıp yerel veriyi siler. Basit PIN'ler (000000, 123456) reddedilir.
- **Otomatik oturum kapatma (v1.1):** Ayarlanan gün sayısı kadar açılmayan cihazda token açılışta silinir.
- **Toplu silme / taşıma (v1.1):** Tek commit, `force: false` ref güncellemesi (dal arada değişirse hiçbir şey ezilmez), yol doğrulaması; klasör silmede ad yazarak onay.
- **CI derlemesi düzeltildi (v1.1):** `build.yml` Terminal uygulamasının geniş izinlerini (QUERY_ALL_PACKAGES, Shizuku) Gitpush APK'sına ekliyordu ve `allowBackup=false` / `usesCleartextTraffic=false` yamasını çalıştırmıyordu. Artık `tool/patch_android_manifest.py` (doğrulamalı) çalışır, APK `--obfuscate` ile derlenir.

- Token biçim doğrulaması (başlık enjeksiyonu / satır sonu engeli), `Bearer` şeması, `X-GitHub-Api-Version`.
- `owner`, `repo`, `branch`, workflow adı doğrulanır ve URL-encode edilir (yol enjeksiyonu engeli).
- Push öncesi **gizli bilgi taraması**: `.env`, `*.pem`, `*.jks`, `key.properties`, özel anahtarlar ve bilinen token/API anahtarı desenleri (GitHub, AWS, Google, Anthropic, Slack) içeren dosyalar push'u durdurur. (`.env.example` gibi şablonlar serbesttir.)
- Harici bağlantılar yalnızca `https` + `github.com` alan adlarına açılır.
- Web derlemesine Content-Security-Policy eklenir (`connect-src` yalnızca `self` ve `api.github.com`).
- Android: `allowBackup=false`, `usesCleartextTraffic=false`; APK `--obfuscate` ile derlenir.
- `.gitignore` gizli dosyaları (env, keystore, servis hesapları) kapsar.

## Canlı barındırma için önerilen HTTP başlıkları

Web sürümünü kendi sunucunuzda yayınlıyorsanız şu başlıkları ekleyin:

```
Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https://avatars.githubusercontent.com; connect-src 'self' https://api.github.com; object-src 'none'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'
X-Content-Type-Options: nosniff
Referrer-Policy: no-referrer
X-Frame-Options: DENY
Strict-Transport-Security: max-age=63072000; includeSubDomains
```

## Token önerileri

- Mümkünse **fine-grained** PAT kullanın; yalnızca gerekli repolara `Contents: Read and write` (+ Actions için `Actions: Read and write`) verin.
- Kısa son kullanma tarihi belirleyin. Sızdığından şüphelenirseniz GitHub → Settings → Developer settings üzerinden hemen iptal edin.

## Bilinen kalan riskler

- Uygulama kilidi, son uygulamalar (recents) önizlemesini gizlemez; bunun için yerel `FLAG_SECURE` gerekir (henüz eklenmedi).

- Release APK, `flutter create` şablonundaki **debug anahtarıyla** imzalanır. Mağaza/dağıtım için kendi keystore'unuzla imzalayın ve keystore'u GitHub Secrets'ta saklayın.
- Web'de token bellekte olduğu sürece sayfada çalışan bir XSS saldırısı onu okuyabilir; CSP bu riski azaltır ama ortadan kaldırmaz.
- GitHub Actions adımları sürüm etiketiyle (`@v4`) sabitlenmiştir; en yüksek güvenlik için tam commit SHA'sına sabitleyin.
