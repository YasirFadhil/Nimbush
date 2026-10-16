# Rencana Migrasi Face ID Nimbush: dari Haar + LBPH ke YuNet + SFace

Status: selesai (migrasi ke YuNet + SFace ONNX berhasil diimplementasikan)
Target distro: NixOS (utama) dan Arch (kadang), harus jalan di keduanya tanpa tweak

---

## 1. Tujuan

- Ganti backend pengenalan wajah di `faceid-helper.py` jadi lebih baru, akurat, dan nggak rewel.
- Hilangkan ketergantungan ke `cv2.face` (modul contrib), karena itu sumber utama error "modul tidak ditemukan".
- Satu codebase untuk NixOS dan Arch. Perbedaan distro cuma di cara menyediakan Python + OpenCV.
- **Jangan ubah** `FaceId.qml`, `Lockscreen.qml`, dan UI di `Settings.qml`. Semuanya cuma boleh ketergantungan ke kontrak output helper.

## 2. Kenapa yang sekarang rewel

| Masalah | Penyebab |
|---|---|
| Helper langsung `exit(1)` | `cv2.face` tidak ada di build OpenCV standar Arch/Nix |
| Cascade tidak ketemu | Path hardcoded (`assets/`, `/usr/share/opencv4/...`) |
| Match gampang salah | LBPH, 1 label saja, threshold 98 longgar, trik `min(d1, d2)` dengan flip |
| `--samples` tidak berfungsi | Argumen di-parse tapi jumlah sampel fix dari `PHASES` (3x8) |

## 3. Pendekatan

Pertahankan arsitektur: `Settings.qml` -> `Config` -> `FaceId.qml` -> `faceid-helper.py` -> `Lockscreen.qml`.
Ganti hanya **isi** `faceid-helper.py`:

- Deteksi: `cv2.FaceDetectorYN` dengan model YuNet (ONNX).
- Pengenalan: `cv2.FaceRecognizerSF` dengan model SFace (ONNX), embedding + cosine similarity.
- Dua-duanya ada di OpenCV utama (bukan contrib), setahu gue dari versi 4.5.4 ke atas. Cek versi di tiap distro (lihat langkah 0).

Dependency akhir: `opencv` + `numpy` + dua file `.onnx`. Tidak ada download saat runtime.

## 4. Kontrak helper (JANGAN diubah)

Subcommand yang dipakai `FaceId.qml`:

- `status`
- `devices`
- `clear`
- `verify --camera --timeout --confidence`
- `enroll --camera --samples`

Event JSON per baris yang sudah dikonsumsi QML:

- verify: `camera_ready`, `scanning`, `detected` (`confidence`, `matches`), `unrecognized`, `success` (`user`, `confidence`), `timeout`, `camera_unavailable`, `not_enrolled`, `error`
- enroll: `enrolling`, `capturing` (`step`, `step_name`, `count`, `total`, `progress`, `message`), `review`, `training`, `complete`, `cancelled`, `error`
- status: `face_module_available`, `detector_available`, `enrolled`, `devices`, dll.

Catatan:

- Field `face_module_available` tetap dipakai walau isinya sekarang artinya "recognizer tersedia". Rename belakangan kalau mau, jangan sekarang.
- Field `confidence` sebelumnya adalah distance (makin kecil makin bagus). Sekarang similarity (makin besar makin bagus). Tentukan dulu mau dibiarkan apa adanya, atau dikonversi supaya semantik di QML tetap konsisten. Cek di `Lockscreen.qml`/`Settings.qml` apakah angka ini ditampilkan atau dibandingkan.

## 5. Langkah kerja

Kerjakan satu per satu, tes dulu sebelum lanjut.

### Langkah 0: Persiapan

1. Cek versi OpenCV di kedua distro: `python -c "import cv2; print(cv2.__version__)"`.
2. Pastikan `cv2.FaceDetectorYN` dan `cv2.FaceRecognizerSF` ada: `hasattr(cv2, ...)`.
3. Siapkan dua model ONNX dari repo `opencv_zoo` (YuNet untuk deteksi wajah, SFace untuk pengenalan wajah). Nama file persis tergantung versi, cek di repo itu.
4. Taruh di `~/.config/quickshell/assets/` (atau tempat lain, tapi konsisten dengan `ASSETS_DIR`).

Cek berhasil: kedua `hasattr` bernilai `True` dan kedua file ada.

### Langkah 1: Deteksi pakai YuNet

1. Ganti `get_face_detector` supaya bikin `FaceDetectorYN` dari file `.onnx`, bukan `CascadeClassifier`.
2. Ingat: detektor ini butuh `setInputSize` sesuai ukuran frame sebelum `detect`.
3. Hasil deteksi sudah berisi bbox, 5 landmark, dan skor. Pakai skor sebagai filter kualitas.
4. Update `cmd_status` supaya `detector_available` mengikuti kondisi baru, dan hapus `get_cascade_path`, `get_profile_detector`, `PROFILE_CASCADE`.

Cek berhasil: `faceid-helper.py status` melapor `detector_available: true` tanpa modul contrib.

### Langkah 2: Enroll jadi embedding

1. Pertahankan 3 fase (tengah, kiri, kanan) dan UI preview ffplay.
2. Tiap sampel yang lolos: `alignCrop` ke wajah, lalu `feature` untuk dapat embedding.
3. Simpan semua embedding ke satu file di `STATE_DIR` (misalnya `faceid_embeddings.npy`). Tetap simpan `faceid_sample.jpg` buat preview di Settings.
4. Pertimbangkan filter kualitas sebelum menerima sampel: ukuran wajah minimum, skor deteksi, mungkin blur.
5. Hapus fase training LBPH. Event `training` bisa tetap dikirim singkat supaya UI nggak berubah, atau dihapus kalau QML nggak bergantung.
6. Perbaiki `--samples`: pakai nilainya atau hapus argumennya.
7. `cmd_status` dan `cmd_clear`: `enrolled` dan penghapusan sekarang mengacu ke file embedding, bukan `faceid_model.xml`.

Cek berhasil: enroll selesai, file embedding terbentuk, `status` melapor `enrolled: true`.

### Langkah 3: Verify pakai cosine similarity

1. Tiap frame: deteksi, ambil wajah terbesar, `alignCrop`, `feature`, lalu `match` ke semua embedding tersimpan dengan cosine.
2. Ambil skor terbaik (atau rata-rata beberapa teratas).
3. Threshold awal pakai angka rekomendasi OpenCV untuk SFace (cosine sekitar 0.363, verifikasi di dokumentasi). Ini titik awal, bukan angka final.
4. Hapus jalur sukses instan di frame pertama dan trik flip `min(d1, d2)`. Hanya terima sukses setelah N frame berturut-turut (mulai dari 3).
5. Pertahankan event `detected` dan `unrecognized` supaya Dynamic Island tetap responsif.
6. Sambungkan argumen `--confidence` ke threshold baru. Putuskan satuannya dan samakan dengan `Config.faceIdConfidence` serta Settings.

Cek berhasil: verify sukses untuk lo, gagal untuk orang lain.

### Langkah 4: Rapikan dan buang yang lama

1. Hapus kode LBPH, cascade, `enhance_low_light` (atau pertahankan kalau di kamera lo terbukti membantu).
2. Hapus path legacy `LEGACY_STATE_DIR` kalau sudah nggak perlu.
3. Migrasi: model XML lama tidak kompatibel, jadi user harus enroll ulang. Pastikan pesan di Settings jelas.

### Langkah 5: Packaging per distro

**NixOS**

- Bungkus Python: `python3.withPackages (ps: [ ps.opencv4 ps.numpy ])`.
- Arahkan env `FACEID_PYTHON` ke interpreter itu (`FaceId.qml` sudah membaca env ini).
- Pastikan `v4l-utils` (untuk `v4l2-ctl`) dan `ffmpeg` (untuk `ffplay` preview) ada di PATH shell/user.
- Model `.onnx` bisa disimpan di repo Nimbush atau di-link lewat Nix.

**Arch**

- `python-opencv`, `python-numpy`, `v4l-utils`, `ffmpeg`.
- Tidak perlu `FACEID_PYTHON`, pakai `python3` default.
- Perbarui audit di `install.sh`: tambah dependency baru dan pengecekan file model.

## 6. Rencana pengujian

1. `status` di NixOS dan Arch: sama-sama hijau.
2. Enroll dari awal sampai `complete`.
3. Verify sebagai diri sendiri: kondisi terang, redup, dan jarak berbeda.
4. Verify oleh orang lain (minta izin dulu). Tujuannya mencari threshold yang menolak orang lain tapi tetap menerima lo.
5. Verify dengan foto/layar HP berisi wajah lo. Ini cuma untuk **mendokumentasikan** bahwa liveness belum ada, bukan untuk dianggap lolos.
6. Jalur gagal: kamera tidak ada, timeout, belum enroll, model hilang. Pastikan Lockscreen tetap menampilkan password normal.
7. Jalankan `Lockscreen.qml` penuh: scan otomatis, retry satu kali, island mengecil, auto-unlock.

## 7. Risiko dan catatan

- **Tidak ada liveness.** Kamera RGB biasa bisa dikelabui foto. Anggap ini kenyamanan, bukan keamanan setara password.
- **Password harus tetap jadi fallback.** Pertimbangkan mematikan `autoUnlock` secara default.
- **Performa di Celeron N4020.** Ukur latensi per frame setelah migrasi. Kalau terasa berat, turunkan resolusi atau hanya hitung embedding tiap beberapa frame.
- **Versi OpenCV berbeda antar distro** bisa mengubah perilaku API. Catat versi yang sudah teruji.
- **Threshold itu spesifik kamera dan pencahayaan.** Jangan salin angka dari tutorial mentah-mentah.

## 8. Tahap lanjutan (opsional, setelah stabil)

- Liveness ringan: tantangan gerak kepala atau kedip, memakai landmark YuNet.
- Update embedding otomatis secara aman (adaptive enrollment) dengan batas ketat.
- Opsi kamera IR kalau lo punya hardware-nya.

## 9. Checklist ringkas

- [x] Langkah 0: versi OpenCV dan model siap
- [x] Langkah 1: deteksi YuNet, `status` hijau
- [x] Langkah 2: enroll menghasilkan embedding
- [x] Langkah 3: verify dengan cosine, threshold diuji
- [x] Langkah 4: kode lama dibersihkan, pesan re-enroll jelas
- [x] Langkah 5: packaging NixOS dan Arch, `install.sh` diperbarui
- [x] Pengujian lengkap (bagian 6)
