#!/usr/bin/env bash
# Datarul kurulum bootstrap'ı — müşteri sunucusundaki tek giriş noktası.
#
# Tek gereksinim: Docker. Bu script GitHub kimlik bilgilerini alır, ghcr.io'ya
# login olur, kurulum araç imajını (setup-tui) çeker, kurulum dosyalarını bu
# dizine çıkarır (export) ve tam ekran ayar arayüzünü (TUI) açar.
#
# Kullanım:
#   ./bootstrap.sh              # tam akış: login → pull → export → TUI
#   ./bootstrap.sh --classic    # TUI yerine klasik soru-cevap akışı (TTY'siz/bozuk terminal)
#   DATARUL_TUI_TAG=v1.2.3 ./bootstrap.sh   # belirli imaj versiyonu

set -euo pipefail
cd "$(dirname "$0")"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

IMAGE="ghcr.io/datarul/setup-tui:${DATARUL_TUI_TAG:-latest}"

if ! command -v docker >/dev/null 2>&1; then
    echo -e "${RED}Hata:${NC} docker bulunamadı. Önce Docker kurulmalı: https://docs.docker.com/engine/install/" >&2
    exit 1
fi

# Mevcut .env'den varsayılanları yükle (varsa)
[ -f .env ] && source .env 2>/dev/null || true

echo -e "${GREEN}Datarul Kurulum${NC}"
echo "GitHub Container Registry erişimi için kimlik bilgileri gerekli"
echo "(PAT için read:packages yetkisi yeterlidir)."
echo ""
echo -n "GitHub kullanıcı adı [${GITHUB_USERNAME:-}]: "
read gh_user
GITHUB_USERNAME="${gh_user:-${GITHUB_USERNAME:-}}"
if [ -z "$GITHUB_USERNAME" ]; then
    echo -e "${RED}Hata:${NC} kullanıcı adı boş olamaz." >&2
    exit 1
fi

if [ -n "${GITHUB_TOKEN:-}" ]; then
    echo -n "GitHub PAT [***${GITHUB_TOKEN: -4}] (Enter=koru): "
else
    echo -n "GitHub PAT: "
fi
read -s gh_token
echo ""
[ -n "$gh_token" ] && GITHUB_TOKEN="$gh_token"
if [ -z "${GITHUB_TOKEN:-}" ]; then
    echo -e "${RED}Hata:${NC} PAT boş olamaz." >&2
    exit 1
fi

echo "$GITHUB_TOKEN" | docker login ghcr.io -u "$GITHUB_USERNAME" --password-stdin

if ! docker pull "$IMAGE"; then
    echo -e "${RED}Hata:${NC} $IMAGE çekilemedi." >&2
    echo "PAT'inizin paket erişimini kontrol edin — bu hatayı alıyorsanız uygulama" >&2
    echo "imajlarını da çekemezsiniz (aynı registry ve aynı yetki kullanılıyor)." >&2
    exit 1
fi

# Kimlik bilgilerini .env'e işle (diğer değerlere dokunmadan güncelle/ekle).
env_set() {
    local key="$1" val="$2"
    touch .env
    if grep -q "^export ${key}=" .env; then
        sed -i.tmp "s|^export ${key}=.*|export ${key}=\"${val}\"|" .env && rm -f .env.tmp
    else
        echo "export ${key}=\"${val}\"" >> .env
    fi
    chmod 600 .env
}
env_set GITHUB_USERNAME "$GITHUB_USERNAME"
env_set GITHUB_TOKEN "$GITHUB_TOKEN"

# Container'ı çağıran kullanıcının UID/GID'iyle koştur — root koşarsa yazdığı
# .env/dosyalar host'ta root sahipli kalır ve sonraki koşular "Permission denied"
# alır (Linux bind-mount davranışı). HOME=/tmp: imajda bu UID'nin passwd kaydı yok.
RUN_AS=(--user "$(id -u):$(id -g)" -e HOME=/tmp)

# Kurulum dosyalarını (compose, nginx, script'ler) imajdan bu dizine çıkar.
# .env'e ve sertifika/log dizinlerine dokunmaz; script/compose dosyalarını
# imajdaki versiyonla günceller.
docker run --rm "${RUN_AS[@]}" -v "$PWD:/workdir" "$IMAGE" export

if [ "${1:-}" = "--classic" ]; then
    exec docker run --rm -i --network host "${RUN_AS[@]}" -v "$PWD:/workdir" "$IMAGE" classic
fi

if [ ! -t 0 ] || [ ! -t 1 ]; then
    echo -e "${YELLOW}Uyarı:${NC} TTY yok — TUI açılamaz. Klasik akış için: ./bootstrap.sh --classic" >&2
    exit 1
fi

exec docker run --rm -it -e TERM -e COLORTERM "${RUN_AS[@]}" -v "$PWD:/workdir" "$IMAGE" tui
