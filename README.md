# Niceflix

แอปดูหนังจาก OneDrive — Android TV (APK) และเว็บ

โค้ดอยู่ที่โฟลเดอร์ [`flutter/`](flutter/)

## Android TV (APK)

```bash
cd flutter
flutter pub get
flutter build apk --release
```

ไฟล์อยู่ที่ `flutter/build/app/outputs/flutter-apk/app-release.apk`

## เว็บ (Vercel)

Build อัตโนมัติจาก `vercel.json` ที่ root → รัน `flutter/scripts/vercel-build.sh`

หรือ build เองแล้ว deploy:

```bash
cd flutter
flutter build web --release --no-wasm-dry-run
npx vercel deploy build/web --prod --project niceflix
```

Production: [https://niceflix-ten.vercel.app](https://niceflix-ten.vercel.app)

## OneDrive

ใช้ Microsoft device-code login (เหมือนบน TV) — สิทธิ์ Graph `Files.Read`
