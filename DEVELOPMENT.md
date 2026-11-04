# Geliştirici notları

Son kullanıcı için kurulum ve kullanım adımları [README.md](README.md) içindedir.

## Mac uygulamasını derleme

Xcode komut satırı araçları, Swift 6, Python Pillow ve Android SDK Platform Tools gerekir.

```sh
zsh scripts/build-app.sh
```

Çıktı `dist/AndroidTransfer.app` konumundadır. Script Swift yürütülebilirini derler, simgeyi üretir ve uygulama paketini oluşturur. Bu yerel paket mağaza için imzalanmamış ve noter onayından geçmemiştir.

## Android uygulamasını derleme

Flutter ve Android SDK kurulu olmalıdır:

```sh
cd mobile
flutter pub get
flutter analyze
flutter build apk --release --split-per-abi
```

Samsung S24 için çıktı `mobile/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` konumundadır. Şimdiki Gradle ayarı release APK'sını da geliştirme anahtarıyla imzalar; halka açık dağıtım için ayrı imza gerekir. Android simgesini Mac simgesiyle eşlemek için Mac uygulaması derlendikten sonra `python3 scripts/sync-android-icon.py` çalıştırılır.

Uygulama `adb` aracını sırasıyla `ANDROID_HOME/platform-tools/adb`, `~/Library/Android/sdk/platform-tools/adb`, `/opt/homebrew/bin/adb` ve `/usr/local/bin/adb` konumlarında arar. Dağıtımdan önce README'deki başka Mac kurulum akışı gerçek bir cihazla ayrıca sınanmalıdır.

## Bilinen sınırlar

- Yalnızca USB ile yetkilendirilmiş ADB cihazları listelenir.
- Android ortak depolaması dışındaki özel uygulama verileri gösterilmez.
- İlerleme çubuğu işlem durumunu gösterir; yüzde ve kalan süre yoktur.
- Finder ile sürükle bırak ve dosya seçme penceresi farklı macOS sürümlerinde ayrıca doğrulanmalıdır.
- Kablosuz kod şimdilik yalnızca özel IPv4 ağlarından istek kabul eden HTTP prototipidir; genel internete açılmamalıdır.
- Kablosuz modda çoklu dosya kopyalama ve dosya bazında ilerleme var; klasör kopyalama, 64 MiB üzeri dosyalar, taşıma/silme ve bağlantı kesintisinden devam etme eksiktir.
- USB aktarımı ve kablosuz temel akış Samsung S24 ile kullanıldı; her cihaz/ağ birleşimi ayrıca sınanmadı.

## GitHub ön sürümü

`v0.2.0-beta.1` için Mac uygulaması `0.2.0 (2)`, Android uygulaması `0.2.0+2` olarak paketlenir. `dist/release-v0.2.0-beta.1/` içindeki ZIP ve APK dosyaları GitHub Release varlığıdır; `SHA256SUMS.txt` indirilen dosyaları doğrulamak içindir. Kaynak kod commit'lerini önce GitHub'a gönderin, ardından bu etiketi güncel `master` commit'inden oluşturup **pre-release** işaretleyin. Android APK hâlâ geliştirme anahtarıyla imzalıdır; bu paket yerel test içindir.
