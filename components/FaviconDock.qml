import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../services" as Services

/**
 * FaviconDock
 * Demonstrates integration with FaviconService and Hyprland to build a dynamic dock.
 */

Scope {
    id: root

    /*────────────────────────────
      Hyprland Client State
    ────────────────────────────*/

    property var clientMap: ({})
    property var monitorMap: ({})
    property var dockItems: []

    readonly property int rebuildDelay: 50

    /*────────────────────────────
      Client Refresh
    ────────────────────────────*/

    function refreshClients() {
        getClients.running = true
        getMonitors.running = true
    }

    function rebuildDockItems() {
        rebuildTimer.restart()
    }

    Timer {
        id: rebuildTimer
        interval: root.rebuildDelay
        repeat: false

        onTriggered: {
            const data = root.clientMap
            const monitors = root.monitorMap

            let toplevels = []

            try {
                toplevels = Array.from(ToplevelManager.toplevels.values)
            } catch (e) {
                console.warn("Failed to read toplevels:", e)
                return
            }

            const result = []

            for (const t of toplevels) {

                const address =
                    t?.HyprlandToplevel?.address
                    ? `0x${t.HyprlandToplevel.address}`
                    : ""

                const client = data[address]
                if (!client) continue

                result.push({
                    toplevel: t,
                    monitor: monitors[client.monitor] ?? "",
                    workspace: client.workspace ?? 0,
                    x: client.x ?? 0,
                    y: client.y ?? 0
                })
            }

            /* Sort order:
               1. workspace
               2. vertical position (top → bottom)
               3. horizontal position (left → right)
            */

            result.sort((a, b) =>
                a.workspace - b.workspace ||
                a.y - b.y ||
                a.x - b.x
            )

            root.dockItems = result
        }
    }

    Component.onCompleted: refreshClients()

    /*────────────────────────────
      Hyprland Events
    ────────────────────────────*/

    readonly property var ignoredEvents: [
        "openlayer",
        "closelayer",
        "screencast"
    ]

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (root.ignoredEvents.includes(event.name))
                return

            refreshClients()
        }
    }

    /*────────────────────────────
      Hyprctl Clients
    ────────────────────────────*/

    Process {
        id: getClients
        command: ["hyprctl", "clients", "-j"]

        stdout: StdioCollector {
            id: clientsCollector

            onStreamFinished: {
                try {
                    const clients = JSON.parse(text)
                    const map = {}

                    for (const c of clients) {
                        map[c.address] = {
                            workspace: c.workspace?.id ?? 0,
                            monitor: c.monitor ?? -1,
                            x: c.at?.[0] ?? 0,
                            y: c.at?.[1] ?? 0
                        }
                    }

                    root.clientMap = map

                } catch (e) {
                    console.warn("Failed to parse hyprctl clients:", e)
                }

                rebuildDockItems()
            }
        }
    }

    /*────────────────────────────
      Hyprctl Monitors
    ────────────────────────────*/

    Process {
        id: getMonitors
        command: ["hyprctl", "monitors", "-j"]

        stdout: StdioCollector {
            id: monitorsCollector

            onStreamFinished: {
                try {
                    const monitors = JSON.parse(text)
                    const map = {}

                    for (const m of monitors)
                        map[m.id] = m.name

                    root.monitorMap = map

                } catch (e) {
                    console.warn("Failed to parse hyprctl monitors:", e)
                }

                rebuildDockItems()
            }
        }
    }

    /*────────────────────────────
      Dock Windows (Per Screen)
    ────────────────────────────*/

    Variants {
        model: Quickshell.screens

        PanelWindow {

            id: dockWindow

            required property var modelData
            screen: modelData

            readonly property string screenName: screen?.name ?? ""

            readonly property var myItems:
                root.dockItems.filter(i => i.monitor === screenName)

            readonly property bool hasApps: myItems.length > 0

            anchors {
                bottom: true
                left: true
                right: true
            }

            WlrLayershell.namespace: "quickshell:favicon-dock"
            WlrLayershell.layer: WlrLayer.Top

            color: "transparent"

            exclusiveZone: hasApps ? 72 : 0
            implicitHeight: hasApps ? 72 : 0
            visible: hasApps

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: 200
                    easing.type: Easing.OutCubic
                }
            }

            /*────────────────────────
              Dock Theme
            ────────────────────────*/

            readonly property color bgColor: "#f8f8f8"
            readonly property color bgBorder: "#dddddd"
            readonly property color itemBg: "#ffffff"
            readonly property color itemHover: "#eeeeee"
            readonly property color textColor: "#333333"
            readonly property color accentColor: "#357abd"
            readonly property color dotActive: "#357abd"
            readonly property color dotInactive: "#bbbbbb"
            readonly property real rounding: 18

            Item {

                anchors.fill: parent

                opacity: hasApps ? 1 : 0
                visible: hasApps

                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                        easing.type: Easing.OutCubic
                    }
                }

                Rectangle {

                    id: dockBg

                    anchors {
                        bottom: parent.bottom
                        bottomMargin: 8
                        horizontalCenter: parent.horizontalCenter
                    }

                    height: 56
                    width: dockRow.implicitWidth + 20
                    radius: dockWindow.rounding

                    color: dockWindow.bgColor
                    border.width: 1
                    border.color: dockWindow.bgBorder

                    Behavior on width {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCubic
                        }
                    }

                    RowLayout {

                        id: dockRow
                        anchors.centerIn: parent
                        spacing: 4

                        Repeater {

                            model: dockWindow.myItems

                            FaviconDockItem {

                                required property var modelData

                                toplevel: modelData.toplevel
                                dockTheme: dockWindow
                            }
                        }
                    }
                }
            }
        }
    }
}
