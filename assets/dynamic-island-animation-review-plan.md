# Dynamic Island: Animation, Privacy Indicators, dan Sharing UI

## Tujuan

Rapikan animasi Dynamic Island agar gerak resize, konten, dan satellite terasa satu rangkaian; pastikan indikator kamera dan screen recording tidak menimpa konten wallpaper/sharing; kecilkan panel saat proses share; dan bedakan proses handoff ke LocalSend dari transfer yang benar-benar bisa dilacak.

Dokumen ini disusun dari video rekaman 30 fps dan file `DynamicIsland(4).qml` yang diberikan. Ini adalah blueprint implementasi, bukan instruksi untuk menulis ulang seluruh komponen.

## Temuan dari video dan source

### 1. Gerakan belum terasa menyatu

- Di `island`, `width` menggunakan `Easing.OutBack` selama 360/380 ms dengan overshoot 1.35/1.45, sedangkan `height` memakai 340 ms dan overshoot yang sama. Radius punya durasi 320 ms. Bentuk jadi melewati target, tetapi konten, ukuran indikator, dan posisi satellite tidak selalu settle bersamaan.
- `rightSatDot` dan `leftSatDot` bergerak berdasarkan margin relatif ke tepi island. Ketika island ikut mengubah width, posisi satellite juga berubah dari anchor ditambah animasi marginnya sendiri. Ini berpotensi terasa seperti gerak bertumpuk, terutama saat pergantian mode yang mengubah width jauh.
- Privacy dot mengatur `x`, `width`, `opacity`, dan `scale` secara terpisah. Lebar dot dan spacing di dalam `Row` juga dianimasikan lagi. Ketika kamera dan recording berubah status hampir bersamaan, beberapa animasi layout dapat saling mengejar.
- Handoff privacy memakai timer 430 ms, sedangkan rangkaian detach satellite bisa berlangsung sekitar 520 ms. Artinya, status clipping dan transfer dot berpotensi selesai sebelum animasi satellite benar-benar settle.
- Pada beberapa cuplikan video, satellite sempat tampak seperti kapsul gelap kosong sebelum ikon terlihat. Konten satellite memakai `contentOpacity`/`contentScale` yang baru mekar setelah satellite mulai bergerak; pergantian jenis aktivitas juga langsung mengganti `visible` icon berdasarkan `activity`.

**Arah perbaikan:** geometri utama harus tenang dan konsisten. Efek lentur tetap boleh ada, tetapi dipusatkan di animasi satellite/bridge atau sedikit entrance scale, bukan membuat width dan height island terus overshoot.

### 2. Akar overlap privacy indicator saat mode lebar

`allSortedCandidates` melakukan early return untuk `dropSendMode` / `isDropSending` dan `wallpaperMode`. Cabang tersebut hanya mengembalikan kandidat `dropsend` atau `wallpaper`, sehingga kandidat `camera` dan `recording` tidak pernah masuk ke distribusi satellite.

Akibatnya, `cameraIndicator` menganggap privacy dot masih perlu digambar di dalam main island. Indikator itu berada di tepi kanan island dan bisa berbagi area visual dengan header, tombol tutup, preview file, atau konten mode lebar. `cameraIndicator` juga punya `z: 4`, sehingga ia merupakan layer visual terpisah dari isi panel, bukan bagian dari layout panel itu sendiri.

**Arah perbaikan:** mode wallpaper dan sharing tetap menjadi pemilik slot tengah, tetapi kamera dan recording aktif harus tetap dimasukkan sebagai kandidat privacy untuk satellite. Jangan mengembalikan satu kandidat modal saja.

### 3. Ukuran panel sharing belum seimbang

Dimensi saat ini di `calculatedExpandedWidth` / `calculatedExpandedHeight`:

- Pilih tujuan / drop hub: `500 × 148`.
- Sending atau success: `400 × 64`.
- Wallpaper: `480 × 120`.

Panel transfer memakai `anchors.margins: 12`, sehingga tinggi isi yang tersedia pada panel 64 px hanya sekitar 40 px. Thumbnail transfer punya implicit height 44 px, belum termasuk kebutuhan alignment dan teks. Layout kemungkinan harus menyusutkan elemen atau terasa sesak. Sebaliknya, ukuran chooser 500 × 148 terasa besar untuk panel yang hanya berisi dua pilihan tujuan.

**Arah perbaikan:** gunakan ukuran terpisah menurut tahap UI, bukan satu ukuran generik untuk semua keadaan sharing.

### 4. LocalSend jangan ditampilkan seolah-olah punya progress transfer

UI saat ini memperlakukan `transferState === "sending"` dan `"success"` sebagai `isDropSending`. Tampilan `transferFeedback` kemudian menampilkan teks “Sending to …”, progress beam berulang, dan lingkaran animasi. Alur ini cocok hanya bila service benar-benar melakukan transfer dan mengetahui statusnya.

Jika fungsi `sendLocalSend()` hanya menyiapkan atau membuka LocalSend agar pengguna melanjutkan proses di aplikasi, maka progress bar tersebut memberi kesan keliru bahwa Quickshell sedang mengirim file dan dapat mengetahui progresnya.

**Arah perbaikan:** cek implementasi `services/DeviceShare.qml` terlebih dahulu untuk memastikan apa yang bisa dipantau. Tampilkan tahap persiapan dan handoff yang jujur; jangan mengklaim file selesai dikirim jika LocalSend tidak memberikan konfirmasi tersebut.

---

## Rancangan perilaku

### A. Satu state sharing yang jelas

Audit state dan kontrak `services/DeviceShare.qml` terlebih dahulu. Jika belum ada status ekuivalen, gunakan model konseptual berikut. Nama akhirnya boleh menyesuaikan kontrak service yang ada.

| Stage | Kapan dipakai | Tampilan |
|---|---|---|
| `choosing` | Hub aktif, pengguna memilih KDE Connect atau LocalSend | Dua kartu tujuan dan informasi file |
| `preparing` | Permintaan handoff LocalSend sedang diproses | “Preparing LocalSend…” dengan ikon/spinner kecil, tanpa progress bar transfer |
| `handoff` | LocalSend berhasil dibuka atau request sudah diserahkan | “Continue in LocalSend” dan petunjuk untuk menyelesaikan pilihan/pengiriman di aplikasi |
| `sending` | Hanya untuk jalur yang benar-benar mengirim file dan statusnya diketahui service | “Sending via KDE Connect…” dengan indikator indeterminate jika persentase tidak tersedia |
| `success` | Service menerima konfirmasi transfer berhasil | Status selesai; isi progress penuh hanya jika success benar-benar terkonfirmasi |
| `error` | Proses membuka aplikasi atau transfer gagal | Pesan yang jelas dan aksi coba lagi/tutup |

Catatan:

- Jangan mengubah `preparing` menjadi `success` hanya karena aplikasi berhasil diluncurkan.
- Jangan memakai timer arbitrer untuk berpura-pura tahu kapan LocalSend selesai memuat. Gunakan hasil proses launch/service jika tersedia; jika tidak, tampilkan status handoff yang stabil dan sediakan cara membuka LocalSend lagi bila memungkinkan.
- Bedakan backend, misalnya `kdeconnect` dan `localsend`, sehingga UI tidak mengasumsikan semua state `sending` punya makna yang sama.
- Buat satu computed flag seperti `dropWorkflowActive` untuk mencakup choosing, preparing, handoff, sending, dan success yang masih ditampilkan. Perbarui semua penggunaan lama `isDropSending` secara konsisten, terutama di `expanded`, `hasExpandContent`, `demand`, `allSortedCandidates`, timer collapse, dan visibility panel. Pertahankan nama lama sebagai alias hanya jika dibutuhkan kompatibilitas.

### B. Ukuran panel sharing yang adaptif

Gunakan ini sebagai titik awal untuk diuji secara visual, bukan angka sakral:

| Tampilan | Ukuran awal yang disarankan | Catatan layout |
|---|---:|---|
| Memilih tujuan / drop hub | sekitar `440 × 136` | Cukup untuk dua kartu, tetapi tidak sebesar 500 × 148. Pertahankan minimum width kartu setelah margin dan gap dihitung. |
| Preparing / LocalSend handoff | sekitar `360 × 76` sampai `360 × 84` | Gunakan ikon 32 px, judul singkat, subtitle satu baris dan aksi opsional. Tidak perlu kartu tujuan. |
| Transfer KDE Connect | sekitar `360 × 72` | Tinggi isi minimal 44 px ditambah margin vertikal 12 px di kedua sisi. Thumbnail tidak boleh terpotong atau dipaksa menyusut. |
| Success / error | Gunakan ukuran transfer jika konten muat; naik sedikit bila perlu | Status tidak boleh membuat teks atau tombol bertabrakan. |

Implementasi ukuran:

1. Tambahkan dimensi eksplisit menurut stage, misalnya `calculatedDropWidth` dan `calculatedDropHeight`, lalu gunakan dari computed width/height island.
2. Ukuran boleh mengikuti `implicitWidth`/`implicitHeight` bila layout bisa menyediakannya dengan benar. Karena container saat ini `anchors.fill: parent`, jangan menganggap `implicitWidth` panel akan terukur otomatis tanpa mengubah struktur layout.
3. Beri batas minimum/maksimum agar panel tetap muat pada layar sempit. Uji di resolusi aktual 1366 × 768 dan pastikan reservation bar menghitung ukuran panel plus satellite dengan benar.
4. Saat masuk stage preparing/handoff, transisikan ukuran chooser ke panel ringkas tanpa menampilkan kembali kartu tujuan di tengah animasi.
5. Ukuran wallpaper boleh tetap sekitar 480 × 120, tetapi indikator privacy harus berada di satellite, bukan di dalam area konten wallpaper.

### C. Privasi kamera dan recording saat island lebar

Perbaiki sumber kandidat, bukan hanya menggeser dot beberapa piksel.

1. Pertahankan prioritas mode modal: `dropsend` atau `wallpaper` tetap menjadi kandidat center dengan prioritas tertinggi.
2. Ketika mode modal aktif, ikutkan kandidat aktif `camera` dan `recording` dalam daftar kandidat. Jangan ikutkan semua notification/media/HUD biasa jika itu akan menghasilkan satellite yang tidak diinginkan selama modal aktif.
3. Biarkan distribusi kandidat yang sudah ada menempatkan kamera dan recording di slot satellite. Distribusi sekarang sudah memberi prioritas kepada kandidat privacy dibanding media/CapsLock.
4. Pastikan `satelliteExtraWidth` dan `reservedWidth` menghitung tambahan area dengan benar supaya satellite tidak bertabrakan dengan item bar lain.
5. `cameraIndicator` di main island hanya tampil ketika mode center memang idle/non-modal dan privacy dot tidak sedang dialihkan ke satellite.
6. Di keadaan non-modal, jangkar tepi privacy indicator harus stabil saat lebar internalnya berubah. Utamakan sisi kanan yang tetap pada posisi sama, dengan hanya ekspansi ke arah kiri, daripada menjalankan `x` dan `width` yang berubah bebas bersamaan.
7. Jika kamera dan recording aktif bersamaan, keduanya harus tetap terbedakan: kamera hijau, recording oranye/merah. Saat pindah main island ↔ satellite, jangan pernah menampilkan duplikat yang tertinggal atau menyembunyikan indikator sebelum tujuan tiba.

Kasus yang harus diperiksa:

- Kamera saja, recording saja, serta keduanya aktif bersamaan.
- Masing-masing kondisi di atas saat wallpaper aktif, chooser sharing terbuka, LocalSend preparing/handoff, KDE Connect sedang transfer, dan notification/media menjadi konten center.
- Saat salah satu aktivitas privacy berakhir sementara yang lain masih aktif.

### D. Choreography animasi supaya terasa halus

#### Geometri utama island

- Samakan timing width dan height melalui satu set nilai bersama, contohnya durasi expand sekitar 300 ms dan collapse sekitar 260 ms.
- Ganti `Easing.OutBack` agresif di width/height dengan easing yang settle pada target, misalnya `Easing.OutCubic`. Jika masih perlu rasa lentur, gunakan hanya sedikit entrance scale atau animasi bridge.
- Samakan radius dan opacity transisi isi dengan fase geometri agar konten tidak terlihat selesai lebih dulu atau tertinggal lama.
- Jika overshoot utama dihilangkan, ukur ulang `overshootAllowance`; jangan mempertahankan kompensasi 28 px secara otomatis tanpa mengecek kebutuhan aktual.

#### Satellite dan privacy handoff

- Tetapkan satu timeline handoff yang menjadi sumber timing animasi posisi dot, clipping, dan bloom konten. Hindari timer 430 ms yang selesai sebelum rangkaian detach selesai.
- Bila memungkinkan, akhiri status `transferringToSatellite` saat animasi detach benar-benar selesai, bukan berdasarkan angka timer yang terpisah. Jika tetap memakai timer, durasinya harus sesuai timeline final dan diuji ulang saat animasi berubah.
- Jangan biarkan bubble kosong terlihat lama. Fade konten lama, ganti `activity` pada titik transisi yang aman, lalu fade konten baru. Saat detach pertama kali, ikon boleh mulai muncul begitu kapsul punya cukup ukuran, bukan menunggu seluruh gerakan berakhir.
- Ketika activity satellite berubah sementara `isSatellite` tetap `true`, animasikan pergantian konten secara eksplisit karena `onIsSatelliteChanged` tidak akan berjalan pada kasus itu.
- Cegah animasi lama menimpa state baru ketika pengguna mengganti mode dengan cepat. Pastikan `stop()`/restart sequence mereset opacity, scale, transform dan margin secara deterministik sebelum animasi baru mulai.

#### Kurangi animasi layout yang berkompetisi

- Untuk dua privacy dots, pertahankan ukuran dasar dot dan animasikan `opacity`/`scale`. Hindari menggabungkan shrink width, perubahan spacing, pergeseran x, dan perpindahan satellite secara independen jika semuanya memengaruhi posisi visual yang sama.
- Pertahankan efek fluid pada bridge/satellite sebagai aksen, bukan di setiap properti sekaligus. Targetnya responsif dan sedikit elastis, bukan memantul beberapa kali pada setiap resize.
- Periksa perubahan lebar konten teks/marquee ketika island sedang berubah ukuran supaya implicit width tidak terus memicu perubahan target tambahan.

---

## Area source yang perlu disentuh

Angka baris ini merujuk ke file unggahan saat ditinjau; bisa bergeser setelah patch.

| Area | Bagian | Perubahan utama |
|---|---|---|
| State kandidat | sekitar 190–390 | Perbaiki modal candidate early-return agar privasi tetap bisa masuk satellite saat wallpaper/sharing aktif |
| State sharing dan timer | sekitar 25–115 serta fungsi collapse | Pisahkan handoff LocalSend dari transfer dan pastikan timer tidak menutup panel pada stage baru |
| Ukuran dan demand | sekitar 1430–1490 | Dimensi menurut stage dan perhitungan reservation yang konsisten |
| Geometry island | sekitar 1670–1820 | Samakan easing/durasi width-height-radius dan kurangi overshoot geometri utama |
| Privacy indicator | sekitar 1860–2050 | Stabilkan anchor, ukuran, dan timeline handoff; cegah overlap/duplikasi |
| Drop hub chooser | sekitar 4080–4500 | Layout chooser yang lebih ringkas dan state preparing/handoff yang terpisah |
| Transfer feedback | sekitar 4500–4700 | Gunakan progress hanya untuk jalur yang benar-benar melacak transfer; tinggi panel harus pas untuk thumbnail 44 px |
| Satellite animation | sekitar 4720–5370 | Sinkronkan detach/retract, transisi konten, dan state saat activity berubah |

Sebelum mengubah logic LocalSend, agent wajib membaca `services/DeviceShare.qml` dan skrip yang dipanggilnya. Sebelum mengubah clipping atau reservation bar, periksa `LiquidSplitBridge.qml` serta implementasi bar/`OverlayManager` terkait. Jangan mengasumsikan API service dari nama property saja.

## Urutan implementasi

1. **Audit alur state.** Baca `DeviceShare.qml`, skrip LocalSend, `LiquidSplitBridge.qml`, dan komponen bar. Catat state yang benar-benar tersedia dan apa sinyal sukses yang bisa dipercaya.
2. **Perbaiki distribusi kandidat modal.** Pastikan kamera/recording tetap menjadi satellite saat wallpaper/sharing menjadi center. Validasi reservation bar sebelum mengubah animasi visual.
3. **Pisahkan LocalSend handoff dari transfer.** Tambahkan stage hanya jika service belum punya konsep ekuivalen. Pastikan preparing/handoff tetap menjaga panel tetap terbuka dan tidak menampilkan progress palsu.
4. **Rapikan ukuran panel.** Mulai dari ukuran chooser sekitar 440 × 136 dan handoff/transfer sekitar 360 × 76–84 atau 360 × 72, lalu sesuaikan berdasarkan implicit size nyata dan hasil uji.
5. **Rapikan animasi geometri utama.** Samakan durasi width/height dan kurangi overshoot. Jangan sekaligus mengubah semua animasi satellite sebelum bentuk utama stabil.
6. **Sinkronkan privacy handoff dan satellite content.** Hilangkan kapsul kosong yang terlalu lama, timing timer yang tidak selaras, dan animasi x/width yang saling mengejar.
7. **Uji transisi cepat dan regresi.** Pastikan pergantian stage, close/collapse, dan perubahan aktivitas di tengah animasi tidak meninggalkan state visual usang.

## Kriteria selesai

- Expand/collapse dan resize mode wallpaper/sharing tidak memantul berlebihan dan tidak terlihat tersendat karena width/height berbeda timing.
- Saat mode modal aktif, kamera dan recording muncul sebagai satellite di luar panel; tidak menimpa judul, tombol tutup, preview, kartu pilihan, atau teks transfer.
- Kamera tetap hijau dan recording tetap oranye/merah, termasuk saat dua-duanya aktif.
- Tidak ada satellite gelap kosong yang menetap; pergantian ikon pada satellite terasa transisional dan tidak pop mendadak.
- Panel chooser lebih ringkas namun kedua kartu masih muat. Panel handoff/transfer cukup tinggi untuk thumbnail dan teks, tanpa clipping atau shrink yang tidak disengaja.
- Memilih LocalSend menampilkan “Preparing LocalSend…” saat penyiapan, lalu status handoff seperti “Continue in LocalSend”. Tidak ada progress bar transfer atau klaim sukses palsu untuk LocalSend.
- KDE Connect tetap menampilkan status transfer yang sesuai dengan sinyal dari service; success/error tidak mengacaukan timer cleanup.
- Tidak ada tabrakan dengan widget bar di resolusi 1366 × 768. `reservedWidth` sesuai dengan lebar aktual plus ruang satellite.
- Mengaktifkan dan mematikan camera/recording, membuka notification, mengganti wallpaper, atau memilih sharing secara cepat tidak meninggalkan dot ganda, panel macet, atau animasi lama yang terus berjalan.

## Catatan implementasi

Lakukan patch kecil dan terarah. Jangan refactor seluruh `DynamicIsland.qml` hanya demi merapikan animasi; file ini juga memuat media, notification, lockscreen, wallpaper dan system HUD. Setelah setiap tahap, jalankan reload/build Quickshell yang biasa dipakai di setup ini, cek log error QML, lalu rekam ulang rangkaian tes yang sama agar hasil geraknya dapat dibandingkan langsung.
