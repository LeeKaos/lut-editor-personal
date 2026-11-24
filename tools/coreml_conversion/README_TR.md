# iOS Core ML model conversion (GitHub-hosted Mac)

Bu klasör, CodeFormer ve Real-ESRGAN ağırlıklarını GitHub Actions'ın macOS bilgisayarında Core ML `.mlpackage` biçimine dönüştürmek içindir. Model dosyaları Git deposuna commit edilmez; yalnızca Actions artifact olarak saklanır.

## Çalıştırma

1. GitHub deposunda **Actions** sekmesine girin.
2. **Convert AI models to Core ML** iş akışını açın.
3. **Run workflow** düğmesine basıp `feature/beautify-natural-grading` dalını seçin.
4. İşlem bitince **Artifacts** bölümünden `iOS-CoreML-models` ZIP dosyasını indirin.
5. ZIP'i iPhone'daki Dosyalar uygulamasına açın. `CodeFormer.mlpackage` ve `RealESRGAN_x4plus.mlpackage` paketlerini LUT Editor içindeki ilgili model yükleme alanlarından seçin.

## Model arayüzleri

- CodeFormer: `input` / `output`, NCHW RGB, 1×3×512×512, giriş ve çıkış [-1, 1]. Fidelity `w=0.7` ve `adain=True` model grafiğine sabitlenir.
- Real-ESRGAN x4plus: `input` NCHW RGB 1×3×64×64, `output` 1×3×256×256, değerler [0, 1].

## Önemli

- Dönüşüm ilk denemede başarısız olabilir: eski BasicSR/CodeFormer bağımlılıkları, PyTorch operatörleri veya Core ML dönüştürücüsü sürüm uyumsuzluğu çıkarabilir. Başarılı bir artifact oluşmadan modelleri çalışır olarak kabul etmeyin.
- Bu workflow macOS GitHub-hosted runner kullanır. GitHub Actions dakika kotası/ücretleri hesabınıza göre uygulanabilir. Uzun model dönüşümleri ücretli dakika tüketebilir.
- CodeFormer deposu NTU S-Lab License 1.0 ile lisanslıdır. Model ağırlıklarını yeniden dağıtmadan önce lisans koşullarını inceleyin. Real-ESRGAN deposu BSD-3-Clause lisanslıdır.
- Workflow sadece artifact üretir; model ağırlıkları veya Core ML paketleri kaynak koda eklenmez.
