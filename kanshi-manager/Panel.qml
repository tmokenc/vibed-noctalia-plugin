import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
    id: root

    property var pluginApi: null

    readonly property var geometryPlaceholder: panelContainer
    readonly property bool allowAttach: true

    property real contentPreferredWidth: (pluginApi?.pluginSettings?.panelWidth || 1180) * Style.uiScaleRatio
    property real contentPreferredHeight: (pluginApi?.pluginSettings?.panelHeight || 720) * Style.uiScaleRatio

    property var stateData: ({
        "config_path": "",
        "profiles": [],
        "monitors": [],
        "current_profile_body": "",
        "kanshi_status": "",
        "active_profile_name": "",
        "monitor_count": 0,
        "enabled_monitor_count": 0,
        "errors": []
    })

    property bool loading: false
    property bool actionBusy: false
    property bool editorOpen: false
    property string editorMode: "create"
    property string selectedProfileId: ""
    property string selectionHintName: ""
    property string pendingActionKind: ""

    anchors.fill: parent

    function helperPath() {
        return pluginApi ? pluginApi.pluginDir + "/helpers/kanshi_manager.py" : ""
    }

    function processEnv(extra) {
        var env = ({
            "KMAN_CONFIG_PATH": pluginApi?.pluginSettings?.configPath || "",
            "KMAN_NIRI": pluginApi?.pluginSettings?.niriCommand || "niri",
            "KMAN_KANSHICTL": pluginApi?.pluginSettings?.kanshictlCommand || "kanshictl"
        })

        if (extra) {
            for (var key in extra) {
                env[key] = extra[key]
            }
        }

        return env
    }

    function pythonCommand() {
        return pluginApi?.pluginSettings?.pythonCommand || "python3"
    }

    function refreshState() {
        if (!pluginApi || loading) {
            return
        }

        loading = true
        stateProcess.exec({
            command: [pythonCommand(), helperPath(), "state"],
            environment: processEnv()
        })
    }

    function profileById(id) {
        var profiles = stateData?.profiles || []
        for (var i = 0; i < profiles.length; ++i) {
            if (profiles[i].id === id) {
                return profiles[i]
            }
        }
        return null
    }

    function selectedProfile() {
        return profileById(selectedProfileId)
    }

    function applySelection(profile) {
        if (!profile) {
            selectedProfileId = ""
            selectionHintName = ""
            return
        }

        selectedProfileId = profile.id || ""
        selectionHintName = profile.name || ""
    }

    function syncSelection() {
        var profiles = stateData?.profiles || []
        if (!profiles.length) {
            applySelection(null)
            return
        }

        var preferred = profileById(selectedProfileId)
        if (preferred) {
            applySelection(preferred)
            return
        }

        if (selectionHintName) {
            for (var i = 0; i < profiles.length; ++i) {
                if ((profiles[i].name || "") === selectionHintName) {
                    applySelection(profiles[i])
                    return
                }
            }
        }

        if (stateData?.active_profile_name) {
            for (var j = 0; j < profiles.length; ++j) {
                if ((profiles[j].name || "") === stateData.active_profile_name) {
                    applySelection(profiles[j])
                    return
                }
            }
        }

        applySelection(profiles[0])
    }

    function handleStatePayload(rawText) {
        try {
            var parsed = JSON.parse(rawText || "{}")
            stateData = parsed
            syncSelection()
            var errs = parsed.errors || []
            if (errs.length) {
                ToastService.showError(errs[0])
            }
        } catch (error) {
            ToastService.showError("Failed to parse plugin state")
        }
    }

    function runAction(args, extraEnv, successFallback, kind) {
        if (!pluginApi || actionBusy) {
            return
        }

        pendingActionKind = kind || ""
        actionBusy = true
        actionProcess.successFallback = successFallback || "Done"
        actionProcess.exec({
            command: [pythonCommand(), helperPath()].concat(args),
            environment: processEnv(extraEnv)
        })
    }

    function closeEditor() {
        editorOpen = false
    }

    function openEditorForProfile(profile) {
        if (!profile) {
            ToastService.showError("Select a profile first")
            return
        }

        applySelection(profile)
        editorMode = "edit"
        editorOpen = true
        nameInput.text = profile.name || ""
        bodyEditor.text = profile.body || ""
    }

    function createEmptyProfile() {
        editorMode = "create"
        editorOpen = true
        nameInput.text = ""
        bodyEditor.text = "    # output eDP-1 enable scale 2\n"
    }

    function createProfileFromCurrent() {
        editorMode = "create"
        editorOpen = true
        nameInput.text = ""
        bodyEditor.text = stateData?.current_profile_body || ""
    }

    function saveCurrentProfile() {
        var trimmedName = (nameInput.text || "").trim()
        if (trimmedName === "") {
            ToastService.showError("Profile name is required")
            return
        }

        if (!/^[A-Za-z0-9._-]+$/.test(trimmedName)) {
            ToastService.showError("Use letters, numbers, dot, underscore, or dash in the profile name")
            return
        }

        selectionHintName = trimmedName
        runAction(
            ["save-profile", editorMode === "edit" ? (selectedProfileId || "") : "", trimmedName],
            ({"KMAN_BODY": bodyEditor.text || ""}),
            "Profile saved",
            "save"
        )
    }

    function deleteCurrentProfile() {
        if (!selectedProfileId) {
            ToastService.showError("Select a saved profile first")
            return
        }

        selectionHintName = ""
        runAction(["delete-profile", selectedProfileId], null, "Profile deleted", "delete")
    }

    function switchCurrentProfile() {
        var profile = selectedProfile()
        if (!profile || !(profile.name || "")) {
            ToastService.showError("Select a named profile to switch")
            return
        }

        selectionHintName = profile.name || ""
        runAction(["switch-profile", profile.name], null, "Profile switched", "switch")
    }

    function enabledMonitorsCount() {
        var monitors = stateData?.monitors || []
        var count = 0
        for (var i = 0; i < monitors.length; ++i) {
            if (monitors[i].enabled) {
                count += 1
            }
        }
        return count
    }

    function hasLayoutGeometry(monitor) {
        return !!monitor
            && monitor.enabled
            && monitor.logical_x !== null
            && monitor.logical_y !== null
            && monitor.logical_width !== null
            && monitor.logical_height !== null
            && monitor.logical_width > 0
            && monitor.logical_height > 0
    }

    function layoutMinX() {
        var monitors = stateData?.monitors || []
        var found = false
        var value = 0
        for (var i = 0; i < monitors.length; ++i) {
            if (hasLayoutGeometry(monitors[i])) {
                var current = Number(monitors[i].logical_x)
                if (!found || current < value) {
                    value = current
                    found = true
                }
            }
        }
        return found ? value : 0
    }

    function layoutMinY() {
        var monitors = stateData?.monitors || []
        var found = false
        var value = 0
        for (var i = 0; i < monitors.length; ++i) {
            if (hasLayoutGeometry(monitors[i])) {
                var current = Number(monitors[i].logical_y)
                if (!found || current < value) {
                    value = current
                    found = true
                }
            }
        }
        return found ? value : 0
    }

    function layoutMaxX() {
        var monitors = stateData?.monitors || []
        var found = false
        var value = 1
        for (var i = 0; i < monitors.length; ++i) {
            if (hasLayoutGeometry(monitors[i])) {
                var current = Number(monitors[i].logical_x) + Number(monitors[i].logical_width)
                if (!found || current > value) {
                    value = current
                    found = true
                }
            }
        }
        return found ? value : 1
    }

    function layoutMaxY() {
        var monitors = stateData?.monitors || []
        var found = false
        var value = 1
        for (var i = 0; i < monitors.length; ++i) {
            if (hasLayoutGeometry(monitors[i])) {
                var current = Number(monitors[i].logical_y) + Number(monitors[i].logical_height)
                if (!found || current > value) {
                    value = current
                    found = true
                }
            }
        }
        return found ? value : 1
    }

    function scenePad() {
        return 18 * Style.uiScaleRatio
    }

    function sceneInnerWidth(sceneWidth) {
        return Math.max(1, sceneWidth - scenePad() * 2)
    }

    function sceneInnerHeight(sceneHeight) {
        return Math.max(1, sceneHeight - scenePad() * 2)
    }

    function sceneScale(sceneWidth, sceneHeight) {
        var spanX = Math.max(1, layoutMaxX() - layoutMinX())
        var spanY = Math.max(1, layoutMaxY() - layoutMinY())
        return Math.min(sceneInnerWidth(sceneWidth) / spanX, sceneInnerHeight(sceneHeight) / spanY)
    }

    function mapXFor(monitor, sceneWidth, sceneHeight) {
        return scenePad() + (Number(monitor.logical_x) - layoutMinX()) * sceneScale(sceneWidth, sceneHeight)
    }

    function mapYFor(monitor, sceneWidth, sceneHeight) {
        return scenePad() + (Number(monitor.logical_y) - layoutMinY()) * sceneScale(sceneWidth, sceneHeight)
    }

    function mapWFor(monitor, sceneWidth, sceneHeight) {
        return Math.max(84 * Style.uiScaleRatio, Number(monitor.logical_width) * sceneScale(sceneWidth, sceneHeight))
    }

    function mapHFor(monitor, sceneWidth, sceneHeight) {
        return Math.max(54 * Style.uiScaleRatio, Number(monitor.logical_height) * sceneScale(sceneWidth, sceneHeight))
    }

    Component.onCompleted: refreshState()

    Rectangle {
        id: panelContainer
        anchors.fill: parent
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            color: Color.mSurface
            radius: Style.radiusL
            border.color: Style.capsuleBorderColor
            border.width: Style.capsuleBorderWidth

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Style.marginL
                spacing: Style.marginL

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginM

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Style.marginXS

                        NText {
                            text: "Kanshi Manager"
                            pointSize: Style.fontSizeL
                            font.weight: Font.Bold
                            color: Color.mOnSurface
                        }

                        NText {
                            text: stateData?.config_path ? ("Config: " + stateData.config_path) : "Config path unavailable"
                            color: Color.mOnSurfaceVariant
                        }
                    }

                    Rectangle {
                        radius: Style.radiusM
                        color: Color.mSurfaceVariant
                        border.color: Style.capsuleBorderColor
                        border.width: 1
                        implicitWidth: activeProfileChip.implicitWidth + Style.marginM * 2
                        implicitHeight: activeProfileChip.implicitHeight + Style.marginS * 2

                        NText {
                            id: activeProfileChip
                            anchors.centerIn: parent
                            text: "Active: " + (stateData?.active_profile_name || "Unknown")
                            color: stateData?.active_profile_name ? Color.mPrimary : Color.mOnSurfaceVariant
                            font.weight: Font.Medium
                        }
                    }

                    Rectangle {
                        radius: Style.radiusM
                        color: Color.mSurfaceVariant
                        border.color: Style.capsuleBorderColor
                        border.width: 1
                        implicitWidth: outputsChip.implicitWidth + Style.marginM * 2
                        implicitHeight: outputsChip.implicitHeight + Style.marginS * 2

                        NText {
                            id: outputsChip
                            anchors.centerIn: parent
                            text: enabledMonitorsCount() + "/" + ((stateData?.monitors || []).length) + " outputs on"
                            color: Color.mOnSurface
                        }
                    }

                    NButton {
                        text: loading ? "Refreshing…" : "Refresh"
                        enabled: !loading && !actionBusy
                        onClicked: refreshState()
                    }

                    NButton {
                        text: actionBusy ? "Running…" : "Reload"
                        enabled: !actionBusy
                        onClicked: runAction(["reload"], null, "kanshi reloaded", "reload")
                    }

                    NButton {
                        text: "New"
                        enabled: !actionBusy
                        onClicked: createEmptyProfile()
                    }

                    NButton {
                        text: "From current"
                        enabled: !actionBusy
                        onClicked: createProfileFromCurrent()
                    }

                    NButton {
                        text: "Close"
                        onClicked: pluginApi.closePanel(pluginApi.panelOpenScreen)
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: Style.marginL

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: Style.marginL

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 315 * Style.uiScaleRatio
                            radius: Style.radiusL
                            color: Color.mSurfaceVariant

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Style.marginM
                                spacing: Style.marginM

                                RowLayout {
                                    Layout.fillWidth: true

                                    NText {
                                        text: "Current layout"
                                        font.weight: Font.Bold
                                        color: Color.mOnSurface
                                    }

                                    Item { Layout.fillWidth: true }

                                    NText {
                                        text: "Scaled from Niri logical coordinates"
                                        color: Color.mOnSurfaceVariant
                                    }
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Style.radiusM
                                    color: Color.mSurface
                                    border.color: Style.capsuleBorderColor
                                    border.width: 1

                                    Item {
                                        id: layoutScene
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        clip: true

                                        Repeater {
                                            model: stateData?.monitors || []

                                            delegate: Rectangle {
                                                required property var modelData

                                                visible: root.hasLayoutGeometry(modelData)
                                                x: root.mapXFor(modelData, layoutScene.width, layoutScene.height)
                                                y: root.mapYFor(modelData, layoutScene.width, layoutScene.height)
                                                width: root.mapWFor(modelData, layoutScene.width, layoutScene.height)
                                                height: root.mapHFor(modelData, layoutScene.width, layoutScene.height)
                                                radius: Style.radiusM
                                                color: Color.mSurfaceVariant
                                                border.color: Style.capsuleBorderColor
                                                border.width: 1

                                                Rectangle {
                                                    anchors.left: parent.left
                                                    anchors.top: parent.top
                                                    anchors.bottom: parent.bottom
                                                    width: 4 * Style.uiScaleRatio
                                                    radius: Style.radiusM
                                                    color: Color.mPrimary
                                                }

                                                ColumnLayout {
                                                    anchors.fill: parent
                                                    anchors.margins: Style.marginM
                                                    spacing: Style.marginXS

                                                    NText {
                                                        text: modelData.name || "Output"
                                                        color: Color.mOnSurface
                                                        font.weight: Font.Bold
                                                    }

                                                    NText {
                                                        text: modelData.current_mode || modelData.preferred_mode || "enabled"
                                                        color: Color.mOnSurfaceVariant
                                                    }

                                                    NText {
                                                        text: modelData.scale ? ("Scale " + modelData.scale) : ""
                                                        visible: text !== ""
                                                        color: Color.mOnSurfaceVariant
                                                    }
                                                }
                                            }
                                        }

                                        NText {
                                            anchors.centerIn: parent
                                            visible: enabledMonitorsCount() === 0
                                            text: "No enabled outputs with layout data"
                                            color: Color.mOnSurfaceVariant
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            radius: Style.radiusL
                            color: Color.mSurfaceVariant

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Style.marginM
                                spacing: Style.marginM

                                RowLayout {
                                    Layout.fillWidth: true

                                    NText {
                                        text: "Available monitors"
                                        font.weight: Font.Bold
                                        color: Color.mOnSurface
                                    }

                                    Item { Layout.fillWidth: true }

                                    NText {
                                        text: "Toggle outputs directly"
                                        color: Color.mOnSurfaceVariant
                                    }
                                }

                                ScrollView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true

                                    Column {
                                        width: parent.width
                                        spacing: Style.marginS

                                        Repeater {
                                            model: stateData?.monitors || []

                                            delegate: Rectangle {
                                                required property var modelData

                                                width: parent.width
                                                height: monitorColumn.implicitHeight + Style.marginM * 2
                                                radius: Style.radiusM
                                                color: Color.mSurface
                                                border.color: Style.capsuleBorderColor
                                                border.width: 1

                                                ColumnLayout {
                                                    id: monitorColumn
                                                    anchors.fill: parent
                                                    anchors.margins: Style.marginM
                                                    spacing: Style.marginXS

                                                    RowLayout {
                                                        Layout.fillWidth: true
                                                        spacing: Style.marginS

                                                        NText {
                                                            text: modelData.name
                                                            font.weight: Font.Bold
                                                            color: Color.mOnSurface
                                                        }

                                                        Rectangle {
                                                            radius: Style.radiusS
                                                            color: Color.mSurfaceVariant
                                                            border.color: Style.capsuleBorderColor
                                                            border.width: 1
                                                            implicitWidth: monitorStateText.implicitWidth + Style.marginS * 2
                                                            implicitHeight: monitorStateText.implicitHeight + Style.marginXS * 2

                                                            NText {
                                                                id: monitorStateText
                                                                anchors.centerIn: parent
                                                                text: modelData.enabled ? "On" : "Off"
                                                                color: modelData.enabled ? Color.mPrimary : Color.mOnSurfaceVariant
                                                            }
                                                        }

                                                        Item { Layout.fillWidth: true }

                                                        NButton {
                                                            text: modelData.enabled ? "Turn off" : "Turn on"
                                                            enabled: !actionBusy
                                                            onClicked: runAction([
                                                                modelData.enabled ? "monitor-off" : "monitor-on",
                                                                modelData.name
                                                            ], null, modelData.enabled ? "Output disabled" : "Output enabled", "monitor")
                                                        }
                                                    }

                                                    NText {
                                                        text: modelData.summary || ""
                                                        color: Color.mOnSurfaceVariant
                                                    }

                                                    NText {
                                                        text: modelData.details || ""
                                                        visible: text !== ""
                                                        color: Color.mOnSurfaceVariant
                                                        wrapMode: Text.Wrap
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        Layout.preferredWidth: 340 * Style.uiScaleRatio
                        Layout.fillHeight: true
                        radius: Style.radiusL
                        color: Color.mSurfaceVariant

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Style.marginM
                            spacing: Style.marginM

                            RowLayout {
                                Layout.fillWidth: true

                                NText {
                                    text: "Profiles"
                                    font.weight: Font.Bold
                                    color: Color.mOnSurface
                                }

                                Item { Layout.fillWidth: true }

                                NText {
                                    text: ((stateData?.profiles || []).length) + " total"
                                    color: Color.mOnSurfaceVariant
                                }
                            }

                            NText {
                                text: selectedProfile() ? (selectedProfile().display_name || selectedProfile().name || "Unnamed profile") : "No profile selected"
                                color: Color.mPrimary
                                font.weight: Font.Medium
                            }

                            ScrollView {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                clip: true

                                Column {
                                    width: parent.width
                                    spacing: Style.marginS

                                    Repeater {
                                        model: stateData?.profiles || []

                                        delegate: Rectangle {
                                            required property var modelData

                                            width: parent.width
                                            height: profileColumn.implicitHeight + Style.marginM * 2
                                            radius: Style.radiusM
                                            color: Color.mSurface
                                            border.color: root.selectedProfileId === modelData.id ? Color.mPrimary : Style.capsuleBorderColor
                                            border.width: 1

                                            Rectangle {
                                                anchors.left: parent.left
                                                anchors.top: parent.top
                                                anchors.bottom: parent.bottom
                                                width: root.selectedProfileId === modelData.id ? 4 * Style.uiScaleRatio : 0
                                                radius: Style.radiusM
                                                color: Color.mPrimary
                                            }

                                            ColumnLayout {
                                                id: profileColumn
                                                anchors.fill: parent
                                                anchors.margins: Style.marginM
                                                spacing: Style.marginXS

                                                RowLayout {
                                                    Layout.fillWidth: true
                                                    spacing: Style.marginS

                                                    NText {
                                                        text: modelData.display_name || modelData.name || "Unnamed profile"
                                                        color: Color.mOnSurface
                                                        font.weight: Font.Bold
                                                    }

                                                    Item { Layout.fillWidth: true }

                                                    Rectangle {
                                                        visible: !!modelData.name && (modelData.name === (stateData?.active_profile_name || ""))
                                                        radius: Style.radiusS
                                                        color: Color.mSurfaceVariant
                                                        border.color: Style.capsuleBorderColor
                                                        border.width: 1
                                                        implicitWidth: activeTagText.implicitWidth + Style.marginS * 2
                                                        implicitHeight: activeTagText.implicitHeight + Style.marginXS * 2

                                                        NText {
                                                            id: activeTagText
                                                            anchors.centerIn: parent
                                                            text: "Active"
                                                            color: Color.mPrimary
                                                        }
                                                    }
                                                }

                                                NText {
                                                    text: modelData.switchable ? "Named profile" : "Unnamed, edit only"
                                                    color: Color.mOnSurfaceVariant
                                                }
                                            }

                                            MouseArea {
                                                anchors.fill: parent
                                                onClicked: root.applySelection(modelData)
                                                onDoubleClicked: root.openEditorForProfile(modelData)
                                            }
                                        }
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: Style.marginS

                                NButton {
                                    Layout.fillWidth: true
                                    text: "Edit selected"
                                    enabled: !!selectedProfile() && !actionBusy
                                    onClicked: openEditorForProfile(selectedProfile())
                                }

                                NButton {
                                    Layout.fillWidth: true
                                    text: "Switch selected"
                                    enabled: !!selectedProfile() && !!((selectedProfile() && selectedProfile().name) || "") && !actionBusy
                                    onClicked: switchCurrentProfile()
                                }

                                NButton {
                                    Layout.fillWidth: true
                                    text: "Delete selected"
                                    enabled: !!selectedProfile() && !actionBusy
                                    onClicked: deleteCurrentProfile()
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        visible: editorOpen
        color: "#66000000"
        z: 10

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeEditor()
        }

        Rectangle {
            width: Math.min(root.width - Style.marginL * 4, 760 * Style.uiScaleRatio)
            height: Math.min(root.height - Style.marginL * 4, 560 * Style.uiScaleRatio)
            anchors.centerIn: parent
            radius: Style.radiusL
            color: Color.mSurface
            border.color: Style.capsuleBorderColor
            border.width: Style.capsuleBorderWidth

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Style.marginL
                spacing: Style.marginM

                RowLayout {
                    Layout.fillWidth: true

                    NText {
                        text: editorMode === "edit" ? "Edit profile" : "Create profile"
                        pointSize: Style.fontSizeL
                        font.weight: Font.Bold
                        color: Color.mOnSurface
                    }

                    Item { Layout.fillWidth: true }

                    NButton {
                        text: "Close"
                        onClicked: closeEditor()
                    }
                }

                NTextInput {
                    id: nameInput
                    Layout.fillWidth: true
                    label: "Profile name"
                    text: ""
                }

                NText {
                    text: "Profile body"
                    color: Color.mOnSurface
                }

                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Style.radiusM
                    color: Color.mSurfaceVariant
                    border.color: Style.capsuleBorderColor
                    border.width: 1

                    ScrollView {
                        anchors.fill: parent
                        anchors.margins: 1
                        clip: true

                        TextArea {
                            id: bodyEditor
                            text: ""
                            wrapMode: TextEdit.NoWrap
                            selectByMouse: true
                            color: Color.mOnSurface
                            selectionColor: Color.mPrimary
                            selectedTextColor: Color.mOnSurface
                            font.family: "monospace"
                            background: Rectangle {
                                color: "transparent"
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Style.marginM

                    NButton {
                        text: actionBusy ? "Working…" : "Save"
                        enabled: !actionBusy
                        onClicked: saveCurrentProfile()
                    }

                    NButton {
                        text: "Delete"
                        enabled: !actionBusy && editorMode === "edit" && !!selectedProfileId
                        onClicked: deleteCurrentProfile()
                    }

                    Item { Layout.fillWidth: true }

                    NText {
                        text: "Double-click a profile to edit quickly"
                        color: Color.mOnSurfaceVariant
                    }
                }
            }
        }
    }

    Process {
        id: stateProcess

        stdout: StdioCollector {
            id: stateStdout
            onStreamFinished: root.handleStatePayload(text)
        }

        stderr: StdioCollector {
            id: stateStderr
        }

        onExited: {
            root.loading = false
            if (exitCode !== 0) {
                ToastService.showError(stateStderr.text || "Failed to refresh state")
            }
        }
    }

    Process {
        id: actionProcess

        property string successFallback: "Done"

        stdout: StdioCollector {
            id: actionStdout
        }

        stderr: StdioCollector {
            id: actionStderr
        }

        onExited: {
            root.actionBusy = false

            var message = successFallback
            var ok = exitCode === 0

            try {
                var payload = JSON.parse(actionStdout.text || "{}")
                if (payload.message) {
                    message = payload.message
                }
                if (payload.ok === false) {
                    ok = false
                }
            } catch (error) {
                if (!ok && actionStderr.text) {
                    message = actionStderr.text
                }
            }

            if (ok) {
                if (root.pendingActionKind === "save" || root.pendingActionKind === "delete") {
                    root.editorOpen = false
                }
                ToastService.showNotice(message)
            } else {
                ToastService.showError(message || actionStderr.text || "Command failed")
            }

            root.pendingActionKind = ""
            root.refreshState()
        }
    }
}
