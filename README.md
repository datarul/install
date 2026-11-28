# Datarul kurulum başlangıcı

Bu dosyalar Datarul tarafından teslim edilir; sunucuda Git deposu veya internetten `git pull` gerekmez.

Kurumun ayırdığı disk altında standart düzen:

```text
/data/datarul/
├── install/
│   ├── deploy.sh       tek giriş: ./deploy.sh <komut>
│   ├── .env            kurulum ayarları ve secret'lar
│   ├── mapping.yaml    imaj sürümleri
│   ├── toolkit/        Datarul tarafından yönetilir, her sürümde bütünüyle yenilenir
│   └── state/          sertifika, TLS, log ve çalışma durumu; sürüm yükseltmesi dokunmaz
├── uploads/
└── backups/
```

1. Docker ve Compose, yeterli disk, registry CA güveni ve erişim yetkileri hazırlanır.
2. Datarul'un verdiği `prepare-installation.sh`, yönetici tarafından çalıştırılır:

   ```bash
   sudo ./prepare-installation.sh --user mert --user ozlem
   ```

   Script disk önerisini onaya sunar. Tahsis edilmiş bir dizin için `--root /data/datarul --fresh` kullanın.
   Önce `--check` (salt kontrol) veya `--dry-run` (çalıştırılacak komutların listesi) ile planı görebilirsiniz.
   Tek kullanıcıda da `datarul` grubu kullanılır. Kullanıcılar üyelik sonrası SSH oturumlarını yeniden açar.
   Docker/containerd veri dizinlerinin yeterli diskte bulunması ayrıca kontrol edilmelidir.
3. Kullanılacak registry'ye `docker login` yapılır; kaynak registry token'ı bootstrap tarafından sorulmaz.
4. Datarul'un verdiği **sürümü sabit** toolkit referansı ile scriptler çıkarılır:

   ```bash
   ./bootstrap.sh '<registry>/datarul/setup-tui:<version>@sha256:<digest>' /data/datarul/install
   ```

Bootstrap yalnız imajı alır ve export eder; ayar sihirbazı, grup hazırlığı veya deploy başlatmaz.
`.env`, `mapping.yaml`, sertifikalar ve mevcut kullanıcı verileri export ile değiştirilmemelidir.

Sonraki işlemler seçilen kökün `install/` dizininde `./deploy.sh` ile yürütülür:

```bash
./deploy.sh set-env        # ayarlar; mapping.yaml yoksa onaylı imaj etiketlerini sorar
./deploy.sh install-infra  # ilk kurulumda veritabanı, RabbitMQ ve Redis
./deploy.sh run            # etkin uygulamaların tam dağıtımı
./deploy.sh help           # bütün komutlar
```

Sertifikalar `state/cert/`, TLS dosyaları `state/ssl/` altına konur.
Registry'ye erişim, gerekli credential'lar ve host ön koşulları kurum tarafından sağlanır.
