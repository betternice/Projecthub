# Niceflix (Flutter)

This repo is a Flutter app under `flutter/`. Android TV and web share one codebase; use `kIsWeb` / platform checks for differences. Do not reintroduce Expo or React Native.

## Commands

```bash
cd flutter
flutter pub get
flutter analyze
flutter build apk --release
flutter build web --release --no-wasm-dry-run
```

## Deploy

- APK: build locally only
- Web: Vercel uses root `vercel.json` → `cd flutter && bash scripts/vercel-build.sh` → output `flutter/build/web`
