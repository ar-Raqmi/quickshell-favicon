import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../services" as Services

Item {
    id: root

    required property var toplevel
    required property var dockTheme

    implicitWidth: 48
    implicitHeight: 48
    Layout.fillHeight: true

    /*────────────────────────────
      Application Identification
    ────────────────────────────*/

    readonly property string className: toplevel?.appId ?? ""
    readonly property string classLower: className.toLowerCase()

    readonly property var browserIds: [
        "firefox","chrome","brave","chromium",
        "librewolf","thorium","vivaldi","edge",
        "waterfox","mullvad","tor-browser",
        "floorp","zen"
    ]

    readonly property bool isBrowser: {
        if (!classLower) return false
        for (const b of browserIds)
            if (classLower.includes(b))
                return true
        return false
    }

    /*────────────────────────────
      Favicon Handling
    ────────────────────────────*/

    readonly property string faviconPath: {
        const _ = Services.FaviconService.cacheCounter
        if (isBrowser && toplevel)
            return Services.FaviconService.getFavicon(toplevel)
        return ""
    }

    readonly property bool useFavicon: faviconPath.length > 0

    /*────────────────────────────
      Icon Resolution
    ────────────────────────────*/

    readonly property var iconSubstitutions: ({
        "code-url-handler": "visual-studio-code",
        "code": "visual-studio-code",
        "zen": "zen-browser",
        "zen-alpha": "zen-browser",
        "footclient": "foot",
        "gnome-tweaks": "org.gnome.tweaks",
        "pavucontrol-qt": "pavucontrol",
        "wps": "wps-office2019-kprometheus",
        "wpsoffice": "wps-office2019-kprometheus"
    })

    function guessIcon(appId) {

        if (!appId)
            return "application-x-executable"

        const lower = appId.toLowerCase()

        // 1. Hardcoded substitutions
        if (iconSubstitutions[appId])
            return iconSubstitutions[appId]

        if (iconSubstitutions[lower])
            return iconSubstitutions[lower]

        // 2. Desktop entry lookup
        const entry = DesktopEntries.byId(appId)
        if (entry)
            return entry.icon

        // 3. Direct icon theme lookup
        if (Quickshell.iconPath(appId, true).length > 0)
            return appId

        if (Quickshell.iconPath(lower, true).length > 0)
            return lower

        // 4. Heuristic lookup
        const heuristic = DesktopEntries.heuristicLookup(appId)
        if (heuristic)
            return heuristic.icon

        // 5. Reverse domain fallback
        const parts = appId.split(".")
        if (parts.length > 1) {
            const last = parts[parts.length - 1].toLowerCase()
            if (Quickshell.iconPath(last, true).length > 0)
                return last
        }

        return "application-x-executable"
    }

    readonly property string systemIcon: guessIcon(className)

    /*────────────────────────────
      Interaction
    ────────────────────────────*/

    property bool hovered: mouseArea.containsMouse

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        onClicked: {
            if (toplevel)
                toplevel.activate()
        }
    }

    /*────────────────────────────
      Dock Item Background
    ────────────────────────────*/

    Rectangle {
        id: itemBg

        anchors.fill: parent
        anchors.margins: 3

        radius: 12
        color: hovered ? dockTheme.itemHover : "transparent"

        scale: hovered ? 1.15 : 1.0

        Behavior on color {
            ColorAnimation { duration: 150 }
        }

        Behavior on scale {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutBack
            }
        }

        /*──────────── Icon ───────────*/

        Image {
            id: faviconImage

            anchors.centerIn: parent
            width: 28
            height: 28

            visible: useFavicon && status !== Image.Error
            source: useFavicon ? faviconPath : ""

            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            cache: false
        }

        IconImage {
            id: sysIcon

            anchors.centerIn: parent
            implicitSize: 28

            visible: !useFavicon || faviconImage.status === Image.Error

            source: Quickshell.iconPath(
                systemIcon,
                "application-x-executable"
            )
        }
    }

    /*────────────────────────────
      Active Indicator
    ────────────────────────────*/

    Rectangle {

        anchors {
            bottom: itemBg.bottom
            bottomMargin: -2
            horizontalCenter: itemBg.horizontalCenter
        }

        width: (toplevel?.activated ?? false) ? 12 : 6
        height: 3
        radius: 99

        color: (toplevel?.activated ?? false)
               ? dockTheme.dotActive
               : dockTheme.dotInactive

        Behavior on width {
            NumberAnimation {
                duration: 200
                easing.type: Easing.OutCubic
            }
        }

        Behavior on color {
            ColorAnimation { duration: 200 }
        }
    }
}
