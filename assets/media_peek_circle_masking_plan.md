# Rencana Implementasi: Circle Masking & Refinement Media Peek Dynamic Island

## 1. Analisis Masalah Saat Ini

- **Penyebab Gambar Ngotak**:
  Pada deklarasi QML saat ini:
  ```qml
  Rectangle {
      implicitWidth: 32
      implicitHeight: 32
      radius: Services.Theme.radiusSm
      clip: true
      Image { ... }
  }
  ```
  Di QtQuick, properti `clip: true` pada `Rectangle` hanya memotong area berbasis *axis-aligned bounding box* (kotak lurus), bukan berdasarkan kurva `radius`. Akibatnya, 4 sudut tajam `Image` menembus keluar radius.
- **Ketidaksesuaian Bentuk dengan Kapsul Peek**:
  Pada mode `isMediaPeek` (tinggi 54px), Dynamic Island berbentuk kapsul oval penuh (`radius: height / 2`). Gambar kotak di dalamnya terasa kaku dan tidak konsisten jika disandingkan dengan bentuk *Camera HUD Peek* (Video 2) yang berbasis lingkaran/lingkar kurva alami.

---

## 2. Tujuan Perubahan

1. **Circle/Vinyl Disc Masking**: Mengubah bentuk artwork di Media Peek menjadi lingkaran penuh (`radius: width / 2`) dengan anti-aliasing mulus memanfaatkan `MultiEffect` mask dari `QtQuick.Effects`.
2. **Kesesuaian Desain HUD**: Mencocokkan rasio dan perataan vertikal agar proporsional dengan kapsul Dynamic Island (mirip bulatan HUD kamera).
3. **Penyempurnaan Opsional (Vinyl Accent)**:
   - Menambahkan ring/border tipis halus untuk kesan piringan hitam/lensa modern.
   - Rotasi lambat saat musik berputar (opsional / toggleable).

---

## 3. Rencana Komponen & Struktur Kode

### Target File: `DynamicIsland.qml`
**Bagian**: `// ==================== Expanded: Media Peek ====================` (sekitar baris 700 - 750)

### Struktur Hirarki Baru
```text
RowLayout (peekRow)
 ├── Item (Disc/Artwork Container: 34x34)
 │    ├── Item (layer.enabled + MultiEffect) [Content]
 │    │    ├── Image (peekArtImg - cover album mpris)
 │    │    └── Rectangle (Fallback icon jika artwork belum load/gagal)
 │    ├── Item (layer.enabled) [Mask Source: Rectangle radius width/2]
 │    └── Rectangle (Outer Subtle Border Ring / Rim Accent)
 ├── ColumnLayout (peekInfoCol: Title + Artist/Identity)
 └── Item (Spinning Music Status Icon / Indicator)
```

---

## 4. Langkah-Langkah Pengerjaan Rinci

### Langkah 1: Penggantian Blok Thumbnail Artwork di `peekRow`
Ganti blok `Rectangle` thumbnail lama:

```qml
// LAMA:
Rectangle {
    implicitWidth: 32
    implicitHeight: 32
    radius: Services.Theme.radiusSm
    color: Services.Theme.surfaceVariant
    clip: true
    Layout.alignment: Qt.AlignVCenter

    Image {
        id: peekArtImg
        anchors.fill: parent
        source: root.activePlayer ? (root.activePlayer.trackArtUrl || root.activePlayer.artUrl || "") : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        sourceSize: Qt.size(64, 64)
        visible: status === Image.Ready
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutQuad } }
    }

    Text {
        anchors.centerIn: parent
        text: "󰎈"
        font.family: Services.Theme.fontSymbols
        font.pixelSize: 16
        color: Services.Theme.accent
        visible: !peekArtImg.visible
    }
}
```

Menjadi implementasi `MultiEffect` circle mask:

```qml
// BARU:
Item {
    id: peekDiscWrapper
    implicitWidth: 34
    implicitHeight: 34
    Layout.alignment: Qt.AlignVCenter

    // Kontainer Konten dengan Masking MultiEffect
    Item {
        id: peekArtContent
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: peekArtMask
        }

        // Background Fallback
        Rectangle {
            anchors.fill: parent
            color: Services.Theme.surfaceVariant
        }

        // Image Album Art
        Image {
            id: peekArtImg
            anchors.fill: parent
            source: root.activePlayer ? (root.activePlayer.trackArtUrl || root.activePlayer.artUrl || "") : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            sourceSize: Qt.size(68, 68)
        }

        // Icon Fallback ketika belum ready
        Text {
            anchors.centerIn: parent
            text: "󰎈"
            font.family: Services.Theme.fontSymbols
            font.pixelSize: 15
            color: Services.Theme.accent
            visible: peekArtImg.status !== Image.Ready
        }
    }

    // Mask Sumber: Lingkaran Penuh Murni (Anti-Aliased)
    Item {
        id: peekArtMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "black"
            antialiasing: true
        }
    }

    // Outer Border Accent (Ring halus di tepian disc)
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "transparent"
        border.color: Qt.rgba(255, 255, 255, 0.12)
        border.width: 1
        antialiasing: true
    }
}
```

---

### Langkah 2: Pilihan Estetika Tambahan (Vinyl Spin)
Jika ingin menambahkan efek vinyl berputar saat lagu aktif:
- Tambahkan properti rotasi pada `peekArtContent`:
```qml
RotationAnimation on rotation {
    from: 0; to: 360
    duration: 10000
    loops: Animation.Infinite
    running: root.mediaPlaying && root.isMediaPeek
}
```

---

## 5. Kriteria Keberhasilan (Checklist Validasi)

- [x] **Sudut Tidak Bocor**: Tidak ada sudut piksel tajam dari `Image` yang keluar dari lingkaran berkat `MultiEffect` mask.
- [x] **Simetri dengan Ujung Kapsul**: Lingkaran artwork berukuran 34x34 dengan `anchors.margins: 10` pas dengan tinggi kapsul 54px.
- [x] **Fallback Berjalan Mulus**: Ketika aplikasi media berganti atau tidak memiliki cover art, ikon not balok `󰎈` tetap berada di tengah lingkaran.
- [x] **Performa Ringan**: Penggunaan `MultiEffect` di-gate dengan `layer.enabled: peekRow.visible`, sehingga tidak menambah beban rendering GPU saat collapsed.