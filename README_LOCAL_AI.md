# Hibrit AI fotoğraf işleme

LUT Studio, hızlı ve güvenilir işlemler için iPhone üzerinde Core Image ve Core ML kullanır. Kullanıcı bulut işlemeyi açıkça etkinleştirip bir HTTPS sunucu adresi tanımlarsa, komut ve fotoğraf hibrit AI API'sine gönderilir. Bulut isteği başarısız olursa desteklenen yerel işlem zinciri denenir.

## İşleme yönlendirmesi

1. **Akıllı görüntü analizi:** Vision; fotoğrafın boyutlarını, portre/yatay yönünü, yüz sayısını ve öne çıkan sahne sınıflandırmalarını çıkarır. Bu bilgiler bulut isteğine bağlam olarak eklenir.
2. **Bulut AI (isteğe bağlı):** Çok adımlı fotoğraf düzenleme komutları ve analiz bilgisi tek istekle sunucuya gönderilir. Sunucu, seçilen bulut görüntü modelini çalıştırır ve JPEG çıktısını döndürür.
3. **Yerel Core ML:** FACEFIX için CodeFormer, HDREAL için Real-ESRGAN x4plus kullanılır.
4. **Yerel profesyonel efekt motoru:** GLOWUP, BGSTUDIO, SOFTLIGHT, PROSHOT, OLD2NEW, COLORFIX, NIGHTFIX, LONGEXPOSURE, MOTIONBLUR ve GOLDENHOUR mevcut Core Image zincirleriyle internet olmadan da çalışır.

## Bulut sunucusu sözleşmesi

iOS uygulamasına sağlayıcı API anahtarı gömülmez. OpenAI veya başka bir model sağlayıcısının anahtarı yalnızca sizin kontrol ettiğiniz backend ortam değişkenlerinde tutulmalıdır.

AI stüdyosunda **Bulut AI ile yüksek kalite** seçeneğini açın ve HTTPS endpoint adresini girin. Endpoint şu JSON isteğini kabul etmelidir:

~~~json
{
  "image_base64": "<base64 JPEG>",
  "mime_type": "image/jpeg",
  "commands": ["glowUp", "proShot"],
  "output_format": "jpeg",
  "analysis": {
    "image_width": 3024,
    "image_height": 4032,
    "face_count": 1,
    "portrait_orientation": true,
    "scene_labels": ["person", "outdoor"]
  }
}
~~~

Başarılı yanıt:

~~~json
{
  "image_base64": "<base64 processed JPEG>"
}
~~~

Hata yanıtı tercihen {"error":"Açıklayıcı hata"} biçiminde ve uygun HTTP hata koduyla dönmelidir. Sunucu; dosya boyutu sınırı, istek kimlik doğrulaması, hız sınırlama, geçici dosyaların silinmesi ve sağlayıcı anahtarlarının gizliliğinden sorumludur. Uygulama yalnızca HTTPS endpoint kabul eder.

## Gizlilik ve kontrol

- Bulut yüklemesi varsayılan olarak kapalıdır.
- Kullanıcı bulut seçeneğini açtığında seçilen fotoğraf işlenmek üzere yapılandırılan sunucuya gönderilir.
- Bulut kapalıysa fotoğraf cihazdan çıkmaz.
- Sağlayıcı anahtarları uygulama içine veya Git deposuna eklenmez.
- Bulut erişilemezse uygulama desteklenen yerel işlem hattına döner.
- Bulut sunucu adresi ve izin tercihi cihazdaki kullanıcı ayarlarında saklanır.

## Yerel modeller

- **CodeFormer:** Vision yüz algılama, yüz kırpma, Core ML çıkarımı ve yumuşak maske ile harmanlama. Resmî CodeFormer projesinin lisans koşullarını ve kullanılan ağırlıkların lisansını kontrol edin.
- **Real-ESRGAN x4plus:** Büyük görselleri örtüşen parçalara ayırarak x4 büyütme. Üst proje BSD-3-Clause lisanslıdır; dağıtımda atıf gerekliliklerini koruyun.
- Model paketleri depoya gömülmez; GitHub Actions dönüşüm iş akışı artifact üretir.

## Kapsam

Kişisel kullanım sürümünde Ghibli stil aktarımı, nesne silme, kıyafet değiştirme ve arka plan silme bulunmaz. AI video kare işleme henüz dahil değildir. LONGEXPOSURE tek fotoğraf üzerinde stilize bir efekttir; çoklu kareden gerçek uzun pozlama birleştirmesi değildir.

## OpenAI bulut sunucusu

OpenAI görsel düzenleme sunucusu `backend/` klasörüne eklendi. Render dağıtımı için kökteki `render.yaml` kullanılabilir. Ayrıntılı kurulum adımları `backend/README.md` içindedir. Sunucu `OPENAI_API_KEY` ve `APP_ACCESS_TOKEN` değerlerini yalnızca hosting ortam değişkenlerinden okur. iOS uygulamasındaki uygulama erişim anahtarı Keychain'de saklanır; OpenAI anahtarı uygulamaya gönderilmez.

Model yönlendirmesi: günlük hızlı işlemler için GPT Image 2.6 Flare; yüz/ayrıntı ve restorasyon ağırlıklı işlemler için GPT Image 2.6 Sunburst. Gerçek API maliyeti ve yanıt süresi seçilen model, görsel boyutu ve kaliteye göre değişir.
