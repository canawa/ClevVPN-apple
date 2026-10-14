#!/bin/bash
# Xcode pre-build: если Libbox нет — собирает автоматически (первый раз 10–30 мин).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRAMEWORK="$ROOT/Frameworks/Libbox.xcframework"
BUILD="$ROOT/scripts/build-libbox.sh"

has_binary() {
  find "$FRAMEWORK" \( -name 'Libbox' -o -name 'Libbox.a' \) 2>/dev/null | grep -q .
}

if [[ -d "$FRAMEWORK" ]] && has_binary; then
  echo "note: Libbox.xcframework OK"
  exit 0
fi

if [[ -d "$FRAMEWORK" ]]; then
  echo "warning: Libbox.xcframework повреждён — пересобираю"
  rm -rf "$FRAMEWORK"
fi

echo "==> Libbox отсутствует — запускаю scripts/build-libbox.sh"
echo "    (первый раз 10–30 минут; дальше Build мгновенный)"
chmod +x "$BUILD"
exec "$BUILD"
