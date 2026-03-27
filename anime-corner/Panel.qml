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
  readonly property var geometryPlaceholder: panelContainer
  readonly property string _panelPosition: pluginApi?.pluginSettings?.panelPosition || pluginApi?.manifest?.metadata?.defaultSettings?.panelPosition || "left"
  readonly property bool _detached: pluginApi?.pluginSettings?.panelDetached ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelDetached ?? true
  readonly property string _attachmentStyle: pluginApi?.pluginSettings?.attachmentStyle || pluginApi?.manifest?.metadata?.defaultSettings?.attachmentStyle || "connected"
  readonly property bool _isFloatingAttached: !_detached && _attachmentStyle === "floating"
  readonly property bool allowAttach: !_detached
  readonly property bool panelAnchorRight: !_detached ? _panelPosition === "right" : (_panelPosition === "right")
  readonly property bool panelAnchorLeft: !_detached ? _panelPosition === "left" : (_panelPosition === "left")
  readonly property bool panelAnchorHorizontalCenter: (_detached && _panelPosition === "center") || (_isFloatingAttached && (_panelPosition === "top" || _panelPosition === "bottom"))
  readonly property bool panelAnchorVerticalCenter: _detached || (_isFloatingAttached && (_panelPosition === "left" || _panelPosition === "right"))
  readonly property bool panelAnchorTop: !_detached && _panelPosition === "top"
  readonly property bool panelAnchorBottom: !_detached && _panelPosition === "bottom"

  property int currentTab: mainInstance?.activeTab ?? 0
  property int panelWidth: pluginApi?.pluginSettings?.panelWidth ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelWidth ?? 920
  property real panelHeightRatio: pluginApi?.pluginSettings?.panelHeightRatio ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelHeightRatio ?? 0.85
  property real uiScale: pluginApi?.pluginSettings?.scale ?? pluginApi?.manifest?.metadata?.defaultSettings?.scale ?? 1
  property real contentPreferredWidth: panelWidth + ((currentTab === 0 && booruViewRef && booruViewRef.attachedPreviewVisible) ? booruViewRef.attachedPreviewExtraWidth : 0)
  property real contentPreferredHeight: screen ? (screen.height * panelHeightRatio) : 720 * Style.uiScaleRatio

  anchors.fill: parent

  onCurrentTabChanged: {
    if (tabBar && tabBar.currentIndex !== currentTab)
      tabBar.currentIndex = currentTab;
    if (mainInstance) {
      mainInstance.activeTab = currentTab;
      if (mainInstance.saveState)
        mainInstance.saveState();
    }
  }

  onVisibleChanged: {
    if (!visible)
      return;
    Qt.callLater(function() {
      if (currentTab === 0 && booruViewRef && booruViewRef.focusInput)
        booruViewRef.focusInput();
      else if (currentTab === 1 && animeThemesViewRef && animeThemesViewRef.focusInput)
        animeThemesViewRef.focusInput();
    });
  }

  Component.onCompleted: Logger.i("AnimeCorner", "Panel initialized")

  Rectangle {
    id: panelContainer
    width: root.contentPreferredWidth
    height: root.contentPreferredHeight
    color: "transparent"
    anchors.horizontalCenter: (_detached && _panelPosition === "center" && parent) ? parent.horizontalCenter : undefined
    anchors.verticalCenter: (_detached && _panelPosition === "center" && parent) ? parent.verticalCenter : undefined
    y: (_detached && (_panelPosition === "left" || _panelPosition === "right")) ? (root.height - root.contentPreferredHeight) / 2 : 0

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
                text: currentTab === 0 ? "Art boards" : "Anime"
                color: Color.mOnSurfaceVariant
                pointSize: Style.fontSizeS
              }
            }
          }
        }
      }

      TabBar {
        id: tabBar
        Layout.fillWidth: true
        currentIndex: root.currentTab
        onCurrentIndexChanged: root.currentTab = currentIndex

        TabButton { text: "Boards" }
        TabButton { text: "Anime" }
      }

      StackLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        currentIndex: root.currentTab

        Item {
          BooruView {
            id: booruViewRef
            anchors.fill: parent
            pluginApi: root.pluginApi
            mainInstance: root.mainInstance
          }
        }

        Item {
          AnimeThemesView {
            id: animeThemesViewRef
            anchors.fill: parent
            pluginApi: root.pluginApi
            mainInstance: root.mainInstance
          }
        }
      }
    }
  }
}
