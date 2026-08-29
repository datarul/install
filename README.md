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
- `.env` gizli değerler içerir (600 izinli tutulur); yedeği her kayıtta `.env.bak`'a alınır.
