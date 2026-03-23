import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
  id: root

  property var pluginApi: null
  readonly property var mainInstance: pluginApi?.mainInstance

  readonly property string panelPosition: pluginApi?.pluginSettings?.panelPosition || pluginApi?.manifest?.metadata?.defaultSettings?.panelPosition || "right"
  readonly property bool detached: pluginApi?.pluginSettings?.panelDetached ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelDetached ?? true
  readonly property string attachmentStyle: pluginApi?.pluginSettings?.attachmentStyle || pluginApi?.manifest?.metadata?.defaultSettings?.attachmentStyle || "connected"
  readonly property bool floatingAttached: !detached && attachmentStyle === "floating"

  readonly property bool allowAttach: !detached
  readonly property bool panelAnchorRight: panelPosition === "right"
  readonly property bool panelAnchorLeft: panelPosition === "left"
  readonly property bool panelAnchorHorizontalCenter: (detached && panelPosition === "center") || (floatingAttached && (panelPosition === "top" || panelPosition === "bottom"))
  readonly property bool panelAnchorVerticalCenter: detached || (floatingAttached && (panelPosition === "left" || panelPosition === "right"))
  readonly property bool panelAnchorTop: !detached && panelPosition === "top"
  readonly property bool panelAnchorBottom: !detached && panelPosition === "bottom"

  property int panelWidth: pluginApi?.pluginSettings?.panelWidth ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelWidth ?? 520
  property real panelHeightRatio: pluginApi?.pluginSettings?.panelHeightRatio ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelHeightRatio ?? 0.85
  property real contentPreferredWidth: panelWidth + ((booruViewRef && booruViewRef.attachedPreviewVisible) ? booruViewRef.attachedPreviewExtraWidth : 0)
  property real contentPreferredHeight: screen ? (screen.height * panelHeightRatio) : 620 * Style.uiScaleRatio
  property real uiScale: pluginApi?.pluginSettings?.scale ?? pluginApi?.manifest?.metadata?.defaultSettings?.scale ?? 1

  readonly property var geometryPlaceholder: panelContainer

  anchors.fill: parent

  onVisibleChanged: {
    if (!visible)
      return;
    Qt.callLater(function() {
      if (booruViewRef && booruViewRef.focusInput)
        booruViewRef.focusInput();
    });
  }

  Component.onCompleted: Logger.i("AnimeCorner", "Panel initialized")

  Rectangle {
    id: panelContainer
    width: root.contentPreferredWidth
    height: root.contentPreferredHeight
    color: "transparent"
    anchors.horizontalCenter: (root.detached && root.panelPosition === "center" && parent) ? parent.horizontalCenter : undefined
    anchors.verticalCenter: (root.detached && root.panelPosition === "center" && parent) ? parent.verticalCenter : undefined
    y: (root.detached && (root.panelPosition === "left" || root.panelPosition === "right")) ? (root.height - root.contentPreferredHeight) / 2 : 0

    Rectangle {
      anchors.fill: parent
      radius: Style.radiusM
      color: Color.mSurface
      border.color: Color.mOutline
      border.width: 1
    }

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: Style.marginM
      spacing: Style.marginM

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: (headerText.implicitHeight * root.uiScale) + Style.marginS * 2
        color: Color.mSurfaceVariant
        radius: Style.radiusM

        Item {
          anchors.fill: parent
          property real s: root.uiScale

          Item {
            width: parent.width / (parent.s || 1)
            height: parent.height / (parent.s || 1)
            scale: parent.s || 1
            anchors.centerIn: parent
            transformOrigin: Item.Center

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: Style.marginM
              anchors.rightMargin: Style.marginM

              NIcon {
                icon: "image"
                color: Color.mOnSurfaceVariant
              }

              NText {
                id: headerText
                text: "Anime Corner"
                color: Color.mOnSurface
                pointSize: Style.fontSizeM
                font.weight: Font.Medium
              }

              Item { Layout.fillWidth: true }

              NText {
                text: "Art boards"
                color: Color.mOnSurfaceVariant
                pointSize: Style.fontSizeS
              }
            }
          }
        }
      }

      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        BooruView {
          id: booruViewRef
          anchors.fill: parent
          pluginApi: root.pluginApi
          mainInstance: root.mainInstance
        }
      }
    }
  }
}
