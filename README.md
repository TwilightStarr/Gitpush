<p align="center">
  <img src="assets/icon/icon.svg" width="110" alt="Gitpush logosu">
</p>

<h1 align="center">Gitpush</h1>

<p align="center">
  <b>Telefonunuzdan GitHub'a güvenle dosya gönderin ve deponuzu yönetin.</b><br>
  Bilgisayar yok, terminal yok, <code>git</code> komutu yok.
</p>

<p align="center">
  <b>Türkçe</b> · <a href="README.en.md">English</a>
</p>

<p align="center">
  <img alt="Sürüm" src="https://img.shields.io/badge/s%C3%BCr%C3%BCm-1.2.1-blue">
  <a href="LICENSE"><img alt="Lisans: MIT" src="https://img.shields.io/badge/lisans-MIT-green"></a>
  <img alt="Flutter" src="https://img.shields.io/badge/Flutter-Android-02569B?logo=flutter&logoColor=white">
  <img alt="React" src="https://img.shields.io/badge/Web-React%20%2B%20Vite-61DAFB?logo=react&logoColor=black">
  <a href="https://github.com/KULLANICI_ADI/REPO_ADI/actions/workflows/test.yml"><img alt="Testler" src="https://github.com/KULLANICI_ADI/REPO_ADI/actions/workflows/test.yml/badge.svg"></a>
</p>

---

Gitpush, telefonda kod yazmadan bir GitHub deposuna **dosya veya ZIP göndermenizi**, depoyu gezmenizi, dosya düzenlemenizi ve GitHub Actions çalışmalarını izlemenizi sağlayan mobil bir Git istemcisidir. Android için **Flutter** ile yazılmıştır; aynı mantığı kullanan bir **React web arayüzü** de projede yer alır.

## Neden Gitpush?

Telefonda bir proje ZIP'i indirdiniz, yapay zekâyla bir dosya ürettiniz ya da küçük bir düzeltme yapmanız gerekiyor. Normalde bunun için bir bilgisayara, Git kurulumuna ve birkaç komuta ihtiyaç duyarsınız. Gitpush bunları tek ekranda, güvenlik önlemleriyle birlikte yapar:

1. Giriş yapın (token veya GitHub Device Flow).
2. Depo ve dalı seçin.
3. Dosyaları ya da ZIP'i seçin.
4. Önizlemede neyin değişeceğini görün, onaylayın. Tek commit olarak gider.

## Ekran görüntüleri

<!--
Ekran görüntülerini docs/screenshots/ klasörüne koyup bu bloğu açın:

<p align="center">
  <img src="docs/screenshots/gonder.png" width="240" alt="Dosya gönderme">
  <img src="docs/screenshots/repo-tarayici.png" width="240" alt="Repo tarayıcı">
  <img src="docs/screenshots/ayarlar.png" width="240" alt="Ayarlar">
</p>
-->

## Özellikler

### Gönderme
- **Atomik push:** Birden çok dosya veya bir ZIP tek commit ile gönderilir. Dal arada değiştiyse hiçbir şey ezilmez (`force: false`).
- **Önizleme ve güvenlik ağı:** Göndermeden önce yeni, güncellenen ve silinecek dosyalar listelenir. Silme işlemi için ayrıca onay istenir.
- **Gizli bilgi taraması:** `.env`, özel anahtarlar, `*.pem`, `*.jks` ve bilinen token desenlerini (GitHub, AWS, Google, Anthropic, Slack) içeren dosyalar push'u durdurur. `.env.example` gibi şablonlar serbesttir.

### Depo yönetimi
- **Repo tarayıcı:** Klasörler üstte, sıralama ve arama, klasör özetleri, yol çubuğu, dosya detayı ve önizleme.
- **Taşı, yeniden adlandır, sil:** Tekli, toplu ve klasör işlemlerinin hepsi tek commit'tir.
- **Uygulama içi düzenleme:** Metin dosyasını düzenleyin veya yeni dosya oluşturun. Kaydedilmemiş değişiklik uyarısı ve gizli bilgi taraması vardır.
- **Commit geçmişi:** Dosya ve dal bazında, sayfalı.
- **Depo ve dal işlemleri:** Depo oluşturma, dal oluşturma ve silme (varsayılan dal korunur), son depoyu hatırlama.
- **GitHub Actions:** Çalışmaları izleyin, workflow tetikleyin.

### Güvenlik ve ayarlar
- **Giriş:** Personal Access Token veya GitHub Device Flow.
- **Güvenli saklama:** Token, Android Keystore destekli şifreli depolamada tutulur.
- **PIN kilidi:** 6 haneli PIN, tuzlu karma ile saklanır. Hatalı denemelerde bekleme süresi artar.
- **Otomatik oturum kapatma:** Belirlediğiniz gün sayısı boyunca açılmayan cihazda token silinir.
- **Kişiselleştirme:** Vurgu rengi, AMOLED tema, varsayılan commit mesajı, önizleme tercihleri ve daha fazlası.
- **Yerel geçmiş:** Yaptığınız gönderimlerin kaydı yalnızca cihazınızda durur.

Ayrıntılı değişiklik listesi için [CHANGES.md](CHANGES.md), güvenlik modeli için [SECURITY.md](SECURITY.md) dosyalarına bakın.

## Kurulum

### Hazır APK (GitHub Actions)

Her `main` push'unda **Build APK** workflow'u çalışır:

1. Deponun **Actions** sekmesine gidin.
2. En son **Build APK** çalışmasını açın.
3. **Artifacts** bölümünden `app-release-apk` dosyasını indirip telefonunuza kurun.

> **Not:** CI'da üretilen APK, `flutter create` şablonundaki debug anahtarıyla imzalanır. Dağıtım için kendi keystore'unuzla imzalayın (bkz. [SECURITY.md](SECURITY.md)).

### Kaynaktan çalıştırma (Flutter)

Gereksinimler: Flutter (Dart `>=3.3.0 <4.0.0`) ve bir Android cihaz ya da emülatör.

```bash
flutter pub get
flutter create . --platforms=android   # android/ klasörü yoksa
python3 tool/patch_android_manifest.py android/app/src/main/AndroidManifest.xml
flutter run
```

Manifest yaması; INTERNET iznini, `allowBackup=false` ve `usesCleartextTraffic=false` ayarlarını ekler.

### GitHub ile giriş (Device Flow)

Token yapıştırmaya alternatif olarak OAuth Device Flow kullanabilirsiniz. Derlemeye yalnızca herkese açık **Client ID** verilir; `client_secret` gerekmez ve istemciye asla konmamalıdır.

```bash
flutter run --dart-define=GITHUB_CLIENT_ID=<client_id>
```

Client ID verilmezse "GitHub ile Giriş Yap" butonu görünmez ve token ile giriş kullanılır.

### Web arayüzü

```bash
npm install      # veya: bun install
npm run dev      # http://localhost:3000
```

Üretim derlemesi için `npm run build`. Web sürümünde token varsayılan olarak yalnızca bellekte tutulur. İsteğe bağlı kalıcı kayıt parola ile AES-256-GCM şifrelenir. Device Flow, tarayıcı CORS kısıtı nedeniyle web'de kullanılamaz.

## Önerilen token izinleri

Mümkünse **fine-grained** bir PAT oluşturun:

| İşlem | Gereken izin |
|---|---|
| Dosya gönderme, düzenleme, silme | `Contents: Read and write` |
| Actions izleme ve tetikleme | `Actions: Read and write` |

Kısa bir son kullanma tarihi seçin. Token sızdığından şüphelenirseniz GitHub → Settings → Developer settings üzerinden hemen iptal edin.

## Proje yapısı

```
lib/
  main.dart        Uygulama giriş noktası
  models/          Veri modelleri, ayarlar, repo listeleme mantığı
  services/        GitHub API, depolama, ZIP, uygulama kilidi, Device Flow
  providers/       Auth, Repo, Upload, Theme, Settings, AppLock
  screens/         Gönder, repo tarayıcı, düzenleyici, Actions, ayarlar, kilit...
  widgets/ utils/ theme/
src/               React web arayüzü (Vite + Tailwind)
test/              Birim ve widget testleri
tool/              Birleşik main.dart üretici, manifest yaması
assets/icon/       Logo (SVG + 1024 px kaynak PNG)
.github/workflows/ APK derlemesi ve test iş akışları
```

## Test

```bash
flutter analyze
flutter test
```

Testler; gizli bilgi taraması, yol doğrulama, ZIP işleme, GitHub servisi, Device Flow, repo farkı (diff) ve ayarlar gibi alanları kapsar. Her push ve PR'da `test.yml` otomatik çalışır.

## Birleşik tek dosya

`lib/` klasörü tek bir `main.dart` dosyasına birleştirilip web arayüzündeki **Flutter Kodu** sekmesinde sunulur:

```bash
node tool/generate_unified_dart.mjs          # yeniden üret
node tool/generate_unified_dart.mjs --check  # senkron mu?
```

Kaynak her zaman `lib/` klasörüdür. Üretilen dosyayı elle düzenlemeyin.

## Güvenlik

- Token yalnızca `https://api.github.com` adresine gönderilir.
- `owner`, `repo`, `branch` ve workflow adları doğrulanır ve URL-encode edilir.
- Harici bağlantılar yalnızca `https` ve `github.com` alan adlarına açılır.
- Android'de `allowBackup=false`, `usesCleartextTraffic=false` ve `--obfuscate` ile derleme kullanılır.
- Web derlemesi Content-Security-Policy ile sınırlandırılmıştır.

Güvenlik açığı bulduysanız lütfen herkese açık bir issue yerine depo sahibine özel olarak bildirin. Bilinen kalan riskler ve önerilen HTTP başlıkları için [SECURITY.md](SECURITY.md) dosyasına bakın.

## Lisans

[MIT](LICENSE) lisansı altında yayınlanmıştır.

## Katkı

Hata bildirimi, öneri ve pull request'lere açığız. Bir PR göndermeden önce `flutter analyze && flutter test` komutlarının geçtiğinden ve `node tool/generate_unified_dart.mjs --check` çıktısının senkron olduğundan emin olun.
