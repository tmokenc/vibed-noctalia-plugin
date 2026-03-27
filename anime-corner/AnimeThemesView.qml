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
  property real animeListScrollY: 0
  property int animeRightTab: 0

  readonly property string cacheDir: mainInstance?.cacheDir || (typeof Settings !== "undefined" && Settings.cacheDir ? Settings.cacheDir + "plugins/anime-corner/" : "")
  readonly property string mpvSocketPath: cacheDir ? cacheDir + "animethemes-mpv.sock" : "/tmp/anime-corner-animethemes-mpv.sock"
  property var selectedAnime: null
  readonly property var selectedAnimeThemesModel: (selectedAnime && Array.isArray(selectedAnime.animethemes)) ? selectedAnime.animethemes : []
  readonly property var selectedAnimeCharactersModel: (selectedAnime && Array.isArray(selectedAnime.characters)) ? selectedAnime.characters : []
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
    if (!anime.detailsLoaded)
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

  function replaceAnimeInList(list, animeId, replacementAnime) {
    var key = String(animeId || "");
    var replaced = false;
    var output = (list || []).map(function(item) {
      if (String(item && item.id || "") !== key)
        return item;
      replaced = true;
      return replacementAnime;
    });
    if (!replaced && replacementAnime)
      output.push(replacementAnime);
    return output;
  }

  function mergeAnimeDetail(detailAnime, requestedAnimeId) {
    if (!detailAnime)
      return;
    var animeId = String(requestedAnimeId || detailAnime.id || detailAnime.anilistId || "");
    if (animeId === "")
      return;
    var existingAnime = findAnimeById(animeId, animeResults) || {};
    var mergedAnime = Object.assign({}, existingAnime, detailAnime, {
      "id": animeId,
      "anilistId": String(detailAnime.anilistId || existingAnime.anilistId || animeId)
    });

    ["name", "titleRomaji", "titleEnglish", "titleNative", "season", "mediaFormat", "status", "countryOfOrigin", "hashtag", "synopsis", "coverUrl", "bannerUrl", "pageUrl", "slug"].forEach(function(key) {
      if ((mergedAnime[key] === undefined || mergedAnime[key] === null || mergedAnime[key] === "") && existingAnime[key] !== undefined)
        mergedAnime[key] = existingAnime[key];
    });

    ["synonyms", "genres", "studios", "resources"].forEach(function(key) {
      if ((!Array.isArray(mergedAnime[key]) || mergedAnime[key].length === 0) && Array.isArray(existingAnime[key]) && existingAnime[key].length > 0)
        mergedAnime[key] = existingAnime[key];
    });

    ["year", "episodes", "duration", "averageScore", "meanScore", "popularity", "favourites"].forEach(function(key) {
      if ((!mergedAnime[key] || mergedAnime[key] === 0) && existingAnime[key])
        mergedAnime[key] = existingAnime[key];
    });

    if ((!mergedAnime.startDate || !mergedAnime.startDate.year) && existingAnime.startDate && existingAnime.startDate.year)
      mergedAnime.startDate = existingAnime.startDate;
    if ((!mergedAnime.endDate || !mergedAnime.endDate.year) && existingAnime.endDate && existingAnime.endDate.year)
      mergedAnime.endDate = existingAnime.endDate;

    animeResults = replaceAnimeInList(animeResults, animeId, mergedAnime);
    if (String(selectedAnimeId || "") === animeId)
      selectedAnime = mergedAnime;
    refreshFilteredResults(false, true);
  }

  function markAnimeLoading(animeId, loading, errorMessage) {
    var key = String(animeId || "");
    if (key === "")
      return;
    animeResults = (animeResults || []).map(function(item) {
      if (String(item && item.id || "") !== key)
        return item;
      var updated = Object.assign({}, item || {});
      updated.detailsLoading = !!loading;
      updated.detailsError = String(errorMessage || "");
      return updated;
    });
    refreshFilteredResults(false, true);
  }

  function ensureAnimeDetails(anime) {
    var item = anime || selectedAnime;
    if (!item)
      return;
    if (item.detailsLoaded || item.detailsLoading)
      return;
    var animeId = String(item.id || item.anilistId || "");
    var anilistId = String(item.anilistId || item.id || "");
    if (animeId === "" || anilistId === "")
      return;
    markAnimeLoading(animeId, true, "");
    Qt.callLater(function() {
      animeThemesService.loadAnimeDetails(animeId, anilistId);
    });
  }

  function restoreAnimeListPosition() {
    if (!animeListView)
      return;
    var maxY = Math.max(0, (animeListView.contentHeight || 0) - (animeListView.height || 0));
    animeListView.contentY = Math.max(0, Math.min(animeListScrollY, maxY));
  }

  function refreshFilteredResults(autoSelectSingle, preservePosition) {
    if (preservePosition && animeListView)
      animeListScrollY = animeListView.contentY;
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
    if (selectedAnime)
      ensureAnimeDetails(selectedAnime);
    if (preservePosition)
      Qt.callLater(function() { root.restoreAnimeListPosition(); });
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

  function formatDate(dateObj) {
    if (!dateObj || !dateObj.year)
      return "";
    var parts = [String(dateObj.year)];
    if (dateObj.month)
      parts.unshift(String(dateObj.month).padStart(2, "0"));
    if (dateObj.day)
      parts.unshift(String(dateObj.day).padStart(2, "0"));
    return parts.join("-");
  }

  function dateRangeLine(anime) {
    if (!anime)
      return "";
    var start = formatDate(anime.startDate);
    var end = formatDate(anime.endDate);
    if (start !== "" && end !== "")
      return start + " → " + end;
    return start || end;
  }

  function infoChips(anime) {
    if (!anime)
      return [];
    var parts = [];
    if (anime.mediaFormat)
      parts.push(String(anime.mediaFormat));
    if (anime.status)
      parts.push(String(anime.status));
    if (anime.countryOfOrigin)
      parts.push(String(anime.countryOfOrigin));
    if (anime.episodes)
      parts.push(String(anime.episodes) + " eps");
    if (anime.duration)
      parts.push(String(anime.duration) + " min");
    return parts;
  }

  function statsLine(anime) {
    if (!anime)
      return "";
    var parts = [];
    if (anime.averageScore)
      parts.push("Avg " + anime.averageScore);
    if (anime.meanScore)
      parts.push("Mean " + anime.meanScore);
    if (anime.popularity)
      parts.push("Pop " + anime.popularity);
    if (anime.favourites)
      parts.push("Fav " + anime.favourites);
    return parts.join(" • ");
  }

  function chooseAnime(anime) {
    if (!anime)
      return;
    if (animeListView)
      animeListScrollY = animeListView.contentY;
    clearPlayerStatus();
    selectedAnimeId = String(anime.id || "");
    updateSelectedAnime(filteredResults);
    ensureAnimeDetails(selectedAnime || anime);
    Qt.callLater(function() { root.restoreAnimeListPosition(); });
    syncState();
  }

  function updateSelectedAnime(source) {
    var list = Array.isArray(source) ? source : (filteredResults.length > 0 ? filteredResults : animeResults);
    if (selectedAnimeId === "") {
      selectedAnime = null;
      return;
    }
    selectedAnime = findAnimeById(selectedAnimeId, list) || findAnimeById(selectedAnimeId, animeResults);
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
      "lastPlayedThemeId": lastPlayedThemeId,
      "animeRightTab": animeRightTab
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
    animeRightTab = Math.max(0, Math.min(2, parseInt(state.animeRightTab, 10) || 0));
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
    statusMessage = "Searching AniList…";
    syncState();
    animeThemesService.searchAnime(query, pageSize);
  }

  function focusInput() {
    searchField.forceActiveFocus();
  }

  function clearPlayerStatus() {
    if (playerStatusMessage === "")
      return;
    playerStatusMessage = "";
    syncState();
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
    playerStatusClearTimer.stop();
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

    function onDetailFinished(payload) {
      var anime = payload && payload.anime ? payload.anime : null;
      var animeId = String(payload && payload.animeId || anime && (anime.id || anime.anilistId) || "");
      if (!anime)
        return;
      root.mergeAnimeDetail(anime, animeId);
      if (String(root.selectedAnimeId || "") === animeId) {
        root.statusMessage = anime.themeCount > 0 ? (anime.themeCount + " themes loaded for " + anime.name) : ("No themes found for " + anime.name);
      }
      root.syncState();
    }

    function onDetailFailed(animeId, message) {
      root.markAnimeLoading(animeId, false, message);
      if (String(root.selectedAnimeId || "") === String(animeId || "")) {
        root.statusMessage = String(message || "Failed to load themes for this anime.");
      }
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
      if (root.playerStatusMessage !== "")
        playerStatusClearTimer.restart();
      root.syncState();
    }
  }

  Process {
    id: browserOpenProcess
  }

  Timer {
    id: playerStatusClearTimer
    interval: 5000
    repeat: false
    onTriggered: root.clearPlayerStatus()
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
        Layout.preferredWidth: root.selectedAnime ? Math.max(320, root.width * 0.36) : root.width
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
            onContentYChanged: root.animeListScrollY = contentY

            delegate: Rectangle {
              required property var modelData
              readonly property var animeItem: modelData || ({})
              readonly property bool selected: String(animeItem.id || "") === root.selectedAnimeId
              width: animeListView.width
              height: Math.max(112, animeRowLayout.implicitHeight + Style.marginS * 2)
              radius: Style.radiusM
              color: selected ? root.secondaryContainerColor : Color.mSurface
              border.color: selected ? Color.mPrimary : Color.mOutline
              border.width: 1

              RowLayout {
                id: animeRowLayout
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
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  NText {
                    text: root.animeMetaLine(animeItem)
                    color: selected ? root.onSecondaryContainerColor : Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeXS
                    applyUiScale: false
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                  }

                  NText {
                    text: animeItem.detailsLoading ? "Loading themes…" : (((animeItem.detailsError || "") !== "") ? "Theme load failed" : (animeItem.detailsLoaded ? (((animeItem.themeCount || 0) > 0) ? ("OP " + (animeItem.openingCount || 0) + " • ED " + (animeItem.endingCount || 0)) : "No themes found") : "Click to load themes"))
                    color: selected ? root.onSecondaryContainerColor : Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeXS
                    applyUiScale: false
                    Layout.fillWidth: true
                    elide: Text.ElideRight
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
        }
      }

      Rectangle {
        visible: !!root.selectedAnime
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: visible ? Math.max(420, root.width * 0.58) : 0
        Layout.minimumWidth: visible ? 360 : 0
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
              text: root.selectedAnime ? root.selectedAnime.name : "Anime"
              pointSize: Style.fontSizeS
              font.weight: Font.DemiBold
              color: Color.mOnSurface
              Layout.fillWidth: true
              wrapMode: Text.Wrap
            }

            NText {
              text: root.playerStatusMessage
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeXS
              applyUiScale: false
              visible: text !== "" && root.animeRightTab === 2
            }
          }

          TabBar {
            id: animeRightTabBar
            Layout.fillWidth: true
            Component.onCompleted: currentIndex = root.animeRightTab
            onCurrentIndexChanged: {
              if (root.animeRightTab !== currentIndex) {
                root.animeRightTab = currentIndex;
                root.syncState();
              }
            }

            TabButton { text: "Info" }
            TabButton { text: "Cast" }
            TabButton { text: "Themes" }
          }

          StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: root.animeRightTab
            Item {
              ScrollView {
                anchors.fill: parent
                clip: true

                ColumnLayout {
                  width: parent.width
                  spacing: Style.marginM

                  Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: infoHeaderRow.implicitHeight + Style.marginM * 2
                    radius: Style.radiusM
                    color: Color.mSurface
                    border.color: Color.mOutline
                    border.width: 1

                    RowLayout {
                      id: infoHeaderRow
                      anchors.fill: parent
                      anchors.margins: Style.marginM
                      spacing: Style.marginM

                      Rectangle {
                        Layout.preferredWidth: 132
                        Layout.preferredHeight: 180
                        radius: Style.radiusM
                        color: Color.mSurfaceVariant
                        border.color: Color.mOutline
                        border.width: 1
                        clip: true

                        Image {
                          anchors.fill: parent
                          source: root.selectedAnime ? (root.selectedAnime.coverUrl || "") : ""
                          asynchronous: true
                          fillMode: Image.PreserveAspectCrop
                        }
                      }

                      ColumnLayout {
                        id: infoHeaderColumn
                        Layout.fillWidth: true
                        spacing: Style.marginS

                        NText {
                          text: root.selectedAnime ? root.selectedAnime.name : ""
                          pointSize: Style.fontSizeM
                          font.weight: Font.DemiBold
                          color: Color.mOnSurface
                          Layout.fillWidth: true
                          wrapMode: Text.Wrap
                        }

                        NText {
                          text: [root.selectedAnime ? root.selectedAnime.titleRomaji : "", root.selectedAnime ? root.selectedAnime.titleEnglish : "", root.selectedAnime ? root.selectedAnime.titleNative : ""].filter(function(part, index, arr) { return part && arr.indexOf(part) === index; }).join(" • ")
                          visible: text !== ""
                          color: Color.mOnSurfaceVariant
                          Layout.fillWidth: true
                          wrapMode: Text.Wrap
                        }

                        Flow {
                          Layout.fillWidth: true
                          spacing: Style.marginXS
                          visible: !!root.selectedAnime && root.infoChips(root.selectedAnime).length > 0

                          Repeater {
                            model: root.selectedAnime ? root.infoChips(root.selectedAnime) : []
                            delegate: Rectangle {
                              required property var modelData
                              radius: Style.radiusM
                              color: root.secondaryContainerColor
                              border.color: Color.mOutline
                              border.width: 1
                              height: chipInfoLabel.implicitHeight + Style.marginS
                              width: chipInfoLabel.implicitWidth + Style.marginM * 2

                              NText {
                                id: chipInfoLabel
                                anchors.centerIn: parent
                                text: String(modelData || "")
                                color: root.onSecondaryContainerColor
                                pointSize: Style.fontSizeXS
                                applyUiScale: false
                              }
                            }
                          }
                        }

                        NText {
                          text: root.statsLine(root.selectedAnime)
                          visible: text !== ""
                          color: Color.mOnSurface
                          Layout.fillWidth: true
                          wrapMode: Text.Wrap
                        }

                        NText {
                          text: root.selectedAnime ? ("Themes: " + (root.selectedAnime.themeCount || 0) + " • OP " + (root.selectedAnime.openingCount || 0) + " • ED " + (root.selectedAnime.endingCount || 0)) : ""
                          color: Color.mOnSurfaceVariant
                          Layout.fillWidth: true
                          wrapMode: Text.Wrap
                        }

                        RowLayout {
                          Layout.fillWidth: true
                          spacing: Style.marginS

                          NButton {
                            text: "Open AniList"
                            enabled: !!(root.selectedAnime && root.selectedAnime.pageUrl)
                            onClicked: root.openUrl(root.selectedAnime ? root.selectedAnime.pageUrl : "")
                          }

                          Item { Layout.fillWidth: true }
                        }
                      }
                    }
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    visible: !!(root.selectedAnime && root.selectedAnime.bannerUrl)
                    implicitHeight: visible ? Math.max(120, width * 0.22) : 0
                    radius: Style.radiusM
                    color: Color.mSurfaceVariant
                    border.color: Color.mOutline
                    border.width: 1
                    clip: true

                    Image {
                      anchors.fill: parent
                      source: root.selectedAnime ? (root.selectedAnime.bannerUrl || "") : ""
                      asynchronous: true
                      fillMode: Image.PreserveAspectCrop
                    }
                  }

                  Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: infoGrid.implicitHeight + Style.marginM * 2
                    radius: Style.radiusM
                    color: Color.mSurface
                    border.color: Color.mOutline
                    border.width: 1

                    GridLayout {
                      id: infoGrid
                      anchors.fill: parent
                      anchors.margins: Style.marginM
                      columns: 2
                      rowSpacing: Style.marginS
                      columnSpacing: Style.marginM

                      NText { text: "Season"; color: Color.mOnSurfaceVariant }
                      NText { text: root.selectedAnime ? root.animeMetaLine(root.selectedAnime) : ""; color: Color.mOnSurface; wrapMode: Text.Wrap; Layout.fillWidth: true }

                      NText { text: "Status"; color: Color.mOnSurfaceVariant; visible: (root.selectedAnime ? String(root.selectedAnime.status || "") : "") !== "" }
                      NText { text: root.selectedAnime ? String(root.selectedAnime.status || "") : ""; color: Color.mOnSurface; wrapMode: Text.Wrap; Layout.fillWidth: true; visible: text !== "" }

                      NText { text: "Dates"; color: Color.mOnSurfaceVariant; visible: root.dateRangeLine(root.selectedAnime) !== "" }
                      NText { text: root.dateRangeLine(root.selectedAnime); color: Color.mOnSurface; wrapMode: Text.Wrap; Layout.fillWidth: true; visible: text !== "" }

                      NText { text: "Episodes"; color: Color.mOnSurfaceVariant; visible: !!(root.selectedAnime && root.selectedAnime.episodes) }
                      NText { text: root.selectedAnime && root.selectedAnime.episodes ? String(root.selectedAnime.episodes) : ""; color: Color.mOnSurface; wrapMode: Text.Wrap; Layout.fillWidth: true; visible: text !== "" }

                      NText { text: "Duration"; color: Color.mOnSurfaceVariant; visible: !!(root.selectedAnime && root.selectedAnime.duration) }
                      NText { text: root.selectedAnime && root.selectedAnime.duration ? (String(root.selectedAnime.duration) + " min") : ""; color: Color.mOnSurface; wrapMode: Text.Wrap; Layout.fillWidth: true; visible: text !== "" }

                      NText { text: "Country"; color: Color.mOnSurfaceVariant; visible: (root.selectedAnime ? String(root.selectedAnime.countryOfOrigin || "") : "") !== "" }
                      NText { text: root.selectedAnime ? String(root.selectedAnime.countryOfOrigin || "") : ""; color: Color.mOnSurface; wrapMode: Text.Wrap; Layout.fillWidth: true; visible: text !== "" }

                      NText { text: "Studios"; color: Color.mOnSurfaceVariant; visible: !!(root.selectedAnime && root.selectedAnime.studios && root.selectedAnime.studios.length > 0) }
                      NText { text: root.selectedAnime && root.selectedAnime.studios && root.selectedAnime.studios.length > 0 ? root.selectedAnime.studios.join(", ") : ""; color: Color.mOnSurface; wrapMode: Text.Wrap; Layout.fillWidth: true; visible: text !== "" }

                      NText { text: "Genres"; color: Color.mOnSurfaceVariant; visible: !!(root.selectedAnime && root.selectedAnime.genres && root.selectedAnime.genres.length > 0) }
                      NText { text: root.selectedAnime && root.selectedAnime.genres && root.selectedAnime.genres.length > 0 ? root.selectedAnime.genres.join(", ") : ""; color: Color.mOnSurface; wrapMode: Text.Wrap; Layout.fillWidth: true; visible: text !== "" }

                      NText { text: "Synonyms"; color: Color.mOnSurfaceVariant; visible: !!(root.selectedAnime && root.selectedAnime.synonyms && root.selectedAnime.synonyms.length > 0) }
                      NText { text: root.selectedAnime && root.selectedAnime.synonyms && root.selectedAnime.synonyms.length > 0 ? root.selectedAnime.synonyms.join(", ") : ""; color: Color.mOnSurface; wrapMode: Text.Wrap; Layout.fillWidth: true; visible: text !== "" }

                      NText { text: "Stats"; color: Color.mOnSurfaceVariant; visible: root.statsLine(root.selectedAnime) !== "" }
                      NText { text: root.statsLine(root.selectedAnime); color: Color.mOnSurface; wrapMode: Text.Wrap; Layout.fillWidth: true; visible: text !== "" }

                      NText { text: "Hashtag"; color: Color.mOnSurfaceVariant; visible: (root.selectedAnime ? String(root.selectedAnime.hashtag || "") : "") !== "" }
                      NText { text: root.selectedAnime ? String(root.selectedAnime.hashtag || "") : ""; color: Color.mOnSurface; wrapMode: Text.Wrap; Layout.fillWidth: true; visible: text !== "" }

                      NText { text: "Loaded cast"; color: Color.mOnSurfaceVariant; visible: !!root.selectedAnime }
                      NText { text: root.selectedAnime ? String(root.selectedAnimeCharactersModel.length || 0) : "0"; color: Color.mOnSurface; wrapMode: Text.Wrap; Layout.fillWidth: true; visible: !!root.selectedAnime }
                    }
                  }
                  Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: synopsisInfoColumn.implicitHeight + Style.marginM * 2
                    radius: Style.radiusM
                    color: Color.mSurface
                    border.color: Color.mOutline
                    border.width: 1

                    ColumnLayout {
                      id: synopsisInfoColumn
                      anchors.fill: parent
                      anchors.margins: Style.marginM
                      spacing: Style.marginS

                      NText {
                        text: "Synopsis"
                        color: Color.mOnSurface
                        font.weight: Font.Medium
                      }

                      NText {
                        text: root.selectedAnime && root.selectedAnime.synopsis ? root.selectedAnime.synopsis : "No synopsis available."
                        color: Color.mOnSurface
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                      }
                    }
                  }

                }
              }
            }

            Item {
              StackLayout {
                anchors.fill: parent
                currentIndex: !root.selectedAnime ? 0 : (root.selectedAnimeCharactersModel.length > 0 ? 1 : 2)

                Item {
                  NText {
                    anchors.centerIn: parent
                    text: "Select an anime to browse characters and voice actors."
                    color: Color.mOnSurfaceVariant
                    wrapMode: Text.Wrap
                    width: parent.width - Style.marginL * 2
                    horizontalAlignment: Text.AlignHCenter
                  }
                }

                Item {
                  ListView {
                    id: castListView
                    anchors.fill: parent
                    clip: true
                    spacing: Style.marginXS
                    model: root.selectedAnimeCharactersModel

                  delegate: Rectangle {
                    required property var modelData
                    readonly property var castItem: modelData || ({})
                    readonly property var primaryVa: castItem.voiceActors && castItem.voiceActors.length > 0 ? castItem.voiceActors[0] : null
                    width: castListView.width
                    height: Math.max(112, castRow.implicitHeight + Style.marginS * 2)
                    radius: Style.radiusM
                    color: Color.mSurface
                    border.color: Color.mOutline
                    border.width: 1

                    RowLayout {
                      id: castRow
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
                          source: castItem.imageUrl || ""
                          asynchronous: true
                          fillMode: Image.PreserveAspectCrop
                        }
                      }

                      Rectangle {
                        Layout.preferredWidth: 72
                        Layout.preferredHeight: 96
                        radius: Style.radiusS
                        color: Color.mSurfaceVariant
                        border.color: Color.mOutline
                        border.width: 1
                        visible: !!(primaryVa && primaryVa.imageUrl)
                        clip: true

                        Image {
                          anchors.fill: parent
                          source: primaryVa ? (primaryVa.imageUrl || "") : ""
                          asynchronous: true
                          fillMode: Image.PreserveAspectCrop
                        }
                      }

                      ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        NText {
                          text: castItem.name || "Character"
                          color: Color.mOnSurface
                          font.weight: Font.Medium
                          Layout.fillWidth: true
                          wrapMode: Text.Wrap
                        }

                        NText {
                          text: castItem.nativeName || ""
                          visible: text !== ""
                          color: Color.mOnSurfaceVariant
                          pointSize: Style.fontSizeXS
                          applyUiScale: false
                          Layout.fillWidth: true
                          wrapMode: Text.Wrap
                        }

                        NText {
                          text: castItem.role ? ("Role: " + castItem.role) : ""
                          visible: text !== ""
                          color: Color.mOnSurfaceVariant
                          pointSize: Style.fontSizeXS
                          applyUiScale: false
                          Layout.fillWidth: true
                          wrapMode: Text.Wrap
                        }

                        NText {
                          text: primaryVa ? ("VA: " + primaryVa.name + (primaryVa.nativeName ? (" • " + primaryVa.nativeName) : "")) : "No voice actor listed"
                          color: Color.mOnSurface
                          pointSize: Style.fontSizeXS
                          applyUiScale: false
                          Layout.fillWidth: true
                          wrapMode: Text.Wrap
                        }

                      }

                      ColumnLayout {
                        spacing: Style.marginXS
                        Layout.alignment: Qt.AlignTop

                        NButton {
                          text: "Character"
                          enabled: !!castItem.pageUrl
                          onClicked: root.openUrl(castItem.pageUrl)
                        }

                        NButton {
                          text: "Voice actor"
                          enabled: !!(primaryVa && primaryVa.pageUrl)
                          onClicked: root.openUrl(primaryVa ? primaryVa.pageUrl : "")
                        }
                      }
                    }
                  }
                  }
                }

                Item {
                  NText {
                    anchors.centerIn: parent
                    text: "No cast information found for " + (root.selectedAnime ? (root.selectedAnime.name || "this anime") : "this anime")
                    color: Color.mOnSurfaceVariant
                    wrapMode: Text.Wrap
                    width: parent.width - Style.marginL * 2
                    horizontalAlignment: Text.AlignHCenter
                  }
                }
              }
            }
            Item {
              ColumnLayout {
                anchors.fill: parent
                spacing: Style.marginS

                NText {
                  Layout.fillWidth: true
                  visible: !!root.selectedAnime
                  text: "Click a row or Play to load that video in mpv. Playing another theme replaces the current video."
                  color: Color.mOnSurfaceVariant
                  pointSize: Style.fontSizeXS
                  applyUiScale: false
                  wrapMode: Text.Wrap
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  spacing: Style.marginS

                  NText {
                    Layout.fillWidth: true
                    visible: !!(root.selectedAnime && root.selectedAnime.detailsLoading)
                    text: "Loading themes…"
                    color: Color.mOnSurfaceVariant
                    pointSize: Style.fontSizeXS
                    applyUiScale: false
                    wrapMode: Text.Wrap
                  }

                  StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: !root.selectedAnime ? 0 : (((root.selectedAnime.detailsError || "") !== "") ? 1 : (root.selectedAnimeThemesModel.length === 0 ? 2 : 3))

                    Item {
                      NText {
                        anchors.centerIn: parent
                        text: "Search and pick an anime from the left column to browse its OP/ED videos."
                        color: Color.mOnSurfaceVariant
                        wrapMode: Text.Wrap
                        width: parent.width - Style.marginL * 2
                        horizontalAlignment: Text.AlignHCenter
                      }
                    }

                    Item {
                      NText {
                        anchors.centerIn: parent
                        text: root.selectedAnime ? (root.selectedAnime.detailsError || "Failed to load themes.") : ""
                        color: Color.mOnSurfaceVariant
                        wrapMode: Text.Wrap
                        width: parent.width - Style.marginL * 2
                        horizontalAlignment: Text.AlignHCenter
                      }
                    }

                    Item {
                      NText {
                        anchors.centerIn: parent
                        text: root.selectedAnime ? ((root.selectedAnime.detailsLoading && root.selectedAnimeThemesModel.length === 0) ? "Waiting for themes…" : ("No themes found for " + (root.selectedAnime.name || "this anime"))) : ""
                        color: Color.mOnSurfaceVariant
                        wrapMode: Text.Wrap
                        width: parent.width - Style.marginL * 2
                        horizontalAlignment: Text.AlignHCenter
                      }
                    }

                    Item {
                      ListView {
                        id: themesListView
                        anchors.fill: parent
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
                  }
                }
              }
            }

          }
        }
      }
    }
  }
}

}