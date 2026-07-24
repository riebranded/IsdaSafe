#!/usr/bin/env bash
# Builds the Flutter web app for Vercel. Vercel's build image has no Flutter
# SDK preinstalled, so this fetches it, then recreates the gitignored .env
# asset (see pubspec.yaml's `assets: - .env`) from Vercel Environment
# Variables before building — main.dart reads SUPABASE_URL/SUPABASE_ANON_KEY
# out of that bundled file at runtime, not from the OS environment.
set -euo pipefail

echo "==> Installing Flutter SDK (stable channel)"
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

flutter doctor
flutter pub get

echo "==> Writing .env from Vercel Environment Variables"
cat > .env <<EOF
SUPABASE_URL=${SUPABASE_URL:-}
SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY:-}
GOOGLE_WEB_CLIENT_ID=${GOOGLE_WEB_CLIENT_ID:-}
GOOGLE_IOS_CLIENT_ID=${GOOGLE_IOS_CLIENT_ID:-}
ISDASAFE_ANDROID_MAPS_KEY=${ISDASAFE_ANDROID_MAPS_KEY:-}
ISDASAFE_WEB_MAPS_KEY=${ISDASAFE_WEB_MAPS_KEY:-}
EOF

echo "==> Building Flutter web (release)"
flutter build web --release
