server\.venv\Scripts\python.exe -m uvicorn app.main:app --app-dir server --host 0.0.0.0 --port 8000

# Gestura - model alfabet statis

Pipeline ini melatih classifier alfabet A-Z dari gambar di
`server/dataset/1_alphabet/<huruf>/`. Pipeline memakai MediaPipe Hand Landmarker
untuk mendeteksi maksimal dua tangan, menormalkan landmark, lalu membandingkan
Random Forest dan SVM RBF.

Model ini adalah baseline untuk **pose pada gambar**, bukan penerjemah BISINDO
universal. Sumber dan konvensi bahasa isyarat dataset perlu dikonfirmasi sebelum
hasilnya dipakai sebagai materi BISINDO. Huruf J dan Z biasanya memerlukan
gerakan, sedangkan model ini tidak mempelajari urutan temporal.

## 1. Siapkan Python di Windows

Pipeline ini sudah diuji pada Python 3.14 64-bit di Windows. Python sistem boleh
tetap terpasang; virtual environment dibuat khusus di folder server.

Dari PowerShell di root repository:

```powershell
py -3.14 -m venv server\.venv
server\.venv\Scripts\python.exe -m pip install --upgrade pip
server\.venv\Scripts\python.exe -m pip install -r server\requirements.txt
```

Jika `py -3.14` tidak tersedia, instal Python 3.14 64-bit terlebih dahulu.
Jangan gunakan environment global untuk pipeline ini.

## 2. Ekstrak dan preprocessing landmark

```powershell
server\.venv\Scripts\python.exe server\scripts\extract_alphabet_landmarks.py
```

Perintah pertama mengunduh model Hand Landmarker resmi MediaPipe ke
`server/.cache/`. Fitur hasil ekstraksi disimpan di
`server/processed/alphabet_landmarks.npz`, dan ringkasan di
`server/processed/alphabet_extraction_report.json`.

Langkah ekstraksi:

- Memastikan seluruh folder A-Z tersedia dan berisi gambar.
- Menghitung SHA-256 dan menghapus salinan gambar yang byte-identik.
- Menghentikan proses jika gambar identik memiliki label yang berbeda.
- Mendeteksi landmark 21 titik untuk maksimal dua tangan.
- Mengurangi koordinat terhadap wrist, menormalkan skala terhadap panjang
  telapak, dan menyimpan posisi wrist relatif terhadap frame.
- Melaporkan gambar tanpa tangan terdeteksi; gambar tersebut tidak dipakai untuk
  training.

Untuk tes singkat tanpa memproses seluruh gambar:

```powershell
server\.venv\Scripts\python.exe server\scripts\extract_alphabet_landmarks.py --limit-per-class 5 --output server\processed\alphabet_smoke_test.npz
```

Hasil smoke test bukan model final. Perintah tersebut membuat arsip fitur dan
`alphabet_extraction_report.json` di folder `processed`; jalankan ekstraksi penuh
setelah smoke test sebelum training.

## 3. Training dan evaluasi

```powershell
server\.venv\Scripts\python.exe server\scripts\train_alphabet.py
```

Training menggunakan `StratifiedGroupKFold` lima fold: satu fold untuk test,
satu untuk validasi, dan tiga untuk training. Grup berdasarkan SHA-256 mencegah
gambar identik masuk ke split berbeda. Random Forest dan SVM RBF dibandingkan
di validation berdasarkan macro F1. Model terpilih kemudian dilatih ulang pada
train + validation dan dievaluasi satu kali pada test.

Artefak disimpan di `server/trained_models/alphabet/`:

- `model.joblib` — classifier dan ambang confidence.
- `evaluation.json` — metrik, pembagian data, batasan, dan konfigurasi.
- `classification_report.csv` — precision, recall, F1-score per huruf.
- `confusion_matrix.csv` dan `confusion_matrix.png`.
- `test_predictions.csv` — prediksi tiap sampel test untuk pemeriksaan.

Prediksi di bawah ambang yang dikalibrasi dari validation menghasilkan status
`not_recognized`. Target awal selective accuracy adalah 95% dengan coverage
minimal 10%; jika validation tidak memenuhi target dan coverage itu, model
menolak semua prediksi alih-alih mengklaim ambang yang tidak didukung data.

## 4. Prediksi satu gambar

```powershell
server\.venv\Scripts\python.exe server\scripts\predict_alphabet.py --input "path\ke\gambar.jpg"
```

Output JSON berisi status, kandidat kelas, confidence, ambang, dan jumlah tangan
yang terdeteksi. Gambar tanpa tangan akan dikembalikan sebagai
`not_recognized`.

## 5. Uji langsung dengan webcam laptop

Jalankan dari root repository di terminal VS Code:

```powershell
server\.venv\Scripts\python.exe server\scripts\run_alphabet_webcam.py
```

Kontrol jendela webcam:

- `Q` atau `Esc`: keluar.
- `M`: hidupkan/matikan mirror. Jika hasil gesture terasa terbalik, coba toggle.
- `R`: reset stabilisasi prediksi.

Huruf stabil baru muncul setelah minimal 5 dari 7 frame terakhir sepakat.
Preview menampilkan landmark, FPS, confidence, kandidat, dan status penolakan.
Jika webcam bukan kamera default, gunakan `--camera 1`; resolusi dapat diatur
dengan `--width 640 --height 480`. Gunakan `--no-mirror` untuk memulai tanpa
mirror. Tutup aplikasi lain yang memakai webcam dan izinkan akses kamera di
pengaturan privasi Windows bila kamera gagal dibuka.

Skrip ini **memakai model yang sudah dilatih**, tidak mengubah model, dan tidak
mengirim atau menyimpan gambar dari kamera. Hasil langsung dari webcam dapat
lebih buruk daripada metrik dataset; pencahayaan, jarak, latar, dan variasi
gesture pengguna belum menjadi bagian dari test set.

Hasil test dataset saat ini: accuracy 95.1%, macro F1 0.950, dengan coverage
95.6% dan selective accuracy 95.3%. Angka ini hanya mengukur gambar dari dataset
yang tersedia; split belum menguji demonstrator baru dan tidak membuktikan bahwa
model menolak gesture di luar alfabet.

## Batas evaluasi

- Split berbasis hash hanya mencegah kebocoran gambar identik. Dataset belum
  memiliki metadata demonstrator/sesi yang cukup untuk menguji generalisasi
  lintas demonstrator secara benar.
- Test merupakan closed-set A-Z. Ambang confidence tidak membuktikan bahwa
  gesture non-alfabet atau isyarat di luar dataset akan ditolak; tambahkan contoh
  negatif dan rekaman pengguna baru sebelum mengandalkan fitur penolakan.
- Gambar yang berasal dari augmentasi berkas sumber yang sama tetapi tidak
  identik byte mungkin masih tersebar di beberapa split. Periksa asal dataset
  dan metadata augmentasinya bila tersedia.
- Dataset dan model hasil training tidak dimasukkan Git; ukuran data cukup besar.
- Sebelum mengintegrasikan kamera/Flutter, uji model dengan gambar baru dari
  beberapa pengguna dan kondisi kamera berbeda, lalu evaluasi ulang threshold.

## 6. Model digit 1-9 (terpisah dari alfabet)

Model digit memakai dataset gambar statis di `server/dataset/3_digit/1` sampai
`9`. Dataset yang tersedia tidak memiliki kelas `0`, sehingga artefak digit
hanya mengeluarkan label 1-9.

Ekstrak landmark dan latih model:

```powershell
server\.venv\Scripts\python.exe server\scripts\extract_digit_landmarks.py
server\.venv\Scripts\python.exe server\scripts\train_digit.py
```

Artefak disimpan terpisah di `server/trained_models/digit/`. File persis
duplikat dihapus sebelum split. Nama dataset menunjukkan grup demonstrator
`P1`-`P10` dan satu sumber bernama `Sign`; split menahan `P9` untuk validation
serta `P10` dan sumber `Sign` untuk test, sedangkan `P1`-`P8` digunakan training.
Laporan berisi accuracy, macro-F1, precision/recall per digit, confusion matrix,
dan confidence threshold. Ini evaluasi sumber yang tersedia, bukan bukti
generalisasi ke semua pengguna.

Hasil test saat ini: accuracy 72.2% dan macro F1 72.3%. Perbedaan antar-sumber
besar: P10 100%, sedangkan sumber `Sign` 66.2%. Pada ambang confidence yang
dikaji dari validation, coverage test 62.1% dan selective accuracy 94.5%.
Perbedaan sumber ini perlu diselesaikan sebelum model dianggap andal; hasil
tersebut bukan jaminan performa pada kamera/pengguna baru.

## 7. Model vocabulary video (terpisah dari alfabet dan digit)

Ekstrak 12 frame berjarak merata dari tiap video `label0`-`label31`, proses
landmark per frame, lalu bentuk fitur video dari rerata, variasi antar-frame,
perubahan landmark awal-ke-akhir, dan rasio deteksi tangan. Label dipetakan ke
32 gloss Indonesia dari daftar Gestura.

```powershell
server\.venv\Scripts\python.exe server\scripts\extract_vocabulary_landmarks.py
server\.venv\Scripts\python.exe server\scripts\train_vocabulary.py
```

Model dan laporan disimpan terpisah di `server/trained_models/vocabulary/`.
Split dilakukan berdasarkan demonstrator: signer0-2 untuk training, signer3
untuk validation, signer4 untuk test. Tidak ada frame dari video yang sama atau
signer yang sama menyebrang split. Dataset menyediakan lima signer untuk gloss
0-11, tetapi hanya empat signer (1-4) untuk gloss 12-31. Karena test hanya
memakai satu signer, hasil harus dianggap evaluasi awal, bukan jaminan
generalisasi ke pengguna lain. Video yang terlalu sedikit frame tangannya
terdeteksi dilaporkan dan tidak dipakai.

Sebagai pemeriksaan tambahan, training juga menjalankan leave-one-signer-out
cross-validation untuk signer1-4. Signer0 tidak menjadi test fold karena tidak
memiliki video untuk gloss12-31. Laporan per signer dan skor pooled tersimpan
di `signer_cross_validation.json`.

Vocabulary memiliki kemungkinan gesture dinamis; fitur video di atas adalah
baseline temporal sederhana, bukan pemahaman bahasa isyarat umum. Tinjau hasil
per gloss dan validasi bentuk/arti BISINDO sebelum menyebutnya model siap pakai.
Hasil test signer4 saat ini: accuracy 74.4%, macro F1 71.7%, coverage 48.9%,
dan selective accuracy 91.3%. Pada cross-validation per signer, Random Forest
memperoleh pooled accuracy 67.1% dan macro F1 67.0%; accuracy tiap signer
bervariasi dari 36.2% sampai 79.5%. Ini menunjukkan variasi antar-demonstrator
yang besar dan model vocabulary masih baseline. Di test signer4, kelas Merah
belum dikenali dengan benar (F1 0), jadi hasil per gloss perlu diperiksa.

## Model yang dipilih aplikasi

Ketiga artefak classifier disimpan di lokasi berbeda:

- `server/trained_models/alphabet/model.joblib` — A-Z.
- `server/trained_models/digit/model.joblib` — 1-9.
- `server/trained_models/vocabulary/model.joblib` — 32 gloss video.

FastAPI dan halaman kamera Flutter sudah memilih artefak sesuai kategori yang
diminta. Label alfabet, digit, dan vocabulary tidak dicampurkan dalam satu
classifier. Classifier terpisah **tidak otomatis berarti model aman/akurat**:
masing-masing masih perlu dievaluasi dengan data pengguna yang belum pernah
dilihat.

## 8. Menjalankan API dan aplikasi

Instal dependency API ke virtual environment yang sama:

```powershell
server\.venv\Scripts\python.exe -m pip install -r server\requirements.txt
```

API melindungi endpoint prediksi dengan Firebase Authentication. Untuk
development lokal, siapkan kredensial Firebase Admin melalui salah satu cara:

- `gcloud auth application-default login` dengan akun yang memiliki akses ke
  project Firebase; atau
- unduh service-account key dari Firebase/Google Cloud dan simpan di luar
  repository. Jangan pernah commit atau membagikan file key tersebut.

Jika memakai service-account key, atur environment variable di PowerShell
sebelum menjalankan API:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\secure\gestura-service-account.json"
$env:FIREBASE_PROJECT_ID = "gestura-b095"
```

Server Admin SDK hanya memverifikasi Firebase ID token; token dikirim aplikasi
setelah pengguna login. Jika credentials tidak tersedia atau project ID tidak
cocok dengan konfigurasi Firebase Flutter, startup/authentication akan gagal.

Jalankan backend dari root proyek:

```powershell
server\.venv\Scripts\python.exe -m uvicorn app.main:app --app-dir server --host 0.0.0.0 --port 8000
```

API memuat ketiga artefak saat mulai. Jika model atau MediaPipe task asset belum
ada, startup gagal dengan pesan yang menjelaskan file yang dibutuhkan. Periksa
`http://127.0.0.1:8000/health` atau buka dokumentasi interaktif di
`http://127.0.0.1:8000/docs`.

Endpoint `POST /api/v1/predict/{category}` menerima multipart field `video`
dengan video MP4, MOV, AVI, MKV, atau WEBM (maksimal 30 MB dan 30 detik).
Kategori `alphabet` dan `digit` memilih satu frame tengah yang representatif;
`vocabulary` memakai agregasi 12 frame temporal yang sama dengan preprocessing.
Video sementara di backend dihapus setelah request selesai. Respons berisi
`status`, `label`, `candidate`, `confidence`, `threshold`, dan jumlah frame
tangan terdeteksi. Jika gesture tidak meyakinkan, API mengembalikan
`not_recognized`.

## Kamera real-time dan penyimpanan

Layar praktik memakai kamera depan dan mengirim satu frame JPEG per request ke
`POST /api/v1/predict/{category}/frame`. Request mengandung Firebase ID token
dan ID sesi acak; backend memverifikasi token, mengambil landmark, lalu
mengembalikan prediksi dan maksimal 21 titik per tangan. Frame tidak ditulis ke
disk atau Firestore. Untuk kosakata, backend menyimpan sementara fitur landmark
hingga 12 frame per sesi di memori dan menghapusnya setelah sesi ditutup atau
TTL 10 menit.

Pilih kategori dan target materi: A-Z, 1-9, atau 32 gloss kosakata. Prediksi
baru dianggap stabil jika label target tetap cocok selama 1,5 detik; latihan
otomatis selesai setelah itu. Prediksi stabil (termasuk percobaan yang salah)
disimpan di `users/{uid}/practicePredictions`, sedangkan sesi yang berhasil
disimpan di `users/{uid}/practiceSessions`. Aturan Firestore di root project
membatasi data tersebut ke pemilik akun. Setelah memperbarui rules, deploy
dengan `firebase deploy --only firestore:rules`.

Di Android, layar kamera memiliki pilihan kategori dan alamat backend. Emulator
Android biasanya dapat memakai `http://10.0.2.2:8000`. Untuk perangkat fisik,
gunakan IPv4 laptop (contoh `http://192.168.1.5:8000`) dan pastikan keduanya
berada pada jaringan Wi-Fi yang sama; atau gunakan `adb reverse tcp:8000
tcp:8000` lalu isi `http://127.0.0.1:8000`. Jika `adb` tidak terdaftar pada
PATH, gunakan `C:\Android\Sdk\platform-tools\adb.exe reverse tcp:8000 tcp:8000`
(sesuaikan lokasi SDK bila berbeda). Beri izin akses private network untuk
Python pada Windows Firewall jika diminta. Tombol **Cek koneksi**
memastikan server sudah terjangkau dan model aktif.

Kamera hanya didukung saat aplikasi berjalan pada perangkat/emulator dengan
plugin kamera yang tersedia. Model tetap baseline: akurasi dataset bukan
jaminan pengenalan pada pengguna baru, terutama untuk kosakata. Server contoh
ini memakai HTTP untuk jaringan development lokal; jangan membuka API ke internet
publik tanpa HTTPS, pembatasan jaringan, dan rate limiting.
