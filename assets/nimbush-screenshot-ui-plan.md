# Nimbush Screenshot UI

## Rencana Implementasi Screenshot Interaktif ala Niri

**Status:** Planning\
**Target:** Nimbush (Quickshell) di Hyprland\
**Tujuan:** Mengganti alur screenshot berbasis `slurp` dengan UI
interaktif fullscreen yang membekukan tampilan layar, menampilkan
pointer secara live, dan memungkinkan pemilihan area seperti screenshot
UI bawaan Niri.

------------------------------------------------------------------------

## 1. Tujuan dan ruang lingkup

Membangun komponen screenshot mandiri di Nimbush yang menyediakan
pengalaman:

-   **Region:** layar ditangkap satu kali, lalu ditampilkan sebagai
    preview statis fullscreen.
-   **Live pointer:** pointer tetap terlihat dan bergerak di atas
    preview yang membeku.
-   **Seleksi area:** pengguna menarik area screenshot dengan mouse.
-   **Pointer option:** pengguna dapat memilih apakah pointer ikut
    dimasukkan ke hasil akhir.
-   **Preview dan aksi:** hasil seleksi dapat disalin ke clipboard,
    dibuka di Swappy, atau disimpan.
-   **Keyboard controls:** aksi utama dapat dijalankan tanpa harus
    memakai toolbar.

Komponen ini dibuat terpisah dari Dynamic Island, Dock, dan komponen UI
lain. Implementasi tidak boleh mengubah tampilan atau perilaku komponen
tersebut.

### Di luar ruang lingkup tahap awal

-   Video recording atau screen recording.
-   Annotation editor buatan sendiri.
-   Multi-monitor workflow lanjutan.
-   Integrasi langsung dengan Niri.
-   Mengubah arsitektur utama Nimbush.

------------------------------------------------------------------------

## 2. Perilaku yang dituju

### 2.1 Region screenshot

1.  Pengguna menekan shortcut screenshot region.
2.  Backend mengambil screenshot layar.
3.  Screenshot ditampilkan sebagai gambar fullscreen yang statis.
4.  UI screenshot muncul di atas gambar tersebut.
5.  Pointer compositor tetap bergerak di atas gambar.
6.  Pengguna menekan dan menarik mouse untuk memilih area.
7.  Area pilihan ditandai dengan border dan overlay transparan.
8.  Pengguna mengonfirmasi pilihan.
9.  Sistem memotong gambar sumber sesuai koordinat seleksi.
10. Hasil akhir dikirim ke clipboard dan/atau dibuka di Swappy.

Poin penting: screenshot sumber tidak diambil ulang selama pengguna
memilih area. Karena itu, konten desktop tidak berubah meskipun aplikasi
atau animasi di belakangnya terus berjalan.

### 2.2 Pointer option

-   Pointer terlihat secara live ketika UI pemilihan area aktif.
-   Tombol `P` mengaktifkan atau menonaktifkan opsi **Include Pointer**.
-   Secara default, pointer tidak dimasukkan ke hasil screenshot.
-   Jika opsi aktif, posisi dan bentuk pointer perlu dikomposisikan ke
    hasil akhir berdasarkan posisi pointer saat konfirmasi.
-   Jangan mengambil screenshot ulang menggunakan cursor capture setelah
    overlay aktif, karena overlay atau elemen UI screenshot berisiko
    ikut tertangkap.

### 2.3 Aksi pengguna

  Aksi             Perilaku
  ---------------- ---------------------------------------
  Drag mouse       Membuat atau mengubah seleksi
  `Enter`          Konfirmasi seleksi
  `Esc`            Membatalkan screenshot
  `P`              Toggle Include Pointer
  `Ctrl+C`         Salin hasil ke clipboard
  Tombol toolbar   Menjalankan aksi yang sama melalui UI

Shortcut final dapat disesuaikan agar tidak bertabrakan dengan shortcut
Nimbush atau Hyprland.

------------------------------------------------------------------------

## 3. Arsitektur

Pisahkan UI dan pekerjaan pemrosesan gambar agar komponen mudah diuji
dan tidak mengganggu modul lain.

``` text
Hyprland keybind
      |
      v
Screenshot launcher
      |
      v
Screenshot backend
      |
      |-- Capture layar dengan grim
      |-- Simpan gambar sementara
      |
      v
Quickshell Screenshot UI
      |
      |-- Tampilkan gambar fullscreen
      |-- Tampilkan pointer compositor secara live
      |-- Tangani drag selection
      |-- Toggle Include Pointer
      |
      v
Screenshot backend
      |
      |-- Crop gambar berdasarkan koordinat
      |-- Komposisikan pointer jika diminta
      |-- Clipboard / Swappy / Save
      |
      v
Notifikasi hasil
```

### Komponen

#### A. Screenshot backend

Tanggung jawab:

-   Mengambil screenshot sumber menggunakan `grim`.
-   Menyimpan file sementara dengan nama unik.
-   Menerima koordinat seleksi dari UI.
-   Memotong gambar menggunakan tool pemrosesan gambar yang tersedia.
-   Mengirim hasil ke `wl-copy`.
-   Membuka hasil di Swappy bila diminta.
-   Membersihkan file sementara.
-   Mengirim status sukses atau gagal ke UI.

Backend tetap menjadi lapisan pemrosesan. Jangan menaruh logika crop
atau clipboard di dalam QML.

#### B. Screenshot UI (Quickshell)

Tanggung jawab:

-   Membuat overlay fullscreen.
-   Memuat gambar sumber sebagai background statis.
-   Menggambar selection rectangle.
-   Menampilkan toolbar dan instruksi keyboard.
-   Menampilkan status Include Pointer.
-   Mengirim koordinat seleksi dan aksi pengguna ke backend.
-   Menutup overlay saat selesai atau dibatalkan.

UI sebaiknya menjadi komponen mandiri, misalnya `ScreenshotOverlay.qml`,
dengan service/controller terpisah bila diperlukan.

#### C. Screenshot controller / service

Tanggung jawab:

-   Mengatur state screenshot.
-   Menghubungkan UI dengan backend.
-   Mengelola path file sementara.
-   Memastikan hanya ada satu sesi screenshot aktif.
-   Menangani error dan cleanup ketika UI ditutup mendadak.

------------------------------------------------------------------------

## 4. State dan alur UI

State minimum:

  State          Fungsi
  -------------- ------------------------------------------
  `idle`         Tidak ada sesi screenshot
  `capturing`    Backend sedang mengambil screenshot
  `selecting`    Preview tampil dan pengguna memilih area
  `processing`   Gambar sedang dipotong atau diproses
  `completed`    Hasil berhasil dibuat
  `error`        Terjadi kegagalan
  `cancelled`    Pengguna membatalkan sesi

State seleksi minimum:

-   Titik awal (`startX`, `startY`).
-   Titik akhir (`endX`, `endY`).
-   Status apakah drag sedang berlangsung.
-   Rectangle hasil normalisasi.
-   Status `includePointer`.

Koordinat harus dikonversi dengan benar antara koordinat UI, koordinat
monitor, dan ukuran gambar sumber. Perhatikan scaling dan HiDPI agar
hasil crop tidak bergeser atau memiliki ukuran yang salah.

------------------------------------------------------------------------

## 5. Struktur file yang diusulkan

Struktur berikut adalah usulan awal. Nama dan lokasi akhir perlu
diselaraskan dengan struktur repository Nimbush yang sebenarnya.

``` text
quickshell/
├── modules/
│   └── screenshot/
│       ├── ScreenshotOverlay.qml
│       ├── ScreenshotController.qml
│       └── ScreenshotToolbar.qml
└── scripts/
    ├── screenshot.sh
    └── screenshot-process.sh
```

Jika Nimbush sudah memiliki pola khusus untuk service, IPC, atau
overlay, ikuti pola yang sudah ada daripada memperkenalkan sistem baru.

------------------------------------------------------------------------

## 6. Integrasi dengan keybind

Keybind yang sudah ada:

``` nix
(commandBind "Print" "~/.config/quickshell/scripts/screenshot.sh full" locked)
(commandBind "SHIFT + Print" "~/.config/quickshell/scripts/screenshot.sh region" locked)
```

Rencana integrasi:

-   Pertahankan `Print` untuk fullscreen screenshot.
-   Ubah `SHIFT + Print` agar membuka Screenshot UI Quickshell.
-   Tambahkan mode window/focused setelah mode region stabil.
-   Hindari menjalankan dua sesi screenshot secara bersamaan.

Nama command dapat berubah mengikuti mekanisme IPC atau launcher yang
dipakai Nimbush.

------------------------------------------------------------------------

## 7. Tahapan implementasi

### Tahap 1: Audit struktur Nimbush

-   Periksa entry point Quickshell.
-   Periksa pola overlay yang sudah digunakan.
-   Periksa cara Nimbush menjalankan script dan menerima IPC.
-   Periksa dependensi yang sudah tersedia (`grim`, `wl-copy`, `swappy`,
    `notify-send`, dan tool crop).
-   Tentukan cara paling aman untuk membuka dan menutup overlay
    fullscreen.

**Hasil:** rancangan file dan komunikasi yang sesuai dengan kode Nimbush
saat ini.

### Tahap 2: Capture dan frozen preview

-   Buat backend untuk mengambil screenshot sumber.
-   Buat overlay fullscreen.
-   Tampilkan screenshot sebagai gambar statis.
-   Pastikan pointer tetap terlihat dan bergerak di atas preview.
-   Pastikan overlay tidak ikut masuk ke gambar sumber.

**Kriteria selesai:** preview membeku, tetapi pointer tetap bergerak.

### Tahap 3: Region selection

-   Implementasikan drag selection.
-   Gambar border dan area seleksi.
-   Normalisasi koordinat.
-   Implementasikan konfirmasi dan pembatalan.
-   Uji crop pada resolusi native dan scaling yang digunakan.

**Kriteria selesai:** hasil crop tepat sesuai area yang dipilih.

### Tahap 4: Pointer option

-   Tambahkan indikator Include Pointer.
-   Implementasikan toggle `P`.
-   Ambil posisi pointer saat konfirmasi.
-   Jika aktif, komposisikan pointer ke hasil akhir tanpa menangkap
    overlay screenshot.

**Kriteria selesai:** pointer hanya masuk ke hasil akhir ketika opsi
diaktifkan.

### Tahap 5: Output dan toolbar

-   Tambahkan aksi Copy.
-   Tambahkan aksi Open in Swappy.
-   Tambahkan aksi Save bila diperlukan.
-   Tampilkan notifikasi hasil.
-   Pastikan file sementara dibersihkan.

**Kriteria selesai:** semua aksi menghasilkan output yang benar dan
tidak meninggalkan file sementara yang tidak diperlukan.

### Tahap 6: Integrasi dan pengujian

-   Hubungkan shortcut `SHIFT + Print`.
-   Uji pembatalan dan error.
-   Uji aplikasi fullscreen dan beberapa workspace.
-   Uji penggunaan berulang.
-   Uji monitor scaling dan kemungkinan multi-monitor.
-   Pastikan tidak ada regresi pada Dock, Dynamic Island, atau
    OverlayManager.

------------------------------------------------------------------------

## 8. Dependensi dan pertimbangan teknis

  Dependensi         Kegunaan
  ------------------ --------------------------------
  `grim`             Mengambil screenshot sumber
  `wl-copy`          Menyalin hasil ke clipboard
  `swappy`           Membuka hasil untuk anotasi
  `notify-send`      Notifikasi
  `Quickshell`       Overlay dan interaksi UI
  Tool crop gambar   Memotong gambar sesuai seleksi

Tool crop final dipilih setelah memeriksa paket yang sudah tersedia di
konfigurasi NixOS. Hindari menambahkan dependensi besar jika tool ringan
yang sudah ada cukup.

### Catatan teknis penting

1.  **Pointer live bukan bagian dari preview.** Pointer harus tetap
    dirender compositor di atas overlay.
2.  **Pointer pada hasil akhir adalah proses terpisah.** Jangan
    mengandalkan capture ulang layar setelah overlay tampil.
3.  **Koordinat harus konsisten.** Perhatikan monitor origin, scaling,
    dan ukuran gambar.
4.  **File sementara harus aman.** Gunakan nama unik dan cleanup saat
    sukses, batal, maupun error.
5.  **Overlay harus punya fokus input.** Pastikan keyboard shortcut dan
    mouse event diterima selama sesi.
6.  **Jangan mengunci seluruh compositor.** Yang dibekukan adalah gambar
    preview, bukan desktop atau pointer sebenarnya.

------------------------------------------------------------------------

## 9. Kriteria penerimaan

Implementasi dianggap selesai jika:

-   [ ] Shortcut region membuka UI screenshot fullscreen.
-   [ ] Seluruh tampilan layar terlihat sebagai preview statis.
-   [ ] Pointer tetap terlihat dan bergerak di atas preview.
-   [ ] Pengguna dapat memilih area dengan drag mouse.
-   [ ] Area hasil crop akurat.
-   [ ] Tombol `P` mengubah opsi Include Pointer.
-   [ ] Pointer dapat dimasukkan ke hasil akhir tanpa overlay ikut
    tertangkap.
-   [ ] `Enter` mengonfirmasi dan `Esc` membatalkan.
-   [ ] Hasil dapat disalin ke clipboard.
-   [ ] Hasil dapat dibuka di Swappy.
-   [ ] Sesi screenshot tidak saling bertabrakan.
-   [ ] Tidak ada perubahan yang tidak diminta pada Dock atau Dynamic
    Island.

------------------------------------------------------------------------

## 10. Urutan pengerjaan yang direkomendasikan

Prioritas implementasi:

1.  Audit struktur Quickshell dan mekanisme overlay/IPC Nimbush.
2.  Buat frozen preview fullscreen.
3.  Pastikan pointer live tetap terlihat.
4.  Implementasikan region selection dan crop.
5.  Tambahkan Include Pointer.
6.  Tambahkan clipboard, Swappy, dan notifikasi.
7.  Hubungkan keybind dan rapikan lifecycle.

**Prinsip utama:** bangun pengalaman screenshot terlebih dahulu, baru
tambahkan fitur tambahan. Jangan mengorbankan perilaku frozen preview
dan pointer live demi shortcut atau toolbar yang lebih banyak.
