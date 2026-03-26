import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtQml
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Widgets
import qs.Services.UI

Item {
  id: root

  signal requestTabCycleForward
  signal requestTabCycleBackward

  property var pluginApi: null
  property var mainInstance: null

  property string provider: pluginApi?.pluginSettings?.booru?.provider || pluginApi?.manifest?.metadata?.defaultSettings?.booru?.provider || "yandere"
  property bool safeOnly: pluginApi?.pluginSettings?.booru?.safeOnly ?? pluginApi?.manifest?.metadata?.defaultSettings?.booru?.safeOnly ?? true
  property bool randomOrder: pluginApi?.pluginSettings?.booru?.randomOrder ?? pluginApi?.manifest?.metadata?.defaultSettings?.booru?.randomOrder ?? false
  property int pageSize: pluginApi?.pluginSettings?.booru?.pageSize || pluginApi?.manifest?.metadata?.defaultSettings?.booru?.pageSize || 20
  property int imagesPerRow: pluginApi?.pluginSettings?.booru?.imagesPerRow || pluginApi?.manifest?.metadata?.defaultSettings?.booru?.imagesPerRow || 3
  property bool variableCardSize: pluginApi?.pluginSettings?.booru?.variableCardSize ?? pluginApi?.manifest?.metadata?.defaultSettings?.booru?.variableCardSize ?? true
  property int recentSearchTagLimit: pluginApi?.pluginSettings?.booru?.recentSearchTagLimit ?? pluginApi?.manifest?.metadata?.defaultSettings?.booru?.recentSearchTagLimit ?? 20
  property int danbooruTagIndexRefreshDays: pluginApi?.pluginSettings?.booru?.danbooruTagIndexRefreshDays ?? pluginApi?.manifest?.metadata?.defaultSettings?.booru?.danbooruTagIndexRefreshDays ?? 7
  readonly property string configuredSaveDirectory: pluginApi?.pluginSettings?.booru?.saveDirectory || pluginApi?.manifest?.metadata?.defaultSettings?.booru?.saveDirectory || ""
  readonly property string saveDirectory: {
    var base = configuredSaveDirectory !== "" ? configuredSaveDirectory : ((Quickshell.env("HOME") || "") + "/Pictures/AnimeCorner");
    if (base.indexOf("~/") === 0)
      return (Quickshell.env("HOME") || "") + base.slice(1);
    return base;
  }
  readonly property string wallpaperCommand: pluginApi?.pluginSettings?.booru?.wallpaperCommand || pluginApi?.manifest?.metadata?.defaultSettings?.booru?.wallpaperCommand || ""

  property string searchText: ""
  property int pageNumber: 1
  property bool lastQueryRandomOrder: false
  property var persistedResponse: null

  property var selectedImage: null
  property bool previewOpen: false
  property bool viewerBusy: false
  property string lastProcessError: ""
  property string pendingFilePath: ""
  property bool pendingSetWallpaperAfterSave: false
  property var contextImage: null
  property bool contextMenuVisible: false
  property real contextMenuX: 0
  property real contextMenuY: 0

  property var saveQueue: []
  property bool queueRunning: false
  property var activeQueueJob: null
  property var queuedKeys: ({})
  property var savedImageKeys: ({})
  property var savedImagePaths: ({})
  property var savedImageResolvedPaths: ({})

  onPageNumberChanged: {
    if (pageSpinBox && pageSpinBox.value !== pageNumber)
      pageSpinBox.value = pageNumber;
  }
  property bool savedImageScanPending: false

  onRecentSearchTagLimitChanged: {
    recentSearchTags = normalizedRecentSearchTags(recentSearchTags);
    syncState();
  }

  onDanbooruTagIndexRefreshDaysChanged: {
    syncState();
    ensureFreshProviderTagIndex();
  }

  property real scrollContentY: 0
  readonly property real attachedPreviewWidth: 420
  readonly property real attachedPreviewExtraWidth: previewOpen && selectedImage !== null ? (attachedPreviewWidth + Style.marginM) : 0
  readonly property bool attachedPreviewVisible: previewOpen && selectedImage !== null
  readonly property string cacheDir: mainInstance?.cacheDir || (typeof Settings !== "undefined" && Settings.cacheDir ? Settings.cacheDir + "plugins/anime-corner/" : "")
  readonly property string tagCachePath: cacheDir ? cacheDir + "booru-tag-cache.json" : ""
  readonly property string booruStateCachePath: cacheDir ? cacheDir + "booru-state.json" : ""
  property var tagCompletionCache: ({
      "version": 1,
      "providers": {}
    })
  property var tagSuggestions: []
  property var recentSearchTags: []
  property string activeSuggestionQuery: ""
  property int activeSuggestionIndex: 0
  property bool suggestionPopupRequested: false
  readonly property bool suggestionPopupVisible: suggestionPopupRequested && tagSuggestions.length > 0 && searchInput && searchInput.activeFocus
  property bool tagCacheReady: false
  property bool booruStateCacheReady: false
  property bool _syncingState: false
  property int tagSuggestionRequestSerial: 0
  property var workerIndexMarkers: ({})
  property var preparedTagIndexCache: ({})
  property var localSuggestionSearchCache: ({})

  function trText(key, fallback) {
    var value = pluginApi && pluginApi.tr ? pluginApi.tr(key) : "";
    value = String(value || "");
    if (value === "" || (/^!!.*!!$/).test(value))
      return fallback;
    return value;
  }

  function focusInput() {
    searchInput.forceActiveFocus();
  }

  function persistBooruSetting(key, value) {
    if (!pluginApi)
      return;
    if (!pluginApi.pluginSettings.booru)
      pluginApi.pluginSettings.booru = {};
    pluginApi.pluginSettings.booru[key] = value;
    pluginApi.saveSettings();
  }

  function splitTags(text) {
    var trimmed = String(text || "").trim();
    if (trimmed === "")
      return [];
    return trimmed.split(/\s+/).filter(function (tag) {
      return tag && tag.length > 0;
    });
  }

  function tagContext(text, cursorPosition) {
    var rawText = String(text || "");
    var cursor = Math.max(0, Math.min(cursorPosition === undefined ? rawText.length : cursorPosition, rawText.length));
    var start = rawText.lastIndexOf(" ", Math.max(0, cursor - 1));
    start = start === -1 ? 0 : start + 1;
    var end = rawText.indexOf(" ", cursor);
    if (end === -1)
      end = rawText.length;

    var token = rawText.slice(start, end);
    var prefix = "";
    var query = token;
    if (query.indexOf("-") === 0 || query.indexOf("~") === 0) {
      prefix = query.charAt(0);
      query = query.slice(1);
    }

    return {
      "start": start,
      "end": end,
      "token": token,
      "prefix": prefix,
      "query": query,
      "normalized": query.toLowerCase()
    };
  }

  function ensureProviderTagCache(providerKey) {
    var cache = tagCompletionCache || { "version": 1, "providers": {} };
    if (!cache.providers)
      cache.providers = {};
    if (!cache.providers[providerKey]) {
      cache.providers[providerKey] = {
        "timestamp": 0,
        "queries": {},
        "index": []
      };
    }
    if (!cache.providers[providerKey].queries)
      cache.providers[providerKey].queries = {};
    if (!cache.providers[providerKey].index)
      cache.providers[providerKey].index = [];
    return cache.providers[providerKey];
  }

  function providerTagCacheMaxAgeMs(providerKey) {
    var resolvedProviderKey = String(providerKey || provider || "");
    if (resolvedProviderKey === "danbooru") {
      var days = Math.max(0, parseInt(danbooruTagIndexRefreshDays || 0, 10) || 0);
      if (days <= 0)
        return 0;
      return days * 24 * 60 * 60 * 1000;
    }
    return 24 * 60 * 60 * 1000;
  }

  function shouldRefreshProviderTagIndex(providerKey) {
    var resolvedProviderKey = String(providerKey || provider || "");
    if (resolvedProviderKey !== "danbooru")
      return true;
    return providerTagCacheMaxAgeMs(resolvedProviderKey) > 0;
  }

  function isProviderTagCacheFresh(providerKey) {
    var entry = ensureProviderTagCache(providerKey);
    var maxAgeMs = providerTagCacheMaxAgeMs(providerKey);
    if (maxAgeMs <= 0)
      return (entry.index || []).length > 0;
    var ageMs = Date.now() - Number(entry.timestamp || 0);
    return ageMs >= 0 && ageMs < maxAgeMs;
  }

  function normalizeTagSuggestions(suggestions) {
    return (suggestions || []).map(function (item) {
      var source = String(item && item.source || "");
      return {
        "name": String(item && item.name || ""),
        "count": Math.max(0, parseInt(item && item.count || 0, 10) || 0),
        "source": source
      };
    }).filter(function (item) {
      return item.name !== "" && (item.source === "history" || item.count > 0);
    });
  }

  function dedupeTagSuggestions(suggestions) {
    var seen = {};
    return normalizeTagSuggestions(suggestions).filter(function (item) {
      var key = String(item.name || "").toLowerCase();
      if (seen[key])
        return false;
      seen[key] = true;
      return true;
    });
  }

  function normalizedRecentSearchTags(tags) {
    var limit = Math.max(0, parseInt(recentSearchTagLimit || 0, 10) || 0);
    var seen = {};
    var results = [];
    (tags || []).forEach(function (tag) {
      var value = String(tag || "").trim();
      if (value === "")
        return;
      var key = value.toLowerCase();
      if (seen[key])
        return;
      seen[key] = true;
      results.push(value);
    });
    if (limit > 0 && results.length > limit)
      results = results.slice(0, limit);
    return results;
  }

  function recentTagSuggestions() {
    return normalizedRecentSearchTags(recentSearchTags).map(function (tag) {
      return {
        "name": tag,
        "count": 0,
        "source": "history"
      };
    });
  }

  function recordRecentSearchTags(text) {
    var tags = splitTags(text).filter(function (tag) {
      return String(tag || "").indexOf(":") === -1;
    });
    if (tags.length === 0)
      return;

    var merged = tags.concat(recentSearchTags || []);
    recentSearchTags = normalizedRecentSearchTags(merged);
  }

  function normalizedTagWords(text) {
    return String(text || "").toLowerCase().replace(/[^a-z0-9_\s]+/g, " ").split(/[\s_]+/).filter(function (part) {
      return part.length > 0;
    });
  }

  function compactTagText(text) {
    return String(text || "").toLowerCase().replace(/[^a-z0-9]+/g, "");
  }

  function isSubsequenceMatch(query, target) {
    var left = String(query || "");
    var right = String(target || "");
    if (left.length === 0)
      return true;
    var li = 0;
    for (var ri = 0; ri < right.length && li < left.length; ++ri) {
      if (left.charAt(li) === right.charAt(ri))
        li += 1;
    }
    return li === left.length;
  }

  function sharedPrefixLength(a, b) {
    var left = String(a || "");
    var right = String(b || "");
    var maxLen = Math.min(left.length, right.length);
    var count = 0;
    while (count < maxLen && left.charAt(count) === right.charAt(count))
      count += 1;
    return count;
  }

  function levenshteinDistance(a, b) {
    var left = String(a || "");
    var right = String(b || "");
    if (left === right)
      return 0;
    if (left.length === 0)
      return right.length;
    if (right.length === 0)
      return left.length;

    var i;
    var j;
    var row = [];
    for (j = 0; j <= right.length; ++j)
      row.push(j);

    for (i = 1; i <= left.length; ++i) {
      var prev = i - 1;
      row[0] = i;
      for (j = 1; j <= right.length; ++j) {
        var old = row[j];
        var cost = left.charAt(i - 1) === right.charAt(j - 1) ? 0 : 1;
        row[j] = Math.min(row[j] + 1, row[j - 1] + 1, prev + cost);
        prev = old;
      }
    }

    return row[right.length];
  }

  function buildPreparedTagEntry(item) {
    var name = String(item && item.name || "");
    var normalizedName = name.toLowerCase();
    var compactName = compactTagText(normalizedName);
    var words = normalizedTagWords(normalizedName);
    return {
      "name": name,
      "count": Math.max(0, parseInt(item && item.count || 0, 10) || 0),
      "normalizedName": normalizedName,
      "compactName": compactName,
      "words": words,
      "initials": words.map(function (part) { return part.charAt(0); }).join("")
    };
  }

  function providerIndexMarker(providerKey) {
    var entry = ensureProviderTagCache(providerKey);
    return String(providerKey || "") + ":" + String(entry.timestamp || 0) + ":" + String((entry.index || []).length);
  }

  function preparedProviderIndex(providerKey) {
    var key = String(providerKey || provider || "");
    var marker = providerIndexMarker(key);
    var cache = preparedTagIndexCache || ({});
    var existing = cache[key];
    if (existing && existing.marker === marker)
      return existing.items || [];

    var entry = ensureProviderTagCache(key);
    var items = normalizeTagSuggestions(entry.index || []).map(function (item) {
      return buildPreparedTagEntry(item);
    });

    cache[key] = {
      "marker": marker,
      "items": items
    };
    preparedTagIndexCache = cache;

    var searchCache = localSuggestionSearchCache || ({});
    searchCache[key] = {
      "marker": marker,
      "queries": {}
    };
    localSuggestionSearchCache = searchCache;
    return items;
  }

  function queryFeatures(query) {
    var normalizedQuery = String(query || "").toLowerCase();
    return {
      "normalized": normalizedQuery,
      "compact": compactTagText(normalizedQuery),
      "words": normalizedTagWords(normalizedQuery)
    };
  }

  function preparedTagMatchInfo(prepared, features) {
    var normalizedQuery = features.normalized;
    var compactQuery = features.compact;
    var queryWords = features.words;
    if (normalizedQuery === "" || compactQuery === "" || !prepared || prepared.count <= 0)
      return null;

    var exact = (prepared.normalizedName === normalizedQuery || prepared.compactName === compactQuery) ? 1 : 0;
    var startsWith = (prepared.normalizedName.indexOf(normalizedQuery) === 0 || prepared.compactName.indexOf(compactQuery) === 0) ? 1 : 0;
    var contains = (prepared.normalizedName.indexOf(normalizedQuery) !== -1 || prepared.compactName.indexOf(compactQuery) !== -1) ? 1 : 0;
    var initialsMatch = compactQuery.length >= 2 && prepared.initials.indexOf(compactQuery) === 0 ? 1 : 0;
    var subsequence = compactQuery.length >= 3 && isSubsequenceMatch(compactQuery, prepared.compactName) ? 1 : 0;
    var wordPrefixMatches = 0;
    var wordContainsMatches = 0;
    for (var i = 0; i < queryWords.length; ++i) {
      var matchedPrefix = false;
      var matchedContains = false;
      for (var j = 0; j < prepared.words.length; ++j) {
        if (prepared.words[j].indexOf(queryWords[i]) === 0) {
          matchedPrefix = true;
          break;
        }
        if (!matchedContains && prepared.words[j].indexOf(queryWords[i]) !== -1)
          matchedContains = true;
      }
      if (matchedPrefix)
        wordPrefixMatches += 1;
      else if (matchedContains)
        wordContainsMatches += 1;
    }

    if (!exact && !startsWith && !contains && !initialsMatch && !subsequence && wordPrefixMatches === 0 && wordContainsMatches === 0)
      return null;

    return {
      "exact": exact,
      "startsWith": startsWith,
      "contains": contains,
      "initialsMatch": initialsMatch,
      "subsequence": subsequence,
      "wordPrefixMatches": wordPrefixMatches,
      "wordContainsMatches": wordContainsMatches
    };
  }

  function cheapPreparedTagScore(prepared, features, matchInfo) {
    var compactQuery = features.compact;
    var countBonus = Math.min(18, Math.log(Math.max(1, Number(prepared.count || 0))) / Math.log(10) * 5);
    return matchInfo.exact * 2000
      + matchInfo.startsWith * 1200
      + matchInfo.contains * 720
      + matchInfo.wordPrefixMatches * 420
      + matchInfo.wordContainsMatches * 160
      + matchInfo.initialsMatch * 220
      + matchInfo.subsequence * 100
      + sharedPrefixLength(prepared.compactName, compactQuery) * 30
      - Math.abs(prepared.compactName.length - compactQuery.length) * 0.35
      + countBonus;
  }

  function detailedPreparedTagScore(prepared, features, baseScore) {
    var compactQuery = features.compact;
    var distance = levenshteinDistance(prepared.compactName.slice(0, Math.min(prepared.compactName.length, compactQuery.length + 8)), compactQuery);
    var bestWordDistance = 999;
    for (var i = 0; i < prepared.words.length; ++i)
      bestWordDistance = Math.min(bestWordDistance, levenshteinDistance(prepared.words[i], compactQuery));
    if (bestWordDistance === 999)
      bestWordDistance = compactQuery.length;
    return baseScore - distance * 8 - bestWordDistance * 18;
  }

  function rankTagSuggestions(query, suggestions, maxResults) {
    var features = queryFeatures(query);
    return dedupeTagSuggestions(suggestions).map(function (item) {
      var prepared = buildPreparedTagEntry(item);
      var matchInfo = preparedTagMatchInfo(prepared, features);
      if (!matchInfo)
        return null;
      var baseScore = cheapPreparedTagScore(prepared, features, matchInfo);
      return {
        "name": prepared.name,
        "count": prepared.count,
        "score": detailedPreparedTagScore(prepared, features, baseScore)
      };
    }).filter(function (item) {
      return item !== null;
    }).sort(function (left, right) {
      if (right.score !== left.score)
        return right.score - left.score;
      if (right.count !== left.count)
        return right.count - left.count;
      return left.name.localeCompare(right.name);
    }).slice(0, Math.max(1, maxResults || 12)).map(function (item) {
      return {
        "name": item.name,
        "count": item.count
      };
    });
  }

  function localTagCandidates(providerKey, query) {
    var normalizedQuery = String(query || "").toLowerCase();
    var features = queryFeatures(normalizedQuery);
    if (features.compact === "")
      return [];

    var key = String(providerKey || provider || "");
    var marker = providerIndexMarker(key);
    var searchCache = localSuggestionSearchCache || ({});
    if (!searchCache[key] || searchCache[key].marker !== marker)
      searchCache[key] = { "marker": marker, "queries": {} };

    var cached = searchCache[key].queries[normalizedQuery];
    if (cached)
      return cached;

    var preparedItems = preparedProviderIndex(key);
    if (preparedItems.length === 0)
      return [];

    var ranked = [];
    var seen = {};
    var shortlistLimit = 120;

    function pushRanked(prepared, score) {
      var seenKey = prepared.normalizedName;
      if (seen[seenKey])
        return;
      seen[seenKey] = true;
      ranked.push({
        "prepared": prepared,
        "score": score
      });
      ranked.sort(function (left, right) {
        if (right.score !== left.score)
          return right.score - left.score;
        if (right.prepared.count !== left.prepared.count)
          return right.prepared.count - left.prepared.count;
        return left.prepared.name.localeCompare(right.prepared.name);
      });
      if (ranked.length > shortlistLimit)
        ranked.pop();
    }

    for (var i = 0; i < preparedItems.length; ++i) {
      var prepared = preparedItems[i];
      var matchInfo = preparedTagMatchInfo(prepared, features);
      if (!matchInfo)
        continue;
      pushRanked(prepared, cheapPreparedTagScore(prepared, features, matchInfo));
    }

    if (ranked.length < 10 && features.compact.length >= 4) {
      for (var j = 0; j < preparedItems.length; ++j) {
        var fallbackPrepared = preparedItems[j];
        if (seen[fallbackPrepared.normalizedName])
          continue;
        if (fallbackPrepared.compactName.charAt(0) !== features.compact.charAt(0) && fallbackPrepared.initials.charAt(0) !== features.compact.charAt(0))
          continue;
        var prefixDistance = levenshteinDistance(fallbackPrepared.compactName.slice(0, Math.min(fallbackPrepared.compactName.length, features.compact.length + 3)), features.compact);
        if (prefixDistance > Math.max(2, Math.floor(features.compact.length / 4)))
          continue;
        pushRanked(fallbackPrepared, 120 - prefixDistance * 14 + Math.min(12, Math.log(Math.max(1, fallbackPrepared.count)) / Math.log(10) * 4));
      }
    }

    var results = ranked.slice(0, 48).map(function (item) {
      return {
        "name": item.prepared.name,
        "count": item.prepared.count,
        "score": detailedPreparedTagScore(item.prepared, features, item.score)
      };
    }).sort(function (left, right) {
      if (right.score !== left.score)
        return right.score - left.score;
      if (right.count !== left.count)
        return right.count - left.count;
      return left.name.localeCompare(right.name);
    }).slice(0, 12).map(function (item) {
      return {
        "name": item.name,
        "count": item.count
      };
    });

    searchCache[key].queries[normalizedQuery] = results;
    localSuggestionSearchCache = searchCache;
    return results;
  }

  function ensureFreshProviderTagIndex() {
    if (!tagCacheReady)
      return;
    if (!shouldRefreshProviderTagIndex(provider))
      return;
    var entry = ensureProviderTagCache(provider);
    if (isProviderTagCacheFresh(provider) && entry.index && entry.index.length > 0)
      return;
    booruService.fetchProviderTagIndex(provider);
  }

  function ensureWorkerProviderIndex(providerKey) {
    var resolvedProviderKey = String(providerKey || provider || "");
    if (resolvedProviderKey === "")
      return;
    var marker = providerIndexMarker(resolvedProviderKey);
    var markers = workerIndexMarkers || ({});
    if (markers[resolvedProviderKey] === marker)
      return;
    tagSuggestionWorker.sendMessage({
      "type": "setIndex",
      "providerKey": resolvedProviderKey,
      "marker": marker,
      "suggestions": dedupeTagSuggestions(ensureProviderTagCache(resolvedProviderKey).index || [])
    });
    markers[resolvedProviderKey] = marker;
    workerIndexMarkers = JSON.parse(JSON.stringify(markers));
  }

  function requestAsyncTagSuggestions(query, seedSuggestions) {
    ensureWorkerProviderIndex(provider);
    tagSuggestionRequestSerial += 1;
    tagSuggestionWorker.sendMessage({
      "type": "query",
      "requestId": tagSuggestionRequestSerial,
      "providerKey": provider,
      "query": String(query || "").toLowerCase(),
      "seedSuggestions": dedupeTagSuggestions(seedSuggestions || [])
    });
  }

  function applyTagSuggestions(query, suggestions, fromCache) {
    var context = tagContext(searchInput ? searchInput.text : searchText, searchInput ? searchInput.cursorPosition : -1);
    if (context.normalized !== String(query || "").toLowerCase())
      return;

    if (!fromCache) {
      var cache = ensureProviderTagCache(provider);
      if (!isProviderTagCacheFresh(provider))
        cache.queries = {};
      cache.timestamp = Date.now();
      cache.queries[context.normalized] = dedupeTagSuggestions(suggestions);
      tagCompletionCache = JSON.parse(JSON.stringify(tagCompletionCache));
      saveTagCacheTimer.restart();
    }

    requestAsyncTagSuggestions(context.normalized, suggestions);
  }

  function updateTagSuggestions() {
    if (!searchInput)
      return;

    if (!suggestionPopupRequested) {
      closeSuggestionPopup(true);
      return;
    }

    var context = tagContext(searchInput.text, searchInput.cursorPosition);
    if (context.query.indexOf(":") !== -1) {
      closeSuggestionPopup(true);
      return;
    }

    if (context.query.length === 0) {
      var recentSuggestions = recentTagSuggestions();
      if (recentSuggestions.length === 0) {
        closeSuggestionPopup(true);
        return;
      }
      activeSuggestionQuery = "";
      activeSuggestionIndex = 0;
      tagSuggestions = recentSuggestions;
      ensureActiveSuggestionVisible();
      return;
    }

    if (context.query.length < 2) {
      closeSuggestionPopup(true);
      return;
    }

    var cache = ensureProviderTagCache(provider);
    if (!isProviderTagCacheFresh(provider)) {
      cache.queries = {};
      ensureFreshProviderTagIndex();
    }

    var cached = cache.queries[context.normalized] || [];
    requestAsyncTagSuggestions(context.normalized, cached);

    if (cached.length === 0 && (!cache.index || cache.index.length === 0)) {
      booruService.currentProvider = provider;
      booruService.triggerTagSearch(context.query);
    }
  }

  function closeSuggestionPopup(clearSuggestions) {
    suggestionPopupRequested = false;
    tagSuggestionRequestSerial += 1;
    if (clearSuggestions === undefined || clearSuggestions) {
      tagSuggestions = [];
      activeSuggestionQuery = "";
      activeSuggestionIndex = 0;
    }
  }

  function applySuggestion(index) {
    if (!searchInput || tagSuggestions.length === 0)
      return false;

    var normalizedIndex = Math.max(0, Math.min(index, tagSuggestions.length - 1));
    var suggestion = tagSuggestions[normalizedIndex];
    var context = tagContext(searchInput.text, searchInput.cursorPosition);
    if (!suggestion || !suggestion.name)
      return false;

    if (context.query.length === 0 && String(searchInput.text || "").trim() !== "")
      return false;

    var before = searchInput.text.slice(0, context.start);
    var after = searchInput.text.slice(context.end);
    var replacement = context.prefix + suggestion.name;
    var spacer = after.length > 0 && after.charAt(0) === " " ? "" : " ";
    searchInput.text = before + replacement + spacer + after;
    searchInput.cursorPosition = (before + replacement + spacer).length;
    closeSuggestionPopup(true);
    return true;
  }

  function ensureActiveSuggestionVisible() {
    if (typeof tagSuggestionList === "undefined" || !tagSuggestionList || tagSuggestions.length === 0)
      return;
    var targetIndex = Math.max(0, Math.min(activeSuggestionIndex, tagSuggestions.length - 1));
    Qt.callLater(function () {
      if (tagSuggestionList)
        tagSuggestionList.positionViewAtIndex(targetIndex, ListView.Contain);
    });
  }

  function moveSuggestionSelection(delta) {
    if (tagSuggestions.length === 0)
      return;
    var total = tagSuggestions.length;
    activeSuggestionIndex = (activeSuggestionIndex + delta + total) % total;
    ensureActiveSuggestionVisible();
  }

  function resetScrollPosition() {
    scrollContentY = 0;
    if (typeof imageFlickable !== "undefined" && imageFlickable)
      imageFlickable.contentY = 0;
    else if (scrollArea && scrollArea.contentItem)
      scrollArea.contentItem.contentY = 0;
  }

  function imageTagList(imageData) {
    if (!imageData || imageData.tags === undefined || imageData.tags === null)
      return [];
    if (imageData.tags instanceof Array)
      return imageData.tags.map(function (tag) { return String(tag || "").trim(); }).filter(function (tag) { return tag.length > 0; });
    return String(imageData.tags || "").split(/\s+/).map(function (tag) { return String(tag || "").trim(); }).filter(function (tag) { return tag.length > 0; });
  }

  function replaceSearchWithTag(tag) {
    var normalizedTag = String(tag || "").trim();
    if (normalizedTag === "" || !searchInput)
      return;
    searchInput.text = normalizedTag;
    searchInput.cursorPosition = normalizedTag.length;
    searchInput.forceActiveFocus();
    closeSuggestionPopup(true);
    syncState();
  }

  function appendTagToSearch(tag) {
    var normalizedTag = String(tag || "").trim();
    if (normalizedTag === "" || !searchInput)
      return;
    var tags = splitTags(searchInput.text);
    if (tags.indexOf(normalizedTag) === -1)
      tags.push(normalizedTag);
    var nextText = tags.join(" ");
    searchInput.text = nextText;
    searchInput.cursorPosition = nextText.length;
    searchInput.forceActiveFocus();
    closeSuggestionPopup(true);
    syncState();
  }

  function restoreScrollPosition() {
    if (typeof imageFlickable !== "undefined" && imageFlickable)
      imageFlickable.contentY = scrollContentY;
    else if (scrollArea && scrollArea.contentItem)
      scrollArea.contentItem.contentY = scrollContentY;
  }

  function loadTagCache() {
    if (!tagCacheFile) {
      tagCacheReady = true;
      return;
    }
    var content = tagCacheFile.text();
    if (!content || String(content).trim() === "") {
      tagCacheReady = true;
      return;
    }
    try {
      var parsed = JSON.parse(content);
      if (parsed && typeof parsed === "object")
        tagCompletionCache = parsed;
    } catch (error) {
      console.log("[Booru] Failed to parse tag cache:", error);
    }
    tagCacheReady = true;
    Qt.callLater(function () {
      root.ensureWorkerProviderIndex(root.provider);
    });
  }

  function loadBooruStateCache() {
    if (!booruStateFile) {
      booruStateCacheReady = true;
      restoreStateFromMain();
      return;
    }
    var content = booruStateFile.text();
    if (!content || String(content).trim() === "") {
      booruStateCacheReady = true;
      restoreStateFromMain();
      return;
    }
    try {
      var parsed = JSON.parse(content);
      if (parsed && typeof parsed === "object")
        applyPersistedState(parsed);
    } catch (error) {
      console.log("[Booru] Failed to parse booru state cache:", error);
      restoreStateFromMain();
    }
    booruStateCacheReady = true;
  }

  function saveTagCache() {
    if (!tagCachePath)
      return;
    try {
      if (cacheDir)
        Quickshell.execDetached(["mkdir", "-p", cacheDir]);
      tagCacheFile.setText(JSON.stringify(tagCompletionCache, null, 2));
    } catch (error) {
      console.log("[Booru] Failed to save tag cache:", error);
    }
  }

  function saveBooruStateCache() {
    if (!booruStateCachePath)
      return;
    try {
      if (cacheDir)
        Quickshell.execDetached(["mkdir", "-p", cacheDir]);
      booruStateFile.setText(JSON.stringify({
        "provider": provider,
        "safeOnly": safeOnly,
        "randomOrder": randomOrder,
        "searchText": searchText,
        "pageNumber": pageNumber,
        "lastQueryRandomOrder": lastQueryRandomOrder,
        "scrollContentY": scrollContentY,
        "recentSearchTags": recentSearchTags,
        "response": persistedResponse
      }, null, 2));
    } catch (error) {
      console.log("[Booru] Failed to save booru state cache:", error);
    }
  }

  function serializeResponse(response) {
    if (!response)
      return null;
    return {
      "provider": String(response.provider || root.provider),
      "tags": (response.tags || []).slice ? response.tags.slice() : (response.tags || []),
      "page": parseInt(response.page || 1, 10),
      "images": (response.images || []).map(function (image) {
        return {
          "provider": image.provider || response.provider || root.provider,
          "id": image.id,
          "width": image.width,
          "height": image.height,
          "aspect_ratio": image.aspect_ratio,
          "tags": image.tags,
          "rating": image.rating,
          "is_nsfw": image.is_nsfw,
          "md5": image.md5,
          "preview_url": image.preview_url,
          "sample_url": image.sample_url,
          "file_url": image.file_url,
          "file_ext": image.file_ext,
          "source": image.source
        };
      }),
      "message": String(response.message || "")
    };
  }

  function applyPersistedState(state) {
    if (!state || _syncingState)
      return;

    _syncingState = true;
    if (state.provider !== undefined)
      provider = state.provider;
    if (state.safeOnly !== undefined)
      safeOnly = state.safeOnly;
    if (state.randomOrder !== undefined)
      randomOrder = state.randomOrder;
    if (state.searchText !== undefined)
      searchText = state.searchText;
    if (state.pageNumber !== undefined)
      pageNumber = Math.max(1, parseInt(state.pageNumber || 1, 10));
    if (state.lastQueryRandomOrder !== undefined)
      lastQueryRandomOrder = state.lastQueryRandomOrder === true;
    if (state.scrollContentY !== undefined)
      scrollContentY = Number(state.scrollContentY || 0);
    if (state.recentSearchTags !== undefined)
      recentSearchTags = normalizedRecentSearchTags(state.recentSearchTags);
    persistedResponse = state.response || null;
    if (searchInput)
      searchInput.text = searchText;
    if (pageSpinBox)
      pageSpinBox.value = pageNumber;
    booruService.currentProvider = provider;
    ensureFreshProviderTagIndex();
    _syncingState = false;
    Qt.callLater(restoreScrollPosition);
  }

  function restoreStateFromMain() {
    if (!mainInstance || !mainInstance.booruState || _syncingState)
      return;
    applyPersistedState(mainInstance.booruState);
  }

  function syncState() {
    if (_syncingState)
      return;

    _syncingState = true;
    var nextState = {
      "provider": provider,
      "safeOnly": safeOnly,
      "randomOrder": randomOrder,
      "searchText": searchText,
      "pageNumber": pageNumber,
      "lastQueryRandomOrder": lastQueryRandomOrder,
      "scrollContentY": scrollContentY,
      "recentSearchTags": recentSearchTags,
      "response": persistedResponse
    };
    if (mainInstance) {
      mainInstance.booruState = nextState;
      if (mainInstance.saveState)
        mainInstance.saveState();
    }
    saveBooruStateTimer.restart();
    _syncingState = false;
  }

  function latestResponse() {
    if (booruService.responses && booruService.responses.length > 0)
      return booruService.responses[booruService.responses.length - 1];
    return persistedResponse;
  }

  function currentImages() {
    var response = latestResponse();
    return response && response.images ? response.images : [];
  }

  function currentMessage() {
    var response = latestResponse();
    return response ? String(response.message || "") : "";
  }

  function providerKeyForImage(imageData) {
    return imageData && imageData.provider ? imageData.provider : (latestResponse() && latestResponse().provider ? latestResponse().provider : provider);
  }

  function providerNameFromKey(key) {
    return booruService.providers[key] ? booruService.providers[key].name : String(key || "");
  }

  function displayProviderName() {
    var response = latestResponse();
    return providerNameFromKey(response && response.provider ? response.provider : provider);
  }

  function shortTags(tags) {
    var text = String(tags || "");
    if (text.length <= 80)
      return text;
    return text.slice(0, 77) + "...";
  }

  function extensionFor(imageData) {
    if (imageData.file_ext && String(imageData.file_ext).trim() !== "")
      return String(imageData.file_ext).replace(/^\./, "");
    var raw = String(imageData.file_url || imageData.sample_url || imageData.preview_url || "");
    raw = raw.split("?")[0];
    var idx = raw.lastIndexOf(".");
    if (idx !== -1)
      return raw.slice(idx + 1);
    return "jpg";
  }

  function imagePath(imageData) {
    var imageProvider = providerKeyForImage(imageData);
    return saveDirectory + "/" + imageProvider + "-" + imageData.id + "." + extensionFor(imageData);
  }

  function imageKey(imageData) {
    return providerKeyForImage(imageData) + ":" + imageData.id;
  }

  function isImageQueued(imageData) {
    if (!imageData)
      return false;
    return (queuedKeys[imageKey(imageData)] || 0) > 0;
  }

  function savedKeyFromFilename(fileName) {
    var match = String(fileName || "").match(/^([a-z0-9_+-]+)-(\d+)\./i);
    if (!match)
      return "";
    return String(match[1]).toLowerCase() + ":" + String(match[2]);
  }

  function isImageSaved(imageData) {
    if (!imageData)
      return false;
    var key = imageKey(imageData);
    if (savedImageKeys[key])
      return true;
    var path = imagePath(imageData);
    return !!savedImagePaths[path];
  }

  function savedImagePath(imageData) {
    if (!imageData)
      return "";
    var key = imageKey(imageData);
    if (savedImageResolvedPaths[key])
      return String(savedImageResolvedPaths[key]);
    var path = imagePath(imageData);
    if (savedImagePaths[path])
      return path;
    return "";
  }

  function markImageSaved(imageData, filePath) {
    if (!imageData)
      return;
    var key = imageKey(imageData);
    var nextKeys = Object.assign({}, savedImageKeys);
    nextKeys[key] = true;
    savedImageKeys = nextKeys;

    var normalizedPath = String(filePath || imagePath(imageData));
    var nextPaths = Object.assign({}, savedImagePaths);
    nextPaths[normalizedPath] = true;
    savedImagePaths = nextPaths;

    var nextResolvedPaths = Object.assign({}, savedImageResolvedPaths);
    nextResolvedPaths[key] = normalizedPath;
    savedImageResolvedPaths = nextResolvedPaths;
  }

  function scheduleSavedImageScan() {
    savedImageScanPending = true;
    savedImageScanTimer.restart();
  }

  function scanSavedImages() {
    savedImageScanPending = false;
    if (saveDirectory === "") {
      savedImageKeys = ({})
      savedImagePaths = ({})
      savedImageResolvedPaths = ({})
      return;
    }
    if (scanSavedImagesProcess.running) {
      savedImageScanPending = true;
      return;
    }

    scanSavedImagesProcess.command = [
      "sh", "-lc",
      'dir="$1"; [ -n "$dir" ] || exit 0; [ -d "$dir" ] || exit 0; find "$dir" -maxdepth 1 -type f \( -name "yandere-*.*" -o -name "konachan-*.*" -o -name "danbooru-*.*" \) -printf "%f\n" 2>/dev/null',
      "sh", saveDirectory
    ];
    scanSavedImagesProcess.running = true;
  }

  function search(resetPage) {
    if (resetPage === true || randomOrder)
      pageNumber = 1;

    resetScrollPosition();
    booruService.clearResponses();
    booruService.currentProvider = provider;
    lastQueryRandomOrder = randomOrder;
    hideContextMenu();
    recordRecentSearchTags(searchText);
    syncState();
    booruService.makeRequest(splitTags(searchText), !safeOnly, pageSize, pageNumber, randomOrder);
  }

  function goToPage(targetPage) {
    var normalized = parseInt(targetPage, 10);
    if (isNaN(normalized) || normalized < 1)
      normalized = 1;
    pageNumber = normalized;
    resetScrollPosition();
    syncState();
    search(false);
  }

  function enqueueJob(imageData, setWallpaperAfterSave) {
    if (!imageData)
      return;

    var key = imageKey(imageData);
    queuedKeys[key] = (queuedKeys[key] || 0) + 1;
    queuedKeys = JSON.parse(JSON.stringify(queuedKeys));
    saveQueue = saveQueue.concat([{
      "image": imageData,
      "setWallpaper": setWallpaperAfterSave === true,
      "key": key
    }]);
    processNextQueueJob();
  }

  function beginSave(imageData, setWallpaperAfterSave) {
    enqueueJob(imageData, setWallpaperAfterSave === true);
  }

  function processNextQueueJob() {
    if (queueRunning || saveQueue.length === 0)
      return;

    activeQueueJob = saveQueue[0];
    saveQueue = saveQueue.slice(1);
    queueRunning = true;
    lastProcessError = "";
    pendingSetWallpaperAfterSave = activeQueueJob.setWallpaper;
    pendingFilePath = imagePath(activeQueueJob.image);

    if (pendingSetWallpaperAfterSave && isImageSaved(activeQueueJob.image)) {
      var localSavedPath = savedImagePath(activeQueueJob.image);
      if (localSavedPath !== "")
        pendingFilePath = localSavedPath;
      pendingSetWallpaperAfterSave = false;
      wallpaperProcess.command = buildWallpaperCommand(pendingFilePath);
      console.log("[Booru] Running wallpaper command:", JSON.stringify(wallpaperProcess.command));
      wallpaperProcess.running = true;
      return;
    }

    var sourceUrl = activeQueueJob.image.file_url || activeQueueJob.image.sample_url || activeQueueJob.image.preview_url;
    downloadProcess.command = [
      "sh", "-lc",
      'mkdir -p "$1" && curl -L --fail --silent --show-error -A "$4" -o "$2" "$3"',
      "sh", saveDirectory, pendingFilePath, sourceUrl, booruService.defaultUserAgent
    ];
    downloadProcess.running = true;
  }

  function finishQueueJob() {
    if (activeQueueJob && activeQueueJob.key) {
      var left = (queuedKeys[activeQueueJob.key] || 0) - 1;
      if (left > 0)
        queuedKeys[activeQueueJob.key] = left;
      else
        delete queuedKeys[activeQueueJob.key];
      queuedKeys = JSON.parse(JSON.stringify(queuedKeys));
    }

    activeQueueJob = null;
    queueRunning = false;
    pendingSetWallpaperAfterSave = false;
    pendingFilePath = "";
    processNextQueueJob();
  }

  function buildWallpaperCommand(filePath) {
    var commandText = (wallpaperCommand || "").trim();
    if (commandText === "")
      commandText = 'qs -c noctalia-shell ipc call wallpaper set {file} ""';

    if (commandText === 'qs -c noctalia-shell ipc call wallpaper set {file}' || commandText === 'noctalia-shell ipc call wallpaper set {file}' || commandText === 'qs ipc call wallpaper set {file}')
      commandText += ' ""';

    if (commandText.indexOf("{file}") !== -1)
      commandText = commandText.split("{file}").join('"$1"');
    else
      commandText = commandText + ' "$1"';

    return ["sh", "-lc", commandText, "sh", filePath];
  }

  function booruPostUrl(imageData) {
    if (!imageData)
      return "";
    var key = providerKeyForImage(imageData);
    var providerInfo = booruService.providers[key];
    if (!providerInfo)
      return "";
    var template = String(providerInfo.postUrlTemplate || "");
    if (template !== "")
      return template.split("{{id}}").join(String(imageData.id));
    var base = String(providerInfo.url || "");
    if (base === "")
      return "";
    return base + "/post/show/" + imageData.id;
  }

  function openBooruPage(imageData) {
    var url = booruPostUrl(imageData);
    if (url !== "")
      Qt.openUrlExternally(url);
  }

  function showContextMenu(imageData, x, y) {
    contextImage = imageData;
    var menuWidth = 240;
    var menuHeight = 220;
    contextMenuX = Math.max(0, Math.min(root.width - menuWidth - Style.marginS, x));
    contextMenuY = Math.max(0, Math.min(root.height - menuHeight - Style.marginS, y));
    contextMenuVisible = true;
  }

  function hideContextMenu() {
    contextMenuVisible = false;
    contextImage = null;
  }

  function openInViewer(imageData) {
    if (!imageData || viewerBusy)
      return;

    viewerBusy = true;
    lastProcessError = "";
    hideContextMenu();

    var sourceUrl = imageData.file_url || imageData.sample_url || imageData.preview_url;
    var ext = extensionFor(imageData);
    openViewerProcess.command = [
      "sh", "-lc",
      'tmp="${XDG_RUNTIME_DIR:-/tmp}/anime-corner-booru-$4-$5.$1" && curl -L --fail --silent --show-error -A "$3" -o "$tmp" "$2" && (xdg-open "$tmp" >/dev/null 2>&1 &)',
      "sh", ext, sourceUrl, booruService.defaultUserAgent, providerKeyForImage(imageData), String(imageData.id)
    ];
    openViewerProcess.running = true;
  }

  Component {
    id: imageCardComponent

    Rectangle {
      id: imageCard
      property var imageData: null
      property bool imageQueued: !!root.isImageQueued(imageData)
      readonly property real innerWidth: Math.max(width - Style.marginS * 2, 1)
      readonly property real fallbackThumbnailHeight: Math.max(110, innerWidth * 0.62)
      readonly property real aspectThumbnailHeight: {
        var imageWidth = Number(imageData && imageData.width || 0);
        var imageHeight = Number(imageData && imageData.height || 0);
        if (imageWidth > 0 && imageHeight > 0)
          return Math.max(110, innerWidth * imageHeight / imageWidth);
        return fallbackThumbnailHeight;
      }
      readonly property real thumbnailHeight: root.variableCardSize ? aspectThumbnailHeight : fallbackThumbnailHeight

      width: 240
      height: implicitHeight
      implicitHeight: contentColumn.implicitHeight + Style.marginS * 2
      radius: Style.radiusS
      color: Color.mSurfaceVariant
      border.color: Color.mOutline
      border.width: 1
      clip: true

      Behavior on x {
        NumberAnimation {
          duration: 140
          easing.type: Easing.OutCubic
        }
      }

      Behavior on y {
        NumberAnimation {
          duration: 140
          easing.type: Easing.OutCubic
        }
      }

      Behavior on height {
        NumberAnimation {
          duration: 120
          easing.type: Easing.OutCubic
        }
      }

      onImplicitHeightChanged: Qt.callLater(function() {
        if (typeof imageMasonry !== "undefined" && imageMasonry)
          imageMasonry.scheduleRelayout();
      })

      ColumnLayout {
        id: contentColumn
        x: Style.marginS
        y: Style.marginS
        width: parent.width - Style.marginS * 2
        spacing: Style.marginS

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: parent.parent.thumbnailHeight
          radius: Style.radiusS
          color: Color.mSurface
          clip: true

          Image {
            id: thumbImage
            anchors.fill: parent
            anchors.margins: 1
            source: (imageCard.imageData && (imageCard.imageData.preview_url || imageCard.imageData.sample_url || imageCard.imageData.file_url)) || ""
            asynchronous: true
            cache: true
            fillMode: root.variableCardSize ? Image.PreserveAspectFit : Image.PreserveAspectCrop
            smooth: true
          }

          Rectangle {
            anchors.fill: parent
            color: Color.mSurface
            opacity: thumbImage.status === Image.Ready ? 0 : 0.92
            visible: thumbImage.status === Image.Loading || thumbImage.status === Image.Null || thumbImage.status === Image.Error

            ColumnLayout {
              anchors.centerIn: parent
              spacing: Style.marginS

              NIcon {
                Layout.alignment: Qt.AlignHCenter
                icon: thumbImage.status === Image.Error ? "image-off" : "loader-2"
                color: Color.mOnSurfaceVariant
                pointSize: Style.fontSizeL
                applyUiScale: false

                RotationAnimation on rotation {
                  from: 0
                  to: 360
                  duration: 900
                  loops: Animation.Infinite
                  running: thumbImage.status === Image.Loading
                }
              }
            }
          }

          MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
              if (mouse.button === Qt.RightButton) {
                var point = mapToItem(root, mouse.x, mouse.y);
                if (imageCard.imageData)
                  root.showContextMenu(imageCard.imageData, point.x + 4, point.y + 4);
                return;
              }
              if (imageCard.imageData)
                root.selectedImage = imageCard.imageData;
              root.previewOpen = true;
            }
          }
        }

        NText {
          id: tagTextLabel
          Layout.fillWidth: true
          text: root.shortTags((imageCard.imageData && imageCard.imageData.tags) || "")
          color: Color.mOnSurface
          pointSize: Style.fontSizeXS
          applyUiScale: false
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginS

          NText {
            text: ((imageCard.imageData && imageCard.imageData.width) || 0) + "×" + ((imageCard.imageData && imageCard.imageData.height) || 0)
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeXS
            applyUiScale: false
          }

          NText {
            text: String((imageCard.imageData && imageCard.imageData.rating) || "s").toUpperCase()
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeXS
            applyUiScale: false
            Layout.fillWidth: true
          }

          NIcon {
            visible: imageCard.imageQueued
            icon: "loader-2"
            color: Color.mPrimary
            pointSize: Style.fontSizeXS
            applyUiScale: false

            RotationAnimation on rotation {
              from: 0
              to: 360
              duration: 900
              loops: Animation.Infinite
              running: imageCard.imageQueued
            }
          }
        }

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.marginXS

          NIconButton {
            icon: "download"
            tooltipText: root.isImageSaved(imageCard.imageData) ? root.trText("booru.saved", "Saved") : root.trText("booru.save", "Save")
            enabled: !imageCard.imageQueued && !root.isImageSaved(imageCard.imageData)
            onClicked: root.beginSave(imageCard.imageData, false)
          }

          NIconButton {
            icon: "image"
            tooltipText: root.trText("booru.setWallpaper", "Set as wallpaper")
            enabled: !imageCard.imageQueued
            onClicked: root.beginSave(imageCard.imageData, true)
          }

          NIconButton {
            icon: "external-link"
            tooltipText: root.trText("booru.openBooruPage", "Open post")
            onClicked: root.openBooruPage(imageCard.imageData)
          }

          Item {
            Layout.fillWidth: true
          }

          NButton {
            text: root.trText("booru.preview", "Preview")
            onClicked: {
              root.selectedImage = imageCard.imageData;
              root.previewOpen = true;
            }
          }
        }
      }
    }
  }

  Component.onCompleted: {
    booruService.currentProvider = provider;
    restoreStateFromMain();
    scheduleSavedImageScan();
  }

  onMainInstanceChanged: Qt.callLater(root.restoreStateFromMain)
  onSaveDirectoryChanged: scheduleSavedImageScan()

  Component.onDestruction: {
    syncState();
    saveTagCache();
    saveBooruStateCache();
    if (mainInstance && mainInstance.performSaveState)
      mainInstance.performSaveState();
  }

  Timer {
    id: tagSuggestionTimer
    interval: 180
    repeat: false
    onTriggered: root.updateTagSuggestions()
  }

  Timer {
    id: saveTagCacheTimer
    interval: 500
    repeat: false
    onTriggered: root.saveTagCache()
  }

  Timer {
    id: saveBooruStateTimer
    interval: 350
    repeat: false
    onTriggered: root.saveBooruStateCache()
  }

  Timer {
    id: savedImageScanTimer
    interval: 80
    repeat: false
    onTriggered: root.scanSavedImages()
  }

  FileView {
    id: tagCacheFile
    path: root.tagCachePath
    watchChanges: false

    onLoaded: {
      root.loadTagCache();
      root.ensureFreshProviderTagIndex();
    }
    onLoadFailed: function (_error) {
      root.tagCacheReady = true;
      root.ensureFreshProviderTagIndex();
    }
  }

  FileView {
    id: booruStateFile
    path: root.booruStateCachePath
    watchChanges: false

    onLoaded: root.loadBooruStateCache()
    onLoadFailed: function (_error) {
      root.booruStateCacheReady = true;
      root.restoreStateFromMain();
    }
  }

  BooruService {
    id: booruService
    currentProvider: root.provider
  }

  WorkerScript {
    id: tagSuggestionWorker
    source: "TagSuggestionWorker.js"

    onMessage: function(message) {
      if (!message || message.type !== "queryResult")
        return;
      if (message.requestId !== root.tagSuggestionRequestSerial)
        return;
      if (!root.suggestionPopupRequested)
        return;

      var context = root.tagContext(searchInput ? searchInput.text : root.searchText, searchInput ? searchInput.cursorPosition : -1);
      if (context.normalized !== String(message.query || "").toLowerCase())
        return;
      if (String(message.providerKey || "") !== String(root.provider || ""))
        return;

      root.tagSuggestions = root.normalizeTagSuggestions(message.suggestions || []);
      root.activeSuggestionQuery = context.normalized;
      root.activeSuggestionIndex = 0;
      root.ensureActiveSuggestionVisible();
    }
  }

  Connections {
    target: booruService

    function onResponseFinished() {
      var response = root.latestResponse();
      if (!response)
        return;
      root.persistedResponse = root.serializeResponse(response);
      root.syncState();
      Qt.callLater(root.restoreScrollPosition);
    }

    function onTagSuggestion(query, suggestions) {
      root.applyTagSuggestions(query, suggestions, false);
    }

    function onProviderTagIndexLoaded(providerKey, suggestions) {
      var cache = root.ensureProviderTagCache(providerKey);
      cache.timestamp = Date.now();
      cache.index = root.dedupeTagSuggestions(suggestions);
      root.tagCompletionCache = JSON.parse(JSON.stringify(root.tagCompletionCache));
      root.ensureWorkerProviderIndex(providerKey);
      saveTagCacheTimer.restart();
      if (providerKey === root.provider)
        root.updateTagSuggestions();
    }
  }

  Process {
    id: downloadProcess

    stderr: StdioCollector {
      onStreamFinished: root.lastProcessError = text || ""
    }

    onExited: function (exitCode) {
      if (exitCode === 0) {
        root.markImageSaved(root.activeQueueJob ? root.activeQueueJob.image : null, root.pendingFilePath);
        ToastService.showNotice(root.trText("booru.savedTo", "Saved to") + " " + root.pendingFilePath);
        if (root.pendingSetWallpaperAfterSave) {
          root.pendingSetWallpaperAfterSave = false;
          wallpaperProcess.command = root.buildWallpaperCommand(root.pendingFilePath);
          console.log("[Booru] Running wallpaper command:", JSON.stringify(wallpaperProcess.command));
          wallpaperProcess.running = true;
          return;
        }
      } else {
        ToastService.showError(root.lastProcessError.trim() !== "" ? root.lastProcessError.trim() : root.trText("booru.saveFailed", "Failed to save image"));
      }
      root.finishQueueJob();
    }
  }

  Process {
    id: wallpaperProcess

    stdout: StdioCollector {
      onStreamFinished: {
        if (text && String(text).trim() !== "")
          console.log("[Booru] Wallpaper stdout:", text);
      }
    }

    stderr: StdioCollector {
      onStreamFinished: {
        root.lastProcessError = text || "";
        if (text && String(text).trim() !== "")
          console.log("[Booru] Wallpaper stderr:", text);
      }
    }

    onExited: function (exitCode) {
      if (exitCode === 0)
        ToastService.showNotice(root.trText("booru.wallpaperSet", "Wallpaper updated"));
      else
        ToastService.showError(root.lastProcessError.trim() !== "" ? root.lastProcessError.trim() : root.trText("booru.wallpaperFailed", "Failed to set wallpaper"));
      root.finishQueueJob();
    }
  }

  Process {
    id: openViewerProcess

    stderr: StdioCollector {
      onStreamFinished: root.lastProcessError = text || ""
    }

    onExited: function (exitCode) {
      root.viewerBusy = false;
      if (exitCode !== 0)
        ToastService.showError(root.lastProcessError.trim() !== "" ? root.lastProcessError.trim() : root.trText("booru.viewerFailed", "Failed to open image viewer"));
    }
  }

  Process {
    id: scanSavedImagesProcess

    stdout: StdioCollector {
      onStreamFinished: {
        var lines = String(text || "").split(/\r?\n/);
        var nextKeys = {};
        var nextPaths = {};
        for (var i = 0; i < lines.length; ++i) {
          var fileName = String(lines[i] || "").trim();
          if (fileName === "")
            continue;
          var key = root.savedKeyFromFilename(fileName);
          if (key !== "")
            nextKeys[key] = true;
          nextPaths[root.saveDirectory + "/" + fileName] = true;
        }
        root.savedImageKeys = nextKeys;
        root.savedImagePaths = nextPaths;
      }
    }

    stderr: StdioCollector {}

    onExited: function (_exitCode) {
      if (root.savedImageScanPending)
        savedImageScanTimer.restart();
    }
  }

  ColumnLayout {
    anchors.fill: parent
    spacing: Style.marginM

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NIcon {
        icon: "image"
        color: Color.mPrimary
        pointSize: Style.fontSizeM
        applyUiScale: false
      }

      NText {
        text: root.trText("booru.title", "Anime Board")
        color: Color.mOnSurface
        pointSize: Style.fontSizeM
        applyUiScale: false
        font.weight: Font.Medium
      }

      NText {
        text: root.displayProviderName()
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeXS
        applyUiScale: false
        Layout.fillWidth: true
        elide: Text.ElideRight
      }

      NIcon {
        icon: "loader-2"
        visible: booruService.runningRequests > 0 || queueRunning || viewerBusy
        color: Color.mPrimary
        pointSize: Style.fontSizeS
        applyUiScale: false

        RotationAnimation on rotation {
          from: 0
          to: 360
          duration: 1000
          loops: Animation.Infinite
          running: booruService.runningRequests > 0 || queueRunning || viewerBusy
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS

      NComboBox {
        model: [
          { "key": "yandere", "name": "yande.re" },
          { "key": "konachan", "name": "Konachan" },
          { "key": "danbooru", "name": "Danbooru" }
        ]
        currentKey: root.provider
        onSelected: function (key) {
          root.provider = key;
          root.tagSuggestions = [];
          root.activeSuggestionQuery = "";
          root.activeSuggestionIndex = 0;
          booruService.currentProvider = key;
          root.persistBooruSetting("provider", key);
          root.ensureWorkerProviderIndex(key);
          root.ensureFreshProviderTagIndex();
          root.syncState();
        }
        defaultValue: "yandere"
      }

      Item {
        Layout.fillWidth: true
      }

      CheckBox {
        text: root.trText("booru.safeOnly", "SFW only")
        checked: root.safeOnly
        enabled: booruService.runningRequests === 0
        onToggled: function () {
          root.safeOnly = checked;
          root.persistBooruSetting("safeOnly", checked);
          root.syncState();
        }
      }

      CheckBox {
        text: root.trText("booru.randomOrder", "Random order")
        checked: root.randomOrder
        enabled: booruService.runningRequests === 0
        onToggled: function () {
          root.randomOrder = checked;
          root.persistBooruSetting("randomOrder", checked);
          root.syncState();
        }
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.marginXS

      NText {
        text: root.trText("booru.tags", "Tags")
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeXS
        applyUiScale: false
      }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginS

        Rectangle {
          id: searchFieldFrame
          Layout.fillWidth: true
          Layout.preferredHeight: 40
          color: Color.mSurface
          radius: Style.radiusS
          border.color: Color.mOutline
          border.width: 1

          TextField {
            id: searchInput
            anchors.fill: parent
            anchors.margins: 1
            text: root.searchText
            placeholderText: root.trText("booru.searchPlaceholder", "e.g. landscape night_sky")
            color: Color.mOnSurface
            selectionColor: Color.mPrimary
            selectedTextColor: Color.mOnPrimary
            background: null

            onTextChanged: {
              root.searchText = text;
              root.syncState();
            }
            onTextEdited: {
              root.suggestionPopupRequested = true;
              tagSuggestionTimer.restart();
            }
            onCursorPositionChanged: {
              if (activeFocus && root.suggestionPopupRequested)
                tagSuggestionTimer.restart();
            }
            onActiveFocusChanged: {
              if (!activeFocus)
                root.closeSuggestionPopup(true);
              else if (String(text || "").trim() === "") {
                root.suggestionPopupRequested = true;
                root.updateTagSuggestions();
              }
            }
            onAccepted: {
              if (!root.applySuggestion(root.activeSuggestionIndex)) {
                root.closeSuggestionPopup(true);
                root.search(true);
              }
            }

            Keys.onPressed: function (event) {
              if (event.key === Qt.Key_Down && root.tagSuggestions.length > 0) {
                root.moveSuggestionSelection(1);
                event.accepted = true;
              } else if (event.key === Qt.Key_Up && root.tagSuggestions.length > 0) {
                root.moveSuggestionSelection(-1);
                event.accepted = true;
              } else if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && root.tagSuggestions.length > 0) {
                root.applySuggestion(root.activeSuggestionIndex);
                event.accepted = true;
              } else if (event.key === Qt.Key_Escape && root.tagSuggestions.length > 0) {
                root.closeSuggestionPopup(true);
                event.accepted = true;
              } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                root.requestTabCycleBackward();
                event.accepted = true;
              } else if (event.key === Qt.Key_Tab && !event.modifiers) {
                if (!root.applySuggestion(root.activeSuggestionIndex))
                  root.requestTabCycleForward();
                event.accepted = true;
              }
            }
          }

          TapHandler {
            acceptedButtons: Qt.LeftButton
            gesturePolicy: TapHandler.ReleaseWithinBounds
            onTapped: function() {
              if (searchInput && searchInput.activeFocus && String(searchInput.text || "").trim() === "") {
                root.suggestionPopupRequested = true;
                root.updateTagSuggestions();
              }
            }
          }

        }

        NButton {
          text: root.trText("booru.search", "Search")
          icon: "search"
          enabled: booruService.runningRequests === 0
          onClicked: {
            root.closeSuggestionPopup(true);
            root.search(true);
          }
        }
      }

    }

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.marginS
      visible: !root.lastQueryRandomOrder

      NText {
        text: root.trText("booru.page", "Page")
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeXS
        applyUiScale: false
      }

      NButton {
        text: root.trText("booru.first", "First")
        enabled: root.pageNumber > 1 && booruService.runningRequests === 0
        onClicked: root.goToPage(1)
      }

      NButton {
        text: root.trText("booru.prev", "Prev")
        enabled: root.pageNumber > 1 && booruService.runningRequests === 0
        onClicked: root.goToPage(root.pageNumber - 1)
      }

      SpinBox {
        id: pageSpinBox
        from: 1
        to: 9999
        value: 1
        editable: true
        Layout.preferredWidth: 96
        Component.onCompleted: value = root.pageNumber
      }

      NButton {
        text: root.trText("booru.go", "Go")
        enabled: booruService.runningRequests === 0 && pageSpinBox.value !== root.pageNumber
        onClicked: root.goToPage(pageSpinBox.value)
      }

      NButton {
        text: root.trText("booru.next", "Next")
        visible: root.currentImages().length >= root.pageSize
        enabled: visible && booruService.runningRequests === 0
        onClicked: root.goToPage(root.pageNumber + 1)
      }

      Item {
        Layout.fillWidth: true
      }

      NText {
        text: root.currentImages().length > 0 ? (root.trText("booru.resultsCount", "Results") + ": " + root.currentImages().length) : ""
        color: Color.mOnSurfaceVariant
        pointSize: Style.fontSizeXS
        applyUiScale: false
        elide: Text.ElideRight
      }
    }

    NText {
      Layout.fillWidth: true
      visible: root.lastQueryRandomOrder
      text: root.trText("booru.randomPaginationHint", "Pagination is disabled for the last random search")
      color: Color.mOnSurfaceVariant
      pointSize: Style.fontSizeXS
      applyUiScale: false
    }

    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      color: Color.mSurface
      radius: Style.radiusM
      clip: true

      Item {
        anchors.fill: parent
        anchors.rightMargin: root.attachedPreviewVisible ? (root.attachedPreviewWidth + Style.marginS * 2) : 0
        visible: booruService.runningRequests === 0 && root.currentImages().length === 0 && root.currentMessage() === ""

        ColumnLayout {
          anchors.centerIn: parent
          spacing: Style.marginM

          NIcon {
            Layout.alignment: Qt.AlignHCenter
            icon: "image"
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeXXL * 2
            applyUiScale: false
          }

          NText {
            Layout.alignment: Qt.AlignHCenter
            text: root.trText("booru.emptyTitle", "Search for wallpapers")
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeM
            applyUiScale: false
            font.weight: Font.Medium
          }

          NText {
            Layout.alignment: Qt.AlignHCenter
            text: root.trText("booru.emptyHint", "Pick a site, enter tags, and search")
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeS
            applyUiScale: false
          }
        }
      }

      Item {
        anchors.fill: parent
        anchors.rightMargin: root.attachedPreviewVisible ? (root.attachedPreviewWidth + Style.marginS * 2) : 0
        visible: booruService.runningRequests === 0 && root.currentImages().length === 0 && root.currentMessage() !== ""

        ColumnLayout {
          anchors.centerIn: parent
          spacing: Style.marginM
          width: parent.width * 0.7

          NIcon {
            Layout.alignment: Qt.AlignHCenter
            icon: "alert-triangle"
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeXL
            applyUiScale: false
          }

          NText {
            Layout.alignment: Qt.AlignHCenter
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            text: root.currentMessage()
            color: Color.mOnSurfaceVariant
            pointSize: Style.fontSizeS
            applyUiScale: false
          }
        }
      }

      ScrollView {
        id: scrollArea
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        anchors.leftMargin: Style.marginS
        anchors.topMargin: Style.marginS
        anchors.bottomMargin: Style.marginS
        anchors.rightMargin: root.attachedPreviewVisible ? (root.attachedPreviewWidth + Style.marginS * 2) : Style.marginS
        visible: root.currentImages().length > 0
        clip: true

        Flickable {
          id: imageFlickable
          width: scrollArea.availableWidth || scrollArea.width
          height: scrollArea.availableHeight || scrollArea.height
          contentWidth: width
          contentHeight: imageMasonry.layoutHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          onContentYChanged: {
            root.scrollContentY = contentY;
            root.syncState();
          }

          Item {
            id: imageMasonry
            width: Math.max(imageFlickable.width - Style.marginS, 1)
            height: layoutHeight

            property real spacing: Style.marginS
            property real layoutHeight: 0
            property bool relayoutPending: false
            readonly property real columnWidth: {
              var columns = Math.max(1, root.imagesPerRow);
              var gaps = spacing * Math.max(0, columns - 1);
              return Math.max(120, Math.floor((width - gaps) / columns));
            }

            function scheduleRelayout() {
              if (relayoutPending)
                return;
              relayoutPending = true;
              Qt.callLater(function() {
                relayoutPending = false;
                relayout();
              });
            }

            function relayout() {
              var columns = Math.max(1, root.imagesPerRow);
              var columnHeights = [];
              for (var c = 0; c < columns; ++c)
                columnHeights.push(0);

              var maxBottom = 0;
              for (var i = 0; i < imageRepeater.count; ++i) {
                var item = imageRepeater.itemAt(i);
                if (!item)
                  continue;

                item.width = columnWidth;

                var targetColumn = 0;
                for (var j = 1; j < columns; ++j) {
                  if (columnHeights[j] < columnHeights[targetColumn])
                    targetColumn = j;
                }

                item.x = targetColumn * (columnWidth + spacing);
                item.y = columnHeights[targetColumn];

                var itemHeight = Math.max(item.implicitHeight || item.height || 0, 1);
                columnHeights[targetColumn] += itemHeight + spacing;
                if (columnHeights[targetColumn] > maxBottom)
                  maxBottom = columnHeights[targetColumn];
              }

              layoutHeight = Math.max(0, maxBottom - (imageRepeater.count > 0 ? spacing : 0));
            }

            onWidthChanged: scheduleRelayout()
            onColumnWidthChanged: scheduleRelayout()

            Connections {
              target: root

              function onImagesPerRowChanged() {
                imageMasonry.scheduleRelayout();
              }

              function onVariableCardSizeChanged() {
                imageMasonry.scheduleRelayout();
              }
            }

            Repeater {
              id: imageRepeater
              model: root.currentImages()

              onItemAdded: imageMasonry.scheduleRelayout()
              onItemRemoved: imageMasonry.scheduleRelayout()

              delegate: Loader {
                x: 0
                y: 0
                width: imageMasonry.columnWidth
                height: item ? (item.implicitHeight || item.height || 1) : 1
                sourceComponent: imageCardComponent

                Behavior on x {
                  NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                  }
                }

                Behavior on y {
                  NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                  }
                }

                Behavior on height {
                  NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                  }
                }

                onLoaded: {
                  if (!item)
                    return;
                  item.imageData = modelData;
                  item.width = width;
                  imageMasonry.scheduleRelayout();
                }

                onWidthChanged: {
                  if (item)
                    item.width = width;
                  imageMasonry.scheduleRelayout();
                }
              }
            }
          }
        }
      }

      Rectangle {
        anchors.fill: parent
        anchors.rightMargin: root.attachedPreviewVisible ? (root.attachedPreviewWidth + Style.marginS * 2) : 0
        visible: booruService.runningRequests > 0
        color: "#70000000"

        ColumnLayout {
          anchors.centerIn: parent
          spacing: Style.marginM

          NIcon {
            Layout.alignment: Qt.AlignHCenter
            icon: "loader-2"
            color: Color.mPrimary
            pointSize: Style.fontSizeXL
            applyUiScale: false

            RotationAnimation on rotation {
              from: 0
              to: 360
              duration: 900
              loops: Animation.Infinite
              running: booruService.runningRequests > 0
            }
          }

          NText {
            Layout.alignment: Qt.AlignHCenter
            text: root.trText("booru.loading", "Loading images…")
            color: Color.mOnSurface
            pointSize: Style.fontSizeS
            applyUiScale: false
          }
        }
      }

      Rectangle {
        id: attachedPreviewPane
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: Style.marginS
        width: root.attachedPreviewWidth
        visible: root.attachedPreviewVisible
        color: "#111111"
        radius: Style.radiusM
        border.color: Color.mOutline
        border.width: 1
        clip: true

        Rectangle {
          id: previewHeader
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: 52
          color: "#cc111111"

          RowLayout {
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginS

            NText {
              text: root.selectedImage ? (root.providerNameFromKey(root.providerKeyForImage(root.selectedImage)) + " · #" + root.selectedImage.id) : ""
              color: "white"
              pointSize: Style.fontSizeM
              applyUiScale: false
              font.weight: Font.Medium
              Layout.fillWidth: true
              elide: Text.ElideRight
            }

            NIconButton {
              icon: "x"
              tooltipText: root.pluginApi?.tr("chat.cancel") || "Close"
              onClicked: root.previewOpen = false
            }
          }
        }

        Item {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: previewHeader.bottom
          anchors.bottom: previewFooter.top
          anchors.margins: Style.marginM

          Image {
            id: previewImage
            anchors.fill: parent
            source: root.selectedImage ? (root.selectedImage.file_url || root.selectedImage.sample_url || root.selectedImage.preview_url) : ""
            asynchronous: true
            cache: true
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            autoTransform: true
          }

          Rectangle {
            anchors.fill: parent
            visible: previewImage.status === Image.Loading || previewImage.status === Image.Null || previewImage.status === Image.Error
            color: "transparent"

            ColumnLayout {
              anchors.centerIn: parent
              spacing: Style.marginM

              NIcon {
                Layout.alignment: Qt.AlignHCenter
                icon: previewImage.status === Image.Error ? "image-off" : "loader-2"
                color: "white"
                pointSize: Style.fontSizeXXL
                applyUiScale: false

                RotationAnimation on rotation {
                  from: 0
                  to: 360
                  duration: 900
                  loops: Animation.Infinite
                  running: previewImage.status === Image.Loading
                }
              }

              NText {
                Layout.alignment: Qt.AlignHCenter
                text: previewImage.status === Image.Error ? root.trText("booru.previewLoadFailed", "Failed to load preview") : root.trText("booru.loadingPreview", "Loading preview…")
                color: "white"
                pointSize: Style.fontSizeS
                applyUiScale: false
              }
            }
          }
        }

        Rectangle {
          id: previewFooter
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          implicitHeight: footerColumn.implicitHeight + Style.marginM * 2
          color: "#cc111111"

          ColumnLayout {
            id: footerColumn
            anchors.fill: parent
            anchors.margins: Style.marginM
            spacing: Style.marginS

            Flickable {
              Layout.fillWidth: true
              Layout.preferredHeight: Math.min(tagFlow.implicitHeight, 92)
              Layout.minimumHeight: root.selectedImage ? 36 : 0
              Layout.maximumHeight: 92
              visible: root.selectedImage !== null
              clip: true
              contentWidth: width
              contentHeight: tagFlow.implicitHeight
              boundsBehavior: Flickable.StopAtBounds

              Flow {
                id: tagFlow
                width: parent.width
                spacing: Style.marginXS

                Repeater {
                  model: root.selectedImage ? root.imageTagList(root.selectedImage) : []

                  delegate: Rectangle {
                    required property var modelData
                    radius: Style.radiusS
                    color: "#26ffffff"
                    border.color: "#55ffffff"
                    border.width: 1
                    implicitHeight: tagChipLabel.implicitHeight + Style.marginXS * 2
                    implicitWidth: Math.min(tagChipLabel.implicitWidth + Style.marginS * 2, tagFlow.width)

                    NText {
                      id: tagChipLabel
                      anchors.centerIn: parent
                      width: Math.min(implicitWidth, parent.width - Style.marginS * 2)
                      text: String(modelData || "")
                      color: "white"
                      pointSize: Style.fontSizeXS
                      applyUiScale: false
                      elide: Text.ElideRight
                    }

                    MouseArea {
                      anchors.fill: parent
                      acceptedButtons: Qt.LeftButton | Qt.RightButton
                      cursorShape: Qt.PointingHandCursor
                      onClicked: function (mouse) {
                        var tag = String(parent.modelData || "");
                        if (mouse.button === Qt.RightButton)
                          root.appendTagToSearch(tag);
                        else
                          root.replaceSearchWithTag(tag);
                      }
                    }
                  }
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS

              NButton {
                text: root.trText("booru.save", "Save")
                icon: "download"
                enabled: root.selectedImage !== null && !root.isImageQueued(root.selectedImage) && !root.isImageSaved(root.selectedImage)
                onClicked: root.beginSave(root.selectedImage, false)
              }

              NButton {
                text: root.trText("booru.setWallpaper", "Set as wallpaper")
                icon: "image"
                enabled: root.selectedImage !== null && !root.isImageQueued(root.selectedImage)
                onClicked: root.beginSave(root.selectedImage, true)
              }

              NButton {
                text: root.trText("booru.openBooruPage", "Open page")
                icon: "external-link"
                enabled: root.selectedImage !== null
                onClicked: root.openBooruPage(root.selectedImage)
              }

              Item {
                Layout.fillWidth: true
              }

            }
          }
        }
      }
    }

    NText {
      Layout.fillWidth: true
      text: root.trText("booru.saveLocation", "Save location") + ": " + root.saveDirectory
      color: Color.mOnSurfaceVariant
      pointSize: Style.fontSizeXS
      applyUiScale: false
      elide: Text.ElideMiddle
    }
  }

  Item {
    id: tagSuggestionOverlay
    anchors.fill: parent
    z: 120
    visible: root.suggestionPopupVisible
    clip: false

    Rectangle {
      id: tagSuggestionPopup
      visible: parent.visible
      x: searchInput ? searchInput.mapToItem(tagSuggestionOverlay, 0, 0).x : 0
      y: searchInput ? (searchInput.mapToItem(tagSuggestionOverlay, 0, searchInput.height).y + Style.marginXS) + 100 : 0
      width: searchFieldFrame ? searchFieldFrame.width : 0
      height: visible ? Math.min(tagSuggestionList.contentHeight, 260) : 0
      radius: Style.radiusS
      color: Color.mSurface
      border.color: Color.mOutline
      border.width: 1
      clip: true

      ListView {
        id: tagSuggestionList
        anchors.fill: parent
        model: root.tagSuggestions
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: root.activeSuggestionIndex
        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

        delegate: Rectangle {
          width: tagSuggestionList.width
          height: 36
          color: index === root.activeSuggestionIndex ? Color.mSurfaceVariant : "transparent"

          RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Style.marginS
            anchors.rightMargin: Style.marginS
            spacing: Style.marginS

            NText {
              Layout.fillWidth: true
              text: modelData.name || ""
              color: Color.mOnSurface
              pointSize: Style.fontSizeXS
              applyUiScale: false
              elide: Text.ElideRight
            }

            NText {
              text: modelData.source === "history" ? "" : (modelData.count > 0 ? String(modelData.count) : "")
              color: Color.mOnSurfaceVariant
              pointSize: Style.fontSizeXS
              applyUiScale: false
            }
          }

          MouseArea {
            anchors.fill: parent
            onClicked: root.applySuggestion(index)
          }
        }
      }
    }
  }


  TapHandler {
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    onTapped: function(eventPoint) {
      if (!root.suggestionPopupRequested || !tagSuggestionPopup.visible)
        return;
      var inputPoint = searchFieldFrame.mapFromItem(root, eventPoint.position.x, eventPoint.position.y);
      var popupPoint = tagSuggestionPopup.mapFromItem(root, eventPoint.position.x, eventPoint.position.y);
      if (!searchFieldFrame.contains(inputPoint) && !tagSuggestionPopup.contains(popupPoint))
        root.closeSuggestionPopup(true);
    }
  }

  Rectangle {
    anchors.fill: parent
    color: "transparent"
    visible: root.contextMenuVisible && root.contextImage !== null
    z: 45

    MouseArea {
      anchors.fill: parent
      onClicked: root.hideContextMenu()
    }

    Rectangle {
      x: root.contextMenuX
      y: root.contextMenuY
      width: 240
      radius: Style.radiusM
      color: Color.mSurface
      border.color: Color.mOutline
      border.width: 1

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.marginS
        spacing: Style.marginXS

        NButton {
          Layout.fillWidth: true
          text: root.trText("booru.openInViewer", "Open in viewer")
          icon: "image"
          enabled: root.contextImage !== null && !root.viewerBusy
          onClicked: root.openInViewer(root.contextImage)
        }

        NButton {
          Layout.fillWidth: true
          text: root.trText("booru.openBooruPage", "Open page")
          icon: "external-link"
          enabled: root.contextImage !== null
          onClicked: {
            root.openBooruPage(root.contextImage);
            root.hideContextMenu();
          }
        }

        NButton {
          Layout.fillWidth: true
          text: root.trText("booru.preview", "Preview")
          icon: "image"
          enabled: root.contextImage !== null
          onClicked: {
            root.selectedImage = root.contextImage;
            root.previewOpen = true;
            root.hideContextMenu();
          }
        }

        NButton {
          Layout.fillWidth: true
          text: root.trText("booru.save", "Save")
          icon: "download"
          enabled: root.contextImage !== null && !root.isImageQueued(root.contextImage) && !root.isImageSaved(root.contextImage)
          onClicked: {
            root.beginSave(root.contextImage, false);
            root.hideContextMenu();
          }
        }

        NButton {
          Layout.fillWidth: true
          text: root.trText("booru.setWallpaper", "Set as wallpaper")
          icon: "image"
          enabled: root.contextImage !== null && !root.isImageQueued(root.contextImage)
          onClicked: {
            root.beginSave(root.contextImage, true);
            root.hideContextMenu();
          }
        }
      }
    }
  }

}
