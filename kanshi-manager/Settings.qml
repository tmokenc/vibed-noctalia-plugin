import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
    id: root

    property var pluginApi: null

    spacing: Style.marginM

    NText {
        text: "Commands"
        font.weight: Font.Bold
        color: Color.mOnSurface
    }

    NTextInput {
        id: pythonInput
        Layout.fillWidth: true
        label: "Python command"
        text: pluginApi?.pluginSettings?.pythonCommand || "python3"
    }

    NTextInput {
        id: niriInput
        Layout.fillWidth: true
        label: "Niri command"
        text: pluginApi?.pluginSettings?.niriCommand || "niri"
    }

    NTextInput {
        id: kanshictlInput
        Layout.fillWidth: true
        label: "kanshictl command"
        text: pluginApi?.pluginSettings?.kanshictlCommand || "kanshictl"
    }

    NText {
        text: "Behavior"
        font.weight: Font.Bold
        color: Color.mOnSurface
    }

    CheckBox {
        id: autoReloadCheckbox
        text: "Reload kanshi once on shell startup"
        checked: pluginApi?.pluginSettings?.autoReloadOnStartup ?? true
    }

    NTextInput {
        id: barPollMsInput
        Layout.fillWidth: true
        label: "Bar refresh interval (ms)"
        text: String(pluginApi?.pluginSettings?.barPollMs || 8000)
    }

    NText {
        text: "The bar title refreshes using this interval so it can show the current profile name."
        color: Color.mOnSurfaceVariant
        wrapMode: Text.Wrap
    }

    NText {
        text: "Optional"
        font.weight: Font.Bold
        color: Color.mOnSurface
    }

    NTextInput {
        id: configPathInput
        Layout.fillWidth: true
        label: "Custom kanshi config path"
        text: pluginApi?.pluginSettings?.configPath || ""
    }

    NTextInput {
        id: panelWidthInput
        Layout.fillWidth: true
        label: "Panel width"
        text: String(pluginApi?.pluginSettings?.panelWidth || 1180)
    }

    NTextInput {
        id: panelHeightInput
        Layout.fillWidth: true
        label: "Panel height"
        text: String(pluginApi?.pluginSettings?.panelHeight || 720)
    }

    NText {
        text: "Leave the config path empty to use ~/.config/kanshi/config."
        color: Color.mOnSurfaceVariant
        wrapMode: Text.Wrap
    }

    function saveSettings() {
        pluginApi.pluginSettings.pythonCommand = (pythonInput.text || "python3").trim() || "python3"
        pluginApi.pluginSettings.niriCommand = (niriInput.text || "niri").trim() || "niri"
        pluginApi.pluginSettings.kanshictlCommand = (kanshictlInput.text || "kanshictl").trim() || "kanshictl"
        pluginApi.pluginSettings.configPath = (configPathInput.text || "").trim()
        pluginApi.pluginSettings.autoReloadOnStartup = autoReloadCheckbox.checked

        var parsedWidth = parseInt(panelWidthInput.text || "1180")
        var parsedHeight = parseInt(panelHeightInput.text || "720")
        var parsedPoll = parseInt(barPollMsInput.text || "8000")

        pluginApi.pluginSettings.panelWidth = Number.isNaN(parsedWidth) ? 1180 : parsedWidth
        pluginApi.pluginSettings.panelHeight = Number.isNaN(parsedHeight) ? 720 : parsedHeight
        pluginApi.pluginSettings.barPollMs = Number.isNaN(parsedPoll) ? 8000 : Math.max(1000, parsedPoll)

        pluginApi.saveSettings()
    }
}
