#!/bin/bash
# Сборка Libbox.xcframework (ядро sing-box) для iOS + iOS Simulator.
# Требует: macOS, Xcode, go (brew install go).
# Результат: Frameworks/Libbox.xcframework
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${SING_BOX_SRC:-$ROOT/scripts/sing-box}"
# Стабильный тег sing-box (можно переопределить: SING_BOX_TAG=v1.12.0 ./scripts/build-libbox.sh)
TAG_PIN="${SING_BOX_TAG:-}"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: Libbox собирается только на macOS с Xcode" >&2
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "error: нужен Go — brew install go" >&2
  exit 1
fi

if [[ ! -d "${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" ]]; then
  echo "error: не найден Xcode (DEVELOPER_DIR /Applications/Xcode.app)" >&2
  exit 1
fi

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
export PATH="$PATH:$(go env GOPATH)/bin"

if [[ ! -d "$SRC/.git" ]]; then
  echo "==> Cloning SagerNet/sing-box"
  rm -rf "$SRC"
  git clone --depth 50 https://github.com/SagerNet/sing-box.git "$SRC"
fi

cd "$SRC"
git fetch --tags --depth 50 origin 2>/dev/null || true

if [[ -n "$TAG_PIN" ]]; then
  TAG="$TAG_PIN"
else
  # Последний стабильный тег (без -rc/-beta/-alpha)
  TAG="$(git tag -l 'v*' | grep -Ev 'rc|beta|alpha' | sort -V | tail -1)"
fi

if [[ -z "$TAG" ]]; then
  echo "error: не найден тег sing-box" >&2
  exit 1
fi

echo "==> Building sing-box $TAG → Libbox.xcframework"
git checkout -q "$TAG"

echo "==> Installing gomobile (make lib_install)"
make lib_install

echo "==> Building Libbox for ios + iossimulator (это 10–30 мин при первом запуске)"
# sing-box 1.11+: -target apple, конкретные платформы через -platform.
# Старый флаг -target ios игнорируется и оставляет пустой результат.
if go run ./cmd/internal/build_libbox -h 2>&1 | grep -q -- '-target'; then
  go run ./cmd/internal/build_libbox -target apple -platform "ios,iossimulator"
else
  # Fallback для очень старых веток
  go run ./cmd/internal/build_libbox -target ios
fi

if [[ ! -d Libbox.xcframework ]]; then
  echo "error: Libbox.xcframework не появился после сборки" >&2
  exit 1
fi

rm -rf "$ROOT/Frameworks/Libbox.xcframework"
mkdir -p "$ROOT/Frameworks"
cp -R Libbox.xcframework "$ROOT/Frameworks/"
echo "==> Done: $ROOT/Frameworks/Libbox.xcframework"
ls -la "$ROOT/Frameworks/Libbox.xcframework"
