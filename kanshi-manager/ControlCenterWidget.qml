import QtQuick
import Quickshell
import qs.Widgets

NIconButtonHot {
    property ShellScreen screen
    property var pluginApi: null

    icon: "device-desktop"
    tooltipText: "Kanshi Manager"

    onClicked: {
        if (pluginApi) {
            pluginApi.togglePanel(screen, this)
        }
    }
}
