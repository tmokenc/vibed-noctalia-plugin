import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
  id: root

  property var pluginApi: null
  property var mainInstance: null

  property int pageSize: pluginApi?.pluginSettings?.animethemes?.pageSize ?? pluginApi?.manifest?.metadata?.defaultSettings?.animethemes?.pageSize ?? 12
  property int recentSearchLimit: pluginApi?.pluginSettings?.animethemes?.recentSearchLimit ?? pluginApi?.manifest?.metadata?.defaultSettings?.animethemes?.recentSearchLimit ?? 20
  property string mpvCommand: pluginApi?.pluginSettings?.animethemes?.mpvCommand || pluginApi?.manifest?.metadata?.defaultSettings?.animethemes?.mpvCommand || "mpv"

  property string searchText: ""
  property string lastSubmittedSearchText: ""
  property var animeResults: []
  property var filteredResults: []
  property string selectedAnimeId: ""
  property var recentSearches: []
  property string filterThemeType: "all"
  property string filterSeason: "any"
  property string filterYear: ""
  property string filterMediaType: "any"
  property string statusMessage: "Search AnimeThemes for OP/ED videos"
  property string playerStatusMessage: ""
  property bool busy: false
  property bool _syncingState: false
  property string lastPlayedThemeId: ""
  property string _lastExternalStateJson: ""

  readonly property string cacheDir: mainInstance?.cacheDir || (typeof Settings !== "undefined" && Settings.cacheDir ? Settings.cacheDir + "plugins/anime-corner/" : "")
  readonly property string mpvSocketPath: cacheDir ? cacheDir + "animethemes-mpv.sock" : "/tmp/anime-corner-animethemes-mpv.sock"
  property var selectedAnime: null
  readonly property var selectedAnimeThemesModel: (selectedAnime && Array.isArray(selectedAnime.animethemes)) ? selectedAnime.animethemes : []
  readonly property bool recentSearchesVisible: !!searchField && searchField.activeFocus && String(searchText || "").trim() === "" && recentSearches.length > 0
  readonly property color outlineVariantColor: (typeof Color !== "undefined" && Color.mOutlineVariant !== undefined && Color.mOutlineVariant !== null) ? Color.mOutlineVariant : (((typeof Color !== "undefined" && Color.mOutline !== undefined && Color.mOutline !== null) ? Color.mOutline : "#5f6368"))
  readonly property color surfaceVariantColor: (typeof Color !== "undefined" && Color.mSurfaceVariant !== undefined && Color.mSurfaceVariant !== null) ? Color.mSurfaceVariant : "#1f1f23"
  readonly property color surfaceColor: (typeof Color !== "undefined" && Color.mSurface !== undefined && Color.mSurface !== null) ? Color.mSurface : "#16181d"
  readonly property color secondaryContainerColor: (typeof Color !== "undefined" && Color.mSecondaryContainer !== undefined && Color.mSecondaryContainer !== null) ? Color.mSecondaryContainer : "#2a3442"
  readonly property color onSecondaryContainerColor: (typeof Color !== "undefined" && Color.mOnSecondaryContainer !== undefined && Color.mOnSecondaryContainer !== null) ? Color.mOnSecondaryContainer : "#f1f3f4"
  readonly property color onSurfaceColor: (typeof Color !== "undefined" && Color.mOnSurface !== undefined && Color.mOnSurface !== null) ? Color.mOnSurface : "#f1f3f4"
  readonly property color onSurfaceVariantColor: (typeof Color !== "undefined" && Color.mOnSurfaceVariant !== undefined && Color.mOnSurfaceVariant !== null) ? Color.mOnSurfaceVariant : "#c5c7d0"
  readonly property color primaryColor: (typeof Color !== "undefined" && Color.mPrimary !== undefined && Color.mPrimary !== null) ? Color.mPrimary : "#8ab4f8"
  readonly property color tertiaryContainerColor: (typeof Color !== "undefined" && Color.mTertiaryContainer !== undefined && Color.mTertiaryContainer !== null) ? Color.mTertiaryContainer : secondaryContainerColor
  readonly property color tertiaryColor: (typeof Color !== "undefined" && Color.mTertiary !== undefined && Color.mTertiary !== null) ? Color.mTertiary : primaryColor
  readonly property color onTertiaryContainerColor: (typeof Color !== "undefined" && Color.mOnTertiaryContainer !== undefined && Color.mOnTertiaryContainer !== null) ? Color.mOnTertiaryContainer : onSecondaryContainerColor

  function normalizeRecentSearches(items) {
    var seen = {};
    var normalized = [];
    (items || []).forEach(function(item) {
      var value = String(item || "").trim();
      if (value === "")
        return;
      var key = value.toLowerCase();
      if (seen[key])
        return;
      seen[key] = true;
      normalized.push(value);
    });
    var limit = Math.max(0, parseInt(recentSearchLimit || 0, 10) || 0);
    if (limit > 0 && normalized.length > limit)
      normalized = normalized.slice(0, limit);
    return normalized;
  }

  function recordRecentSearch(query) {
    var value = String(query || "").trim();
    if (value === "")
      return;
    recentSearches = normalizeRecentSearches([value].concat(recentSearches || []));
    syncState();
  }

  function normalizeSeason(value) {
    var text = String(value || "").trim().toLowerCase();
    if (text === "")
      return "";
    if (text === "fall" || text === "autumn")
      return "fall";
    return text;
  }

  function normalizeMediaType(value) {
    return String(value || "").trim().toLowerCase();
  }

  function findAnimeById(id, source) {
    var key = String(id || "");
    var list = source || [];
    for (var i = 0; i < list.length; ++i) {
      if (String(list[i] && list[i].id || "") === key)
        return list[i];
    }
    return null;
  }

  function animeMatchesThemeFilter(anime) {
    if (!anime)
      return false;
    if (filterThemeType === "all")
      return true;
    if (filterThemeType === "opening")
      return (anime.openingCount || 0) > 0;
    if (filterThemeType === "ending")
      return (anime.endingCount || 0) > 0;
    if (filterThemeType === "both")
      return (anime.openingCount || 0) > 0 && (anime.endingCount || 0) > 0;
    return true;
  }

  function passesFilters(anime) {
    if (!anime)
      return false;
    if (!animeMatchesThemeFilter(anime))
      return false;

    if (filterSeason !== "any") {
      var animeSeason = normalizeSeason(anime.season);
      if (animeSeason !== filterSeason)
        return false;
    }

    var yearFilter = String(filterYear || "").trim();
    if (yearFilter !== "") {
      if (String(anime.year || "") !== yearFilter)
        return false;
    }

    if (filterMediaType !== "any") {
      var animeMedia = normalizeMediaType(anime.mediaFormat);
      if (animeMedia !== filterMediaType)
        return false;
    }

    return true;
  }

  function refreshFilteredResults(autoSelectSingle) {
    var list = (animeResults || []).filter(function(anime) {
      return passesFilters(anime);
    });
    filteredResults = list;

    if (list.length === 1 && autoSelectSingle !== false) {
      selectedAnimeId = String(list[0].id || "");
    } else if (selectedAnimeId !== "" && !findAnimeById(selectedAnimeId, list)) {
      selectedAnimeId = list.length > 0 ? String(list[0].id || "") : "";
    }

    updateSelectedAnime(list);
    syncState();
  }

  function selectedAnimeThemes() {
    var anime = selectedAnime;
    if (!anime || !Array.isArray(anime.animethemes))
      return [];
    return anime.animethemes;
  }

  function themeMetaLine(theme) {
    if (!theme)
      return "";
    var parts = [];
    var firstEntry = theme.entries && theme.entries.length > 0 ? theme.entries[0] : null;
    if (firstEntry && firstEntry.episodes)
      parts.push("eps " + firstEntry.episodes);
    if (theme.bestVideoResolution)
      parts.push(theme.bestVideoResolution + "p");
    return parts.join(" • ");
  }

  function animeMetaLine(anime) {
    if (!anime)
      return "";
    var parts = [];
    if (anime.year)
      parts.push(String(anime.year));
    if (anime.season)
      parts.push(String(anime.season));
    if (anime.mediaFormat)
      parts.push(String(anime.mediaFormat));
    return parts.join(" • ");
  }

  function chooseAnime(anime) {
    if (!anime)
      return;
    selectedAnimeId = String(anime.id || "");
    updateSelectedAnime(filteredResults);
    syncState();
  }

  function updateSelectedAnime(source) {
    var list = Array.isArray(source) ? source : (filteredResults.length > 0 ? filteredResults : animeResults);
    if (selectedAnimeId === "") {
      selectedAnime = null;
      return;
    }
    selectedAnime = findAnimeById(selectedAnimeId, list);
  }

  function syncState() {
    if (_syncingState || !mainInstance)
      return;
    mainInstance.animeThemesState = {
      "searchText": searchText,
      "lastSubmittedSearchText": lastSubmittedSearchText,
      "results": animeResults,
      "selectedAnimeId": selectedAnimeId,
      "recentSearches": recentSearches,
      "filters": {
        "themeType": filterThemeType,
        "season": filterSeason,
        "year": filterYear,
        "mediaType": filterMediaType
      },
      "statusMessage": statusMessage,
      "playerStatusMessage": playerStatusMessage,
      "lastPlayedThemeId": lastPlayedThemeId
    };
    _lastExternalStateJson = JSON.stringify(mainInstance.animeThemesState || {});
    if (mainInstance.saveState)
      mainInstance.saveState();
  }

  function maybeAdoptExternalState() {
    if (!mainInstance || _syncingState)
      return;
    var serialized = JSON.stringify(mainInstance.animeThemesState || {});
    if (serialized === _lastExternalStateJson)
      return;
    _lastExternalStateJson = serialized;
    applyPersistedState(mainInstance.animeThemesState);
  }

  function applyPersistedState(state) {
    if (!state || typeof state !== "object")
      return;
    _syncingState = true;
    searchText = String(state.searchText || "");
    lastSubmittedSearchText = String(state.lastSubmittedSearchText || "");
    animeResults = Array.isArray(state.results) ? state.results : [];
    selectedAnimeId = String(state.selectedAnimeId || "");
    recentSearches = normalizeRecentSearches(state.recentSearches || []);
    var filters = state.filters || {};
    filterThemeType = String(filters.themeType || "all");
    filterSeason = String(filters.season || "any");
    filterYear = String(filters.year || "");
    filterMediaType = String(filters.mediaType || "any");
    statusMessage = String(state.statusMessage || (animeResults.length > 0 ? (animeResults.length + " anime cached") : "Search AnimeThemes for OP/ED videos"));
    playerStatusMessage = String(state.playerStatusMessage || "");
    lastPlayedThemeId = String(state.lastPlayedThemeId || "");
    _syncingState = false;
    refreshFilteredResults(true);
  }

  function search() {
    var query = String(searchText || "").trim();
    if (query === "") {
      statusMessage = "Enter an anime title to search AnimeThemes.";
      syncState();
      return;
    }
    busy = true;
    lastSubmittedSearchText = query;
    statusMessage = "Searching AnimeThemes…";
    syncState();
    animeThemesService.searchAnime(query, pageSize);
  }

  function focusInput() {
    searchField.forceActiveFocus();
  }

  function buildMpvCommand(videoUrl, title) {
    var code = [
      "import json, os, socket, subprocess, sys",
      "sock_path, url, title, mpv_bin = sys.argv[1:5]",
      "payload = (json.dumps({'command': ['loadfile', url, 'replace']}) + '\\n').encode('utf-8')",
      "sent = False",
      "if os.path.exists(sock_path):",
      "    try:",
      "        client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)",
      "        client.connect(sock_path)",
      "        client.sendall(payload)",
      "        client.close()",
      "        sent = True",
      "    except Exception:",
      "        try:",
      "            os.unlink(sock_path)",
      "        except OSError:",
      "            pass",
      "if not sent:",
      "    subprocess.Popen([mpv_bin, '--force-window=yes', '--title=' + title, '--input-ipc-server=' + sock_path, url], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)"
    ].join("\n");

    return ["python3", "-c", code, mpvSocketPath, String(videoUrl || ""), String(title || "AnimeThemes"), String(mpvCommand || "mpv")];
  }

  function openThemeInMpv(theme) {
    if (!theme || !theme.bestVideoUrl)
      return;
    playerStatusMessage = "Loading " + (theme.displayName || theme.songTitle || "theme") + " in mpv…";
    lastPlayedThemeId = String(theme.id || "");
    syncState();
    mpvProcess.command = buildMpvCommand(theme.bestVideoUrl, (selectedAnime ? selectedAnime.name + " - " : "") + (theme.displayName || theme.songTitle || "AnimeThemes"));
    mpvProcess.running = true;
  }

  function openUrl(url) {
    var target = String(url || "").trim();
    if (target === "")
      return;
    var opened = false;
    try {
      opened = Qt.openUrlExternally(target);
    } catch (e) {
      opened = false;
    }
    if (!opened) {
      browserOpenProcess.command = ["xdg-open", target];
      browserOpenProcess.running = true;
    }
  }

  function useRecentSearch(query) {
    searchText = String(query || "");
    searchField.forceActiveFocus();
    search();
  }

  onRecentSearchLimitChanged: {
    recentSearches = normalizeRecentSearches(recentSearches);
    syncState();
  }

  onAnimeResultsChanged: refreshFilteredResults(false)
  onSelectedAnimeIdChanged: updateSelectedAnime()
  onFilterThemeTypeChanged: {
    if (themeFilterCombo) {
      var idx = ["all", "opening", "ending", "both"].indexOf(filterThemeType);
      if (idx >= 0 && themeFilterCombo.currentIndex !== idx)
        themeFilterCombo.currentIndex = idx;
    }
    refreshFilteredResults(false)
  }
  onFilterSeasonChanged: {
    if (seasonFilterCombo) {
      var idx = ["any", "winter", "spring", "summer", "fall"].indexOf(filterSeason);
      if (idx >= 0 && seasonFilterCombo.currentIndex !== idx)
        seasonFilterCombo.currentIndex = idx;
    }
    refreshFilteredResults(false)
  }
  onFilterYearChanged: {
    if (yearFilterField && yearFilterField.text !== filterYear)
      yearFilterField.text = filterYear;
    refreshFilteredResults(false)
  }
  onFilterMediaTypeChanged: {
    if (mediaTypeCombo) {
      var idx = ["any", "tv", "movie", "ova", "ona", "special"].indexOf(filterMediaType);
      if (idx >= 0 && mediaTypeCombo.currentIndex !== idx)
        mediaTypeCombo.currentIndex = idx;
    }
    refreshFilteredResults(false)
  }
  onSearchTextChanged: {
    if (searchField && searchField.text !== searchText)
      searchField.text = searchText;
  }

  Component.onCompleted: root.maybeAdoptExternalState()

  Timer {
    interval: 250
    repeat: true
    running: true
    onTriggered: root.maybeAdoptExternalState()
  }

  AnimeThemesService {
    id: animeThemesService
  }

  Connections {
    target: animeThemesService

    function onSearchFinished(payload) {
      root.busy = false;
      root.animeResults = Array.isArray(payload && payload.results) ? payload.results : [];
      root.statusMessage = root.animeResults.length > 0 ? (root.animeResults.length + " anime found") : "No anime matched that search.";
      root.recordRecentSearch(payload && payload.query || root.lastSubmittedSearchText);
      root.refreshFilteredResults(true);
    }

    function onSearchFailed(message) {
      root.busy = false;
      root.statusMessage = String(message || "AnimeThemes search failed.");
      root.syncState();
    }
  }

  Process {
    id: mpvProcess

    stderr: StdioCollector {
      onStreamFinished: function(text) {
        if (String(text || "").trim() !== "")
          root.playerStatusMessage = String(text || "").trim();
      }
    }

    onExited: function(exitCode) {
      if (exitCode === 0 && root.playerStatusMessage.indexOf("failed") === -1)
        root.playerStatusMessage = "Sent to mpv";
      else if (exitCode !== 0)
        root.playerStatusMessage = "mpv command failed";
      root.syncState();
    }
  }

  Process {
    id: browserOpenProcess
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.marginM

    Rectangle {
      Layout.fillWidth: true
      implicitHeight: searchPanelContent.implicitHeight + Style.marginM * 2
      Layout.preferredHeight: implicitHeight
      color: Color.mSurfaceVariant
      radius: Style.radiusM
      border.color: Color.mOutline
      border.width: 1

      ColumnLayout {
        id: searchPanelContent
        anchors {
          left: parent.left
          right: parent.right
          top: parent.top
          margins: Style.marginM
        }
        spacing: Style.marginS

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          TextField {
            id: searchField
            Layout.fillWidth: true
            text: root.searchText
            placeholderText: "Search anime title…"
            selectByMouse: true
            onTextChanged: {
              root.searchText = text;
              root.syncState();
            }
            onAccepted: root.search()
          }

          NButton {
            text: busy ? "Searching…" : "Search"
            icon: "search"
            enabled: !busy
            onClicked: root.search()
          }

          NButton {
            text: "Clear"
            enabled: root.searchText !== "" || root.animeResults.length > 0
            onClicked: {
              root.searchText = "";
              root.lastSubmittedSearchText = "";
              root.animeResults = [];
              root.filteredResults = [];
              root.selectedAnimeId = "";
              root.statusMessage = "Search AnimeThemes for OP/ED videos";
              root.syncState();
            }
          }
        }

        Flow {
          Layout.fillWidth: true
          visible: root.recentSearchesVisible
          spacing: Style.marginXS

          Repeater {
            model: root.recentSearches
            delegate: Rectangle {
              required property var modelData
              radius: Style.radiusM
              color: root.secondaryContainerColor
              border.color: Color.mOutline
              border.width: 1
              height: chipLabel.implicitHeight + Style.marginS
              width: chipLabel.implicitWidth + Style.marginM * 2

              NText {
                id: chipLabel
                anchors.centerIn: parent
                text: String(modelData || "")
                color: root.onSecondaryContainerColor
                pointSize: Style.fontSizeXS
                applyUiScale: false
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.useRecentSearch(modelData)
              }
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          ComboBox {
            id: themeFilterCombo
            Layout.preferredWidth: 150
            model: ["All themes", "Openings", "Endings", "Both"]
            Component.onCompleted: currentIndex = ["all", "opening", "ending", "both"].indexOf(root.filterThemeType)
            onActivated: root.filterThemeType = ["all", "opening", "ending", "both"][currentIndex]
          }

          ComboBox {
            id: seasonFilterCombo
            Layout.preferredWidth: 130
            model: ["Any season", "Winter", "Spring", "Summer", "Fall"]
            Component.onCompleted: currentIndex = ["any", "winter", "spring", "summer", "fall"].indexOf(root.filterSeason)
            onActivated: root.filterSeason = ["any", "winter", "spring", "summer", "fall"][currentIndex]
          }

          TextField {
            id: yearFilterField
            Layout.preferredWidth: 100
            placeholderText: "Year"
            inputMethodHints: Qt.ImhDigitsOnly
            text: root.filterYear
            onTextChanged: root.filterYear = text.replace(/[^0-9]/g, "").slice(0, 4)
          }

          ComboBox {
            id: mediaTypeCombo
            Layout.preferredWidth: 130
            model: ["Any type", "TV", "Movie", "OVA", "ONA", "Special"]
            Component.onCompleted: currentIndex = ["any", "tv", "movie", "ova", "ona", "special"].indexOf(root.filterMediaType)
            onActivated: root.filterMediaType = ["any", "tv", "movie", "ova", "ona", "special"][currentIndex]
          }

          Item { Layout.fillWidth: true }

          NText {
            text: root.statusMessage
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeXS
            applyUiScale: false
            elide: Text.ElideRight
            Layout.preferredWidth: 240
            horizontalAlignment: Text.AlignRight
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      Layout.fillHeight: true
      spacing: Style.marginM

      Rectangle {
        Layout.fillWidth: true
        Layout.preferredWidth: root.selectedAnime ? Math.max(280, root.width * 0.34) : root.width
        Layout.fillHeight: true
        radius: Style.radiusM
        color: Color.mSurfaceVariant
        border.color: Color.mOutline
        border.width: 1

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginS

          NText {
            text: "Anime"
            pointSize: Style.fontSizeS
            font.weight: Font.DemiBold
            color: Color.mOnSurface
          }

          ListView {
            id: animeListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Style.marginXS
            model: root.filteredResults

            delegate: Rectangle {
              required property var modelData
              readonly property var animeItem: modelData || ({})
              readonly property bool selected: String(animeItem.id || "") === root.selectedAnimeId
              width: animeListView.width
              height: 112
              radius: Style.radiusM
              color: selected ? root.secondaryContainerColor : Color.mSurface
              border.color: selected ? Color.mPrimary : Color.mOutline
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.margins: Style.marginS
                spacing: Style.marginS

                Rectangle {
                  Layout.preferredWidth: 72
                  Layout.preferredHeight: 96
                  radius: Style.radiusS
                  color: Color.mSurfaceVariant
                  clip: true

                  Image {
                    anchors.fill: parent
                    source: animeItem.coverUrl || ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 2

                  NText {
                    text: animeItem.name || ""
                    color: selected ? root.onSecondaryContainerColor : Color.mOnSurface
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  NText {
                    text: root.animeMetaLine(animeItem)
                    color: selected ? root.onSecondaryContainerColor : Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeXS
                    applyUiScale: false
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                  }

                  NText {
                    text: "OP " + (animeItem.openingCount || 0) + " • ED " + (animeItem.endingCount || 0)
                    color: selected ? root.onSecondaryContainerColor : Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeXS
                    applyUiScale: false
                  }
                }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.chooseAnime(animeItem)
              }
            }
          }

          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 220
            radius: Style.radiusM
            color: Color.mSurface
            border.color: Color.mOutline
            border.width: 1
            clip: true

            Item {
              anchors.fill: parent
              anchors.margins: Style.marginM

              ColumnLayout {
                anchors.fill: parent
                spacing: Style.marginS
                visible: !!root.selectedAnime

                NText {
                  text: root.selectedAnime ? root.selectedAnime.name : ""
                  pointSize: Style.fontSizeM
                  font.weight: Font.DemiBold
                  color: Color.mOnSurface
                  wrapMode: Text.Wrap
                  Layout.fillWidth: true
                }

                NText {
                  text: root.animeMetaLine(root.selectedAnime)
                  color: Color.mOnSurfaceVariant
                  pointSize: Style.fontSizeXS
                  applyUiScale: false
                  Layout.fillWidth: true
                  wrapMode: Text.Wrap
                }

                NText {
                  text: root.selectedAnime && root.selectedAnime.studios && root.selectedAnime.studios.length > 0 ? ("Studios: " + root.selectedAnime.studios.join(", ")) : ""
                  visible: text !== ""
                  color: Color.mOnSurfaceVariant
                  pointSize: Style.fontSizeXS
                  applyUiScale: false
                  Layout.fillWidth: true
                  wrapMode: Text.Wrap
                }

                ScrollView {
                  id: synopsisScroll
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  clip: true

                  NText {
                    width: Math.max(0, synopsisScroll.availableWidth)
                    text: root.selectedAnime && root.selectedAnime.synopsis ? root.selectedAnime.synopsis : "No synopsis available."
                    color: Color.mOnSurface
                    wrapMode: Text.Wrap
                  }
                }

                RowLayout {
                  Layout.fillWidth: true

                  NButton {
                    text: "Open page"
                    enabled: !!(root.selectedAnime && root.selectedAnime.pageUrl)
                    onClicked: root.openUrl(root.selectedAnime ? root.selectedAnime.pageUrl : "")
                  }

                  Item { Layout.fillWidth: true }
                }
              }

              NText {
                anchors.centerIn: parent
                visible: !root.selectedAnime
                text: "Select an anime to see its details"
                color: Color.mOnSurfaceVariant
              }
            }
          }
        }
      }

      Rectangle {
        visible: !!root.selectedAnime
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: visible ? Math.max(360, root.width * 0.5) : 0
        Layout.minimumWidth: visible ? 320 : 0
        radius: Style.radiusM
        color: Color.mSurfaceVariant
        border.color: Color.mOutline
        border.width: 1

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginS

          RowLayout {
            Layout.fillWidth: true

            NText {
              text: root.selectedAnime ? (root.selectedAnime.name + " themes") : "Themes"
              pointSize: Style.fontSizeS
              font.weight: Font.DemiBold
              color: Color.mOnSurface
            }

            Item { Layout.fillWidth: true }

            NText {
              text: root.playerStatusMessage
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeXS
              applyUiScale: false
              visible: text !== ""
            }
          }

          NText {
            Layout.fillWidth: true
            visible: !!root.selectedAnime
            text: "Click a row or Play to load that video in mpv. Playing another theme replaces the current video."
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeXS
            applyUiScale: false
            wrapMode: Text.Wrap
          }

          ListView {
            id: themesListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Style.marginXS
            model: root.selectedAnimeThemesModel

            delegate: Rectangle {
              required property var modelData
              readonly property var themeItem: modelData || ({})
              readonly property bool activeTheme: String(themeItem.id || "") === root.lastPlayedThemeId
              width: themesListView.width
              height: 108
              radius: Style.radiusM
              color: activeTheme ? root.tertiaryContainerColor : Color.mSurface
              border.color: activeTheme ? root.tertiaryColor : Color.mOutline
              border.width: 1

              RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Style.marginM
                anchors.topMargin: Style.marginS
                anchors.rightMargin: Style.marginS
                anchors.bottomMargin: Style.marginS
                spacing: Style.marginS

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: 2

                  NText {
                    text: themeItem.displayName ? (themeItem.displayName + (themeItem.songTitle ? (" - " + themeItem.songTitle) : "")) : (themeItem.songTitle || "Theme")
                    color: activeTheme ? root.onTertiaryContainerColor : Color.mOnSurface
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  NText {
                    text: themeItem.artists && themeItem.artists.length > 0 ? themeItem.artists.join(", ") : ""
                    visible: text !== ""
                    color: activeTheme ? root.onTertiaryContainerColor : Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeXS
                    applyUiScale: false
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  NText {
                    text: [themeItem.groupName || "", root.themeMetaLine(themeItem)].filter(function(part) { return String(part || "") !== ""; }).join(" • ")
                    color: activeTheme ? root.onTertiaryContainerColor : Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeXS
                    applyUiScale: false
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }
                }

                NButton {
                  text: "Play"
                  enabled: !!themeItem.bestVideoUrl
                  onClicked: root.openThemeInMpv(themeItem)
                }

                NButton {
                  text: "Open page"
                  enabled: !!themeItem.pageUrl
                  onClicked: root.openUrl(themeItem.pageUrl)
                }
              }

              MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openThemeInMpv(themeItem)
              }
            }
          }

          NText {
            visible: !root.selectedAnime
            text: "Search and pick an anime from the left column to browse its OP/ED videos."
            color: Color.mOnSurfaceVariant
            Layout.fillWidth: true
            wrapMode: Text.Wrap
          }
        }
      }
    }
  }
}
