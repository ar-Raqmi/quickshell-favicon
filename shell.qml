// main.qml
// Entry point for the Quickshell Favicon Dock
// Initializes the Quickshell environment and loads the dock UI.

// Enable QApplication instead of QGuiApplication
//@ pragma UseQApplication

// Disable reload popup during development
//@ pragma Env QS_NO_RELOAD_POPUP=1

import QtQuick 6.6
import Quickshell 1.0

// Import project components
import "./components" as Components


ShellRoot {

    id: root

    // Main dock component
    Components.FaviconDock {
        id: faviconDock

        // Future configuration hooks
        anchors.centerIn: parent
    }

    Component.onCompleted: {
        console.log("Quickshell Favicon Dock initialized")
    }
}
