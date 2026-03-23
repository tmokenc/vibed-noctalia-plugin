import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Widgets

ColumnLayout {
  id: root

  property var pluginApi: null

  property bool editPanelDetached: pluginApi?.pluginSettings?.panelDetached ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelDetached ?? true
  property string editPanelPosition: pluginApi?.pluginSettings?.panelPosition || pluginApi?.manifest?.metadata?.defaultSettings?.panelPosition || "right"
  property real editPanelHeightRatio: pluginApi?.pluginSettings?.panelHeightRatio ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelHeightRatio ?? 0.85
  property int editPanelWidth: pluginApi?.pluginSettings?.panelWidth ?? pluginApi?.manifest?.metadata?.defaultSettings?.panelWidth ?? 520
  property string editAttachmentStyle: pluginApi?.pluginSettings?.attachmentStyle || pluginApi?.manifest?.metadata?.defaultSettings?.attachmentStyle || "connected"
  property real editScale: pluginApi?.pluginSettings?.scale ?? pluginApi?.manifest?.metadata?.defaultSettings?.scale ?? 1

  property string editBooruProvider: pluginApi?.pluginSettings?.booru?.provider || pluginApi?.manifest?.metadata?.defaultSettings?.booru?.provider || "yandere"
  property bool editBooruSafeOnly: pluginApi?.pluginSettings?.booru?.safeOnly ?? pluginApi?.manifest?.metadata?.defaultSettings?.booru?.safeOnly ?? true
  property int editBooruPageSize: pluginApi?.pluginSettings?.booru?.pageSize ?? pluginApi?.manifest?.metadata?.defaultSettings?.booru?.pageSize ?? 20
  property bool editBooruRandomOrder: pluginApi?.pluginSettings?.booru?.randomOrder ?? pluginApi?.manifest?.metadata?.defaultSettings?.booru?.randomOrder ?? false
  property string editBooruSaveDirectory: pluginApi?.pluginSettings?.booru?.saveDirectory || pluginApi?.manifest?.metadata?.defaultSettings?.booru?.saveDirectory || ""
  property string editBooruWallpaperCommand: pluginApi?.pluginSettings?.booru?.wallpaperCommand || pluginApi?.manifest?.metadata?.defaultSettings?.booru?.wallpaperCommand || ""
  property int editBooruImagesPerRow: pluginApi?.pluginSettings?.booru?.imagesPerRow ?? pluginApi?.manifest?.metadata?.defaultSettings?.booru?.imagesPerRow ?? 2
  property int editBooruRecentSearchTagLimit: pluginApi?.pluginSettings?.booru?.recentSearchTagLimit ?? pluginApi?.manifest?.metadata?.defaultSettings?.booru?.recentSearchTagLimit ?? 20
  property int editDanbooruTagIndexRefreshDays: pluginApi?.pluginSettings?.booru?.danbooruTagIndexRefreshDays ?? pluginApi?.manifest?.metadata?.defaultSettings?.booru?.danbooruTagIndexRefreshDays ?? 7

  spacing: Style.marginM

  NText {
    text: "Anime Corner Settings"
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NToggle {
    Layout.fillWidth: true
    label: "Detached panel"
    description: "Show panel as a detached floating window"
    checked: root.editPanelDetached
    onToggled: function(checked) {
      root.editPanelDetached = checked;
      if (checked) {
        if (root.editPanelPosition === "top" || root.editPanelPosition === "bottom")
          root.editPanelPosition = "right";
      } else if (root.editPanelPosition === "center") {
        root.editPanelPosition = "right";
      }
    }
    defaultValue: true
  }

  NComboBox {
    Layout.fillWidth: true
    label: "Panel position"
    description: "Default screen edge for Anime Corner"
    model: root.editPanelDetached ? [
      { "key": "left", "name": "Left" },
      { "key": "center", "name": "Center" },
      { "key": "right", "name": "Right" }
    ] : [
      { "key": "left", "name": "Left" },
      { "key": "top", "name": "Top" },
      { "key": "bottom", "name": "Bottom" },
      { "key": "right", "name": "Right" }
    ]
    currentKey: root.editPanelPosition
    onSelected: function(key) { root.editPanelPosition = key; }
    defaultValue: "right"
  }

  NComboBox {
    Layout.fillWidth: true
    visible: !root.editPanelDetached
    label: "Attachment style"
    description: "How Anime Corner attaches to the side"
    model: [
      { "key": "connected", "name": "Connected to Bar" },
      { "key": "floating", "name": "Floating (Drawer)" }
    ]
    currentKey: root.editAttachmentStyle
    onSelected: function(key) { root.editAttachmentStyle = key; }
    defaultValue: "connected"
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NLabel { label: "Panel height ratio: " + (root.editPanelHeightRatio * 100).toFixed(0) + "%" }
    NSlider {
      Layout.fillWidth: true
      from: 0.3
      to: 1.0
      stepSize: 0.01
      value: root.editPanelHeightRatio
      onValueChanged: root.editPanelHeightRatio = value
    }

    NLabel { label: "Panel width: " + root.editPanelWidth + "px" }
    NSlider {
      Layout.fillWidth: true
      from: 320
      to: 1200
      stepSize: 1
      value: root.editPanelWidth
      onValueChanged: root.editPanelWidth = value
    }

    NLabel { label: "UI scale: " + (root.editScale * 100).toFixed(0) + "%" }
    NSlider {
      Layout.fillWidth: true
      from: 0.5
      to: 2.0
      stepSize: 0.01
      value: root.editScale
      onValueChanged: root.editScale = value
    }
  }

  NDivider {
    Layout.fillWidth: true
    Layout.topMargin: Style.marginM
    Layout.bottomMargin: Style.marginM
  }

  NText {
    text: "Boards & Library"
    pointSize: Style.fontSizeM
    font.weight: Font.Bold
    color: Color.mOnSurface
  }

  NComboBox {
    Layout.fillWidth: true
    label: "Default board"
    description: "Choose which image board Anime Corner opens with"
    model: [
      { "key": "yandere", "name": "yande.re" },
      { "key": "konachan", "name": "Konachan" },
      { "key": "danbooru", "name": "Danbooru" }
    ]
    currentKey: root.editBooruProvider
    onSelected: function(key) { root.editBooruProvider = key; }
    defaultValue: "yandere"
  }

  NToggle {
    Layout.fillWidth: true
    label: "Safe mode"
    description: "Prefer safe results where the board supports it"
    checked: root.editBooruSafeOnly
    onToggled: function(checked) { root.editBooruSafeOnly = checked; }
    defaultValue: true
  }

  NToggle {
    Layout.fillWidth: true
    label: "Shuffle results"
    description: "Ask the board for random ordering when supported"
    checked: root.editBooruRandomOrder
    onToggled: function(checked) { root.editBooruRandomOrder = checked; }
    defaultValue: false
  }

  ColumnLayout {
    Layout.fillWidth: true
    spacing: Style.marginS

    NLabel { label: "Posts per page: " + root.editBooruPageSize }
    NSlider {
      Layout.fillWidth: true
      from: 5
      to: 100
      stepSize: 1
      value: root.editBooruPageSize
      onValueChanged: root.editBooruPageSize = value
    }

    NLabel { label: "Cards per row: " + root.editBooruImagesPerRow }
    NSlider {
      Layout.fillWidth: true
      from: 1
      to: 6
      stepSize: 1
      value: root.editBooruImagesPerRow
      onValueChanged: root.editBooruImagesPerRow = value
    }

    NLabel { label: "Recent tags shown: " + root.editBooruRecentSearchTagLimit }
    NSlider {
      Layout.fillWidth: true
      from: 0
      to: 50
      stepSize: 1
      value: root.editBooruRecentSearchTagLimit
      onValueChanged: root.editBooruRecentSearchTagLimit = value
    }

    NLabel { label: "Danbooru tag cache refresh (days): " + root.editDanbooruTagIndexRefreshDays }
    NSlider {
      Layout.fillWidth: true
      from: 0
      to: 60
      stepSize: 1
      value: root.editDanbooruTagIndexRefreshDays
      onValueChanged: root.editDanbooruTagIndexRefreshDays = value
    }
  }

  NTextInput {
    Layout.fillWidth: true
    label: "Library folder"
    description: "Leave blank to use ~/Pictures/AnimeCorner"
    text: root.editBooruSaveDirectory
    placeholderText: "~/Pictures/AnimeCorner"
    onTextChanged: root.editBooruSaveDirectory = text
  }

  NTextInput {
    Layout.fillWidth: true
    label: "Wallpaper command"
    description: "Optional custom command. Use {file} for the saved image path"
    text: root.editBooruWallpaperCommand
    placeholderText: 'qs -c noctalia-shell ipc call wallpaper set {file} ""'
    onTextChanged: root.editBooruWallpaperCommand = text
  }

  function saveSettings() {
    if (!pluginApi)
      return;
    if (!pluginApi.pluginSettings.booru)
      pluginApi.pluginSettings.booru = {};

    pluginApi.pluginSettings.panelDetached = root.editPanelDetached;
    pluginApi.pluginSettings.panelPosition = root.editPanelPosition;
    pluginApi.pluginSettings.panelHeightRatio = root.editPanelHeightRatio;
    pluginApi.pluginSettings.panelWidth = root.editPanelWidth;
    pluginApi.pluginSettings.attachmentStyle = root.editAttachmentStyle;
    pluginApi.pluginSettings.scale = root.editScale;

    pluginApi.pluginSettings.booru.provider = root.editBooruProvider;
    pluginApi.pluginSettings.booru.safeOnly = root.editBooruSafeOnly;
    pluginApi.pluginSettings.booru.pageSize = root.editBooruPageSize;
    pluginApi.pluginSettings.booru.randomOrder = root.editBooruRandomOrder;
    pluginApi.pluginSettings.booru.saveDirectory = root.editBooruSaveDirectory;
    pluginApi.pluginSettings.booru.wallpaperCommand = root.editBooruWallpaperCommand;
    pluginApi.pluginSettings.booru.imagesPerRow = root.editBooruImagesPerRow;
    pluginApi.pluginSettings.booru.recentSearchTagLimit = root.editBooruRecentSearchTagLimit;
    pluginApi.pluginSettings.booru.danbooruTagIndexRefreshDays = root.editDanbooruTagIndexRefreshDays;

    pluginApi.saveSettings();
    Logger.i("AnimeCorner", "Settings saved successfully");
  }
}
