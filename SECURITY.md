# Güvenlik

## Veri saklama
- **Token:** AndroidX Security Crypto (Android Keystore destekli AES-256) ile şifreli saklanır; çıkışta silinir.
- **PIN:** düz metin saklanmaz. Rastgele 16 baytlık tuz + 20.000 tur SHA-256 karması, şifreli depoda tutulur.
  5 hatalı denemeden sonra bekleme süresi (30 sn → en çok 32 dk) kalıcı olarak artar.
- Ayarlar ve gönderim geçmişi yalnızca cihazda tutulur; `allowBackup=false` ve veri çıkarma kuralları ile yedeklenmez.

## Ağ
- Yalnızca HTTPS (`usesCleartextTraffic=false`). Token yalnızca `https://api.github.com/` adresine gönderilir.
- Device Flow'da yalnızca herkese açık `client_id` kullanılır; doğrulama adresi `https://github.com` olmalıdır.
- Harici bağlantılar `https://github.com` ve `*.github.com` ile sınırlıdır.

## Gönderim güvenliği
- Yol doğrulama, gizli bilgi taraması, çakışma denetimi, onaysız silme engeli.
- Yeni ağaç eski ağaçla karşılaştırılır; beklenmedik dosya kaybında commit atılmaz.
- Ref güncellemesi `force:false`; dal arada değiştiyse işlem reddedilir, hiçbir şey ezilmez.
- ZIP girdilerinde `..` ve mutlak yollar (zip-slip) atlanır.

## Bilinen sınırlar
- Uygulama kilidi açıkken ekran görüntüsü engellenmez (`FLAG_SECURE` eklenmemiştir).
- Release derlemesi varsayılan olarak debug anahtarıyla imzalanır; dağıtımdan önce kendi keystore'unuzla imzalayın.
- 50 MB üstü dosyalar gönderilmez; çok büyük repolarda GitHub ağaç yanıtı kesilebilir ve bazı denetimler sınırlı yapılır.

## Güvenlik açığı bildirimi
Lütfen herkese açık issue yerine depo sahibine özel olarak bildirin.
