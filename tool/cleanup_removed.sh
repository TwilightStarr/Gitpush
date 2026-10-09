#!/usr/bin/env bash
# Zip'i mevcut deponun ÜZERİNE açınca silinen dosyalar eski depoda kalır.
# Bu betik, tool/silinecek_dosyalar.txt içindeki dosyaları siler (git rm ile).
# Kullanım (depo kökünde):  bash tool/cleanup_removed.sh
set -euo pipefail
while IFS= read -r f; do
  [ -z "$f" ] && continue
  if [ -e "$f" ]; then git rm -q -f -- "$f" 2>/dev/null || rm -f -- "$f"; echo "silindi: $f"; fi
done < "$(dirname "$0")/silinecek_dosyalar.txt"
find lib test -type d -empty -delete 2>/dev/null || true
