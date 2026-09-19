# Plan: Adaptive StatusTray — Graceful Degradation terhadap Dynamic Island

**Proyek:** Nimbush (Quickshell / NixOS)
**Scope file:** `modules/bar/Bar.qml`, `modules/bar/components/StatusTray.qml`, `DynamicIsland.qml`, `SysmonIndicator.qml`, `ClockCenter.qml`, `SystemTrayIcons.qml`, `WorkspaceIndicator.qml`
**Tujuan:** Mengganti sistem hide berbasis threshold hardcoded dengan sistem _budget_ berbasis pengukuran, dengan degradasi 3 tahap (squeeze → compact → yield) dan tanpa binding loop.

---

## ATURAN MUTLAK — baca sebelum menulis kode apa pun

Tiga aturan ini tidak boleh dilanggar di fase mana pun. Kalau ragu, hentikan dan laporkan.

### A1. Keputusan layout TIDAK BOLEH bergantung pada ukuran hasil layout

Dilarang keras menghitung `overflow` dari `width`, `Layout.preferredWidth`, atau `implicitWidth` milik anak-anak StatusTray.

Alasan: `implicitWidth` pill berubah saat mode compact aktif (teks dibuang). Kalau keputusan compact dihitung dari `implicitWidth`, terjadi siklus: `overflow > 0` → compact → `implicitWidth` mengecil → `overflow <= 0` → un-compact → `implicitWidth` membesar → `overflow > 0` → osilasi tak berujung pada 60fps.

Semua pengukuran wajib memakai **nilai konstan yang dihitung dari konten, bukan dari state layout**. Implementasinya: `TextMetrics` (Fase 1).

### A2. Keputusan layout dihitung IMPERATIF, bukan deklaratif

Hasil keputusan (`tier`, `yieldedSet`) disimpan di `property` biasa yang di-assign dari dalam sebuah fungsi, **bukan** di `readonly property` dengan binding. Histeresis mustahil diimplementasikan dalam binding murni karena binding tidak boleh membaca state sebelumnya tanpa memicu loop.

### A3. Jangan menghapus fitur yang sudah ada

`Services.OverlayManager.isLocked`, semua flag `Services.Config.show*Tray`, dan seluruh `barStyle` (islands / floating / unified / minimal) harus tetap berfungsi persis seperti sekarang. Sistem baru **berlapis di atas** logika lock, bukan menggantikannya.

---

## Peta perubahan per fase

| Fase | Isi                                                       | File                                |
| ---- | --------------------------------------------------------- | ----------------------------------- |
| 1    | Kontrak `trayWidthFull` / `trayWidthCompact` di tiap anak | 5 file komponen                     |
| 2    | Island expose `reservedWidth` + `demand`                  | `DynamicIsland.qml`, `Bar.qml`      |
| 3    | Mesin budget + histeresis di StatusTray                   | `StatusTray.qml`                    |
| 4    | Tahap 1: squeeze (spacing & padding)                      | `StatusTray.qml`                    |
| 5    | Tahap 2: compact (buang teks)                             | `StatusTray.qml` + komponen         |
| 6    | Tahap 3: yield berurutan                                  | `StatusTray.qml`                    |
| 7    | Sisi kiri (WorkspaceIndicator)                            | `Bar.qml`, `WorkspaceIndicator.qml` |
| 8    | Verifikasi                                                | —                                   |

Kerjakan **berurutan**. Setiap fase harus bisa dijalankan (`qs` reload) tanpa error sebelum lanjut.

---

## FASE 1 — Kontrak lebar di setiap anak tray

Setiap komponen yang duduk di `StatusTray` harus mengumumkan dua lebar konstan. Nilai ini tidak boleh bergantung pada `trayCompact`.

### 1.1 Kontrak yang harus diimplementasikan

Tambahkan property berikut di elemen root tiap komponen:

```qml
// ── Tray layout contract ──────────────────────────────────────
property bool trayCompact: false      // di-set dari luar oleh StatusTray
property bool trayYielded: false      // di-set dari luar oleh StatusTray

readonly property real trayWidthFull: 0      // override di tiap komponen
readonly property real trayWidthCompact: 0   // override di tiap komponen
```

### 1.2 `SysmonIndicator.qml`

Ganti isi `RowLayout` supaya teks persen bisa dilepas, dan tambahkan `TextMetrics` untuk mengukur tanpa merender.

```qml
Rectangle {
    id: sysmonPill

    property bool trayCompact: false
    property bool trayYielded: false

    readonly property int hPad: isMinimal ? 12 : 20
    readonly property int innerSpacing: isMinimal ? 4 : 6

    TextMetrics {
        id: mIcon
        font.family: Services.Theme.fontSymbols
        font.pixelSize: sysmonPill.isMinimal ? Services.Theme.fontSizeMd : Services.Theme.fontSizeXl
        text: Services.Icons.cpu
    }
    TextMetrics {
        id: mPct
        font.family: Services.Theme.fontMono
        font.pixelSize: sysmonPill.isMinimal ? Services.Theme.fontSizeSm : Services.Theme.fontSizeMd
        // PENTING: pakai lebar tetap 3 digit ("100%"), JANGAN nilai live.
        // Kalau pakai nilai live, lebar berubah tiap detik dan memicu
        // recompute terus-menerus.
        text: "100%"
    }

    readonly property real trayWidthCompact: Math.ceil(mIcon.width) + hPad
    readonly property real trayWidthFull: trayWidthCompact + innerSpacing + Math.ceil(mPct.width)

    implicitHeight: isMinimal ? 24 : 28
    implicitWidth: trayCompact ? trayWidthCompact : trayWidthFull
    // ... sisanya tetap
}
```

Lalu pada `Text` persen di dalam `sysmonRow`:

```qml
Text {
    id: sysmonPctText
    text: Math.round(Services.Sysmon.cpuUsage) + "%"
    visible: !sysmonPill.trayCompact
    opacity: sysmonPill.trayCompact ? 0 : 1
    Layout.preferredWidth: sysmonPill.trayCompact ? 0 : implicitWidth
    clip: true
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on Layout.preferredWidth { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
    // ... font & color tetap
}
```

Catatan: `visible` dan `Layout.preferredWidth` animasi bertabrakan — `visible: false` memutus animasi. Ganti `visible` menjadi `visible: opacity > 0.01` supaya fade-out sempat berjalan.

### 1.3 `ClockCenter.qml`

Mode compact = buang prefix tanggal, sisakan jam.

Ubah `clockText.updateTime()`:

```qml
function updateTime() {
    const is24 = Services.Config ? Services.Config.clock24h : true
    const showSec = Services.Config ? Services.Config.clockShowSeconds : false
    // compact memaksa: tanpa tanggal, tanpa detik
    const showDate = clockPill.trayCompact ? false : (Services.Config ? Services.Config.clockShowDate : true)
    const useSec   = clockPill.trayCompact ? false : showSec
    const dateFmt  = Services.Config ? Services.Config.clockDateFormat : "short"

    const timePattern = is24
        ? (useSec ? "HH:mm:ss" : "HH:mm")
        : (useSec ? "hh:mm:ss A" : "hh:mm A")

    let datePrefix = ""
    if (showDate) datePrefix = (dateFmt === "full" ? "dddd, d MMMM  " : "ddd, d MMM  ")

    clockText.text = Qt.formatDateTime(new Date(), datePrefix + timePattern)
}
```

Tambahkan pemicu:

```qml
onTrayCompactChanged: clockText.updateTime()
```

Dan dua `TextMetrics` untuk mengukur kedua varian. Gunakan **string sampel terpanjang yang mungkin**, bukan teks saat ini:

```qml
TextMetrics {
    id: mClockFull
    font: clockText.font
    text: {
        const is24 = Services.Config ? Services.Config.clock24h : true
        const sec  = Services.Config ? Services.Config.clockShowSeconds : false
        const date = Services.Config ? Services.Config.clockShowDate : true
        const fmt  = Services.Config ? Services.Config.clockDateFormat : "short"
        let p = ""
        if (date) p = (fmt === "full" ? "Wednesday, 30 September  " : "Wed, 30 Sep  ")
        return p + (is24 ? (sec ? "00:00:00" : "00:00") : (sec ? "00:00:00 AM" : "00:00 AM"))
    }
}
TextMetrics {
    id: mClockCompact
    font: clockText.font
    text: (Services.Config && Services.Config.clock24h) ? "00:00" : "00:00 AM"
}

readonly property real trayWidthFull: Math.ceil(mClockFull.width) + (isMinimal ? 12 : 20)
readonly property real trayWidthCompact: Math.ceil(mClockCompact.width) + (isMinimal ? 12 : 20)
implicitWidth: trayCompact ? trayWidthCompact : trayWidthFull
```

> `ClockCenter` juga dipakai di `Bar.qml` sebagai jam tengah untuk mode non-island. Di sana `trayCompact` tidak pernah di-set, jadi default `false` → perilaku lama persis sama. Jangan ubah pemakaian itu.

### 1.4 Volume pill & Battery pill (di dalam `StatusTray.qml`)

Kedua pill ini didefinisikan inline. Terapkan pola yang sama:

- **Volume**: compact = hanya ikon, teks `"XX%"` dilepas. Ukur dengan `TextMetrics` teks `"100%"`.
- **Battery**: compact = hanya ikon, teks persen dilepas. Ukur dengan `TextMetrics` teks `"100%"`.

Catatan untuk battery: ikonnya dinamis (`Services.Icons.powerIcon`) dan lebarnya bisa berbeda antar glyph. Ukur dengan glyph yang sedang aktif — perubahan lebar ikon kecil (<3px) dan tidak memicu osilasi karena masuk zona histeresis.

**Perhatian pada `volPill`:** `volLayout` saat ini pakai `anchors.right` + `rightMargin`, bukan `centerIn`. Pertahankan, jangan diganti ke `centerIn` — itu disengaja untuk animasi crossfade ikon.

### 1.5 `SystemTrayIcons.qml`

Tidak punya mode compact (ikon tidak bisa dikecilkan tanpa jadi jelek). Cukup expose:

```qml
readonly property real trayWidthFull: trayLayout.implicitWidth + 16
readonly property real trayWidthCompact: trayWidthFull
```

`trayLayout.implicitWidth` di sini aman dipakai karena tidak terpengaruh `trayCompact` — tidak ada jalur umpan balik.

**Peluang opsional (kerjakan hanya setelah Fase 8 lulus):** turunkan `maxVisibleCount` saat tekanan tinggi supaya ikon berlebih terlipat ke `TrayOverflowPopup` alih-alih pill-nya hilang total. Ini lebih baik daripada yield, karena tidak ada informasi yang benar-benar lenyap. Simpan sebagai follow-up, jangan dikerjakan sekarang.

### 1.6 Checkpoint Fase 1

Reload shell. Bar harus tampil **persis seperti sebelumnya** (tidak ada yang men-set `trayCompact`, jadi semua masih `false`). Kalau ada pergeseran 1–2px, itu wajar — `TextMetrics` sedikit berbeda dari `Text.implicitWidth`. Kalau pergeserannya > 5px, periksa `font` pada `TextMetrics` sudah identik dengan `Text` aslinya.

---

## FASE 2 — Dynamic Island mengumumkan niat, bukan angka mentah

### 2.1 Tambahkan di `DynamicIsland.qml`

Letakkan tepat setelah blok `calculatedExpandedHeight` (sekitar baris 694):

```qml
// ── Bar layout negotiation ────────────────────────────────────
// Lebar yang di-"klaim" island dari bar, sudah termasuk kompensasi
// overshoot animasi.
readonly property real reservedWidth: {
    const base = expanded ? calculatedExpandedWidth : calculatedCollapsedWidth
    return base + satelliteExtraWidth + (expanded ? overshootAllowance : 0)
}

// Behavior on width memakai Easing.OutBack, yang MELAMPAUI nilai target
// sebelum settle. Tanpa kompensasi ini, island menabrak tray
// selama ~100ms di puncak overshoot.
// OutBack default overshoot = 1.70158 → puncak ≈ +10% dari delta.
readonly property real overshootAllowance: 28

readonly property string demand: {
    if (!expanded) return "idle"
    if (dropSendMode || isDropSending || wallpaperMode) return "greedy"
    if (isMediaPeek) return "peek"
    return "normal"
}
```

### 2.2 Sederhanakan `Bar.qml`

Ganti blok `Components.StatusTray` (baris 167–174) menjadi:

```qml
Components.StatusTray {
    id: statusTray
    Layout.alignment: Qt.AlignVCenter
    barWidth: root.width
    rightMargin: root.isFloating ? 18 : (root.isUnified ? 16 : 12)

    // Lebar yang diklaim oleh elemen tengah — island, atau jam tengah
    // pada mode non-island.
    centerReservedWidth: root.showDynamicIsland
        ? dynamicIsland.reservedWidth
        : (centerClockContainer.visible ? centerClockContainer.width : 0)

    islandDemand: root.showDynamicIsland ? dynamicIsland.demand : "idle"
}
```

Hapus property lama `islandRightEdge`, `islandCollapsedRightEdge`, `isIslandExpanded` dari pemanggilan ini.

> Ini sekaligus memperbaiki bug yang belum pernah kelihatan: pada mode `floating`/`unified`/`minimal`, `centerClockContainer` tidak pernah diperhitungkan oleh tray, jadi di layar sempit tray bisa menimpa jam tengah.

**Jangan** buat ini singleton di `Services/`. `Bar.qml` adalah `Variants` per-screen; state ini harus per-`PanelWindow`.

### 2.3 Checkpoint Fase 2

Reload. Perilaku akan **mundur sementara** — semua logika hide lama sudah tidak punya input yang benar. Ini diharapkan. Tray akan selalu tampil penuh dan bisa bertabrakan dengan island. Lanjut ke Fase 3.

---

## FASE 3 — Mesin budget di `StatusTray.qml`

### 3.1 Hapus yang lama

Hapus seluruh property berikut dari `StatusTray.qml`:

```
barWidth (ganti signature), islandRightEdge, islandCollapsedRightEdge,
isIslandExpanded, islandPushDelta, availableRightSpace,
hideVolume, hideSysmon, hideTrayIcons, hideBattery, hideControl,
hideClock, fullUncollapsedWidth
```

Semuanya digantikan oleh mesin di bawah.

### 3.2 Input & pengukuran

```qml
// ── Input dari Bar ────────────────────────────────────────────
property real barWidth: 1920
property real rightMargin: 12
property real centerReservedWidth: 0
property string islandDemand: "idle"

// ── Konstanta tuning ──────────────────────────────────────────
readonly property real safetyGap: 20      // jarak napas minimum island↔tray
readonly property real hysteresisPx: 24   // beda ambang naik vs turun tier
readonly property int  restoreDelayMs: 140

// ── Ruang yang tersedia ───────────────────────────────────────
readonly property real centerRightEdge: (barWidth + centerReservedWidth) / 2
readonly property real availableWidth:
    Math.max(0, barWidth - rightMargin - centerRightEdge - safetyGap)
```

### 3.3 Daftar item dan urutan mengalah

Satu tempat, deklaratif. Urutan = siapa mengalah duluan.

```qml
// Urutan mengalah: paling depan = paling dulu dikorbankan.
// Alasan urutan: Volume & CPU punya panel sendiri yang bisa dibuka lewat
// cara lain; Clock & Control Center adalah anchor terakhir yang harus
// bertahan.
readonly property var yieldOrder: [volPill, sysmonInd, sysTrayIcons, batPill, ctrlPill, clockCenterPill]

// Item mana yang boleh masuk mode compact (buang teks).
readonly property var compactables: [clockCenterPill, batPill, volPill, sysmonInd]
```

`clockCenterPill` ada di urutan terakhir yield dan di daftar compactable — ini disengaja: jam mengecil jauh sebelum ia hilang.

### 3.4 Fungsi lebar total pada tier tertentu

```qml
function widthAtTier(tier) {
    // tier 0 = full, 1 = squeeze, 2 = compact, 3+ = compact + yield bertahap
    const spacing = spacingForTier(tier)
    const compact = tier >= 2
    let total = 0
    let yieldCount = Math.max(0, tier - 2)

    for (let i = 0; i < yieldOrder.length; i++) {
        const item = yieldOrder[i]
        if (!item || !item.visible) continue
        if (i < yieldCount) continue   // item ini mengalah pada tier ini
        const useCompact = compact && compactables.indexOf(item) !== -1
        total += (useCompact ? item.trayWidthCompact : item.trayWidthFull) + spacing
    }
    return Math.max(0, total - spacing)  // spacing terakhir tidak dihitung
}

function spacingForTier(tier) {
    const base = isMinimal ? 4 : 8
    if (tier === 0) return base
    return Math.max(2, base - 4)
}
```

### 3.5 State machine dengan histeresis

**Ini bagian paling penting. Jangan diubah jadi binding.**

```qml
// State hasil — di-assign dari fungsi, BUKAN binding.
property int layoutTier: 0

// Tier maksimum yang tersedia: 2 (compact) + jumlah item yang bisa yield
readonly property int maxTier: 2 + yieldOrder.length

function recomputeLayout() {
    const avail = availableWidth
    let tier = layoutTier

    // Naik tier (perketat) — langsung, tanpa histeresis.
    // Tabrakan visual lebih buruk daripada satu langkah ekstra.
    while (tier < maxTier && widthAtTier(tier) > avail) {
        tier++
    }

    // Turun tier (longgarkan) — butuh margin histeresis,
    // supaya tidak berkedip di ambang batas.
    while (tier > 0 && widthAtTier(tier - 1) + hysteresisPx <= avail) {
        tier--
    }

    layoutTier = tier
}

// Debounce asimetris:
//  - memperketat: SEGERA (0ms) — jangan sampai tabrakan sempat terlihat
//  - melonggarkan: TERTUNDA — supaya island selesai menyusut dulu,
//    dan supaya HUD volume yang muncul-hilang cepat tidak bikin kedip
Timer {
    id: restoreTimer
    interval: root.restoreDelayMs
    onTriggered: root.recomputeLayout()
}

function requestLayout() {
    // Cek cepat: apakah kondisi saat ini sudah overflow?
    if (widthAtTier(layoutTier) > availableWidth) {
        restoreTimer.stop()
        recomputeLayout()        // perketat sekarang juga
    } else {
        restoreTimer.restart()   // longgarkan nanti
    }
}

onAvailableWidthChanged: requestLayout()
onIslandDemandChanged: requestLayout()
Component.onCompleted: recomputeLayout()
```

Tambahkan juga `onVisibleChanged: root.requestLayout()` pada `sysTrayIcons` — jumlah ikon tray berubah saat aplikasi dibuka/ditutup, dan itu mengubah `trayWidthFull`.

### 3.6 Terapkan hasil ke anak-anak

Ganti setiap `shouldHide` lama. Pola baru untuk **setiap** item di `yieldOrder`:

```qml
// contoh untuk volPill
readonly property int yieldIndex: root.yieldOrder.indexOf(volPill)
readonly property bool isYielded:
    Services.OverlayManager.isLocked
    || (root.layoutTier >= 3 && yieldIndex < (root.layoutTier - 2))
readonly property bool isCompact:
    root.layoutTier >= 2 && root.compactables.indexOf(volPill) !== -1

trayCompact: isCompact
trayYielded: isYielded

Layout.preferredWidth: isYielded ? 0 : (isCompact ? trayWidthCompact : trayWidthFull)
Layout.rightMargin: isYielded ? 0 : root.itemSpacing
opacity: isYielded ? 0.0 : 1.0
enabled: opacity > 0.5
clip: true
```

`Layout.preferredWidth` sekarang dirantai langsung ke konstanta terukur, **tidak lagi ke `implicitWidth`**. Ini yang memutus kemungkinan feedback loop (aturan A1).

Pertahankan semua `Behavior` yang sudah ada (350ms OutCubic untuk width, 250ms untuk opacity). Pertahankan juga `Easing.OutBack` khusus di `ctrlPill` — itu aksen yang disengaja.

### 3.7 Checkpoint Fase 3

Reload. Uji: putar musik (island → 360px), lalu buka Wallpaper Studio (island → 480px). Item harus mengalah bertahap dan kembali mulus. **Perhatikan khusus:** tidak boleh ada kedipan sama sekali saat menekan tombol volume berulang-ulang cepat (`sysHudActive` menyala-padam). Kalau berkedip, naikkan `hysteresisPx` ke 32 dan `restoreDelayMs` ke 200.

---

## FASE 4 — Tahap squeeze

Sudah tercakup `spacingForTier()` di Fase 3. Tambahan: perketat juga padding horizontal pill.

Di `StatusTray.qml`:

```qml
readonly property int itemSpacing: spacingForTier(layoutTier)
readonly property int pillHPad: layoutTier >= 1 ? (isMinimal ? 8 : 12) : (isMinimal ? 12 : 20)
```

Lalu di setiap komponen, ganti `(isMinimal ? 12 : 20)` yang hardcoded dengan nilai yang diturunkan dari parent. Untuk komponen terpisah (`SysmonIndicator`, `ClockCenter`), tambahkan property yang di-set dari `StatusTray`:

```qml
property int hPadOverride: -1
readonly property int hPad: hPadOverride >= 0 ? hPadOverride : (isMinimal ? 12 : 20)
```

**Penting:** `hPad` ikut dipakai di `trayWidthFull`/`trayWidthCompact`, sedangkan `hPad` bergantung pada `layoutTier` yang dihitung dari `widthAtTier()` yang memanggil `trayWidthFull`. **Ini melanggar aturan A1.**

Solusinya: `trayWidthFull` dan `trayWidthCompact` harus selalu memakai padding **tier 0** (nilai penuh), lalu `widthAtTier()` mengurangi selisihnya sendiri:

```qml
function widthAtTier(tier) {
    const spacing = spacingForTier(tier)
    const padSaving = tier >= 1 ? (isMinimal ? 4 : 8) : 0
    // ... dalam loop:
    total += (useCompact ? item.trayWidthCompact : item.trayWidthFull) - padSaving + spacing
}
```

Dengan begitu `trayWidthFull` tetap konstan dan aturan A1 aman.

---

## FASE 5 — Verifikasi compact

Tidak ada kode baru; ini fase uji. Pastikan pada `layoutTier === 2`:

- Jam menampilkan `10:30` saja (tanpa `Wed, 16 Sep`)
- Battery menampilkan ikon saja
- Volume menampilkan ikon saja
- CPU menampilkan ikon saja
- **Tidak ada satu pun item yang hilang**

Hitung penghematan aktual dan catat. Target: tier 2 harus menyerap ≥ 130px. Kalau di layar 1920 dengan island 480px (`wallpaperMode`) masih ada item yang yield, berarti penghematan compact kurang — periksa apakah `ClockCenter` benar-benar membuang prefix tanggal.

---

## FASE 6 — Verifikasi yield

Uji di layar sempit (paksa dengan `Services.Config.barScreens` atau resize output Hyprland ke 1366x768):

- `dropSendMode` (island 500px) di 1366px → beberapa item wajib yield
- Urutan yang hilang harus: Volume → CPU → SysTray → Battery → Control → Clock
- Jam adalah yang terakhir bertahan

---

## FASE 7 — Simetri sisi kiri

`WorkspaceIndicator` saat ini tidak pernah mengalah. Island tumbuh dua arah dari tengah, jadi di layar sempit ia akan tertabrak lebih dulu daripada tray.

Di `Bar.qml`:

```qml
Components.WorkspaceIndicator {
    Layout.alignment: Qt.AlignVCenter
    visible: Services.Config ? Services.Config.showWorkspaces : true

    readonly property real centerLeftEdge: root.showDynamicIsland
        ? ((root.width - dynamicIsland.reservedWidth) / 2) : root.width
    readonly property real availableLeft:
        centerLeftEdge - (root.isFloating ? 18 : (root.isUnified ? 16 : 12)) - 20

    // compact = tampilkan dots saja, tanpa label/ikon window
    compactMode: availableLeft < implicitWidth

    // ... opacity & transform untuk isLocked tetap seperti sekarang
}
```

Implementasikan `property bool compactMode: false` di `WorkspaceIndicator.qml` dengan perilaku: sembunyikan label teks / ikon aplikasi, sisakan indikator titik. Gunakan pola animasi yang sama (`Layout.preferredWidth` + `opacity`, 350ms / 250ms OutCubic).

Ini boleh memakai `implicitWidth` karena `WorkspaceIndicator` adalah item tunggal, bukan bagian dari mesin budget tray — tapi tetap butuh histeresis kecil. Bungkus dengan pola `requestLayout()` sederhana kalau terdeteksi kedip.

---

## FASE 8 — Checklist verifikasi akhir

Jalankan semua, centang satu per satu:

**Fungsional**

- [ ] `barStyle` = islands / floating / unified / minimal — keempatnya tampil benar
- [ ] Non-island: tray tidak menimpa `centerClockContainer` di layar sempit
- [ ] Semua `Services.Config.show*Tray` masih menyembunyikan itemnya
- [ ] `OverlayManager.isLocked` masih menyembunyikan semua tray
- [ ] Klik Volume / Battery / CPU / Clock / Control Center masih membuka panel, dan `targetX` panel masih benar setelah item bergeser
- [ ] Popup tray (`TrayMenuPopup`, `TrayOverflowPopup`) masih muncul di posisi benar

**Stabilitas — ini yang paling sering gagal**

- [ ] Spam tombol volume 20x cepat → tidak ada kedip, tidak ada osilasi
- [ ] Notifikasi beruntun (island 360 → 390 saat replyMode) → transisi mulus
- [ ] Buka/tutup aplikasi ber-tray-icon berulang → layout stabil
- [ ] Jam berdetak setiap detik (`clockShowSeconds: true`) → **tidak** memicu recompute (ini alasan `TextMetrics` pakai `"00:00:00"`, bukan teks live)
- [ ] Cek log Quickshell: **nol** peringatan binding loop
- [ ] Idle 5 menit dengan musik jalan → CPU shell tidak naik

**Visual**

- [ ] Saat island membesar cepat (OutBack overshoot), island **tidak pernah** menyentuh pill tray
- [ ] Saat island menyusut, tray kembali setelah island selesai (bukan bersamaan)
- [ ] Multi-monitor: tiap layar menghitung sendiri, layar lebar tidak ikut compact gara-gara layar sempit

---

## Yang TIDAK dikerjakan di plan ini

Catat sebagai follow-up, jangan dikerjakan sekarang:

1. Melipat ikon tray ke `TrayOverflowPopup` saat tekanan tinggi (turunkan `maxVisibleCount`) — lebih baik daripada yield, tapi butuh perubahan di `SystemTrayIcons` + `TrayOverflowPopup` sekaligus.
2. Menjadikan `yieldOrder` bisa diatur user dari `Settings.qml`.
3. Menerapkan pola yang sama ke dock (belum dibuat).
