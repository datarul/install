# Datarul Kurulum

Datarul'u kendi sunucunuza kurmak için giriş noktası.

## Gereksinimler

- Docker (compose eklentisiyle) — [kurulum](https://docs.docker.com/engine/install/)
- Datarul ekibinden alınmış GitHub kullanıcı adı + PAT (`read:packages` yetkisi yeterli)

## Kurulum

```bash
git clone https://github.com/datarul/install.git datarul && cd datarul
./bootstrap.sh
```

Bootstrap sırasıyla:

1. GitHub kimlik bilgilerinizi sorar ve `ghcr.io`'ya login olur,
2. kurulum araç imajını (`setup-tui`) çeker,
3. kurulum dosyalarını (docker compose, nginx, yardımcı script'ler) bu dizine çıkarır,
4. tam ekran ayar arayüzünü (TUI) açar — ayarlar `.env` dosyasına kaydedilir.

Ayarları tamamladıktan sonra:

```bash
./deploy.sh
```

## Notlar

- Bu clone bir **kurulum dizinidir**: bootstrap'ın çıkardığı dosyalar ve `.env`
  `.gitignore` ile izlenmez, `git status` temiz kalır. Buradan commit/push yapılmaz;
  bootstrap güncellemeleri için `git pull` yeterlidir.

- Ayarları sonradan değiştirmek için `./set-env.sh` (ayar TUI'si; ya da tekrar `./bootstrap.sh`).
- TTY olmayan/bozuk terminaller için klasik soru-cevap akışı: `./bootstrap.sh --classic`
- Belirli bir kurulum aracı versiyonu için: `DATARUL_TUI_TAG=<tag> ./bootstrap.sh`
- `.env` gizli değerler içerir (tek kullanıcıda 600, açıkça seçilen ortak kurulumda 660 izinli tutulur); yedeği her kayıtta `.env.bak`'a alınır.
- Bootstrap rootful ve rootless Docker'ı otomatik algılar; bind mount dosya sahipliğini her iki
  daemon türünde de komutu çalıştıran host kullanıcısında tutar.


## Birden fazla Linux kullanıcısıyla ortak kurulum

Ortak mod otomatik algılanmaz. Yönetici, yalnız yetkili kurulum hesaplarını içeren bir Linux
grubunu açıkça seçer. Grup adı veya GID ürün içinde sabit değildir. Onarım, seçilen sayısal
GID'yi kurulum dizinindeki `.datarul-install-group` dosyasına kaydeder; bu dosya `.env`'den
bağımsızdır ve export sırasında değiştirilmez. Grup değişikliği aynı onarım akışıyla yapılır.

| Dosya/dizin | Tek kullanıcı | Ortak kurulum |
|---|---|---|
| `.env`, `.env.bak` | `0600` | `0660`, seçilen kurulum grubu; others kapalı |
| Export edilen normal dosyalar | `0644` | `0664`, seçilen kurulum grubu |
| Export edilen çalıştırılabilir dosyalar | `0755` | `0775`, execute korunur |
| Yönetilen dizinler | Mevcut normal dizin davranışı | `2775`, setgid + grup yazma |

Secret yazıcısı rastgele isimli `0600` geçici dosya oluşturur, access ACL'yi kaldırır,
seçilen grubu ve son izinleri uygular, sonra atomik değiştirir. Yedek aynı yöntemle alınır;
önceki sahibin inode'una chmod veya `copy2` uygulanmaz. Default ACL'deki başka kullanıcı/grup
izinleri `.env` veya yedeğine aktarılmaz. Kayıtlar kullanıcılar arasında sırayla yapılmalıdır;
aynı anda açılan iki ayar oturumunun birleştirilmesi/transaction kilidi bu akışın parçası değildir.

Rootful container çağrıları host UID/primary GID'sini korur ve yalnız seçilen ek GID'yi
`--group-add` ile aktarır. Host grubunun container'ın `/etc/group` dosyasında bulunması gerekmez.
Tek kullanıcı rootless akışında `--user` kullanılmaz. Ortak host GID'si rootless namespace'e
doğrudan eşlenemediğinden **ortak kurulum rootful Docker gerektirir**; bu kombinasyon sessizce
farklı izin üretmek yerine açık hata verir. `userns-remap`, NFS root squash ve özel UID/GID
mapping'leri ayrıca değerlendirilmelidir.

### Mevcut kurulumun onarımı ve yayın sırası

Önce bu değişiklikleri içeren **setup-tui imajı** yayımlanmalı ve etiketi/digest'i doğrulanmalı.
Ardından **install/bootstrap.sh güncellenmeli**. Eski imajla yeni bootstrap veya eski bootstrap'la
ortak mod kullanmayın. Yeni bootstrap, export'tan önce `.env` okuduğu için bozuk kurulumda
**önce onarım**, sonra bootstrap/export yapılmalıdır. Onarım, export ve ayar kaydı uygulama
container'larını yeniden başlatmaz; deploy ayrı bir işlemdir.

Eski sahibi veya yönetici aşağıdaki işlemi kurulum sunucusunda uygular. Eski sahibin değiştiremediği
root/yabancı sahipli dosyalar varsa yönetici gerekir. Komut, yeni onarım script'i henüz export
edilmemiş olsa da çalışır. Grup üyeliği değişen kullanıcılar yeniden oturum açmalıdır.

```bash
cd /data/datarul                         # Kendi kurulum dizininiz
INSTALL_GROUP='<yetkili-kurulum-grubu>'   # Sunucuda önceden oluşturulmuş grup
INSTALL_GID="$(getent group "$INSTALL_GROUP" | cut -d: -f3)"
case "$INSTALL_GID" in ''|*[!0-9]*|0) echo 'Geçersiz kurulum grubu' >&2; exit 1;; esac
TOOLKIT_IMAGE='ghcr.io/datarul/setup-tui:<duzeltilmis-imaj-etiketi>'

# GHCR girişi yapılmış, Docker yetkili kullanıcıyla çekin.
docker pull "$TOOLKIT_IMAGE"
# Yönetici olarak DAR KAPSAMLI onarım; tüm /data ağacına recursive işlem yok.
sudo docker run --rm --network none --user 0:0 -e HOME=/tmp \
  -v "$PWD:/workdir" "$TOOLKIT_IMAGE" repair-permissions "$INSTALL_GID"

# install/bootstrap.sh güncellemesini alın (Git .git izinleri ayrıca uygun olmalı).
git pull --ff-only
# Düzeltilmiş imaj etiketiyle bootstrap/export ve ayar kaydı.
DATARUL_TUI_TAG='<duzeltilmis-imaj-etiketi>' ./bootstrap.sh
# Terminal uyumsuzsa: aynı değişkenle ./bootstrap.sh --classic
```

Onarım tekrar çalıştırılabilir. Kapsamı: kurulum kökü; imajın gerçek toolkit dosyaları ve bunların
mevcut dizinleri; `bootstrap.sh`, `README.md`, `.gitignore`; `.env`, `.env.bak`, eski `.env.tmp`
ve `.env.bak.*` yedekleri; bilinen yazıcı geçici dosyaları; üretilen `nginx/conf.d/00-upstream.conf`,
`nginx/conf.d/default.conf` ve `docker-compose.ldap.yml`. Dosya sahibi UID'leri korunur;
sonraki atomik kayıt/export yeni sahibin UID'sine geçer. `.git`, `cert`, `logs`, `nginx/ssl`,
uploads ve listede olmayan dosyalar değiştirilmez. Yönetilen yoldaki symlink/hard link onarımı
durdurur; yönetici bu yolu ayrıca incelemelidir. `.git` erişimi ve Git güvenli-dizin ayarları
ayrı sorumluluktur; bu onarım Git yapılandırmasını değiştirmez.

Yeni script erişilebilir hale geldikten sonra aynı işlem:
`./repair-install-permissions.sh --group "$INSTALL_GROUP" -y`.
Bu biçim eski sahibin tüm yönetilen yolları değiştirebildiği ve gruba üye olduğu kurulumlar
içindir; aksi halde yönetici yukarıdaki container komutunu kullanır. Grup kimliği, yalnız yetkili
hesapların üye olduğu gruptan seçilmelidir; ortak grup üyeleri kurulum secret'larına erişir.

İçerik göstermeden her iki hesapta doğrulayın:

```bash
test -r .env && test -w .env
test -r .env.bak && test -w .env.bak    # En az bir ikinci kayıttan sonra
test -w lib && test -w deploy.sh && test -x deploy.sh
getfacl -p .env .env.bak lib deploy.sh docker-compose.yml
```

A kullanıcısı ayar kaydeder, B okuyup tekrar kaydeder, A tekrar kaydeder. Her iki kullanıcıyla
bootstrap/export tekrarlanır. Grup dışı bir hesapta `.env` ve `.env.bak` için `test -r` başarısız
olmalıdır. `cat .env`, `bash -x` veya secret içeriklerini loglayan kontroller kullanılmaz.
