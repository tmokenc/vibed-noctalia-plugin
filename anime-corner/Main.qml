import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Services.UI

Item {
  id: root

  property var pluginApi: null

  readonly property string cacheDir: typeof Settings !== "undefined" && Settings.cacheDir ? Settings.cacheDir + "plugins/anime-corner/" : ""
  readonly property string stateCachePath: cacheDir + "state.json"

  property int activeTab: 0

  property var booruState: ({
      "provider": pluginApi?.pluginSettings?.booru?.provider || pluginApi?.manifest?.metadata?.defaultSettings?.booru?.provider || "yandere",
      "safeOnly": pluginApi?.pluginSettings?.booru?.safeOnly ?? pluginApi?.manifest?.metadata?.defaultSettings?.booru?.safeOnly ?? true,
      "randomOrder": pluginApi?.pluginSettings?.booru?.randomOrder ?? pluginApi?.manifest?.metadata?.defaultSettings?.booru?.randomOrder ?? false,
      "searchText": "",
      "pageNumber": 1,
      "lastQueryRandomOrder": false,
      "scrollContentY": 0,
      "response": null
    })

  property var animeThemesState: ({
      "searchText": "",
      "lastSubmittedSearchText": "",
      "results": [],
      "selectedAnimeId": "",
      "recentSearches": [],
      "filters": {
        "themeType": "all",
        "season": "any",
        "year": "",
        "mediaType": "any"
      },
      "statusMessage": "Search AnimeThemes for OP/ED videos",
      "playerStatusMessage": "",
      "lastPlayedThemeId": ""
    })

  signal stateCacheReady

  function ensureCacheDir() {
    if (cacheDir)
      Quickshell.execDetached(["mkdir", "-p", cacheDir]);
  }

  Component.onCompleted: {
    Logger.i("AnimeCorner", "Plugin initialized");
    ensureCacheDir();
  }

  FileView {
    id: stateCacheFile
    path: root.stateCachePath
    watchChanges: false

    onLoaded: {
      root.loadStateFromCache();
      root.stateCacheReady();
    }

    onLoadFailed: function(error) {
      if (error !== 2)
        Logger.e("AnimeCorner", "Failed to load state cache: " + error);
      root.stateCacheReady();
    }
  }

  function loadStateFromCache() {
    var content = String(stateCacheFile.text() || "").trim();
    if (content === "")
      return;

    try {
      var parsed = JSON.parse(content);
      if (parsed && typeof parsed === "object") {
        if (parsed.booruState)
          root.booruState = parsed.booruState;
        if (parsed.animeThemesState)
          root.animeThemesState = parsed.animeThemesState;
        if (parsed.activeTab !== undefined)
          root.activeTab = parseInt(parsed.activeTab, 10) || 0;
      }
    } catch (e) {
      Logger.e("AnimeCorner", "Failed to parse state cache: " + e);
    }
  }

  Timer {
    id: saveStateTimer
    interval: 500
    onTriggered: root.performSaveState()
  }

  property bool saveStateQueued: false

  function saveState() {
    saveStateQueued = true;
    saveStateTimer.restart();
  }

  function performSaveState() {
    if (!saveStateQueued || !cacheDir)
      return;
    saveStateQueued = false;

    try {
      ensureCacheDir();
      stateCacheFile.setText(JSON.stringify({
        "activeTab": root.activeTab,
        "booruState": root.booruState,
        "animeThemesState": root.animeThemesState
      }));
    } catch (e) {
      Logger.e("AnimeCorner", "Failed to save state cache: " + e);
    }
  }

  IpcHandler {
    target: "plugin:anime-corner"

    function toggle() {
      if (!pluginApi)
        return;
      pluginApi.withCurrentScreen(function(screen) {
        pluginApi.togglePanel(screen);
      });
    }

    function open() {
      if (!pluginApi)
        return;
      pluginApi.withCurrentScreen(function(screen) {
        pluginApi.openPanel(screen);
      });
    }

    function close() {
      if (!pluginApi)
        return;
      pluginApi.withCurrentScreen(function(screen) {
        pluginApi.closePanel(screen);
      });
    }
  }
}
