import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets

Item {
    id: root

    property var pluginApi: null
    property ShellScreen screen
    property string widgetId: ""
    property string section: ""

    property string activeProfileName: "Displays"
    property int enabledMonitorCount: 0
    property int monitorCount: 0

    readonly property string screenName: screen?.name ?? ""
    readonly property string barPosition: Settings.getBarPositionForScreen(screenName)
    readonly property bool isBarVertical: barPosition === "left" || barPosition === "right"
    readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
    readonly property real barFontSize: Style.getBarFontSizeForScreen(screenName)
    readonly property real contentWidth: layout.implicitWidth + Style.marginM * 2
    readonly property real contentHeight: capsuleHeight

    implicitWidth: contentWidth
    implicitHeight: contentHeight

    function helperPath() {
        return pluginApi ? pluginApi.pluginDir + "/helpers/kanshi_manager.py" : ""
    }

    function pythonCommand() {
        return pluginApi?.pluginSettings?.pythonCommand || "python3"
    }

    function processEnv() {
        return ({
            "KMAN_CONFIG_PATH": pluginApi?.pluginSettings?.configPath || "",
            "KMAN_NIRI": pluginApi?.pluginSettings?.niriCommand || "niri",
            "KMAN_KANSHICTL": pluginApi?.pluginSettings?.kanshictlCommand || "kanshictl"
        })
    }

    function refreshSummary() {
        if (!pluginApi) {
            return
        }

        summaryProcess.exec({
            command: [pythonCommand(), helperPath(), "summary"],
            environment: processEnv()
        })
    }

    function startupReload() {
        if (!pluginApi || !(pluginApi?.pluginSettings?.autoReloadOnStartup ?? true)) {
            return
        }

        reloadOnceProcess.exec({
            command: [pythonCommand(), helperPath(), "reload-once"],
            environment: processEnv()
        })
    }

    function compactTitle(maxChars) {
        var text = activeProfileName || "Displays"
        if (text.length <= maxChars) {
            return text
        }
        return text.slice(0, Math.max(1, maxChars - 1)) + "…"
    }

    Component.onCompleted: {
        startupReload()
        refreshSummary()
    }

    Timer {
        interval: pluginApi?.pluginSettings?.barPollMs || 8000
        running: true
        repeat: true
        onTriggered: root.refreshSummary()
    }

    Rectangle {
        id: visualCapsule
        x: Style.pixelAlignCenter(parent.width, width)
        y: Style.pixelAlignCenter(parent.height, height)
        width: root.contentWidth
        height: root.contentHeight
        color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
        radius: Style.radiusL
        border.color: Style.capsuleBorderColor
        border.width: Style.capsuleBorderWidth

        Item {
            id: layout
            anchors.centerIn: parent
            implicitWidth: rowLayout.visible ? rowLayout.implicitWidth : colLayout.implicitWidth
            implicitHeight: rowLayout.visible ? rowLayout.implicitHeight : colLayout.implicitHeight

            RowLayout {
                id: rowLayout
                visible: !root.isBarVertical
                spacing: Style.marginS

                NIcon {
                    icon: "device-desktop"
                    color: Color.mPrimary
                }

                NText {
                    text: root.activeProfileName || "Displays"
                    color: Color.mOnSurface
                    pointSize: root.barFontSize
                    font.weight: Font.Medium
                }
            }

            ColumnLayout {
                id: colLayout
                visible: root.isBarVertical
                spacing: Style.marginXS

                NIcon {
                    icon: "device-desktop"
                    color: Color.mPrimary
                }

                NText {
                    text: root.compactTitle(6)
                    color: Color.mOnSurface
                    pointSize: root.barFontSize
                    font.weight: Font.Medium
                }
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (pluginApi) {
                pluginApi.togglePanel(root.screen, root)
            }
        }
    }

    Process {
        id: summaryProcess

        stdout: StdioCollector {
            id: summaryStdout
        }

        onExited: {
            if (exitCode !== 0) {
                return
            }

            try {
                var payload = JSON.parse(summaryStdout.text || "{}")
                root.activeProfileName = payload.active_profile_name || "Displays"
                root.enabledMonitorCount = payload.enabled_monitor_count || 0
                root.monitorCount = payload.monitor_count || 0
            } catch (error) {
            }
        }
    }

    Process {
        id: reloadOnceProcess

        onExited: root.refreshSummary()
    }
}
