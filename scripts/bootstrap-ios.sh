#!/bin/bash
# Однократная подготовка iOS-клиента на Mac заказчика.
# После скрипта: открыть ClevVPN.xcodeproj → схема ClevVPN → выбрать Team → Run на устройстве.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: нужен macOS с Xcode" >&2
  exit 1
fi

echo "==> 1/4 Проверка инструментов"
if ! command -v brew >/dev/null 2>&1; then
  echo "error: установите Homebrew — https://brew.sh" >&2
  exit 1
fi
command -v go >/dev/null 2>&1 || brew install go
command -v xcodegen >/dev/null 2>&1 || brew install xcodegen
xcode-select -p >/dev/null

echo "==> 2/4 Сборка ядра Libbox (sing-box) для iOS"
chmod +x scripts/build-libbox.sh scripts/ensure-libbox.sh
./scripts/build-libbox.sh

echo "==> 3/4 Генерация Xcode-проекта"
xcodegen generate
# На случай если xcodegen старый — добить ссылки на Libbox в pbxproj
if command -v python3 >/dev/null 2>&1; then
  python3 scripts/patch-libbox-pbxproj.py || true
fi

echo "==> 4/4 Готово"
echo ""
echo "Дальше в Xcode:"
echo "  1. open ClevVPN.xcodeproj"
echo "  2. Схема: ClevVPN (не ClevVPNPreview)"
echo "  3. Signing: ваш платный Apple Developer Team для"
echo "     таргетов ClevVPN и PacketTunnel"
echo "  4. В Developer Portal создайте App Group: group.com.clevvpn.ios"
echo "     и включите Network Extension (Packet Tunnel) для"
echo "     com.clevvpn.ios и com.clevvpn.ios.tunnel"
echo "  5. Run на физическом iPhone"
echo ""
echo "Симулятор: UI работает; системный VPN-туннель — только на устройстве."
open "$ROOT/ClevVPN.xcodeproj"
