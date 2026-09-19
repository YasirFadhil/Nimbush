# Implementation Plan: Ultra-Smooth Circular Media Peek Anti-Aliasing & Vinyl Disc Refinement

## 1. Problem Diagnosis
Tangkapan layar menunjukkan tepi thumbnail cover album pada Media Peek tampak kasar, bergerigi (*aliased/jagged*), dan tidak bulat presisi.

### Root Causes
1. **FBO Layer 1x Sampling**: `layer.enabled: true` di Qt Quick secara default merender item mask ke FBO tanpa antialiasing (*supersampling*), menyebabkan tepi kurva terpotong kasar (*hard alpha step*).
2. **Ketiadaan MSAA**: `layer.samples` belum diatur pada container maupun mask source.
3. **MultiEffect Threshold Quantization**: Nilai threshold/spread `0.0` menyebabkan fungsi `step()` memotong gradien alpha sub-piksel menjadi biner (1 atau 0), meniadakan kehalusan MSAA.
4. **Rotational Boundary Aliasing**: Menempelkan `RotationAnimation` langsung pada layer yang meng-host `MultiEffect` memutar batas lingkaran terhadap grid piksel layar, menciptakan efek *shimmering* / gerigi bergerak.
5. **High-Contrast Boundary Artifact**: Belum ada cincin penegas sub-piksel di `z: 3` untuk menyamarkan batas potong terhadap latar hitam Dynamic Island.

---

## 2. Architecture & Solution Strategy

### A. Hardware Multisampling (MSAA 8x) & Dynamic Gating
- Tambahkan `layer.samples: 8` dan `layer.smooth: true` pada `peekArtContent` serta `peekArtMask`. Ini mengaktifkan 8x multisample anti-aliasing pada tingkat GPU sebelum tekstur dialihkan ke `MultiEffect`.
- Tetap gunakan gating performa `layer.enabled: peekRow.visible` agar framebuffer MSAA 8x tidak mengonsumsi VRAM dan siklus GPU saat island dalam keadaan tertutup/collapsed.

### B. Alpha Feathering via MultiEffect Tuning
- Konfigurasi `MultiEffect`:
  - `maskThresholdMin: 0.5`
  - `maskSpreadAtMin: 0.5`
- Ini memastikan transisi alpha lingkaran direntangkan secara proporsional dengan `smoothstep`, mempertahankan kehalusan gradien sub-piksel dari rasterizer MSAA.

### C. Pemisahan Rotasi Vinyl dari Aperture Mask Statis
- Tempatkan animasi rotasi pada kontainer dalam (`peekArtSpinContainer`), **bukan** pada `peekArtContent`.
- **Manfaat**: Piringan artwork berputar mulus seperti piringan hitam di dalam lubang aperture yang tetap statis pada grid layar. Tepi luar lingkaran bebas dari kedipan rotasi (*zero moiré / rotational jitter*).
- Ikon fallback `󰎈` tetap tegak dan berada persis di tengah saat artwork belum siap.

### D. Texture Upsampling & Resampling
- Atur `sourceSize: Qt.size(102, 102)` (3x dari 34x34) pada `Image`.
- Aktifkan `smooth: true`, `mipmap: true`, dan `antialiasing: true` untuk memastikan resampling resolusi tinggi tanpa tangga piksel saat dirotasi maupun di-downscale.

### E. Sub-Pixel Anti-Aliasing Border Overlay (Vinyl Rim)
Tambahkan cincin penegas di `z: 3`:
- `radius: width / 2`
- `border.width: 1`
- `border.color: Qt.rgba(255, 255, 255, 0.14)`
- `antialiasing: true`
- `smooth: true`

Cincin ini menutup batas mikro rasterisasi dan memberikan estetika piringan audio premium (*vinyl disc rim*).

---

## 3. Implementation Blueprint (`DynamicIsland.qml`)

Target: Mengganti blok thumbnail album di dalam `peekRow` (baris 1824–1904).

```qml
// ==================== Compact Track Artwork (Ultra-Smooth Vinyl / Circular Masked) ====================
Item {
    id: peekDiscWrapper
    implicitWidth: 34
    implicitHeight: 34
    Layout.alignment: Qt.AlignVCenter

    // 1. Layer Konten Gambar + MSAA Buffer
    Item {
        id: peekArtContent
        anchors.fill: parent
        layer.enabled: peekRow.visible
        layer.samples: 8
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: peekArtMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 0.5
        }

        // Inner spinning disc (Artwork spins smoothly inside static mask aperture)
        Item {
            id: peekArtSpinContainer
            anchors.fill: parent
            transformOrigin: Item.Center

            // Base background fallback
            Rectangle {
                anchors.fill: parent
                color: Services.Theme.surfaceVariant
            }

            // High-Res Resampled Album Artwork
            Image {
                id: peekArtImg
                anchors.fill: parent
                source: root.activePlayer ? (root.activePlayer.trackArtUrl || root.activePlayer.artUrl || "") : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                smooth: true
                mipmap: true
                antialiasing: true
                sourceSize: Qt.size(102, 102)
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
            }

            // Smooth subtle vinyl rotation (decoupled from circular frame)
            RotationAnimation on rotation {
                from: 0; to: 360
                duration: 12000
                loops: Animation.Infinite
                running: root.mediaPlaying && root.isMediaPeek && peekRow.activeState && (peekArtImg.status === Image.Ready)
            }
        }

        // Fallback Music Symbol (static & upright, centered)
        Text {
            anchors.centerIn: parent
            text: "󰎈"
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 15
            color: Services.Theme.accent
            visible: peekArtImg.status !== Image.Ready
        }
    }

    // 2. High-Precision Anti-Aliased Circle Mask
    Item {
        id: peekArtMask
        anchors.fill: parent
        visible: false
        layer.enabled: peekRow.visible
        layer.samples: 8
        layer.smooth: true

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#ffffff"
            antialiasing: true
            smooth: true
        }
    }

    // 3. Sub-Pixel Anti-Aliasing Border Overlay (Vinyl Rim)
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.color: Qt.rgba(255, 255, 255, 0.14)
        border.width: 1
        antialiasing: true
        smooth: true
        z: 3
    }
}
```

---

## 4. Verification Checklist
- [x] Tepi kurva cover bulat mulus tanpa sudut tangga piksel (*jagged*).
- [x] Piringan album berputar mulus tanpa merusak/menggoyang batas lingkaran luar (*no rotational jitter*).
- [x] Aspect ratio tetap 1:1 (34x34) konsentris pas dengan kapsul 54px (margin 10px atas & bawah).
- [x] Fallback ikon tetap tegak di tengah tanpa ikut berputar terbalik saat cover belum siap.
- [x] Animasi expand dan collapse pulau tetap berjalan di 60 FPS tanpa beban GPU sia-sia berkat gating `layer.enabled: peekRow.visible`.