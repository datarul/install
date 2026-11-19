# Datarul kurulum başlangıcı

Bu dosyalar Datarul tarafından teslim edilir; sunucuda Git deposu veya internetten `git pull` gerekmez.

Kurumun ayırdığı disk altında standart düzen:

```text
/data/datarul/
├── install/
└── uploads/
```

1. Docker ve Compose, yeterli disk, registry CA güveni ve erişim yetkileri hazırlanır.
2. Datarul'un verdiği `prepare-installation.sh`, yönetici tarafından çalıştırılır:

   ```bash
   sudo ./prepare-installation.sh --root /data/datarul --user mert --user ozlem
   ```

   Tek kullanıcıda da `datarul` grubu kullanılır. Kullanıcılar üyelik sonrası SSH oturumlarını yeniden açar.
   Docker/containerd veri dizinlerinin yeterli diskte bulunması ayrıca kontrol edilmelidir.
3. Kullanılacak registry'ye `docker login` yapılır; kaynak registry token'ı bootstrap tarafından sorulmaz.
4. Datarul'un verdiği **sürümü sabit** toolkit referansı ile scriptler çıkarılır:

   ```bash
   ./bootstrap.sh '<registry>/datarul/setup-tui:<version>@sha256:<digest>' /data/datarul/install
   ```

Bootstrap yalnız imajı alır ve export eder; ayar sihirbazı, grup hazırlığı veya deploy başlatmaz.
`.env`, `mapping.yaml`, sertifikalar ve mevcut kullanıcı verileri export ile değiştirilmemelidir.

Sonraki işlemler kurulum paketinin talimatlarıyla `/data/datarul/install` içinde yürütülür.
Registry'ye erişim, gerekli credential'lar ve host ön koşulları kurum tarafından sağlanır.
