# Android Transfer APK

Samsung telefona yerel olarak kurulabilen Flutter eşlikçi uygulaması. Kullanım ve güvenlik sınırları için kökteki [README](../README.md) ve [kablosuz plan](../WIRELESS_PLAN.md) dosyalarına bakın.

```sh
flutter pub get
flutter analyze
flutter build apk --release --split-per-abi
```

Samsung S24 APK'sı `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` konumunda oluşur. Bu kişisel deneme sürümü geliştirme anahtarıyla imzalanır; yalnızca özel IPv4 yerel ağlarında tek dosya aktarımı için hazırlanmıştır. Dış ağ portu açmayın.
