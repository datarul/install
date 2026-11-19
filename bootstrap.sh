#!/usr/bin/env bash
# Verilen kurulum araç imajını alır ve mevcut install dizinine çıkarır.
# Registry girişi ve prepare-installation.sh önceden tamamlanmış olmalıdır.
set -euo pipefail
if [ "$#" -ne 2 ]; then
    echo 'Kullanım: ./bootstrap.sh <registry/repository:version[@sha256:digest]> <install-dizini>' >&2
    exit 2
fi
image="$1"
destination="$(cd "$2" && pwd -P)"
command -v docker >/dev/null 2>&1 || { echo 'Hata: Docker gerekli.' >&2; exit 2; }
docker pull "$image"
image_id="$(docker image inspect --format '{{.Id}}' "$image")"
# Export çağıranın UID'siyle ve install dizininin ortak grubuyla çalışır.
docker run --rm --pull=never --network none \
    --user "$(id -u):$(id -g)" --group-add "$(stat -c '%g' "$destination")" \
    -e HOME=/tmp -e "DATARUL_TOOLKIT_IMAGE_ID=$image_id" -e "DATARUL_TOOLKIT_REFERENCE=$image" \
    -e "DATARUL_HOST_INSTALL_DIR=$destination" \
    -v "$destination:/workdir" "$image_id" export
