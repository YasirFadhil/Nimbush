# Instruksi Fix: Icon Theme Tidak Konsisten Antar-OS di Nimbush

## Ringkasan Masalah

Icon theme yang di-set via `nwg-look`/GTK settings **tidak ikut ke Quickshell** di distro selain NixOS, walaupun `currentIconTheme` di `SystemTheme.qml` sudah ke-query dan ke-set dengan benar (lewat `gsettings`/`dconf`). Ini murni masalah di **layer resolusi icon Quickshell**, bukan di layer query/GTK.

## Root Cause (sudah dikonfirmasi dari source Quickshell)

`Quickshell.iconPath()` **tidak pernah membaca** `currentIconTheme` di QML kita. Dari dokumentasi resmi Quickshell:

> By default, icons are loaded from the theme selected by the **Qt platform theme**... If you want to use a different icon theme, you can put `//@ pragma IconTheme <name>` at the top of your root config file, or set the `QS_ICON_THEME` environment variable.

Dan dari source code-nya: `QIcon::setThemeName(...)` **hanya dipanggil sekali, saat proses Quickshell pertama kali launch** — dibaca dari pragma `IconTheme` atau env var `QS_ICON_THEME`. Setelah proses jalan, **tidak ada API runtime untuk ganti icon theme tanpa restart proses Quickshell-nya**.

Kenapa "kebetulan" work di NixOS: kemungkinan besar env `QT_QPA_PLATFORMTHEME` atau default fallback Qt di sistem NixOS kamu kebetulan berhasil membaca `gtk-icon-theme-name` dari `~/.config/gtk-3.0/settings.ini` (yang ditulis Home Manager). Di distro lain, chain fallback implisit itu putus (beda env, beda platform theme plugin, atau `settings.ini` tidak ke-generate sama).

**Kesimpulan:** kita tidak boleh bergantung pada auto-detect Qt yang tidak deterministik ini. Nimbush harus jadi satu-satunya sumber kebenaran, dengan set `QS_ICON_THEME` secara eksplisit sebelum proses Quickshell start — dan trigger **restart proses**, bukan hot-reload, tiap kali icon theme berubah.

---

## Langkah Perbaikan

### 1. `system-theme-helper.py` — persist pilihan icon theme ke file env, bukan cuma gsettings/dconf

Di dalam action `set_icon_theme <name>`, tambahkan: setelah menulis ke gsettings/dconf seperti biasa, tulis juga nilai tersebut ke file kecil yang independen dari desktop environment, misalnya:

```
~/.config/quickshell/state/icon-theme.env
```

isinya:

```
QS_ICON_THEME=<name>
```

Ini penting supaya Nimbush tidak bergantung pada gsettings/dconf sama sekali untuk resolve icon-nya sendiri (gsettings/dconf tetap ditulis untuk kompatibilitas app GTK lain, tapi bukan sumber yang dibaca Quickshell).

### 2. Wrapper launch Quickshell — source file env itu SEBELUM proses start

Cari command yang men-_launch_ Quickshell dan sesuaikan dengan compositor yang dipakai. **Jangan pakai syntax hyprlang klasik (`exec-once = ...`)** — kalau target kalian Hyprland 0.55+ dengan config Lua-only, dan/atau Niri, pakai salah satu (atau keduanya, tergantung auto-detect di `install.sh`):

**Hyprland (Lua, 0.55+):**

```lua
hl.on("hyprland.start", function()
    hl.exec_cmd("bash -c 'source ~/.config/quickshell/state/icon-theme.env 2>/dev/null; export QS_ICON_THEME; exec quickshell'")
end)
```

**Niri (KDL):**

```kdl
spawn-at-startup "bash" "-c" "source ~/.config/quickshell/state/icon-theme.env 2>/dev/null; export QS_ICON_THEME; exec quickshell"
```

Kalau pakai systemd user unit (compositor-agnostic, jadi opsi paling robust kalau install.sh kalian sudah setup systemd service buat Nimbush), tambahkan `EnvironmentFile=-%h/.config/quickshell/state/icon-theme.env` di section `[Service]` — ini nggak perlu peduli compositor Lua/KDL sama sekali.

> Kalau file env belum pernah ada (first run), pastikan tidak error (`2>/dev/null` di atas sudah handle itu) dan biarkan Quickshell pakai default Qt platform theme seperti biasa.

### 3. `SystemTheme.qml` — `setIconTheme()` harus trigger restart proses, bukan cuma ganti properti

Icon theme itu beda dari GTK widget theme: GTK theme bisa live-apply (lewat symlink/settings.ini), tapi icon theme di Quickshell **baked di process launch**. Jadi setelah `execProc` untuk `set_icon_theme` selesai (`onExited`), Nimbush harus:

1. Tampilkan notifikasi/toast ke user: _"Icon theme diubah — Nimbush akan restart sebentar untuk menerapkan."_
2. Trigger restart proses Quickshell sendiri, contoh pendekatan:
   ```qml
   function setIconTheme(name) {
       if (!name) return
       currentIconTheme = name
       execProc.running = false
       execProc.command = ["python3", helperScript, "set_icon_theme", name]
       execProc.running = true
   }
   ```
   Tambahkan handler baru (atau modifikasi `execProc.onExited`) yang, khusus untuk aksi `set_icon_theme`, memanggil restart. Kalau kalian sudah punya mekanisme restart shell (systemd `systemctl --user restart quickshell`, atau script kill+relaunch), panggil itu. Kalau belum ada, buat action baru di `system-theme-helper.py` atau `Process` terpisah:
   ```qml
   Process {
       id: restartProc
       command: ["bash", "-c", "systemctl --user restart quickshell.service"]
       // atau: "pkill -f 'quickshell' ; sleep 0.3 ; nohup quickshell >/dev/null 2>&1 & disown"
   }
   ```
   Panggil `restartProc.running = true` setelah `execProc` untuk `set_icon_theme` sukses (`exitCode === 0`).

### 4. (Opsional, robust) Tandai action mana yang butuh restart

Karena cuma `set_icon_theme` yang butuh full restart (GTK theme, cursor, font semua bisa live-apply), sebaiknya beri flag eksplisit di `execProc.onExited` untuk membedakan:

```qml
Process {
    id: execProc
    property string lastAction: ""
    onExited: (exitCode, exitStatus) => {
        if (lastAction === "set_icon_theme" && exitCode === 0) {
            restartProc.running = true
        }
    }
}
```

Dan set `execProc.lastAction = "set_icon_theme"` di dalam `setIconTheme()` sebelum `execProc.running = true`.

---

## Kenapa BUKAN pakai `//@ pragma IconTheme <name>` saja

Pragma itu di-parse dari root config file **saat compile/load**, bersifat statis per-file — tidak praktis untuk diubah otomatis dari Settings GUI runtime. Pendekatan env var (`QS_ICON_THEME` via file yang di-source sebelum exec) jauh lebih gampang dikontrol secara programatik dan konsisten dipakai di semua distro, tidak bergantung pragma hardcoded.

## Test Plan

1. Ganti icon theme dari Settings GUI Nimbush → pastikan file `~/.config/quickshell/state/icon-theme.env` terupdate.
2. Pastikan proses Quickshell benar-benar restart (cek PID berubah / cek log timestamp baru).
3. Setelah restart, buka launcher → app icon harus ikut icon theme baru, bukan monogram fallback.
4. Test di 2 distro berbeda (bukan cuma NixOS) untuk pastikan tidak lagi bergantung fallback implisit `settings.ini`.
