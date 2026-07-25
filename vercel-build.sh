#!/usr/bin/env bash
# Vercel build entrypoint for this Flutter web app.
# Vercel's build image has no Flutter SDK, so we fetch it, then regenerate the
# gitignored .env asset (see pubspec.yaml `assets: - .env`) from the project's
# Vercel Environment Variables before building.
set -euo pipefail

FLUTTER_VERSION="3.44.1"

cat > .env <<EOF
ISDASAFE_ANDROID_MAPS_KEY=${ISDASAFE_ANDROID_MAPS_KEY:-}
ISDASAFE_WEB_MAPS_KEY=${ISDASAFE_WEB_MAPS_KEY:-}
SUPABASE_URL=${SUPABASE_URL:-}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-}
GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID:-}
GOOGLE_IOS_CLIENT_ID=${GOOGLE_IOS_CLIENT_ID:-}
EOF

git clone https://github.com/flutter/flutter.git --depth 1 --branch "$FLUTTER_VERSION" _flutter
export PATH="$PATH:$(pwd)/_flutter/bin"

flutter config --enable-web
flutter pub get
flutter build web --release
