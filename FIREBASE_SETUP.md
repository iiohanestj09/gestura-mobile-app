# Menyiapkan Firebase untuk Gestura

Firebase Auth dan Cloud Firestore sudah dipakai oleh aplikasi. Ikuti langkah ini
satu kali untuk menghubungkan aplikasi ke project Firebase milikmu.

## 1. Buat dan atur project Firebase

1. Buka [Firebase Console](https://console.firebase.google.com/) dan buat project.
2. Tambahkan aplikasi Android dengan package name `com.example.gestura`.
3. Buka **Authentication → Sign-in method**, lalu aktifkan **Email/Password**.
4. Buka **Firestore Database** dan buat database. Untuk tugas ini, pilih lokasi
   yang dekat dengan pengguna aplikasi.
5. Di halaman **Firestore Database → Rules**, salin isi file
   [`firestore.rules`](./firestore.rules), lalu tekan **Publish**. Aturan ini
   membatasi setiap pengguna agar hanya bisa membaca dan mengubah profil serta
   progres miliknya sendiri.

## 2. Hubungkan aplikasi Flutter

Di terminal, masuk ke folder project `gestura`, lalu jalankan:

```powershell
npm install -g firebase-tools
firebase login
dart pub global activate flutterfire_cli
flutterfire configure --platforms=android
```

Pilih project Firebase yang baru dibuat dan aplikasi Android yang terdaftar.
Perintah konfigurasi akan membuat `lib/firebase_options.dart` berisi konfigurasi
project Firebase-mu. File tersebut akan menggantikan placeholder yang ada di
project sekarang.

Kemudian jalankan aplikasi:

```powershell
flutter pub get
flutter run
```

Jangan menghapus `lib/firebase_options.dart` setelah menjalankan konfigurasi.
File itu menghubungkan aplikasi ke project Firebase-mu.

## 3. Coba alur aplikasi

1. Tekan **Mulai belajar**, isi nama, email, dan password (minimal 8 karakter).
2. Pendaftaran membuat akun di Firebase Authentication dan dokumen profil di
   `users/{uid}`.
3. Buka materi, lalu tekan **Tandai materi selesai**. Progres tersimpan di
   `users/{uid}/progress/{lessonId}`.
4. Keluar, lalu masuk lagi dengan akun yang sama. Progres tetap tersimpan dan
   dapat dilihat di tab Profil serta Riwayat belajar.
5. **Lupa password?** mengirim tautan pengaturan ulang melalui email.

Password hanya dikelola Firebase Authentication, tidak disimpan di Firestore.
Untuk versi tugas ini, konten materi tetap menggunakan data lokal; FastAPI
belum diperlukan untuk autentikasi atau progres.
