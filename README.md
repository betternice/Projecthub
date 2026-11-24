# Movie Collection

แอป Android สำหรับเปิดคลังหนังจากไฟล์ใน OneDrive มีปก เรื่องย่อ และหน้ารายละเอียด แล้วเล่นไฟล์ด้วยตัวเล่นของเครื่อง

## รันบนมือถือ

โปรเจกต์นี้เป็น Flutter และล็อกเวอร์ชันไว้ด้วย [FVM](https://fvm.app) ใน `.fvmrc` ต่อมือถือหรือเปิด emulator แล้วรัน

```bash
fvm install
fvm flutter pub get
fvm flutter run
```

## เชื่อม OneDrive

1. เปิด [portal.azure.com](https://portal.azure.com) แล้วสร้าง App registration ชื่อ Movie Collection
2. เลือกบัญชี Microsoft ทั้งส่วนตัวและที่ทำงาน
3. ไปที่ Authentication แล้วตั้ง Allow public client flows เป็น Yes
4. เพิ่มสิทธิ์ Microsoft Graph แบบ Delegated ชื่อ `Files.Read`
5. นำ Application (client) ID มาใส่ในหน้าเข้าสู่ระบบของแอป

จากนั้นแอปจะให้รหัสสำหรับยืนยันที่หน้า Microsoft แล้วยืนยันด้วยบัญชีที่เป็นเจ้าของไฟล์หนัง

## ปกและรายละเอียด

แอปจับชื่อไฟล์แล้วดึงปก ภาพ และเรื่องย่อมาให้เอง ถ้าใส่ API key จาก [themoviedb.org](https://www.themoviedb.org/settings/api) จะได้รูปนักแสดงเพิ่ม

## การเล่น

ตอนกดเล่น แอปขอลิงก์ไฟล์ต้นฉบับจาก OneDrive แล้วส่งให้ตัวเล่นของเครื่อง ไฟล์ mp4 และ mkv ที่เป็นวิดีโอทั่วไปเล่นได้ ไฟล์ที่เครื่องถอดรหัสไม่ได้จะเล่นไม่ได้

## โครงสร้างโค้ด

```
lib/
  app/        router, theme, MaterialApp
  core/       DI, error, network, utils, widgets ที่ใช้ร่วมกัน
  features/
    auth/          เข้าสู่ระบบ Microsoft แบบ device code
    library/       คลังไฟล์และโฟลเดอร์ใน OneDrive
    metadata/      ปกและรายละเอียดจาก TMDB และ Wikipedia
    settings/      TMDB API key
    movie_detail/  หน้ารายละเอียด
    player/        หน้าเล่นวิดีโอ
```

แต่ละ feature แบ่งเป็น `domain` (entity, repository interface, use case), `data` (data source, repository) และ `presentation` (Cubit, page)
