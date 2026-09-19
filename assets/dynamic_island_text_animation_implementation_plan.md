# Dynamic Island Text & Motion Choreography Plan

Dokumen ini berisi arsitektur dan langkah teknis untuk mengubah animasi teks media pada `DynamicIsland.qml` dari sekadar *fade-in/fade-out* menjadi pergerakan fisik berkesinambungan (*continuous shared-element / kinetic typography*) di setiap fase.

---

## 1. Analisis Arsitektur & Masalah Saat Ini

| Komponen / Fase | Status Saat Ini | Masalah Visual | Solusi Target |
| :--- | :--- | :--- | :--- |
| **Track Switch** | `trackSwitchAnim` memakai `opacity: 0 -> 1` pada teks yang sama. | Teks berkedip (*blinking*) di tempat tanpa kesan perpindahan trek. | **Vertical Rolodex / Push Slot**: Teks lama terdorong ke atas/bawah, teks baru meluncur masuk. |
| **Open (Collapsed $\to$ Expanded)** | Menggunakan 2 elemen `Text` terpisah dengan `opacity` cross-fade. | Dua teks terpisah hilang-timbul; terasa putus koneksi fisiknya. | **Translational Flight & Font Scaling**: Teks terbang dari koordinat pill menuju koordinat expanded header. |
| **Close (Expanded $\to$ Collapsed)** | Teks expanded fade-out, teks pill fade-in setelah resize. | Sensasi layout patah saat mengecil kembali ke pill. | **Reverse Coordinate Retract**: Teks meluncur kembali ke titik asal pill sebelum lebar mengecil. |
| **Stop Media** | Mengandalkan debounce timer, teks langsung dipotong visibilitasnya. | Teks terpotong (*clipped*) secara kasar sebelum kontainer menyusut. | **Slide & Scale Exit (Squeeze Out)**: Teks meluncur cepat ke samping/tengah lalu disusul penyusutan island. |

---

## 2. Fase Implementasi Bertahap

### Tahap 1: Struktur Dual-Slot Text untuk Pergantian Track (Rolodex Push)

Ganti `collapsedTextContainer` agar menggunakan sistem **Dual-Slot Buffer** (Slot A & Slot B) sehingga dua teks lagu dapat eksis bersamaan selama durasi transisi:

```qml
Item {
    id: collapsedTextContainer
    clip: true // Memotong teks yang meluncur keluar batas pill

    property string displayedText: ""
    property bool useSlotA: true

    function updateTrackPush(newTitle, isNextTrack) {
        if (newTitle === displayedText) return
        displayedText = newTitle

        const offset = isNextTrack ? 18 : -18 // Arah dorongan (Next: dari bawah ke atas; Prev: sebaliknya)
        if (useSlotA) {
            slotB.text = newTitle
            slotB.y = offset
            slotB.opacity = 0.0

            slotPushAnimB.restart()
            useSlotA = false
        } else {
            slotA.text = newTitle
            slotA.y = offset
            slotA.opacity = 0.0

            slotPushAnimA.restart()
            useSlotA = true
        }
    }
}
```

#### Parameter Kurva Animasi (Easing & Duration):
* **Keluar (Out)**: `duration: 220ms`, `easing.type: Easing.InQuad`
* **Masuk (In)**: `duration: 320ms`, `easing.type: Easing.OutBack`, `easing.overshoot: 1.15`

---

### Tahap 2: Seamless Shared Flight (Collapsed $\to$ Expanded)

Hubungkan posisi spasial saat transisi membuka media control:

1. **Mapping Titik Awal (Origin)**:
   * Posisi awal teks collapsed relatif terhadap root island: `(X_start, Y_start)`.
   * Posisi target teks title di media expanded: `(X_target, Y_target)`.
2. **Delta Offset**:
   * Hitung selisih:
     $$\Delta X = X_{\text{start}} - X_{\text{target}}$$
     $$\Delta Y = Y_{\text{start}} - Y_{\text{target}}$$
3. **Trigger Transform**:
   * Saat `root.expanded` menjadi `true`:
     * Set `titleMorphTranslate.x = deltaX`
     * Set `titleMorphTranslate.y = deltaY`
     * Jalankan animasi ke `(0, 0)` secara paralel dengan pelebaran island (`island.width` dan `island.height`).

```qml
ParallelAnimation {
    id: textFlightAnim
    NumberAnimation {
        target: titleMorphTranslate
        property: "x"
        to: 0
        duration: 360
        easing.type: Easing.OutBack
        easing.overshoot: 1.12
    }
    NumberAnimation {
        target: titleMorphTranslate
        property: "y"
        to: 0
        duration: 340
        easing.type: Easing.OutCubic
    }
    NumberAnimation {
        target: mediaTitleText
        property: "font.pixelSize"
        from: 11
        to: 13
        duration: 320
        easing.type: Easing.OutCubic
    }
}
```

---

### Tahap 3: Staggered Fade & Slide Down (Expanded Controls)

Agar teks tetap menjadi fokus utama selama ekspansi, tunda sedikit elemen pendukung lainnya:
* **Cover Art**: Membesar dari titik tengah atau slide dari kiri (`duration: 280ms`).
* **Title Text**: Mengalir langsung ke posisinya tanpa delay (`duration: 340ms`).
* **Artist Text**: Mengikuti dengan jeda 30ms di bawah title.
* **Progress Bar & Control Buttons**: Muncul dengan pergeseran vertikal lembut dari bawah (`y: +8 -> 0`, `opacity: 0 -> 1`, delay 60ms).

---

### Tahap 4: Koreografi Stop Media (Graceful Exit)

Ubah alur `mediaStopping` agar teks keluar lebih dahulu sebelum kontainer mengecil:

1. **Event `mediaPlaying = false` diterima**:
   * Matikan marquee (`globalMediaMarqueeAnim.stop()`).
   * Geser teks judul ke arah visualizer atau pudar ke kiri:
     ```qml
     NumberAnimation {
         target: collapsedTextContainer
         property: "opacity"
         to: 0.0
         duration: 180
         easing.type: Easing.InQuad
     }
     NumberAnimation {
         target: collapsedTextContainer
         property: "x"
         to: collapsedTextContainer.x - 20
         duration: 180
         easing.type: Easing.InQuad
     }
     ```
2. **On Finished (180ms)**:
   * Set `root.mediaTextCollapsed = true`.
   * Biarkan `calculatedCollapsedWidth` menyusut kembali ke default pill (140px / capsule idle).

---

## 3. Checklist Eksekusi Mandiri

- [ ] **Persiapan**: Buat backup berkas `DynamicIsland.qml` sebelum melakukan modifikasi.
- [ ] **Langkah 1**: Refaktor `collapsedTextContainer` menjadi dual-slot teks (`slotA` dan `slotB`).
- [ ] **Langkah 2**: Sambungkan `trackTitleChanged` MPRIS ke fungsi `updateTrackPush()`.
- [ ] **Langkah 3**: Sinkronisasi durasi `Behavior on width` pada `island` (360ms–380ms) dengan durasi `textFlightAnim`.
- [ ] **Langkah 4**: Pasang `clip: true` pada kontainer judul untuk memastikan tidak ada artefak teks yang bocor keluar kapsul saat bergerak.
- [ ] **Langkah 5**: Sesuaikan urutan `mediaStopPhase1Timer` agar animasi keluar selesai sebelum reset state.