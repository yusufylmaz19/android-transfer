# Geliştirici notları

Son kullanıcı için kurulum ve kullanım adımları [README.md](README.md) içindedir.

## Derleme

Xcode komut satırı araçları, Swift 6, Python Pillow ve Android SDK Platform Tools gerekir.

```sh
zsh scripts/build-app.sh
```

Çıktı `dist/AndroidTransfer.app` konumundadır. Script Swift yürütülebilirini derler, simgeyi üretir ve uygulama paketini oluşturur. Bu yerel paket mağaza için imzalanmamış ve noter onayından geçmemiştir.

Uygulama `adb` aracını sırasıyla `ANDROID_HOME/platform-tools/adb`, `~/Library/Android/sdk/platform-tools/adb`, `/opt/homebrew/bin/adb` ve `/usr/local/bin/adb` konumlarında arar. Dağıtımdan önce README'deki başka Mac kurulum akışı gerçek bir cihazla ayrıca sınanmalıdır.

## Bilinen sınırlar

- Yalnızca USB ile yetkilendirilmiş ADB cihazları listelenir.
- Android ortak depolaması dışındaki özel uygulama verileri gösterilmez.
- İlerleme çubuğu işlem durumunu gösterir; yüzde ve kalan süre yoktur.
- Finder ile sürükle bırak ve dosya seçme penceresi farklı macOS sürümlerinde ayrıca doğrulanmalıdır.
