# Gestura

Demo UI Flutter untuk belajar BISINDO. Autentikasi, progres, pemutar video, kamera, pengenalan gerakan, dan preferensi di versi ini masih menggunakan simulasi lokal. Tidak ada backend, Firebase, atau model Computer Vision.

## Menjalankan

Persyaratan: Flutter SDK stable, Android Studio/Android SDK, dan emulator Android atau perangkat USB dengan USB debugging. Nama paket proyek adalah `gestura`.

Jika Flutter SDK tersedia di PATH, dari folder proyek jalankan:

```powershell
flutter pub get
flutter analyze
flutter run
```

Jika SDK berada di folder `flutter/` satu tingkat di atas proyek, gunakan `..\flutter\bin\flutter.bat` sebagai pengganti `flutter`.

## Struktur

- `lib/main.dart` — entry point aplikasi.
- `lib/app/gestura_app.dart` — konfigurasi aplikasi dan splash screen.
- `lib/features/auth/` — onboarding dan alur autentikasi demo.
- `lib/features/home/` — bottom navigation dan tab utama.
- `lib/features/details/` — kategori, materi, kamera simulasi, hasil, dan pengaturan.
- `lib/core/gestura_theme.dart` — warna dan komponen Material 3 Gestura.
- `lib/data/sample_data.dart` — kategori, materi, course, dan kosakata dummy.
- `lib/widgets/gestura_widgets.dart` — komponen yang digunakan ulang.
- `android/` — konfigurasi platform Android dan entry point Kotlin.
- `assets/videos/` — tempat menaruh video peraga BISINDO autentik.
- `assets/images/` — tempat menaruh aset visual lokal.

Gunakan rekaman peraga BISINDO yang tervalidasi untuk mengganti placeholder video sebelum materi dipublikasikan.
