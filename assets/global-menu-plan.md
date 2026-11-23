# Global Menu Nimbush (AT-SPI bridge)

Rencana kerja dari tes sampai terintegrasi ke bar. Path mengikuti struktur repo
Nimbush di `~/.config/quickshell` yang gue tau. Isi `Bar.qml` dan komponen lain
belum gue lihat langsung, jadi kalau ada nama/path yang beda, sesuaiin.

## Gambaran arsitektur

```
Hyprland IPC (window fokus + pid)
        |
        v
services/ActiveApp.qml ---- pid ----> services/AppMenu.qml
                                           |  (Process + SplitParser)
                                           v
                              tools/atspi/atspi_menu.py  (helper daemon)
                                           |
                                           v
                                  AT-SPI bus (app asli)

AppMenu.model --> AppMenuButton.qml (bar) --> AppMenuPopup.qml (GlassSurface + MenuRow)
klik item     --> AppMenu.trigger(path) --> helper do_action --> app asli
```

Fallback kalau app nggak punya menu bar: aksi dari `.desktop` + aksi generik Hyprland.

## Status

- [x] `services.gnome.at-spi2-core.enable = true`
- [x] `IsEnabled` bisa di-set `true` manual
- [x] FeatherPad (Qt) kebaca sebagai application node di accerciser
- [ ] Mousepad (GTK) belum kebaca, kemungkinan kebuka sebelum flag true
- [ ] Skrip dump jalan dan hasilnya sudah dibandingkan (sebelum vs sesudah menu dibuka)

---

## Fase 0: Prasyarat sistem

1. **Flag a11y harus true tiap sesi.** Di setup tanpa GNOME nggak ada yang ngisi.
   Helper yang bakal nyalain sendiri pas start (Fase 2). Manual buat tes:
   ```
   busctl --user set-property org.a11y.Bus /org/a11y/bus org.a11y.Status IsEnabled b true
   ```
2. **Env var buat app yang lu launch.** Apps mewarisi env dari Hyprland/session,
   bukan dari systemd user service Quickshell. Jadi taruh di NixOS
   (`environment.sessionVariables`) atau di `hyprland.lua` tulisan tangan lu,
   **bukan** di Home Manager module Nimbush (keputusan lu: module itu nggak
   nulis apa pun soal Hyprland).
   - `QT_ACCESSIBILITY=1`
   - kalau GTK nggak muncul di tree: `GTK_A11Y=atspi` (tes dulu, mungkin nggak perlu)
3. **App harus di-restart** setelah flag jadi true. GTK cuma ngecek sekali pas start.

## Fase 1: Validasi helper standalone (terminal, belum Quickshell)

Folder: `~/.config/quickshell/tools/atspi/` isi `shell.nix` + `atspi_menu.py`.

1. `nix-shell` lalu `pgrep -a featherpad` buat PID.
2. `python atspi_menu.py <pid>` dengan menu **belum** dibuka. Simpan outputnya.
3. Klik menu File di FeatherPad sampai kebuka, jalanin skrip lagi. Simpan outputnya.
4. Bandingin dua output itu:
   - Submenu `children=0` sebelum dibuka lalu terisi sesudahnya: **lazy**, butuh trik "buka dulu, baca, tutup".
   - Sudah terisi dari awal: baca langsung, lebih simpel.
5. Cek kolom `actions=`: item yang bisa di-trigger harus punya action (misal `click`).
6. Ulangi di Mousepad (GTK) setelah restart app. Catat apakah butuh `GTK_A11Y`.
7. Coba juga `python atspi_menu.py active` buat window fokus lewat `hyprctl`.

**Keluaran fase ini:** catatan app mana yang kebaca, lazy atau nggak, env var apa yang perlu.

## Fase 2: Helper jadi daemon (JSON lines)

Ubah `atspi_menu.py` dari "dump sekali" jadi proses yang hidup terus.

1. **Saat start:** nyalain flag `IsEnabled` sendiri, lalu `Atspi.init()`.
2. **Protokol stdin** (satu JSON per baris):
   - `{"cmd":"menu","pid":1234}` minta menu bar app itu
   - `{"cmd":"trigger","pid":1234,"path":[0,2,1]}` jalanin item di path itu
3. **Protokol stdout** (satu JSON per baris):
   - `{"type":"menu","pid":1234,"items":[...]}`
   - `{"type":"error","msg":"..."}`
4. **Skema item:** `label`, `role`, `path` (list index dari menu bar), `enabled`,
   `separator`, `shortcut` (kalau ada), `children` (rekursif, dibatasi kedalaman).
5. **Trigger berdasarkan path, bukan referensi node.** Re-resolve dari app node
   tiap kali, karena node lama bisa basi setelah menu berubah.
6. **Kalau lazy:** buka menu parent dulu (`do_action(0)` di menu), tunggu sebentar
   sampai anak muncul, baca, lalu tutup lagi. Kalau ngedip, coba dump per level
   saat user hover, bukan sekaligus.
7. **Jangan polling.** Baca tree cuma saat window fokus berubah atau menu diklik.
8. Tangkap semua exception per node (tree AT-SPI sering ngasih node yang mati).

## Fase 3: Integrasi Quickshell

Urutan kerja, satu file per langkah. Setelah bikin file QML baru, **restart
Quickshell penuh** (bukan reload), karena cache stale.

### 3.1 `services/ActiveApp.qml` (singleton)

- Ambil window fokus dari integrasi Hyprland Quickshell: `class`, `title`, `pid`.
- Mapping `class` ke desktop entry lewat `DesktopEntries` (cek API
  `heuristicLookup` di docs Quickshell) buat dapet nama rapi + `actions`.
- **Bug yang udah keliatan:** FeatherPad tampil "Desktop" di bar, bukan
  "FeatherPad". Itu mapping class gagal, benerin di sini, bukan di bar.
- Abaikan PID Quickshell sendiri (window overlay Nimbush jangan dianggap app).
- Daftarin di `services/qmldir`.

### 3.2 `services/AppMenu.qml` (singleton)

- `Process` yang jalanin helper, `stdout: SplitParser` buat baca JSON per baris
  (pola sama kayak `Clipboard.qml` ke `cliphist`).
- Properti: `model` (items terbaru), `pid`, `loading`, `available` (ada menu bar atau nggak).
- Fungsi: `request(pid)`, `trigger(path)`.
- Panggil `request` saat `ActiveApp.pid` berubah, dengan debounce kecil.
- Kalau helper mati, restart otomatis dengan jeda, jangan loop cepat.
- Daftarin di `services/qmldir`.

### 3.3 Pindahin shared component

- `MenuRow.qml` sekarang di `modules/dock/`. Pindah ke `modules/common/`
  (bareng `GlassSurface`) supaya dock dan app menu pakai baris yang sama.
- Update import di `DockMenu.qml`.

### 3.4 `modules/bar/components/AppMenuButton.qml`

- Tampilin nama app (bold) dari `ActiveApp`, lalu judul menu top-level
  (File, Edit, ...) dari `AppMenu.model` kalau `available`.
- Dibangun di atas `BarPill` supaya konsisten sama bar glass.
- Klik judul menu membuka popup di posisi item tersebut.
- Cek dulu komponen mana yang sekarang nampilin nama app di kiri bar
  (kemungkinan `WorkspaceIndicator`) lalu ganti/arahkan ke komponen ini.

### 3.5 `modules/bar/components/AppMenuPopup.qml`

- Contek pola `TrayMenuPopup.qml`.
- Isi: `GlassSurface` + daftar `MenuRow`, submenu rekursif.
- Namespace `nimbush-appmenu`, tambah Hyprland layer rule (`blur`, `ignore_alpha`)
  dan matiin layer animation buat namespace itu, fade in/out di QML
  (sama kayak keputusan di dock).
- Item `enabled: false` ditampilin redup, separator ditampilin sebagai garis.
- Klik item: `AppMenu.trigger(path)` lalu tutup popup.

### 3.6 `OverlayManager`

- Tambah `appMenuVisible` biar popup ini ikut aturan fokus eksklusif dan
  nutup saat klik di luar, konsisten sama overlay lain.

### 3.7 `modules/bar/Bar.qml`

- Pasang `AppMenuButton` di sisi kiri. Jangan ganggu `exclusiveZone: 36`.

### 3.8 Fallback (app tanpa menu bar)

Kalau `AppMenu.available` false, popup nampilin:
- aksi dari `.desktop` (`actions` di entry), pola sama kayak dock menu
- aksi generik lewat Hyprland dispatch: Close Window, Fullscreen, Toggle Float,
  Move to Workspace
- Quit / Hide ala macOS

## Fase 4: Packaging Nix & installer

1. **Flake Nimbush:** tambah helper ke package/devShell: `python3.withPackages
   (ps: [ ps.pygobject3 ])` + `at-spi2-core`, `GI_TYPELIB_PATH` ke
   `lib/girepository-1.0`.
2. **`nix/home-manager-module.nix`:** helper dan dependensinya masuk PATH/environment
   systemd user service Quickshell. Tetap **tanpa** nulis file Hyprland.
3. **`install.sh`:** tambah ke dependency audit: `python-gobject` dan
   `at-spi2-core` (nama paket Arch), plus skip logic NixOS yang udah ada.
4. Catat di README bahwa app mungkin butuh `QT_ACCESSIBILITY=1` dan restart.

## Fase 5: Edge case & polish

- App Electron/Chromium: butuh `--force-renderer-accessibility`, sering berat. Anggap opsional.
- App libadwaita/GNOME tanpa menu bar: fallback Fase 3.8 yang kepake.
- Cache hasil menu per PID, invalidasi saat window fokus balik atau menu berubah.
- Tree besar: batasin kedalaman dan jumlah item, load submenu lazy saat hover.
- Shortcut: kalau AT-SPI ngasih keybinding, tampilin rata kanan di `MenuRow`.
- Window yang baru dibuka belum tentu langsung muncul di registry, retry singkat sebelum nyerah ke fallback.

## Debug checklist

- Tree kosong total: `IsEnabled` false, atau app belum di-restart setelah flag true.
- Qt nggak muncul: `QT_ACCESSIBILITY=1 <app>` dari terminal.
- GTK nggak muncul: tes `GTK_A11Y=atspi <app>`.
- Node ada di accerciser tapi nggak ketemu skrip: salah PID (wrapper script / flatpak
  ngasih PID beda), cocokin lewat nama app juga.
- Komponen QML baru nggak ke-load: restart Quickshell penuh, cek `qs log`.
- "MenuRow is not a type": file harus berdiri sendiri dan didaftarin/di-import dengan benar.
- Trigger nggak ngapa-ngapain: item bukan leaf (cuma buka submenu) atau node basi,
  re-resolve dari path.
