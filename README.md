# Gitpush

Telefonunuzdan GitHub depolarınıza güvenle dosya gönderin: ZIP arşivlerini açıp tek commit ile yükleyin,
birden fazla dosyayı farklı yollara güncelleyin, repoyu gezin, düzenleyin ve GitHub Actions'ı izleyin.
Android için Jetpack Compose ile yazılmıştır.

## Özellikler

**Giriş ve hesap**
- Adım adım, animasyonlu giriş akışı: Karşılama → Yöntem → Erişim → GitHub'da onay → Commit kimliği → Hazır
- GitHub ile giriş (OAuth Device Flow — `client_secret` gerekmez): e-posta ve doğrulayıcı uygulama (2 adımlı doğrulama)
  GitHub'ın kendi sayfasında yapılır, uygulama parolayı/kodu görmez. İsteğe bağlı olarak Personal Access Token
- Commit kimliği GitHub profilinden (yoksa gizlilik dostu noreply adresiyle) otomatik doldurulur
- Token Android Keystore destekli şifreli depolamada saklanır; yalnızca `api.github.com` adresine gönderilir
- İsteğe bağlı commit yazar adı/e-postası, API limit görüntüleme, çıkışta tüm yerel verinin silinmesi

**Gönderme**
- **ZIP'ten Aktar:** arşivi açar, `__MACOSX`/`.DS_Store`/`.git` gibi önemsizleri ayıklar, zip-slip girdilerini reddeder,
  tek üst klasörü düzleştirir, repodaki gerçek konuma otomatik hizalar, harf büyüklüğü farklarını düzeltir,
  isteğe bağlı "ZIP'te olmayan repo dosyalarını sil" (kapsamlı ve ayrıca onaylı)
- **Dosyaları Güncelle:** birden çok dosya, her biri için ayrı hedef yol; repoda aynı adlı dosyayı otomatik eşleştirme,
  klasör seçici, kısayol çipleri, metinle toplu yol komutları, geri alınabilir silme/temizleme
- Her gönderim önce **önizlenir** (yeni / güncelleme / silinecek / değişmedi / çakışma)
- Değişmeyen dosyalar (Git blob SHA-1 karşılaştırması) gönderilmez
- Tek **atomik commit** (Git Data API), `force:false` ref güncellemesi, dal arada değişirse güvenli hata
- **Güvenlik ağı:** yeni ağaç eski ağaçla karşılaştırılır; onaysız dosya kaybı varsa hiçbir şey yazılmaz
- Gizli bilgi taraması (GitHub/AWS/Google/Slack token'ları, özel anahtarlar, `.env`, `*.pem`, `id_rsa`…)
- Yol doğrulama (`..`, `.git`, geçersiz karakter, uzunluk), dosya↔klasör çakışması denetimi
- Oran sınırı / 429 durumunda otomatik bekleyip yeniden deneme
- Sonuç ekranında commit bağlantısı ve o commit'e ait Actions çalışmalarının canlı takibi

**Repo tarayıcı**
- Klasör gezinme, yol çubuğu, depo genelinde arama, doğal sıralama (`a2 < a10`), gizli dosya filtresi
- Dosya önizleme (metin / görsel yakınlaştırma / ikili), satır numaraları, kaydırma, yazı boyutu
- Uygulama içi **düzenleyici** (büyük dosyalar için bölümlü düzenleme), yeni dosya oluşturma
- Tek commit ile dosya/klasör **silme**, **taşıma / yeniden adlandırma** (içerik yeniden yüklenmeden)
- Commit geçmişi (dosya veya dal bazında), son commit bilgisi

**Depo ve dal**
- Depo listesi (arama, sıralama), yeni depo oluşturma (özel/herkese açık), dal listesi, yeni dal, dal silme
- Son kullanılan depo/dal hatırlanır (kapatılabilir)

**GitHub Actions**
- Son çalışmalar, çalışırken otomatik yenileme, `workflow_dispatch` ile tetikleme, tarayıcıda açma

**Güvenlik ve gizlilik**
- 6 haneli PIN kilidi (tuzlu, 20.000 tur SHA-256; zayıf PIN reddi; hatalı denemede kalıcı artan bekleme)
- Arka plandan dönünce zaman aşımına göre kilitleme, "PIN'imi unuttum" ile güvenli sıfırlama
- Otomatik oturum kapatma (N gün açılmazsa), yedekleme kapalı, yalnızca HTTPS
- Harici bağlantılar yalnızca `https://github.com` ve alt alan adlarına açılır

**Kişiselleştirme**
- Yeni kurulumda AMOLED saf siyah tema; cam (glass) yüzeyler ve yavaş süzülen ışık efektleri; açık/koyu/sistem tema, 6 vurgu rengi, dokunsal geri bildirim
- Önizleme boyut sınırı, satır kaydırma, yazı boyutu, geçmiş sınırı, varsayılan commit mesajı
- Telefonda tüm yönler, tabletlerde yalnızca yatay ve yan gezinti çubuğu

## Derleme

Gereksinimler: Android Studio (Koala veya üstü), JDK 17.

1. Klasörü Android Studio ile açın; Gradle eşitlemesi otomatik çalışır.
2. (İsteğe bağlı) GitHub ile giriş için bir OAuth App oluşturup **Enable Device Flow** seçeneğini açın ve Client ID'yi verin:

   ```bash
   gradle :app:assembleDebug -PGITHUB_CLIENT_ID=<client_id>
   ```

   Client ID verilmezse uygulama giriş ekranında sizden ister; token ile giriş her zaman çalışır.
3. Testler: `gradle :app:testDebugUnitTest`
4. Release APK: `gradle :app:assembleRelease` (yerelde debug anahtarıyla imzalanır; sabit imza için aşağıya bakın)

Komut satırı için Gradle wrapper isterseniz proje klasöründe bir kez `gradle wrapper --gradle-version 8.10.2` çalıştırın.

`.github/workflows/build.yml`, `GITHUB_CLIENT_ID` deposu gizli değişkeniyle testleri çalıştırır, APK üretir ve gerekiyorsa yeni bir GitHub Release yayımlar (aşağıya bakın).

## Sürümleme ve otomatik yayın

`main` dalına her push'ta sürüm numarası commit mesajlarından **otomatik** hesaplanır (`MAJOR.MINOR.PATCH`).
Testler ve derleme başarılı olursa `vX.Y.Z` etiketi ve APK ekli bir GitHub Release oluşturulur; sürüm notları commit'lerden üretilir.

| Basamak | Ne zaman artar? | Nasıl tetiklenir? |
|---|---|---|
| **MAJOR** (`1`.x.x) | Yalnızca sizin isteğinizle, geriye dönük uyumsuz büyük değişiklikte | Commit mesajında `[major]`, `feat!: ...` biçimi veya gövdede `BREAKING CHANGE: ...` |
| **MINOR** (x.`1`.x) | Yeni özellik; PATCH sıfırlanır | `feat: ...`, `özellik: ...`, `yeni: ...` (veya `[minor]`) |
| **PATCH** (x.x.`1`) | Düzeltme / iyileştirme | `fix: ...`, `düzeltme: ...`, `perf:`, `refactor:`, `security:`, `revert:` ve önek **olmayan** mesajlar (`Update files` gibi) |

Sürüm **artmaz** (release yayımlanmaz) şu durumlarda:
- Son sürümden beri tüm commit'ler `docs:`, `chore:`, `ci:`, `test:`, `style:` türünde ya da `[skip release]` içeriyor.
- Son sürümden beri uygulamayı etkileyen hiçbir dosya (`app/`, `gradle/`, `*.kts`, `gradle.properties`) değişmedi (ör. yalnızca README). `[major]` bu kuralı aşar.

Birden çok commit tek seferde gönderilirse en yüksek düzey geçerlidir (ör. `fix` + `feat` → MINOR).
Etiket yokken ilk yayın `version.properties` içindeki `BASE_VERSION` ile yapılır. `versionCode`, sürümden türetilir
(`MAJOR*1.000.000 + MINOR*1.000 + PATCH`), bu yüzden her yeni sürümde kendiliğinden büyür.
Mantık: `.github/scripts/next_version.py`.

## Sabit imza

Release APK'ları hep aynı anahtarla imzalanır; bu sayede yeni sürüm, telefondaki eskisinin üzerine güncelleme olarak kurulur.
Anahtar bir kez oluşturulur ve GitHub secret olarak saklanır (depoya **asla** konmaz).

1. Anahtarı oluşturun (bilgisayarda, JDK 17 ile gelen `keytool`):
   ```bash
   keytool -genkeypair -v -keystore gitpush-release.jks -alias gitpush \
     -keyalg RSA -keysize 2048 -validity 10000
   ```
   Sorulan şifreyi ve adınızı girin. **Dosyayı ve şifreleri güvenli bir yere yedekleyin**: kaybederseniz güncelleme yapılamaz.
2. Dosyayı base64'e çevirin:
   - Linux: `base64 -w0 gitpush-release.jks`
   - macOS: `base64 -i gitpush-release.jks`
   - Windows (PowerShell): `[Convert]::ToBase64String([IO.File]::ReadAllBytes("gitpush-release.jks"))`
3. GitHub'da depo → **Settings → Secrets and variables → Actions → New repository secret** ile şu dört secret'ı ekleyin:

   | Secret | Değer |
   |---|---|
   | `KEYSTORE_BASE64` | 2. adımdaki base64 metni |
   | `KEYSTORE_PASSWORD` | keystore şifresi |
   | `KEY_ALIAS` | `gitpush` (1. adımdaki `-alias`) |
   | `KEY_PASSWORD` | anahtar şifresi (genelde keystore şifresiyle aynı) |

`KEYSTORE_BASE64` yoksa release yayımlanmaz, workflow açık bir hata mesajıyla durur.

## Token yetkileri

- Classic token: `repo` ve `workflow`
- Fine-grained token: ilgili depolarda *Contents: Read & write* ve *Actions: Read & write*

## Proje yapısı

```
app/src/main/java/com/example/gitpush/
  model/     veri modelleri, ayarlar, repo ağacı/listeleme mantığı
  service/   GitHub API, Device Flow, repo farkı, ZIP, depolama, PIN kilidi
  state/     Auth / Repo / Upload / Settings / Theme / AppLock sağlayıcıları
  ui/        Compose ekranları, bileşenler, tema, diyalog ve gezinme altyapısı
  util/      yol doğrulama, gizli bilgi taraması, biçimleme, önizleme, URL güvenliği
app/src/test/  birim testleri
```

Güvenlik tasarımı için bkz. [SECURITY.md](SECURITY.md).
