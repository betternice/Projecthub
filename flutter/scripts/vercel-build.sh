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
flutter build web --release --no-wasm-dry-run --base-href=/

if [[ ! -f build/web/index.html ]]; then
  echo "ERROR: build/web/index.html missing" >&2
  exit 1
fi

# Ensure SPA entry is clearly HTML for static hosts
if ! grep -q '<!DOCTYPE html>' build/web/index.html; then
  echo "ERROR: build/web/index.html is not HTML" >&2
  exit 1
fi

# Static hosting hints when someone deploys build/web directly
cat > build/web/vercel.json <<'EOF'
{
  "rewrites": [
    { "source": "/((?!assets/|canvaskit/|icons/).*)", "destination": "/index.html" }
  ],
  "headers": [
    {
      "source": "/index.html",
      "headers": [
        { "key": "Content-Type", "value": "text/html; charset=utf-8" },
        { "key": "Cache-Control", "value": "no-cache" }
      ]
    },
    {
      "source": "/(.*)\\.js",
      "headers": [{ "key": "Content-Type", "value": "application/javascript; charset=utf-8" }]
    }
  ]
}
EOF

echo "Web build ready at build/web"
