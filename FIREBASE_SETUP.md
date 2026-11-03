# Menyiapkan Firebase untuk Gestura

Firebase Auth dan Cloud Firestore sudah dipakai oleh aplikasi. Ikuti langkah ini
satu kali untuk menghubungkan aplikasi ke project Firebase milikmu.

## 1. Buat dan atur project Firebase

1. Buka [Firebase Console](https://console.firebase.google.com/) dan buat project.
2. Tambahkan aplikasi Android dengan package name `com.example.gestura`.
3. Buka **Authentication → Sign-in method**, lalu aktifkan **Email/Password**
   dan **Google**. Untuk Google, isi nama publik `Gestura` dan pilih email
   support project.
4. Buka **Firestore Database** dan buat database. Untuk tugas ini, pilih lokasi
   yang dekat dengan pengguna aplikasi.
5. Di halaman **Firestore Database → Rules**, salin isi file
   [`firestore.rules`](./firestore.rules), lalu tekan **Publish**. Aturan ini
   membatasi setiap pengguna agar hanya bisa mengakses profil, progres, sesi
   latihan, dan masukan miliknya sendiri.
6. Untuk Google Sign-In Android, tambahkan fingerprint **SHA-1 debug** aplikasi
   di **Project settings → Your apps → aplikasi Android → Add fingerprint**.
   Di project ini, ambil nilainya dengan `.\gradlew signingReport` dari folder
   `android`.
7. Setelah Google provider aktif dan SHA-1 ditambahkan, unduh ulang
   `google-services.json` dari pengaturan aplikasi Android Firebase dan
   gantikan file `android/app/google-services.json`. Pastikan file baru berisi
   OAuth client bertipe `3`; tanpa itu Google Sign-In Android tidak dapat
   menyelesaikan konfigurasi klien.
8. Agar tautan verifikasi membuka aplikasi Android:
   - Di **Project settings → Your apps → aplikasi Android**, daftarkan SHA-1
     dan SHA-256 debug yang sama dari `signingReport`.
   - Di **Authentication → Settings → Authorized domains**, pastikan
     `gestura-b095.firebaseapp.com` terdaftar.
   - Tautan verifikasi baru dibuat dengan Firebase Hosting link dan
     `handleCodeInApp`. Android akan membuka Gestura jika tautan berasal dari
     domain tersebut dan aplikasi terpasang.

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
   Gestura mengirim tautan verifikasi; akun email/password belum bisa membuka
   materi sampai tautan itu dibuka. Di ponsel Android yang sama, tautan
   verifikasi baru akan membuka Gestura dan membawa pengguna ke aplikasi
   setelah status email diperbarui. Google Sign-In memverifikasi akun melalui
   Google dan bisa langsung digunakan.
2. Pendaftaran email/password membuat akun di Firebase Authentication dan
   dokumen profil di `users/{uid}`. Pengguna juga dapat memilih tombol
   **Lanjutkan dengan Google**.
3. Buka materi, lalu tekan **Tandai materi selesai**. Progres tersimpan di
   `users/{uid}/progress/{lessonId}`.
4. Keluar, lalu masuk lagi dengan akun yang sama. Progres tetap tersimpan dan
   dapat dilihat di tab Profil serta Riwayat belajar.
5. **Lupa password?** mengirim tautan pengaturan ulang melalui email. Jika
   email belum terverifikasi, layar verifikasi menyediakan opsi untuk mengirim
   ulang tautan atau memeriksa status verifikasi.
6. Dari **Pengaturan akun**, pilih **Konfirmasi hapus akun** untuk menghapus
   akun Firebase Authentication, profil, dan seluruh progres. Pengguna harus
   mengonfirmasi kembali password aplikasi atau masuk kembali dengan Google.
7. Nama pada **Edit profil** disimpan di Firebase Authentication dan
   `users/{uid}` di Firestore. Perubahan email baru aktif setelah tautan
   verifikasi dari email baru dibuka. Password hanya dapat diubah untuk akun
   Email/Password; akun Google mengelola password melalui Google.
8. Preview kamera hanya menampilkan gambar langsung dan lama sesi latihan.
   Gestura tidak merekam gambar atau mengenali gerakan. Hasil kuis dan durasi
   latihan disimpan ke Firestore.

Password hanya dikelola Firebase Authentication, tidak disimpan di Firestore.
Folder `assets/videos` dan direktori dataset server belum memiliki bahan.
Karena itu video peraga dan pengenalan gerakan BISINDO belum tersedia; aplikasi
menjelaskan batasan tersebut dan tidak menampilkan hasil pengenalan palsu.
Untuk versi tugas ini, katalog topik materi tetap menggunakan data lokal;
FastAPI belum digunakan untuk autentikasi atau progres.
