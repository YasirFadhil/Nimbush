# Arsitektur Pengambilan GTK Theme dan Icon Aplikasi di QuickShell

Dokumen ini menjelaskan secara rinci dan mendalam bagaimana konfigurasi QuickShell (QS) ini mengambil dan mengelola **GTK Theme** serta bagaimana **Icon Aplikasi pada Launcher** diambil dan dirender.

---

## 1. Mekanisme Pengambilan GTK Theme

Pengambilan GTK theme dalam QuickShell ini menggunakan arsitektur **Hybrid QML + Python Subprocess (GSettings / DConf & XDG Discovery)**.

### A. Komponen Utama
1. **Frontend Service (QML Singleton):**
   - [`services/SystemTheme.qml`](../services/SystemTheme.qml)
   - Berfungsi sebagai state manager terpusat yang menyimpan properti reaktif seperti `gtkThemes` (daftar tema) dan `currentGtkTheme` (tema aktif).
2. **Backend Helper (Python Script):**
   - [`scripts/system-theme-helper.py`](../scripts/system-theme-helper.py)
   - Bertanggung jawab untuk berinteraksi langsung dengan sistem operasi (GSettings, DConf, Nix profiles, direktori XDG, dan konfigurasi GTK).
3. **UI Pengaturan:**
   - [`modules/settings/Settings.qml`](../modules/settings/Settings.qml) (bagian menu *Appearance*).

---

### B. Alur Pengambilan (Query) GTK Theme

```
[SystemTheme.qml]
       │
       ▼ (Component.onCompleted / refresh())
[Process: python3 scripts/system-theme-helper.py query]
       │
       ├──► 1. Ambil Tema Aktif (Current GTK Theme)
       │         │
       │         ├─► gsettings get org.gnome.desktop.interface gtk-theme
       │         └─► (Fallback) dconf read /org/gnome/desktop/interface/gtk-theme
       │
       ├──► 2. Pindai Daftar Tema Terinstall (Available GTK Themes)
       │         │
       │         └─► get_data_dirs("themes")
       │               ├─ ~/.local/share/themes & ~/.themes
       │               ├─ /etc/profiles/per-user/$USER/share/themes
       │               ├─ /run/current-system/sw/share/themes
       │               ├─ ~/.nix-profile/share/themes
       │               ├─ /usr/share/themes & /usr/local/share/themes
       │               └─ $XDG_DATA_DIRS/themes
       │
       ▼ Output JSON dikirim melalui stdout
[SystemTheme.qml SplitParser]
       │
       ▼ JSON.parse(rawOutput)
Properti QML diperbarui:
- root.currentGtkTheme
- root.gtkThemes
- root.currentColorScheme (dark/light)
```

#### Rincian Teknis:
1. **Deteksi Tema Aktif (`currentGtkTheme`):**
   - Python memanggil `gsettings get org.gnome.desktop.interface gtk-theme`.
   - Jika `gsettings` gagal (misalnya karena environment D-Bus atau schema belum terinstall), ada fallback otomatis ke `dconf read /org/gnome/desktop/interface/gtk-theme`.
   - Nilai tema aktif dimasukkan ke object JSON: `data.current.gtk_theme`.
2. **Deteksi Daftar Tema yang Tersedia (`gtkThemes`):**
   - Fungsi `get_gtk_themes()` di `system-theme-helper.py` memindai seluruh direktori tema yang terdaftar di XDG dan profil NixOS:
     - `~/.local/share/themes` dan direktori legacy `~/.themes`
     - Profil NixOS pengguna: `/etc/profiles/per-user/<user>/share/themes`
     - Profil NixOS sistem: `/run/current-system/sw/share/themes`
     - Profil Nix standalone: `~/.nix-profile/share/themes` dan `/nix/profile/share/themes`
     - Standar distro: `/usr/share/themes` dan `/usr/local/share/themes`
     - Direktori yang ada di variabel `$XDG_DATA_DIRS`
   - Folder diverifikasi sebagai tema GTK jika memuat salah satu folder: `gtk-3.0/`, `gtk-4.0/`, `gtk-2.0/`, atau berkas `index.theme`.
3. **Penerimaan di QML:**
   - Di `SystemTheme.qml`, output subprocess dibaca menggunakan `SplitParser` pada sinyal `queryProc.stdout`.
   - Setelah proses exit (`onExited`), string di-parse dengan `JSON.parse(trimmed)`.
   - Properti `root.gtkThemes` dan `root.currentGtkTheme` otomatis terisi dan memicu pembaruan antarmuka secara reaktif.

---

### C. Alur Pengubahan (Setter) GTK Theme
Ketika tema GTK dipilih melalui antarmuka pengaturan:
1. Memanggil `Services.SystemTheme.setGtkTheme(name)`.
2. `SystemTheme.qml` menjalankan `python3 system-theme-helper.py set_gtk_theme <name>`.
3. Skrip Python menerapkan tema secara sinkron ke seluruh layer Linux desktop:
   - **GSettings & DConf:** Menulis `org.gnome.desktop.interface gtk-theme <name>`.
   - **GTK 3 & GTK 4 Config:** Memperbarui `gtk-theme-name` di `~/.config/gtk-3.0/settings.ini` dan `~/.config/gtk-4.0/settings.ini` (dengan proteksi cerdas tidak menimpa symlink read-only milik Nix store / Home Manager via fungsi `is_nix_store_managed()`).
   - **GTK 2 Config:** Memperbarui `~/.gtkrc-2.0`.
   - **XSettings Daemon (X11):** Menulis ke `~/.config/xsettingsd/xsettingsd.conf` dan mengirim sinyal `pkill -HUP xsettingsd`.
   - **Symlink Stylesheet:** Mengaitkan symlink `gtk.css`, `gtk-dark.css`, dan `libadwaita.css` di `~/.config/gtk-4.0/` dan `~/.config/gtk-3.0/` agar aplikasi Libadwaita/GTK4 langsung mengikuti tema tersebut.

---

## 2. Mekanisme Pengambilan Icon Aplikasi di Launcher

Pengambilan icon aplikasi di launcher QuickShell melewati rantai: **Desktop Entry Specification (XDG) ➔ Quickshell Engine C++ Resolution ➔ Sanitasi Jalur di SystemTheme.qml ➔ Render Asinkron di QML Image dengan Fallback Monogram**.

### A. Komponen Utama
1. **Sumber Data Aplikasi:**
   - [`services/Applications.qml`](../services/Applications.qml)
   - Menggunakan singleton engine bawaan Quickshell: `DesktopEntries.applications`.
2. **Universal Icon Resolver:**
   - [`services/SystemTheme.qml`](../services/SystemTheme.qml) -> fungsi `getIcon(iconName)`.
   - C++ Native Engine Method: `Quickshell.iconPath(iconName, fallback)`.
3. **Komponen Antarmuka Launcher:**
   - [`modules/launcher/Launcher.qml`](../modules/launcher/Launcher.qml) (komponen delegate aplikasi `appItem`).

---

### B. Dari Mana Data Icon Diambil?

```
Direktori Berkas .desktop:
├── ~/.local/share/applications/*.desktop
├── /etc/profiles/per-user/$USER/share/applications/*.desktop
├── /run/current-system/sw/share/applications/*.desktop
├── ~/.nix-profile/share/applications/*.desktop
└── /usr/share/applications/*.desktop
       │
       ▼ Dibaca & di-parse oleh Quickshell C++ Engine
[DesktopEntries.applications.values]
       │
       ▼ Diindeks & difilter di Applications.qml
Setiap objek aplikasi memiliki field:
- app.name (Contoh: "Firefox")
- app.icon (Contoh: "firefox", "code", atau path "/opt/app/icon.png")
```

1. **Spesifikasi FreeDesktop .desktop:**
   - Setiap aplikasi di Linux menyertakan baris entri `Icon=...` di dalam berkas `.desktop` miliknya.
   - Contoh isi `firefox.desktop`:
     ```ini
     [Desktop Entry]
     Name=Firefox
     Exec=firefox %u
     Icon=firefox
     Type=Application
     ```
2. **Parsing oleh Quickshell Engine:**
   - Di `Applications.qml`, properti `DesktopEntries.applications.values` mengekstrak seluruh metadata `.desktop` ke dalam JavaScript Object di QML.
   - Properti `icon` dapat berupa string nama tema (misal `"firefox"`, `"org.gnome.Nautilus"`), path absolut (misal `"/usr/share/pixmaps/app.png"`), atau object icon.

---

### C. Lewat Apa Icon Diresolusi Menjadi Gambar?

Di dalam [`modules/launcher/Launcher.qml`](../modules/launcher/Launcher.qml#L311-L335), setiap item aplikasi merender icon melalui proses resolusi bertingkat:

```
[Nama Icon Mentah (rawIcon)]
       │
       ▼
[Services.SystemTheme.getIcon(rawIcon)]
       │
       ├──► 1. Cek Apakah Sudah Berupa Path/URI
       │         Jika diawali "file://", "http://", "https://", atau "/"
       │         ──► Kembalikan langsung (e.g. "file:///path/icon.png")
       │
       ├──► 2. Resolusi Lewat Engine Native C++:
       │         Quickshell.iconPath(iconName, true)
       │         │
       │         ▼
       │     Mencari di tema icon yang sedang aktif (misal MacTahoe-dark)
       │     dan direktori standar:
       │       - ~/.icons/<theme>/
       │       - ~/.local/share/icons/<theme>/
       │       - /run/current-system/sw/share/icons/<theme>/
       │       - /etc/profiles/per-user/$USER/share/icons/<theme>/
       │       - /usr/share/icons/<theme>/
       │       - /usr/share/pixmaps/
       │     (Parameter 'true' mengaktifkan fallback ke Parent Theme & hicolor)
       │
       ├──► 3. Fallback Penghapusan Ekstensi
       │         Jika nama icon memiliki ekstensi ("app.png" / "app.svg"),
       │         ekstensi dihilangkan menjadi "app", lalu dicari ulang lewat
       │         Quickshell.iconPath(baseName, true).
       │
       └──► 4. Fallback Kosong & Monogram
                 Jika tidak ditemukan file fisik di sistem:
                 ──► Mengembalikan string kosong "" (mencegah black-magenta broken texture).
                 ──► QML menampilkan Fallback Letter Badge (huruf inisial aplikasi).
```

#### Detail Algoritma `getIcon(iconName)` pada `SystemTheme.qml`:
```javascript
function getIcon(iconName) {
    if (!iconName) return ""
    var s = typeof iconName === "string" ? iconName.trim() : (iconName.name || iconName.toString() || "").trim()
    if (!s) return ""

    // 1. Jika sudah berupa path absolut atau URI jaringan
    if (s.startsWith("file://") || s.startsWith("http://") || s.startsWith("https://")) return s
    if (s.startsWith("/")) return "file://" + s
    
    // 2. Bersihkan skema Qt image provider jika ada
    if (s.startsWith("image://icon/")) s = s.substring(13).trim()
    else if (s.startsWith("image://")) return s
    if (!s) return ""

    // 3. Quickshell theme resolution dengan fallback enabled (FreeDesktop Icon Spec)
    var qp = Quickshell.iconPath(s, true)
    if (qp && qp.length > 0) {
        return qp.startsWith("/") ? ("file://" + qp) : qp
    }

    // 4. Jika aplikasi menyertakan nama berkas (misal: "app.png" / "app.svg")
    if (s.indexOf(".") !== -1) {
        var baseName = s.replace(/\.[^/.]+$/, "")
        if (baseName.length > 0) {
            var qpBase = Quickshell.iconPath(baseName, true)
            if (qpBase && qpBase.length > 0) {
                return qpBase.startsWith("/") ? ("file://" + qpBase) : qpBase
            }
        }
    }

    // 5. Kembalikan string kosong jika tidak ditemukan
    return ""
}
```

#### Render di `Launcher.qml` & Fallback Monogram:
Jika file icon fisik tidak ditemukan di sistem, `getIcon` mengembalikan string kosong `""`. Pada `Launcher.qml`, elemen `Image` akan berstatus `ico.status !== Image.Ready`, sehingga secara otomatis menampilkan kotak inisial huruf dari nama aplikasi:

```qml
// Fallback monogram jika icon tidak ada / gagal dimuat
Rectangle {
    anchors.fill: parent
    radius: 8
    color: appItem.index === resultList.currentIndex ? Qt.rgba(255, 255, 255, 0.1) : Qt.rgba(255, 255, 255, 0.05)
    visible: !ico.source || ico.status !== Image.Ready || !ico.visible

    Text {
        anchors.centerIn: parent
        text: (appItem.modelData.name || "?").charAt(0).toUpperCase()
        color: appItem.index === resultList.currentIndex ? Services.Theme.accent : Services.Theme.textDisabled
        font.pixelSize: Services.Theme.fontSizeXl
        font.bold: true
    }
}
```

---

## 3. Ringkasan Singkat

| Aspek | Diambil Dari Mana? | Lewat Apa / Mekanisme? |
| :--- | :--- | :--- |
| **GTK Theme Aktif** | GNOME Desktop Interface config | Perintah CLI `gsettings get org.gnome.desktop.interface gtk-theme` (fallback `dconf read`), dieksekusi lewat helper `scripts/system-theme-helper.py` oleh `Quickshell.Io.Process`. |
| **Daftar Tema GTK** | Direktori sistem & user (`~/.local/share/themes`, `/run/current-system/sw/share/themes`, dsb.) | Pemindaian direktori Python via `system-theme-helper.py query` yang memvalidasi keberadaan folder `gtk-3.0`, `gtk-4.0`, atau `index.theme`. |
| **Daftar Aplikasi Launcher** | Berkas `.desktop` di direktori aplikasi standar XDG (`/usr/share/applications`, `/run/current-system/sw/share/applications`, dll.) | Engine C++ Quickshell melalui binding singleton `DesktopEntries.applications.values` di `services/Applications.qml`. |
| **Nama Icon Aplikasi** | Field `Icon=...` di masing-masing berkas `.desktop` | Properti `app.icon` yang diparsing oleh Quickshell ke objek QML. |
| **Resolusi File Gambar Icon** | Paket Icon Theme aktif (misal `MacTahoe-dark`, `Adwaita`, `hicolor`) di direktori `share/icons` dan `pixmaps` | Method native C++ `Quickshell.iconPath(name, true)` yang dibungkus oleh `Services.SystemTheme.getIcon()` dengan sanitasi jalur dan fallback monogram. |
