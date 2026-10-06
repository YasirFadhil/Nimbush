pragma Singleton
import QtQuick
import Quickshell

// Satu-satunya tempat angka/warna "kaca" boleh ditulis.
// Taruh di folder services dan daftarkan di qmldir:
//     singleton Glass 1.0 Glass.qml
Singleton {
    id: root

    // ── Kontrol global ──────────────────────────────────────────────────
    // Skala semua alpha. 1.0 = default, bisa dihubungkan ke slider Config.
    property real intensity: 1.0

    readonly property bool dark: Theme.isDark

    // ── Level elevasi ───────────────────────────────────────────────────
    // 0 = elemen di dalam permukaan kaca lain (tipis, tanpa highlight)
    // 1 = permukaan melayang mandiri (popup, menu, tooltip)
    // 2 = permukaan utama (bar, dock)
    readonly property var darkFill: [0.06, 0.38, 0.34]
    readonly property var lightFill: [0.12, 0.68, 0.64]

    // TODO: turunkan dari Theme (matugen) kalau sudah cocok. Sementara
    // memakai nilai lama dari Dock supaya tampilan tidak bergeser.
    readonly property color tintDark:  Qt.rgba(0.35, 0.38, 0.50, 1)
    readonly property color tintLight: Qt.rgba(0.96, 0.96, 0.98, 1)

    function clamp01(v) { return Math.max(0, Math.min(1, v)) }

    function fill(level) {
        const a = clamp01((dark ? darkFill : lightFill)[level] * intensity)
        const c = dark ? tintDark : tintLight
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    function border(level, hovered) {
        if (dark)
            return Qt.rgba(1, 1, 1, clamp01((hovered ? 0.22 : 0.14) * intensity))
        return Qt.rgba(0, 0, 0, clamp01((hovered ? 0.16 : 0.10) * intensity))
    }

    // Garis dalam tipis di bawah border
    function rim(level) {
        return Qt.rgba(1, 1, 1, dark ? 0.04 : 0.15)
    }

    // Overlay hover/aktif untuk elemen di atas kaca (pill bar, dst.).
    // Transparan supaya blur tetap terlihat; ikut skala intensity.
    readonly property color hoverFill: dark
        ? Qt.rgba(1, 1, 1, clamp01(0.10 * intensity))
        : Qt.rgba(0, 0, 0, clamp01(0.07 * intensity))

    // Kilau di tepi atas (puncak gradient horizontal)
    readonly property color specular: Qt.rgba(1, 1, 1, dark ? 0.28 : 0.55)
    readonly property color specularEdge: Qt.rgba(1, 1, 1, 0)

    // ── Bentuk ──────────────────────────────────────────────────────────
    readonly property int borderWidth: 1
    readonly property int radiusXs: 6
    readonly property int radiusSm: 8
    readonly property int radiusMd: 12
    readonly property int radiusLg: 22

    // ── Warna pendukung ─────────────────────────────────────────────────
    readonly property color separator:       dark ? Qt.rgba(1, 1, 1, 0.22) : Qt.rgba(0, 0, 0, 0.18)
    readonly property color separatorShadow: dark ? Qt.rgba(0, 0, 0, 0.30) : Qt.rgba(1, 1, 1, 0.45)
    readonly property color iconBubble:      Qt.rgba(1, 1, 1, 0.08)
    readonly property color dangerHover:     Qt.rgba(0.9, 0.2, 0.2, 0.15)

    function accentAlpha(a) {
        const c = Theme.accent
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    // ── Gerak ───────────────────────────────────────────────────────────
    readonly property int durFast: 120
    readonly property int durNormal: 180
    readonly property int durSlow: 240
}
