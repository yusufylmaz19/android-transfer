# Android Transfer — kurulum ve kullanım

Android telefon ile Mac arasında USB kablosuyla dosya kopyalamak için yerel uygulama. Telefona ayrıca bir uygulama yüklemeniz veya hesap açmanız gerekmez.

## Gerekli olanlar

- macOS 13 veya daha yeni bir Mac
- Android telefon ve **veri aktarabilen** USB kablosu
- AndroidTransfer.app dosyası
- Google'ın ücretsiz **Android SDK Platform Tools** paketi (adb için)

## 1. Mac'e Platform Tools kurun

1. Google'ın [SDK Platform Tools indirme sayfasını](https://developer.android.com/tools/releases/platform-tools) açın ve **Download SDK Platform-Tools for Mac** seçeneğini indirin. Android Studio'nun tamamını kurmanız gerekmez.
2. İndirilen ZIP dosyasını açın. İçinden `platform-tools` klasörü çıkmalı; bu klasörde `adb` dosyası bulunur.
3. Mac'te **Terminal** uygulamasını açın, aşağıdaki iki satırı sırayla yapıştırıp Return'a basın:

   ```sh
   mkdir -p "$HOME/Library/Android/sdk"
   ditto "$HOME/Downloads/platform-tools" "$HOME/Library/Android/sdk/platform-tools"
   ```

   ZIP'i farklı bir klasöre açtıysanız ikinci satırdaki `Downloads/platform-tools` bölümünü o konuma göre değiştirin. Platform Tools önceden bu konumda kuruluysa bu adımı atlayabilirsiniz.

## 2. Uygulamayı yükleyin

1. `AndroidTransfer.app` dosyasını Finder'da **Uygulamalar (Applications)** klasörüne sürükleyin.
2. Uygulamalar klasöründen **Android Transfer**'i açın. Uygulama mağaza için imzalanmadığından macOS açılışı engellerse, yalnızca dosyayı güvenilir bir kaynaktan aldıysanız **Sistem Ayarları > Gizlilik ve Güvenlik > Yine de Aç** yolunu kullanın. [Apple'ın açıklaması](https://support.apple.com/102445).
3. Sık kullanacaksanız Dock'taki simgesine sağ tıklayıp **Seçenekler > Dock'ta Tut** seçeneğini seçin.

Uygulamayı güncellemek için önce tamamen kapatın, sonra yeni `AndroidTransfer.app` dosyasını Uygulamalar'daki eski kopyanın üzerine koyun.

## 3. Telefonda USB hata ayıklamayı açın

1. Telefonda **Ayarlar > Telefon Hakkında** bölümünü açın. **Yapım numarası**na yedi kez dokunun. Samsung telefonlarda yol genellikle **Ayarlar > Telefon Hakkında > Yazılım Bilgileri > Yapım numarası**dır.
2. Ayarlar'a dönüp **Geliştirici seçenekleri**ni açın ve **USB hata ayıklama**yı etkinleştirin. Menü adları marka ve Android sürümüne göre değişebilir. [Android'in resmi yönergesi](https://developer.android.com/studio/debug/dev-options).
3. Telefonu kabloyla Mac'e bağlayın ve kilidini açın. Telefonda **USB hata ayıklamaya izin verilsin mi?** sorusu çıkarsa onaylayın. Bu izni yalnızca güvendiğiniz Mac'te verin.

## 4. İlk bağlantı

1. Android Transfer'i açın. Sol tarafta **USB cihazı bağlı** yazmasını bekleyin.
2. Cihaz görünmezse **Cihazları Yenile**ye basın; telefon ekranındaki izin sorusunu ve kablonun veri aktarabildiğini kontrol edin.
3. Sağ tarafta telefonun ortak depolamasındaki dosyalar görünür. Klasör adına çift tıklayın; **Backspace / Delete** tuşuyla üst klasöre çıkın.

## Telefondan Mac'e kopyalama

1. Sağdaki dosya listesinde istediğiniz dosya veya klasörlerin **solundaki seçim kutularını** işaretleyin.
2. Alt tarafta **Hedef Seç** ile Mac'teki kayıt klasörünü belirleyin.
3. **Mac'e Aktar**a basın. İşlem bitene kadar uygulamayı ve USB bağlantısını açık tutun.

İsterseniz öğenin sağındaki üç çizgili tutamaçtan Finder'daki bir klasöre sürükleyebilirsiniz. Sağ tık menüsündeki **Kopyala (Finder'a Yapıştır)** öğeyi Mac'e hazırlayıp Finder'da `⌘V` ile yapıştırmanıza olanak verir.

## Mac'ten telefona kopyalama

- Finder'daki dosya veya klasörleri soldaki **Buraya Bırak** alanına sürükleyin. Dosyalar telefonda o anda açık olan klasöre gider.
- **Mac'ten Dosya Seç** ile dosya veya klasör seçin.
- Finder'da dosyaları `⌘C` ile kopyalayıp uygulamada **Yapıştır**a basın.
- Belirli bir telefon klasörüne göndermek için önce o klasöre girin. Klasör satırına bırakma ve klasöre sağ tıklayıp **Bu Klasöre Yapıştır** da kullanılabilir.

## Taşıma ve silme

- **Mac'ten Taşı:** Dosya telefona aktarıldıktan sonra Mac'teki aslı **Çöp Sepeti**ne taşınır.
- Telefonda bir öğeye sağ tıklayıp **Kes / Mac'e Taşı** seçerseniz, Mac'e aktarıldıktan sonra telefondaki aslı silinir.
- **Telefondan Sil** telefondaki öğeyi kalıcı olarak siler; klasör seçilirse içeriği de silinir. Uygulama önce onay ister.
- Hedefte aynı adda bir öğe varsa uygulama üzerine yazmaz. Taşıma sırasında hata olursa ekrandaki sonucu kontrol edin.

## Sorun giderme

| Sorun | Kontrol edin |
| --- | --- |
| **ADB bulunamadı** | Platform Tools'un `~/Library/Android/sdk/platform-tools/adb` konumunda olduğundan emin olun. |
| **Cihaz görünmüyor** | Veri kablosu, telefon kilidi, USB hata ayıklama ve telefondaki izin penceresi. Ardından **Cihazları Yenile**. |
| **Dosya listesi boş** | Telefon bağlı mı ve açık klasörde dosya var mı? **Yenile**ye basın. |
| **Aynı ad var** | Hedefteki dosyayı farklı adlandırın veya başka klasör seçin; uygulama mevcut dosyayı ezmez. |

USB bağlantısı kesilirse cihaz ve dosya listesi birkaç saniye içinde temizlenir. Uygulama Android'in ortak depolamasını gösterir; diğer uygulamaların özel verilerine erişmez. Bu sürüm yerel kullanım içindir ve mağazada yayımlanmamıştır.
