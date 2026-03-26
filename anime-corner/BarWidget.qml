import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
  id: root

  property var pluginApi: null
  property ShellScreen screen
  property string widgetId: ""
  property string section: ""

  readonly property real uiScale: pluginApi?.pluginSettings?.scale ?? pluginApi?.manifest?.metadata?.defaultSettings?.scale ?? 1
  readonly property string screenName: screen ? screen.name : ""
  readonly property real capsuleHeight: Style.getCapsuleHeightForScreen(screenName)
  readonly property real contentWidth: capsuleHeight
  readonly property real contentHeight: capsuleHeight

  implicitWidth: contentWidth
  implicitHeight: contentHeight

  Rectangle {
    anchors.centerIn: parent
    width: root.contentWidth
    height: root.contentHeight
    color: mouseArea.containsMouse ? Color.mHover : Style.capsuleColor
    radius: Style.radiusL
    border.color: Style.capsuleBorderColor
    border.width: Style.capsuleBorderWidth

    NIcon {
      anchors.centerIn: parent
      icon: "image"
      color: Color.mOnSurface
      applyUiScale: false
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    onEntered: TooltipService.show(root, "Anime Corner\nAnime art, wallpapers & themes", BarService.getTooltipDirection())
    onExited: TooltipService.hide()

    onClicked: function(mouse) {
      if (mouse.button === Qt.LeftButton) {
        pluginApi?.openPanel(root.screen, root);
      } else if (mouse.button === Qt.RightButton) {
        PanelService.showContextMenu(contextMenu, root, screen);
      }
    }
  }

  NPopupContextMenu {
    id: contextMenu
    model: [
      { "label": "Open Anime Corner", "action": "open", "icon": "external-link" },
      { "label": "Settings", "action": "settings", "icon": "settings" }
    ]

    onTriggered: function(action) {
      contextMenu.close();
      PanelService.closeContextMenu(screen);
      if (action === "open")
        pluginApi?.openPanel(root.screen, root);
      else if (action === "settings")
        BarService.openPluginSettings(screen, pluginApi.manifest);
    }
  }

  Component.onCompleted: Logger.i("AnimeCorner", "BarWidget initialized")
}
