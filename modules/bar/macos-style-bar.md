# Task: Rombak Total Module `modules/bar/` — macOS-style Floating Bar

## Instruksi Umum

Ini BUKAN patch kecil. Ini perintah untuk **bongkar total dan bikin ulang dari nol** seluruh module `modules/bar/` di project Quickshell (`~/.config/quickshell`), diganti jadi floating pill bar ala macOS. Struktur file lama boleh dihapus/diganti total kalau memang nggak sesuai target di bawah.

## Konteks Project

- Lokasi: `~/.config/quickshell`
- Compositor: Hyprland (Lua config, `hyprland.lua`, Hyprland 0.55+)
- Struktur project:
  - `services/` — singleton QML (`Notifications`, `Audio`, `Brightness`, `Icons`, `Power`, `Applications`, `Clipboard`, `OverlayManager`)
  - `modules/` — komponen UI
- Module lama ada di `modules/bar/` (cek isinya dulu, sesuaikan path kalau beda)

## Target Struktur File Baru

Bar dipecah jadi beberapa file kecil per section — supaya nggak numpuk semua logic di 1 file gede:

```
modules/bar/
├── Bar.qml                      # entry point: PanelWindow + pill Rectangle,
│                                 # compose komponen dari components/
└── components/
    ├── WorkspaceIndicator.qml   # kiri: icon + label workspace aktif
    ├── ClockCenter.qml          # tengah: jam, absolute center
    └── StatusTray.qml           # kanan: volume, brightness, battery
```

`Bar.qml` isinya cuma PanelWindow + pill Rectangle + layout container yang nge-import dan nyusun 3 komponen di atas. Semua logic detail (binding service, format text, icon) tinggal di masing-masing file component-nya sendiri.

## Goal / Visual Reference

Bar macOS asli itu:

- Melayang (floating) dengan margin dari top-edge dan side-edge layar
- Bentuk pill / rounded, bukan kotak tajam
- Background blur/transparent (frosted glass effect)
- Layout 3 kolom: **kiri** (app/workspace info), **tengah** (jam, benar-benar center absolute terhadap layar, bukan cuma center RowLayout), **kanan** (status tray: volume, brightness, battery, network, dll)

ASCII mockup (representasi kasar, margin di semua sisi dari edge layar):

```
┌──────────────────────────────────────────────────────────────────┐
│  (margin 8px top, 12px left/right dari edge screen)               │
│   ╭──────────────────────────────────────────────────────────╮   │
│   │ 󰣇 Workspace 1        Sen, 4 Agu  14:32        󰕾 󰃞 󰖩 󰁹 100% │   │
│   ╰──────────────────────────────────────────────────────────╯   │
│              ↑ pill shape (radius = height/2), blur bg            │
└──────────────────────────────────────────────────────────────────┘
```

Detail visual:

- Radius pill = `height / 2` (setengah tinggi bar → jadi kapsul sempurna)
- Background: `#cc1e1e2e` (semi-transparent dark) + border tipis `#33ffffff` (1px, putih 20% opacity) — efek "kaca"
- Tinggi bar total ~34px, cukup ramping (macOS bar itu tipis, bukan chunky)
- Padding horizontal internal ~14px kiri-kanan
- Font clock: bold, ukuran sedikit lebih besar dari item lain biar jadi focal point tengah

## Spec: `Bar.qml` (Entry Point)

1. **PanelWindow** dengan `anchors { top: true; left: true; right: true }` (BUKAN full-screen, jangan pakai `bottom: true`)
2. **Margins** eksplisit: `top: 8, left: 12, right: 12` — ini yang bikin efek "floating", jangan nempel ke edge
3. **`color: "transparent"`** di root PanelWindow — WAJIB, kalau nggak nanti area di luar pill radius keliatan kotak solid
4. **`WlrLayershell.namespace: "quickshell:bar"`** — dipakai buat match layer_rule blur di Hyprland (lihat section Blur di bawah)
5. **Rectangle** di dalam PanelWindow sebagai visual pill: `radius: height/2`, isi RowLayout yang compose 3 komponen
6. **`exclusiveZone`** di-set ke `implicitHeight + margin top` supaya window lain (misal fullscreen app) nggak ketiban bar
7. Import components: `import "components" as Components`, lalu dipakai sebagai `Components.WorkspaceIndicator {}`, dst
8. Layout container: RowLayout isi `WorkspaceIndicator` (kiri) → `Item fillWidth` spacer → `Item fillWidth` spacer → `StatusTray` (kanan). `ClockCenter` DITARUH SEBAGAI SIBLING dari RowLayout ini (bukan child di dalamnya) — anchor langsung ke pill Rectangle, supaya posisinya absolute-center terhadap lebar bar, bukan relatif ke sisa ruang RowLayout

## Spec: `components/WorkspaceIndicator.qml`

- Icon + label workspace aktif
- Bind ke Hyprland active workspace via IPC/event — kemungkinan belum ada service khusus untuk ini. Kalau belum ada, buat `services/Workspaces.qml` baru: singleton yang expose `activeWorkspaceId`/`activeWorkspaceName`, pola sama seperti target `"notifications"`/`"launcher"`/`"clipboard"` yang udah ada di project (lihat `IpcHandler` di services lain sebagai referensi)
- Daftarkan singleton baru ini secara eksplisit di `services/qmldir` kalau dibuat

## Spec: `components/ClockCenter.qml`

- `anchors.horizontalCenter: parent.horizontalCenter` DAN `anchors.verticalCenter: parent.verticalCenter` terhadap parent-nya (pill Rectangle) — BUKAN `Layout.fillWidth` trick antara dua spacer
- Update tiap detik via `Timer { interval: 1000; repeat: true }`
- Kenapa harus anchor langsung, bukan lewat RowLayout spacer: kalau clock ditaruh di antara dua `Item Layout.fillWidth`, dia cuma "terlihat" center kalau lebar section kiri dan kanan persis sama. Begitu section kanan (status tray) lebih lebar dari section kiri (workspace), clock bakal kegeser dari center asli layar

## Spec: `components/StatusTray.qml`

- Icon status: volume, brightness, battery (bisa ditambah network/dll sesuai kebutuhan)
- Bind ke services yang udah ada — **cek isi file service dulu sebelum bikin binding**, karena nama property bisa beda dari asumsi:
  - `services/Audio.qml` → cari property volume/mute buat icon `󰕾`
  - `services/Brightness.qml` → cari property level buat icon `󰃞`
  - `services/Power.qml` → cari property battery percentage/charging state buat icon `󰁹`/`󰁹`, pakai `\u{f0084}` (charging) / `\u{f008e}` (outline) sesuai konvensi Nerd Font 5-digit PUA codepoint yang udah dipakai di `PowerOsd.qml`

## Pola Arsitektur Wajib Diikuti (Konsisten Sama Project Ini)

- Import services pakai relative path `../../services` (dari dalam `components/`, jadi `../../../services`) — JANGAN `root:/services`
- Icon dari icon-theme (bukan Nerd Font glyph) harus lewat `Quickshell.iconPath(icon, true)` dengan passthrough check untuk path yang udah mulai `/`, `file://`, atau `http`
- `services/qmldir` harus deklarasi singleton baru secara eksplisit kalau bikin service baru

## Blur Background (Efek Kaca Beneran)

Quickshell sendiri TIDAK render blur di balik surface-nya. Blur harus di-handle Hyprland via layer rule di `hyprland.lua`:

```lua
hl.layer_rule({ rule = "blur", match = "quickshell:bar" })
hl.layer_rule({ rule = "ignorezero", match = "quickshell:bar" })
hl.layer_rule({ rule = "xray", match = "quickshell:bar" })
```

Catatan:

- `match` harus sesuai `WlrLayershell.namespace` yang di-set di `Bar.qml`
- `xray` supaya area transparan di luar pill radius blur konten DI BELAKANGnya, bukan blur bar itu sendiri jadi kotak buram
- Kalau Hyprland belum ada `decoration { blur { enabled = true } }` global, blur layer rule ini nggak akan efek — cek dulu

## Gotcha dari Pengalaman Project Ini (WAJIB DIPERHATIKAN)

Pola-pola ini udah kejadian berulang di project quickshell yang sama, jadi kemungkinan besar relevan juga di module bar baru:

- Kalau nanti ada bagian interaktif (klik buat buka Center/Launcher), inget `notif.invokeAction(actionId)` itu API YANG SALAH — cari action via `.identifier` di array lalu panggil `.invoke()`
- Kalau ada `MouseArea` buat klik pill (misal klik jam buka calendar popup), declare MouseArea SEBELUM content Layout secara z-order kalau ada children lain yang bisa ke-swallow click-nya
- JANGAN taruh `MouseArea` sebagai child dari `Layout` (RowLayout/ColumnLayout) kalau dia bukan bagian dari flow — jadiin sibling `Item` yang di-anchor, supaya nggak ada undefined-behavior warning dari Qt
- Kalau workspace list di-render dari JS array of objects ke `ListModel`, inget itu jadi nested list-model: pakai `.count` bukan `.length`, akses via role property di delegate, BUKAN index langsung
- `PanelWindow.visible` harus di-kondisikan dengan benar biar nggak ngeblokir klik ke window lain — untuk bar yang emang selalu visible, ini biasanya udah aman (`visible: true` default), tapi kalau ada popup dari bar (misal dropdown status), popup itu butuh `visible: <list>.count > 0` pattern

## File yang Perlu Disentuh

1. `modules/bar/Bar.qml` — rewrite total jadi entry point yang compose components/
2. `modules/bar/components/WorkspaceIndicator.qml` — file baru
3. `modules/bar/components/ClockCenter.qml` — file baru
4. `modules/bar/components/StatusTray.qml` — file baru
5. `hyprland.lua` — tambah layer_rule buat blur (case-sensitive match namespace)
6. (Opsional, kalau workspace binding belum ada service-nya) `services/Workspaces.qml` — service baru + registrasi di `services/qmldir`
7. Hapus/bersihkan file lama di `modules/bar/` yang udah nggak relevan sama struktur baru ini

## Definition of Done

- [ ] Bar tampil floating dengan margin jelas dari edge (bukan nempel top-left-right kayak bar biasa)
- [ ] Bentuk pill (rounded penuh di kiri-kanan, radius = height/2)
- [ ] Background blur keliatan (bukan cuma solid semi-transparent tanpa blur — verifikasi visual dengan window lain di belakangnya)
- [ ] Jam di tengah ABSOLUTE terhadap lebar screen, bukan cuma "tengah" secara layout relatif, tetap center walau lebar kiri/kanan nggak simetris
- [ ] Icon status kanan (volume/brightness/battery) reflect state asli dari services, bukan placeholder statis
- [ ] Workspace aktif di kiri update real-time saat ganti workspace di Hyprland
- [ ] Struktur file sesuai target: `Bar.qml` + `components/` folder, bukan numpuk semua di 1 file
- [ ] Tidak ada QML warning/error di `qs log` atau output console saat load
- [ ] `nh-switch` sukses tanpa error setelah perubahan (kalau module bar di-manage lewat Nix module)
