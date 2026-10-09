# CHANGES.md

## Logo yenilendi
- Degrade, parlama ve gölge içeren eski logo yerine düz, iki renkli sade bir logo: koyu zemin, beyaz yukarı ok (push) ve indigo commit düğümü.
- Güncellenen yerler: `assets/icon/icon.svg`, `assets/icon/app_icon_kaynak_1024.png` (APK ikonları buradan üretilir), `public/favicon.svg`, `GitpushLogo` widget'ı, web gezinti çubuğu ve birleşik Dart dosyaları.

## v1.2.0 — Terminal kalıntıları silindi, yeni özellikler
- **Silindi:** Terminal (cihaz paneli) uygulamasına ait tüm dosyalar (tabs, core, home_screen, pil/süreç/Shizuku servisleri, ilgili testler, assets/config, kök `services/` ve `tabs/`, eski README) ve kullanılmayan bağımlılıklar (battery_plus, shizuku_api, installed_apps, permission_handler, wakelock_plus vb.).
- **Yeni:** uygulama içi dosya düzenleme ve yeni dosya oluşturma (kaydedilmemiş değişiklik uyarısı, gizli bilgi taraması), dosya / dal commit geçmişi (sayfalı), dal silme (varsayılan dal korumalı).
- Birleşik dosya yeniden üretildi (64 dosya).

## v1.1.0 — Gitpush: ayarlar, güvenlik, logo, dosya gezgini

Dürüstlük notu: bu ortamda Flutter/Dart SDK yok; `flutter analyze` ve `flutter test`
ÇALIŞTIRILAMADI. Yapılan: parantez dengesi taraması, göreli import denetimi, birleşik
dosya üretimi (çakışan ad denetimiyle). İlk işiniz: `flutter pub get && flutter analyze && flutter test`.

### 0) Depo onarımı
- `lib/` içinde Gitpush ile "Terminal" (cihaz paneli) dosyaları karışmış; `main.dart`,
  `storage_service.dart` ve `format_utils.dart` Terminal sürümleriyle ezilmişti. Gitpush
  sürümleri birleşik dosyadan geri yüklendi; Terminal dosyaları çakışmasın diye
  `terminal_main.dart`, `device_storage_service.dart` (`DeviceStorageService`) ve
  `TerminalTheme` olarak yeniden adlandırıldı.
- `pubspec.yaml`: paket adı `gitpush`; eksik bağımlılıklar eklendi (provider, archive, crypto,
  file_picker, flutter_secure_storage).
- `tool/generate_unified_dart.mjs` Terminal dosyalarını dışarıda bırakır.

### 1) Repo tarayıcı (klasör sırası + ayrıntı)
- Klasörler her zaman üstte; sıralama: ad (doğal sıra), boyut, tür. Gizli dosya anahtarı.
- Klasör satırlarında dosya/klasör sayısı ve toplam boyut; yol çubuğu (breadcrumb), depo geneli arama, çoklu seçim.
- Yeni **dosya detay ekranı**: metin/görsel önizleme (satır numaralı), boyut, SHA, kip, son commit, kopyala, GitHub'da aç.
- Taşı / yeniden adlandır (içerik yeniden yüklenmeden), tek ve toplu silme, klasör silme — hepsi tek commit, geçmişe yazılır.
- Depo seçici: son güncellenen / ada göre / özel önce sıralama.

### 2) Ayarlar
Hesap (token türü, API kotası), vurgu rengi, AMOLED, titreşim, varsayılan commit mesajı,
sıralama, gizli dosyalar, son depoyu hatırla, önizleme sınırı/yazı boyutu/kaydırma,
uygulama kilidi, otomatik kilitlenme, otomatik oturum kapatma, geçmiş sınırı, kısayol ekle/sil/sıfırla,
ayarları sıfırla, lisanslar.

### 3) Güvenlik — bkz. SECURITY.md
### 4) Logo — yeni degrade ikon (assets/icon, web favicon, `GitpushLogo` widget'ı)

---

# CHANGES.md — TerminalF inceleme/düzeltme raporu

Bu değişiklik seti üç ana istek etrafında toplanıyor: (1) Shizuku'nun gerçekten
çalışmaması, (2) yanlışlıkla kaldırılmış/eksik bileşenler, (3) tweak durumunun
(açık/kapalı) cihazdan doğrulanamaması. Her madde: **neydi / neden
eksikti-hataydı / nasıl düzeltildi** sırasıyla anlatılıyor.

Dürüstlük notu: bu ortamda çalışan bir Flutter/Dart SDK'sı yok (`flutter` ve
`dart` komutları PATH'te bulunamadı), bu yüzden `flutter analyze` ve
`flutter test` ÇALIŞTIRILAMADI. Bunun yerine: (a) `shizuku_api` paketinin
gerçek API yüzeyi pub.dev'den doğrulandı (bkz. madde 1), (b) yeni saf-Dart
mantık (`sh -c` sarmalayıcısı, `id` çıktısı ayrıştırma, durum karşılaştırma)
gerçek bir POSIX kabuğuyla (bu konteynerdeki `sh`) manuel olarak test edildi,
(c) tüm değiştirilen dosyalar parantez/parça dengesi için otomatik taranarak
sözdizimi bütünlüğü doğrulandı, (d) yeni mantık için `test/shell_utils_test.dart`
ve `test/tweak_status_test.dart` eklendi ama bunlar da gerçek bir Flutter test
koşucusuyla ÇALIŞTIRILMADI — yalnızca elle yazıldı ve gözden geçirildi. Gerçek
cihazda/CI'da `flutter pub get && flutter analyze && flutter test`
çalıştırılması önerilir.

---

## 1) Shizuku bileşenleri çalışmıyor

### 1.1 `.github/workflows/build.yml` — eksik Shizuku izinleri/queries
- **Neydi:** İş akışı yalnızca `ShizukuProvider`'ı `AndroidManifest.xml`'e
  ekliyordu. `moe.shizuku.manager.permission.API_V23` izni ve
  `<queries><package android:name="moe.shizuku.privileged.api"/></queries>`
  girdisi HİÇ eklenmiyordu.
- **Neden hataydı:** Bu iki girdi olmadan Shizuku'nun izin/servis
  mekanizması (Android 11+ paket görünürlüğü kısıtı dahil) düzgün
  çalışmayabilir; kullanıcının "Shizuku'yu açıyorum ama tweak'lerin hiçbir
  etkisi olmuyor" şikayetinin kök nedenlerinden biri budur.
- **Nasıl düzeltildi:** "Shizuku provider'ini AndroidManifest.xml'e ekle"
  adımı, manifest'i Python ile ayrıştırıp şunları **idempotent** biçimde
  ekleyen "AndroidManifest.xml'e izinleri, queries ve Shizuku provider'ini
  ekle" adımıyla değiştirildi: `INTERNET`, `VIBRATE`, `POST_NOTIFICATIONS`,
  `QUERY_ALL_PACKAGES` (`tools:ignore` ile), `API_V23` izni, Shizuku
  `<queries>` girdisi (varsa mevcut `<queries>` bloğunun içine eklenir) ve
  `ShizukuProvider`. Ardından yeni bir "Manifest'i doğrula" adımı bu yedi
  girdinin hepsinin gerçekten manifest'te olduğunu `grep` ile kontrol edip
  eksikse derlemeyi `exit 1` ile durdurur (sessiz başarısızlık yok). Bu
  adımın Python bloğu, örnek bir Flutter şablon manifest'i üzerinde iki kez
  (idempotency için) ve `<queries>` bloğu olan/olmayan iki senaryoda elle
  test edildi; sonuç XML olarak geçerli.
  **Ayrıca (bkz. madde 2.1):** aynı adımda `VIBRATE` ve `QUERY_ALL_PACKAGES`
  de ekleniyor — bu, aşağıdaki 2.1 maddesiyle aynı kod değişikliği.

### 1.2 `lib/services/shizuku_service.dart` — hata/exit code hiç kontrol edilmiyordu
- **Neydi:** `runTweak`, `_api.runCommand(command)` çağrısının döndürdüğü
  metni doğrudan "başarılı" sayıp her zaman `› tamamlandı` yazıyordu.
  `shizuku_api` paketi (pub.dev'den doğrulanan gerçek imza: yalnızca
  `pingBinder()`, `checkPermission()`, `requestPermission()`,
  `runCommand(String) -> Future<String?>`) **çıkış kodu döndürmüyor** —
  yalnızca çıktı metni veriyor. Ayrıca `;` ile zincirlenmiş komutlar
  (`pm disable-user ...; pm disable-user ...; pm disable-user ...`)
  Shizuku'nun `runCommand`'ına doğrudan verildiğinde, bu paketin komutu
  gerçekten bir kabuk (`sh -c`) üzerinden mi yoksa doğrudan mı çalıştırdığı
  **belirsiz** — eğer doğrudan çalıştırıyorsa `;` bir kabuk operatörü değil,
  düz bir karakter olarak muhtemelen tek bir işleme argüman olarak gidip
  hataya yol açar.
- **Neden hataydı:** Kullanıcının bildirdiği "tweak'lerin hiçbir etkisi
  olmuyor" davranışıyla birebir örtüşüyor: komut sessizce başarısız olsa
  bile arayüz "tamamlandı" gösteriyordu, `_appliedIds`'e ekleniyordu, switch
  "açık" görünüyordu — ama cihazda hiçbir şey değişmemiş olabiliyordu.
- **Nasıl düzeltildi:**
  - Yeni `lib/utils/shell_utils.dart`: `wrapForShell()` komutu
    `sh -c '( komut ) 2>&1; echo "__TF_EXIT__:$?"'` şeklinde sarıp hem
    `;` zincirinin bir alt kabukta çalışmasını garanti eder hem de çıkış
    kodunu çıktının sonuna ekler; `parseWrappedOutput()` bu satırı geri
    ayrıştırıp gerçek `ShellResult(output, exitCode)` üretir. Bu sarmalayıcı
    gerçek bir `sh` ile (`id`, `echo a; echo b`, `ls /yok; echo done`,
    `false` gibi komutlarla) test edilip çıkış kodlarının doğru geldiği
    doğrulandı.
  - `ShizukuService.probe()`, ÖNCE bu sarmalayıcıyı gerçek bir `id` komutuyla
    dener; sarmalayıcı beklenen biçimde yanıt vermezse (bu Shizuku/eklenti
    sürümü desteklemiyor olabilir) ham `id` komutuna düşer ve **çıkış kodu
    doğrulanamaz** modunda çalışmaya devam eder — bu, kullanıcıya ve konsola
    açıkça bildirilir ("Bu Shizuku sürümünde çıkış kodu alınamıyor; başarı
    yalnızca çıktıya bakılarak tahmin edilecek."), sessizce yutulmaz.
  - `failureReason()` (bkz. `shell_utils.dart`): çıkış kodu sıfırdan
    farklıysa VEYA çıktı `Exception`/`Permission denied`/`Unknown package`/
    `not found`/`Failure` gibi tipik Android kabuk hata izlerinden birini
    içeriyorsa komutu başarısız sayar.
  - `runTweak`, başarısız bir komutta artık **hiçbir zaman** "tamamlandı"
    yazmaz; yeni `TweakCommandFailedException` fırlatır (çağıran taraf —
    `winutil_tab.dart` — bunu yakalayıp `_appliedIds`'e EKLEMEZ, kullanıcıya
    gösterir ve durumu cihazdan tekrar okur, bkz. madde 3).

### 1.3 Gerçek test komutu (`id`) ile kimlik doğrulama ve gösterme
- **Neydi:** Shizuku "hazır" sayılmak için yalnızca `isRunning()` VE
  `hasPermission()` kontrol ediliyordu — komutların GERÇEKTEN çalıştığı hiç
  sınanmıyordu.
- **Neden hataydı:** Servis çalışıyor + izin verilmiş olması, komutların
  fiilen yürütülebildiğinin kanıtı değildir (ör. eklenti sürümüyle
  Shizuku sürümü arasında bir uyumsuzluk olabilir).
- **Nasıl düzeltildi:** Yeni `ShizukuService.probe()`, `id` komutunu gerçekten
  çalıştırıp çıktısını `parseIdOutput()` (yeni, `shell_utils.dart`) ile
  ayrıştırır: `uid=2000(shell) ...` -> `ShellIdentity(uid: 2000, name:
  'shell', isRoot: false)`. Yalnızca bu ayrıştırma başarılı olursa Shizuku
  "hazır" (`ShizukuProbe.ready`) sayılır. `winutil_tab.dart`'taki
  `_PrivilegeStatusBanner` artık hangi kimlikle (`shell` ya da `root`,
  `uid`'siyle birlikte) çalışıldığını açıkça gösterir; `_toggleTweak`
  konsola "Shizuku, shell üzerinden ... uygulanıyor" gibi yazar.

### 1.4 Root yoksa `winutil_tab.dart` içinde Shizuku yolu doğru seçiliyor mu?
- **Kontrol edildi, DOĞRUYDU, iyileştirildi:** `_toggleTweak` zaten
  `useRoot = _hasRoot == true; useShizuku = !useRoot && _shizukuReady;`
  mantığıyla kökü önceliklendirip yoksa Shizuku'ya düşüyordu — bu mantık
  korundu (bkz. yeni `_AccessPath` enum'u — aynı önceliklendirmeyi daha
  merkezi/tekrar kullanılabilir hale getirir: `root -> shizuku -> none`).
  Tek fark: `_shizukuReady` artık yalnızca "çalışıyor + izinli" değil,
  yukarıdaki 1.3'teki gerçek `id` testini de gerektiriyor.

### 1.5 Uydurma API kullanılmadı
- `shizuku_api` paketinin pub.dev'deki resmi belgeleri (sürüm 1.2.3,
  `ShizukuApi` sınıfının API referansı) bu oturumda web'den çekilip
  doğrulandı: yalnızca `pingBinder()`, `checkPermission()`,
  `requestPermission()`, `runCommand(String)` metotları var — hepsi bu
  şekilde kullanıldı, başka hiçbir metot/alan varsayılmadı.

---

## 2) Yanlışlıkla kaldırılmış / eksik şeyler

### 2.1 Manifest izinleri: `VIBRATE`, `QUERY_ALL_PACKAGES`
- **Neydi:** README'nin "Kurulum" bölümü bu iki izni **elle** eklemeyi
  anlatıyordu ("derleme sonrası ... bir kez kontrol edin") ama
  `.github/workflows/build.yml` OTOMATİK derlemede bunları hiç eklemiyordu.
- **Neden eksikti:** Workflow yalnızca Shizuku provider'ını ve
  `compileSdk`/`minSdk` ayarlarını değiştiriyordu; izin ekleme adımı hiç
  yazılmamıştı.
- **Nasıl düzeltildi:** Madde 1.1'deki aynı workflow adımı bu iki izni de
  ekliyor (`VIBRATE` — titreşim testi için; `QUERY_ALL_PACKAGES` —
  "Uygulamalar" sekmesinin yüklü uygulama listesi için, `tools:ignore`
  ile Play Console uyarısı bastırılmış olarak, README'nin zaten belirttiği
  gibi).
- **Ek bulgu (istenenin ötesinde, ayrıca eklendi):** Kod
  `Permission.notification` kullanıyor (`home_screen.dart` >
  `_managedPermissions`) ama manifest'te `POST_NOTIFICATIONS` yoktu — bu,
  Android 13+ (API 33) cihazlarda bildirim izni isteğinin sessizce
  reddedilmesine yol açar. Aynı workflow adımına eklendi.
- **Ek bulgu 2:** `assets/config/tweaks.json` içindeki "Uzaktan
  Yapılandırma" özelliği `http` paketiyle ağ isteği yapıyor
  (`WinUtilService.fetchRemoteTweaks`), ama manifest'te `INTERNET` izni
  yoktu — debug derlemelerde Flutter'ın otomatik eklediği hata ayıklama
  manifesti bunu gizler, ama **release** APK'da (`flutter build apk
  --release`, tam olarak bu workflow'un yaptığı) ağ isteği sessizce
  başarısız olurdu. Aynı adıma eklendi.

### 2.2 README'de anlatılıp kodda karşılığı olmayan özellikler
- Tüm README özellik listesi (Genel Bakış/Cihaz/Performans/Kontroller/
  Uygulamalar sekmeleri, pil/cihaz/ekran/bellek/depolama/ağ servisleri,
  önbellek+izin+titreşim+parlaklık+başlangıç sekmesi yönetimi, kopyalanabilir
  satırlar, uygulama yönetimi, pil tahmini, `Permission.storage` temizliği,
  liste sanallaştırması, iOS bildirimi, test edilebilir pil matematiği,
  ekran ölçüm düzeltmesi) tek tek koda karşılık geldi — **eksik özellik
  bulunamadı.**
- "Android Araçları" (winutil uyarlaması: tweak'ler, önerilen uygulamalar,
  kısayollar, Shizuku) bölümü README'de hiç belgelenmemişti (yalnızca
  `pubspec.yaml` yorumlarında bahsediliyordu) — bu bir "kaldırılmış özellik"
  değil ama belgesizlik, "hangi tweak'in ne yaptığını anlayamıyorum" türü
  kafa karışıklığına yol açabilir. README'ye yeni "Android Araçları:
  Tweak'ler, Shizuku ve Durum Paneli" bölümü eklendi.

### 2.3 Kodda import/referans edilip dosyası olmayan veya bağlanmamış bileşenler
- Tüm `lib/` ve `test/` dosyaları tarandı: her göreli import
  (`import '../...'`) hedef dosyaya karşılık geliyor, her
  `package:...` importu `pubspec.yaml`'daki bir bağımlılığa karşılık
  geliyor, ve `main.dart` dışındaki her `lib/` dosyası en az bir yerden
  referans ediliyor (kullanılmayan/bağlanmamış dosya yok). **Eksik/dangling
  referans bulunamadı** — bu maddede yapılacak bir düzeltme yoktu.

---

## 3) Tweak durumu (açık mı kapalı mı) → Durum Paneli

### 3.1 `tweaks.json` şemasına `checkCommand` / `expectedOutput`
- **Neydi:** Şemada yalnızca `id/title/description/category/applyCommand/
  revertCommand/requiresRoot/dangerous` vardı; durumu cihazdan okuyacak
  hiçbir alan yoktu.
- **Nasıl düzeltildi:** İki opsiyonel alan eklendi. Anahtar (toggle) olan
  12 tweak'in **hepsine** anlamlı bir `checkCommand`/`expectedOutput` çifti
  eklendi (`settings get ...`, `pm list packages -d ...`); tek seferlik eylem
  olan `performance_kill_background` (arka planı temizle, geri alınamaz,
  kalıcı bir "durumu" yok) kasıtlı olarak dışarıda bırakıldı.
  `lib/models/tweak_model.dart`'taki `Tweak` sınıfı bu iki alanı okuyacak
  şekilde güncellendi (`hasCheck`, `isToggle` getter'larıyla birlikte).
  `test/tweak_status_test.dart`, paketle gelen `tweaks.json`'daki her
  toggle-tweak'in gerçekten bir `checkCommand`'a sahip olduğunu doğrulayan
  bir test içeriyor.

### 3.2 AÇIK / KAPALI / BİLİNMİYOR — cihazdan okuma mantığı
- Yeni `lib/utils/tweak_status.dart`: `outputsMatch()` iki çıktıyı satır
  satır (boşluk kırpılmış, sayılar sayısal — `0` ile `0.0` eşit sayılır,
  çünkü `settings get` bazı cihazlarda ondalıklı döner) karşılaştırır;
  `stateFromCheckResult()` komut başarısızsa/çıktı hata içeriyorsa
  `unknown`, eşleşiyorsa `on`, aksi halde `off` döner.
- `WinUtilService.exec()` (yeni) ve `ShizukuService.exec()` (yeni, genel
  amaçlı — `runTweak`'in altyapısını salt-okunur komutlar için de kullanır)
  eklendi; ikisi de aktif yetki yoluyla `checkCommand`'ı çalıştırıp
  `ShellResult` döner.
- Renkli rozet: yeni `_StateBadge` widget'ı (`winutil_tab.dart`) yeşil
  (AÇIK) / kırmızı (KAPALI) / turuncu (BİLİNMİYOR) gösterir; okunamayan bir
  durum `_appliedIds`'den tahmin edildiyse rozette "(tahmini)" eklenir.

### 3.3 Durum Paneli
- Yeni `_StatusPanel` widget'ı, Tweak sekmesinin en üstüne eklendi: toplam
  tweak sayısı, kaç tanesi aktif (tahmini olanlar ayrıca belirtilir),
  durumu bilinmeyen sayısı, kategoriye göre dağılım (Debloat/Performans/
  Gizlilik, her biri "aktif / toplam"), aktif yetki yolu (`Root (uid 0)` /
  `Shizuku (shell, uid 2000)` / `Yok`), cihazdan kaç tanesinin gerçekten
  okunabildiği (`live / checkable`), son okuma saati ve bir "Yenile" düğmesi.
  "Yenile", kök/Shizuku yetkisini yeniden sınar (Shizuku sonradan açılmış
  olabilir) VE tüm tweak durumlarını cihazdan tekrar okur.

### 3.4 Sekme açılınca / tweak uygulanınca yeniden okuma; okunamazsa "tahmini"
- `_bootstrap()` artık ilk yüklemede `_refreshStatuses()` çağırır.
- `SegmentedTabBar`'da "Tweak'ler" sekmesine her geçişte `_refreshStatuses()`
  tetiklenir.
- Bir tweak uygulandığında/geri alındığında (`_toggleTweak`), komut hatasız
  bitse bile durum **cihazdan tekrar okunup doğrulanır**
  (`_verifyAfterRun`): komut hata vermedi ama cihazdaki durum beklenenle
  eşleşmiyorsa ("tweak bu cihazda/yetkiyle etkisiz olabilir") kullanıcıya
  hem konsolda hem snackbar'da açıkça bildirilir — sessizce "başarılı"
  varsayılmaz. Komut başarısız olduysa bile (zincirin bir kısmı çalışmış
  olabileceğinden) durum yine cihazdan yeniden okunur.
- Okunamayan her durumda (`hasCheck == false`, yetki yok, ya da komut
  başarısız) `_fallbackStatus()`'a düşülür: `_appliedIds`'te kayıtlıysa
  "AÇIK (tahmini)", değilse "BİLİNMİYOR" (kayıtlı OLMAMASI "KAPALI" anlamına
  gelmez — tweak uygulama dışında açılmış olabilir, bu yüzden KAPALI asla
  tahmin edilmez). Bu her durumda arayüze ve konsola "tahmini"/"okunamadı"
  olarak yansıtılır.

---

## Dokunulan dosyalar (özet)

| Dosya | Değişiklik |
|---|---|
| `.github/workflows/build.yml` | İzin/`<queries>`/Shizuku provider ekleme adımı Python tabanlı, idempotent bir adımla değiştirildi + doğrulama adımı eklendi (madde 1.1, 2.1) |
| `README.md` | Kurulum notu güncellendi (izinler artık otomatik ekleniyor) + yeni "Android Araçları" bölümü (madde 2.2) |
| `assets/config/tweaks.json` | 12 toggle-tweak'e `checkCommand`/`expectedOutput` eklendi (madde 3.1) |
| `lib/models/tweak_model.dart` | `Tweak`'e `checkCommand`/`expectedOutput`/`hasCheck`/`isToggle` eklendi (madde 3.1) |
| `lib/services/shizuku_service.dart` | Baştan yazıldı: gerçek `probe()`, `sh -c` sarmalayıcı + çıkış kodu, başarısızlık algılama, `exec()` (madde 1.2, 1.3, 3.2) |
| `lib/services/winutil_service.dart` | `exec()` eklendi, `_stream()` artık çıkış kodu/hata izini değerlendirip `TweakCommandFailedException` fırlatıyor, kimlik (`rootIdentity`) saklanıyor (madde 1.2, 3.2) |
| `lib/tabs/winutil_tab.dart` | Durum Paneli, AÇIK/KAPALI/BİLİNMİYOR rozetleri, gerçek kimlik gösterimi, yeniden okuma/doğrulama akışı (madde 1.3, 3.2, 3.3, 3.4) |
| `lib/utils/shell_utils.dart` | *(yeni)* `sh -c` sarmalayıcı, `id` çıktısı ayrıştırma, başarısızlık sezgisi — saf Dart, birim testli |
| `lib/utils/tweak_status.dart` | *(yeni)* Durum karşılaştırma/çıkarım mantığı — saf Dart, birim testli |
| `test/shell_utils_test.dart` | *(yeni)* `shell_utils.dart` için birim testleri |
| `test/tweak_status_test.dart` | *(yeni)* `tweak_status.dart` ve güncellenmiş `Tweak` modeli için birim testleri |

## Doğrulanamayanlar (dürüstlük)

- `flutter analyze` / `flutter test` bu ortamda çalıştırılamadı (SDK yok).
  Tüm değişiklikler elle yazıldı, sözdizimi bütünlüğü otomatik parça/parantez
  dengesi taramasıyla ve `sh -c` sarmalayıcısının gerçek bir POSIX kabuğuyla
  manuel testiyle desteklendi — ama bu, gerçek bir Dart derleyicisinin/analiz
  aracının yerini tutmaz.
- `shizuku_api` paketinin `runCommand`'ının komutu GERÇEKTEN nasıl
  yürüttüğü (doğrudan `Runtime.exec` mi, bir kabuk üzerinden mi) pub.dev
  belgelerinde açıkça yazmıyor; bu yüzden `probe()` bunu varsaymak yerine
  gerçek bir `id` komutuyla SINAR ve sarmalayıcı işe yaramazsa ham moda
  (çıkış kodu doğrulanamayan) düşer — ilk gerçek cihazda bu iki yoldan
  hangisinin kullanıldığının bir kez gözlemlenmesi önerilir.
- Workflow'daki manifest-düzenleme Python bloğu yalnızca örnek/temsili bir
  Flutter şablon manifest'i üzerinde test edildi (bu depoda henüz
  `android/` klasörü yok, `flutter create` ilk derlemede üretiyor); gerçek
  `flutter create` çıktısıyla ilk CI çalıştırmasının bir kez izlenmesi
  önerilir.
