#!/usr/bin/env bash
set -euo pipefail

FLUTTER_DIR="${FLUTTER_HOME:-$HOME/flutter}"
CHANNEL="${FLUTTER_CHANNEL:-stable}"

if [[ ! -x "$FLUTTER_DIR/bin/flutter" ]]; then
  echo "Installing Flutter ($CHANNEL)…"
  rm -rf "$FLUTTER_DIR"
  git clone https://github.com/flutter/flutter.git \
    --branch "$CHANNEL" \
    --depth 1 \
    "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"
flutter --version
flutter config --no-analytics --enable-web
flutter pub get
flutter build web --release --no-wasm-dry-run

echo "Web build ready at build/web"
