# Kablosuz dosya aktarımı: Mac ve Samsung S24

## Hedef

Mac uygulamasından telefonun izin verilen dosyalarını gezmek ve iki yönde kopyalamak; telefondaki kendi uygulamamızdan da Mac kullanıcı klasörünü gezmek ve iki yönde kopyalamak. USB/ADB akışı korunur. Telefon uygulaması Flutter arayüzlü, yerel APK olarak kurulabilir. Hesap veya üçüncü taraf dosya paylaşım uygulaması gerekmez. Mevcut kablosuz gezgin telefonda `/storage/emulated/0` kökünü, Mac'te kullanıcı klasörünü gerçek dizin ve dosya adlarıyla gösterir.

## Ağ gerçeği ve kapsam

| Durum | Doğrudan bağlantı | Yöntem |
| --- | --- | --- |
| İkisi aynı Wi-Fi'de | Genellikle evet | Yerel IP, otomatik keşif veya QR eşleştirme |
| Mac telefonun mobil erişim noktasında | Genellikle evet | Mac ve telefon aynı yerel ağda; yerel IP/QR |
| Telefon mobil veride, Mac ev Wi-Fi'de | Koşullu | Mac'in genel IPv4/IPv6 adresi ve gerekiyorsa modem port yönlendirmesi |
| İki farklı Wi-Fi / telefon mobil veride, en az bir cihaz erişilebilir | Evet | Erişilebilir cihaza öbür cihaz bağlantı başlatır; tek oturum iki yönlüdür |
| İkisi farklı, dışarıdan erişilemeyen ağlarda | Hayır | Doğrudan bağlantı kurulamaz; bu durum kapsam dışında |

SFTP veya kendi uygulamamızı yazmak son satırdaki NAT/CGNAT engelini kaldırmaz. Dolayısıyla **hiçbir dış bağlantı noktası kullanmadan her farklı ağda çalışma** sözü verilemez. Mobil erişim noktasında görülen dış IP, ev modeminin erişilebilirliğini göstermez. Ev ağının WAN koşulları ayrıca kontrol edilecek.

## Mimari kararı

1. **Telefon uygulaması gerekli.** Samsung Dosyalar'ın ağ depolama seçeneği istemcidir; Mac'in telefon dosyalarını kablosuz gezmesine sunucu sağlamaz.
2. Android tarafı: Flutter arayüzü; kamera, depolama ve gerektiğinde ağ işlemleri için Kotlin katmanı. Yerel APK, Android'in **Tüm dosyalara erişim** iznini kullanıcıdan ister ve ağ sunucusu ortak depolamanın `/storage/emulated/0` kökünü açar. Android 11+ `Android/data` gibi korunan uygulama özel yolları yine kısıtlar. İleride daha dar izin modeli değerlendirilebilir.
3. Mac tarafı: mevcut SwiftUI uygulamasına kablosuz oturum ve karşılıklı dosya işlemleri eklenir. Masaüstü, İndirilenler ve Resimler için erişim macOS'un dosya gizliliği izinlerine tabidir; uygulama gerektiğinde kullanıcıya klasör seçtirir.
4. **Tek bağlantı, iki yönlü işlemler:** bağlantıyı hangi cihaz başlatırsa başlatsın, iki uygulama da karşı tarafın izinli dosyalarını listeleyebilir, alabilir ve gönderebilir. Dosya aktarımı parçalı akış, iptal, yeniden deneme ve aynı isim çakışması yönetimiyle yapılır. Kimlik doğrulama ve şifreli taşıma tamamlanmadan dış ağ erişimi açılmaz.
5. **QR eşleştirme:** Mac QR üretir, telefon tarar ve Mac'e bağlanır. Telefon QR üretir, Mac kamerasıyla tarar ve telefona bağlanır. QR adres, port, tek kullanımlık eşleştirme bilgisi ve sunucu kimliğini taşır; parolayı veya kalıcı özel anahtarı taşımaz. Kamera izni yoksa kod/adres girme yedeği olur. QR bağlantı yönünü belirler, dosya aktarım yönünü belirlemez.
6. Ağ: aynı ağ ve telefon erişim noktasında yerel adres kullanılır. Farklı ağda QR içindeki yerel adres tek başına yetmez; uygulama erişilebilir genel adresi kullanır. Telefon mobil ağda ve erişilemezse Mac'in QR'ı telefondan taranarak telefon Mac'e çıkış bağlantısı açar; Mac de aynı oturum üzerinden telefonu gezebilir.

## Aşamalar ve kabul ölçütleri

### 1. Yerel bağlantı ve eşleştirme

- Flutter APK telefonda açılır; temel koleksiyonlara Android'in izin verdiği şekilde erişir.
- Mac ve telefon aynı Wi-Fi'de veya telefonun erişim noktasındayken Mac QR → telefon tarama ve telefon QR → Mac kamera tarama akışları eşleşir; bağlantı kopunca iki arayüz de eski dosya listesini temizler.
- Yanlış eşleştirme koduyla erişim reddedilir.

### 2. İki yönlü dosya işlemleri

- Mac'ten telefondaki `/storage/emulated/0` içindeki erişilebilir klasörler gerçek adlarıyla gezilir; telefon → Mac ve Mac → telefon kopyalama yapılır.
- Telefondan Mac kullanıcı klasörünün erişilebilen içeriği gerçek adlarıyla gezilir; her iki yönde kopyalama yapılır.
- Klasör aktarımı, sürükle bırak (Mac), kopyala/yapıştır, taşıma ve silme uygun onaylarla çalışır. Hedefte aynı ad varsa veri sessizce ezilmez.
- Büyük dosya aktarımı ekrana yüzde/işlem durumu verir; bağlantı kesintisi eksik dosyayı tamamlanmış gibi göstermez.

### 3. Farklı ağ

- Mac ev ağına bağlandığında genel IPv4/IPv6 ve modem WAN durumu kontrol edilir.
- Erişilebilir uç nokta varsa güvenli doğrudan bağlantı telefon mobil verideyken iki yönde gerçek cihazda sınanır.
- CGNAT ve genel IPv6 yoksa kullanıcıya fiziksel sınır açıkça gösterilir. Bu durumda genel adres veya kullanıcıya ait erişilebilir sunucu/relay olmadan farklı ağ desteği tamamlanmış sayılmaz.

## Şu anki durum

04.11.2026'da Mac telefonun mobil erişim noktasına bağlıydı. Bu durum yerel ağ akışının denenmesine elverişlidir; ev modeminin uzaktan erişim koşullarını ölçmeye elverişli değildir. USB/ADB akışı korunarak Mac'e Kablolu/Kablosuz ekranları, Flutter APK'ya gerçek `/storage/emulated/0` kökü ve karşılıklı QR üretme/tarama akışları eklendi. Mac paylaşımı kullanıcı klasörünü gerçek adlarıyla açıyor. İki uygulamada çoklu aktarım için dosya bazında byte ilerlemesi ve sonuç özeti eklendi. Mac HTTP sunucusunda parçalı PUT gövdesi ve kök yol çözümleme düzeltildi; izole Mac–Dart protokol testlerinde dosya içeriği doğrulandı. İki cihaz arası güncel çoklu aktarım akışı henüz gerçek cihazda yeniden doğrulanmadı. **Bu henüz bitmiş kablosuz sürüm değildir:** bağlantı HTTP ile şifresizdir; dış ağ erişimi kodda reddedilir. Klasör aktarımı, taşıma/silme, 64 MB üzeri dosya akışı ve güvenli uzak erişim tamamlanmadı.
