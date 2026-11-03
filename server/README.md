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
