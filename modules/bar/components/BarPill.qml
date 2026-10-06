import QtQuick
import "../../../services" as Services
import "../../common" as Common

// Satu-satunya tempat yang memutuskan "pill bar itu kelihatannya seperti apa".
// Dipakai oleh semua pill di bar (workspace, clock, sysmon, tray, volume,
// baterai, control center) supaya tidak ada lagi logika warna yang diduplikasi.
//
// Cara pakai: ganti `Rectangle { ... }` dengan `BarPill { ... }`, hapus
// color / border / Behavior on color, lalu isi `hovered`.
Item {
    id: root

    // true saat di-hover atau panel miliknya sedang terbuka
    property bool hovered: false

    // Isi pill diletakkan di atas kaca (lihat contentHolder di bawah).
    default property alias content: contentHolder.data

    // ── Turunan dari barStyle ─────────────────────────────────────────
    // Nama sengaja berawalan "pill" supaya tidak bentrok dengan properti
    // isMinimal / isIslands / dst. yang dideklarasikan di komponen pemakai.
    readonly property string pillStyle: Services.Config ? Services.Config.barStyle : "islands"
    readonly property bool pillMinimal: pillStyle === "minimal"
    readonly property bool pillIslands: pillStyle === "islands"

    // Di floating/unified pill duduk DI ATAS strip kaca (level 0: tipis,
    // tanpa highlight). Di islands pill berdiri sendiri sebagai permukaan
    // utama bar (level 2). Di minimal tidak ada permukaan sama sekali.
    readonly property int glassLevel: pillIslands ? 2 : 0
    readonly property bool showSurface: !pillMinimal

    // Radius lama dipertahankan (14 / 10 / 6), bisa di-override pemakai.
    property real radius: pillMinimal ? 6 : (pillIslands ? 14 : 10)

    implicitHeight: pillMinimal ? 24 : 28

    Common.GlassSurface {
        anchors.fill: parent
        visible: root.showSurface
        level: root.glassLevel
        radius: root.radius
        hovered: root.hovered
    }

    // Overlay hover/aktif. Sengaja transparan (bukan warna solid seperti
    // bgHover dulu), supaya blur kaca tetap kelihatan saat di-hover.
    // Tetap tampil di style minimal, sama seperti perilaku lama.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: Services.Glass.hoverFill
        opacity: root.hovered ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation { duration: Services.Glass.durNormal; easing.type: Easing.OutCubic }
        }
    }

    // Harus dideklarasikan PALING AKHIR supaya tergambar di atas kaca.
    // Mengisi seluruh pill, jadi `anchors.centerIn: parent` dan
    // `anchors.left: parent.left` di komponen pemakai berperilaku sama
    // seperti saat parent-nya masih Rectangle.
    Item {
        id: contentHolder
        anchors.fill: parent
    }
}
