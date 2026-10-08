#!/usr/bin/env bash
# Datarul kurulum bootstrap'ı — müşteri sunucusundaki tek giriş noktası.
#
# Tek gereksinim: Docker. Bu script Datarul'un verdiği Docker Hub erişim token'ını
# alır, Docker Hub'a login olur, kurulum araç imajını (datarulplatform/setup-tui)
# çeker, kurulum dosyalarını bu dizine çıkarır (export) ve ayar sihirbazını açar
# (--tui ile tam ekran ayar arayüzünü). İkisi de imajın içinden çalışır: export'tan önce
# sunucuda set-env.sh gibi script'ler henüz yoktur.
#
# ghcr.io'dan geçiş (2026-10): `git pull --ff-only && ./bootstrap.sh` → token'ı girin
# → `./deploy.sh --run`. .env'deki eski GITHUB_USERNAME/GITHUB_TOKEN ilk kayıtta silinir;
# deploy eski ghcr.io/datarul/* imajlarını temizler.
#
# Kullanım:
#   ./bootstrap.sh              # tam akış: login → pull → export → soru-cevap sihirbazı
#   ./bootstrap.sh --tui        # sihirbaz yerine tam ekran ayar arayüzü (TUI; TTY ister)
#   (--classic eski çağrılar için kabul edilir, varsayılanla aynı)
#   DATARUL_TUI_TAG=v1.2.3 ./bootstrap.sh   # belirli imaj versiyonu
#   DOCKERHUB_ACCESS_TOKEN=... ./bootstrap.sh # token'ı ortamdan ver (Enter ile kabul edilir)

set -euo pipefail
cd "$(dirname "$0")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# Docker Hub (org: datarulplatform) — setup'ın lib/registry.sh'ı ile aynı sabitler.
REGISTRY_USERNAME="datarulplatform"  # org access token: kullanıcı adı = org adı (sabit)
IMAGE="datarulplatform/setup-tui:${DATARUL_TUI_TAG:-latest}"

MODE=classic
case "${1:-}" in
    "" | --classic) ;;
    --tui) MODE=tui ;;
    *) echo -e "${RED}Hata:${NC} bilinmeyen seçenek: $1 — kullanım: $0 [--tui]" >&2; exit 1 ;;
esac

if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}Hata:${NC} docker bulunamadı. Önce Docker kurulmalı: https://docs.docker.com/engine/install/" >&2
    exit 1
fi

# Toolkit export edilmeden de çalışmalı: lib/install-permissions.sh ile aynı
# host sözleşmesi (setup testleri iki kopyanın eşitliğini doğrular).
install_policy_load() {
    local root="${1:-$PWD}" marker gid
    marker="$root/.datarul-install-group"
    INSTALL_GID=""
    if [ -e "$marker" ] || [ -L "$marker" ]; then
        if [ -L "$marker" ] || [ ! -f "$marker" ] || [ ! -r "$marker" ]; then
            echo "Hata: $marker okunamıyor veya normal dosya değil; eski sahibi/yönetici izin onarımı yapmalı." >&2
            return 1
        fi
        gid="$(cat "$marker")" || return 1
        case "$gid" in ''|*[!0-9]*|0|0*) echo "Hata: $marker geçerli sayısal GID içermeli." >&2; return 1;; esac
        if [ "${#gid}" -gt 10 ] || [ "$gid" -gt 2147483647 ]; then
            echo "Hata: $marker GID aralık dışında." >&2; return 1
        fi
        if [ "$(id -u)" != 0 ]; then
            case " $(id -G) " in *" $gid "*) ;; *)
                echo "Hata: $root için kurulum grubuna (GID=$gid) üyelik gerekli; üyelikten sonra yeniden oturum açın." >&2
                return 1;;
            esac
        fi
        INSTALL_GID="$gid"
    fi
}

install_require_readable_env() {
    local path="${1:-.env}"
    if [ -e "$path" ] || [ -L "$path" ]; then
        if [ -L "$path" ] || [ ! -f "$path" ] || [ ! -r "$path" ]; then
            echo "Hata: $path okunamıyor veya normal dosya değil. Eski sahibi/yönetici repair-install-permissions.sh --group <kurulum-grubu> -y ile onarmalı." >&2
            return 1
        fi
    fi
}

install_container_args() {
    install_policy_load "${1:-$PWD}" || return 1
    local options
    options="$(docker info --format '{{json .SecurityOptions}}')" || return 1
    INSTALL_RUN_AS=(-e HOME=/tmp)
    if [[ "$options" == *'"name=rootless"'* ]]; then
        if [ -n "$INSTALL_GID" ]; then
            echo "Hata: ortak kurulum GID=$INSTALL_GID rootless namespace'e doğrudan aktarılamaz; ortak kurulum için rootful Docker kullanın. Tek kullanıcı rootless desteklenir." >&2
            return 1
        fi
    else
        INSTALL_RUN_AS=(--user "$(id -u):$(id -g)" "${INSTALL_RUN_AS[@]}")
        if [ -n "$INSTALL_GID" ]; then
            INSTALL_RUN_AS+=(--group-add "$INSTALL_GID" -e "DATARUL_INSTALL_GID=$INSTALL_GID")
        fi
    fi
}


install_policy_load || exit 1
install_require_readable_env .env || exit 1
if [ -f .env ]; then source .env || exit 1; fi

echo -e "${GREEN}Datarul Kurulum${NC}"
echo "Docker Hub erişimi için Datarul'un verdiği erişim token'ı gerekli."
echo ""
# Önce açık ortam değişkeni, sonra mevcut .env. Token yalnız burada sorulur; sihirbaz/TUI .env'den okur.
# Enter = gösterilen (maskeli) kayıtlı token'ın TAM değeri kullanılır. Giriş reddedilirse token'ın
# kaynağı söylenir ve (TTY varsa) yeniden sorulur — reddedilen değer bir daha önerilmez.
DOCKERHUB_TOKEN="${DOCKERHUB_ACCESS_TOKEN:-${DOCKERHUB_TOKEN:-}}"
if [ -n "${DOCKERHUB_ACCESS_TOKEN:-}" ]; then
    token_source="DOCKERHUB_ACCESS_TOKEN ortam değişkenindeki token (shell profilinizden kaldırın)"
else
    token_source=".env'deki kayıtlı token"
fi
attempt=1
while :; do
    if [ -n "$DOCKERHUB_TOKEN" ]; then
        echo -n "Docker Hub erişim token'ı [***${DOCKERHUB_TOKEN: -4}] (Enter=koru): "
    else
        echo -n "Docker Hub erişim token'ı: "
    fi
    read -s hub_token || hub_token=""
    echo ""
    if [ -n "$hub_token" ]; then
        DOCKERHUB_TOKEN="$hub_token"
        token_source="girilen token"
    fi
    if [ -z "${DOCKERHUB_TOKEN:-}" ]; then
        echo -e "${RED}Hata:${NC} token boş olamaz." >&2
    elif printf '%s' "$DOCKERHUB_TOKEN" | docker login --username "$REGISTRY_USERNAME" --password-stdin; then
        break
    else
        echo -e "${RED}Hata:${NC} Docker Hub girişi başarısız ($REGISTRY_USERNAME) — reddedilen: ${token_source}." >&2
        DOCKERHUB_TOKEN=""
    fi
    if [ ! -t 0 ] || [ "$attempt" -ge 3 ]; then
        exit 1
    fi
    attempt=$((attempt + 1))
    echo "Datarul'un verdiği geçerli token'ı yapıştırın (deneme $attempt/3)."
done

if ! docker pull "$IMAGE"; then
    echo -e "${RED}Hata:${NC} $IMAGE çekilemedi." >&2
    echo "Token'ın Datarul depolarına okuma yetkisini kontrol edin — bu hatayı alıyorsanız" >&2
    echo "uygulama imajlarını da çekemezsiniz (aynı registry ve aynı yetki kullanılıyor)." >&2
    exit 1
fi

# Rootful Docker'da container UID/GID'ini cagiran kullaniciya sabitle; aksi halde
# bind mount'a yazilan dosyalar host'ta root sahipli kalir. Rootless Docker'da ise
# container UID 0 zaten daemon'u calistiran host kullanicisina eslenir. Orada
# `--user $(id -u):$(id -g)` kullanmak subordinate UID/GID'ye eslenir ve 0750
# izinli /workdir'e erisimi engeller.
install_container_args || exit 1

# Token'ı .env'e işle — imajdaki TEK yazıcıyla (write-env birleştirir: yalnız bu anahtar
# güncellenir, diğer değerler ve elle eklenmiş satırlar korunur; emekli GITHUB_* /
# DOCKERHUB_USERNAME anahtarları bu kayıtta düşer). Aynı kayıt anında boş makine sırları (realtime ticket secret,
# Redis parolası) da üretilir — deploy.sh üretmez.
printf 'DOCKERHUB_TOKEN=%s\n' "$DOCKERHUB_TOKEN" \
    | docker run --rm -i "${INSTALL_RUN_AS[@]}" -v "$PWD:/workdir" "$IMAGE" write-env

# Kurulum dosyalarını (compose, nginx, script'ler) imajdan bu dizine çıkar.
# .env'e ve sertifika/log dizinlerine dokunmaz; script/compose dosyalarını
# imajdaki versiyonla günceller.
docker run --rm "${INSTALL_RUN_AS[@]}" -v "$PWD:/workdir" "$IMAGE" export

if [ "$MODE" = classic ]; then
    # Sihirbaz imajdaki set-env.sh'tır (entrypoint `classic`). TTY varsa -t: token istemi
    # (read -s) ekrana yansımasın; TTY'siz (CI, pipe) -i yeter.
    tty_args=(-i)
    [ -t 0 ] && [ -t 1 ] && tty_args=(-it -e TERM)
    exec docker run --rm "${tty_args[@]}" --network host "${INSTALL_RUN_AS[@]}" -v "$PWD:/workdir" "$IMAGE" classic
fi

if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo -e "${YELLOW}Uyarı:${NC} TTY yok — TUI açılamaz. Soru-cevap sihirbazı için: ./bootstrap.sh" >&2
    exit 1
fi

# Host'ta algılanan sunucu IP'si TUI'ye varsayılan olarak iner ("algılanan: x.x.x.x"); container
# host ağını görmediği için bunu kendisi bulamaz. Boş bırakılan alan deploy'da yeniden algılanır.
HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
[ -z "$HOST_IP" ] && HOST_IP="$(ipconfig getifaddr en0 2>/dev/null || true)"
docker run --rm -it -e TERM -e COLORTERM -e "DATARUL_DEFAULT_SERVER_IP=$HOST_IP" \
    "${INSTALL_RUN_AS[@]}" -v "$PWD:/workdir" "$IMAGE" tui
tui_rc=$?
# Ekranı gerçekten temizle: bazı terminaller TUI'nin alternate-screen çıkış dizisini tanımıyor
# (içerik ekranda kalıyor). terminfo'ya bağlı değil: ekran + scrollback sil, imleç eve, göster.
[ -t 1 ] && printf '\033[2J\033[3J\033[H\033[?25h'
exit $tui_rc
