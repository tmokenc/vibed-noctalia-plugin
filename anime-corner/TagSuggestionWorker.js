var providerIndexes = {};
var queryCaches = {};

function normalizeSuggestions(suggestions) {
  return (suggestions || []).map(function(item) {
    return {
      "name": String(item && item.name || ""),
      "count": Math.max(0, parseInt(item && item.count || 0, 10) || 0)
    };
  }).filter(function(item) {
    return item.name !== "" && item.count > 0;
  });
}

function dedupeSuggestions(suggestions) {
  var seen = {};
  return normalizeSuggestions(suggestions).filter(function(item) {
    var key = String(item.name || "").toLowerCase();
    if (seen[key])
      return false;
    seen[key] = true;
    return true;
  });
}

function normalizedTagWords(text) {
  return String(text || "").toLowerCase().replace(/[^a-z0-9_\s]+/g, " ").split(/[\s_]+/).filter(function(part) {
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

  var row = [];
  var i;
  var j;
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
    "initials": words.map(function(part) { return part.charAt(0); }).join("")
  };
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
    + sharedPrefixLength(prepared.compactName, compactQuery) * 18
    + countBonus;
}

function detailedPreparedTagScore(prepared, features, baseScore) {
  var compactQuery = features.compact;
  var distanceScore = 0;
  if (compactQuery.length >= 3) {
    var candidateSlice = prepared.compactName.slice(0, Math.min(prepared.compactName.length, compactQuery.length + 4));
    var distance = levenshteinDistance(compactQuery, candidateSlice);
    distanceScore = Math.max(0, 40 - distance * 7);
  }
  return baseScore + distanceScore + Math.min(24, Math.log(Math.max(1, Number(prepared.count || 0))) / Math.log(10) * 7);
}

function queryCacheBucket(providerKey) {
  if (!queryCaches[providerKey])
    queryCaches[providerKey] = {};
  return queryCaches[providerKey];
}

function setProviderIndex(providerKey, marker, suggestions) {
  var normalized = dedupeSuggestions(suggestions);
  providerIndexes[providerKey] = {
    "marker": String(marker || ""),
    "items": normalized.map(function(item) {
      return buildPreparedTagEntry(item);
    })
  };
  queryCaches[providerKey] = {};
}

function rankedSuggestions(providerKey, query, seedSuggestions) {
  var normalizedQuery = String(query || "").toLowerCase();
  var cacheKey = normalizedQuery + "||" + JSON.stringify(dedupeSuggestions(seedSuggestions || []));
  var bucket = queryCacheBucket(providerKey);
  if (bucket[cacheKey])
    return bucket[cacheKey];

  var features = queryFeatures(normalizedQuery);
  if (features.normalized === "" || features.compact === "")
    return [];

  var merged = {};
  var indexItems = providerIndexes[providerKey] ? providerIndexes[providerKey].items || [] : [];
  var i;
  for (i = 0; i < indexItems.length; ++i) {
    var matchInfo = preparedTagMatchInfo(indexItems[i], features);
    if (!matchInfo)
      continue;
    var cheapScore = cheapPreparedTagScore(indexItems[i], features, matchInfo);
    merged[indexItems[i].normalizedName] = {
      "prepared": indexItems[i],
      "score": cheapScore,
      "name": indexItems[i].name,
      "count": indexItems[i].count
    };
  }

  var seeds = dedupeSuggestions(seedSuggestions || []);
  for (i = 0; i < seeds.length; ++i) {
    var preparedSeed = buildPreparedTagEntry(seeds[i]);
    var seedMatchInfo = preparedTagMatchInfo(preparedSeed, features);
    if (!seedMatchInfo)
      continue;
    var seedScore = cheapPreparedTagScore(preparedSeed, features, seedMatchInfo) + 80;
    var seedKey = preparedSeed.normalizedName;
    if (!merged[seedKey] || merged[seedKey].score < seedScore) {
      merged[seedKey] = {
        "prepared": preparedSeed,
        "score": seedScore,
        "name": preparedSeed.name,
        "count": preparedSeed.count
      };
    }
  }

  var shortlist = Object.keys(merged).map(function(key) {
    return merged[key];
  }).sort(function(left, right) {
    if (right.score !== left.score)
      return right.score - left.score;
    if (right.count !== left.count)
      return right.count - left.count;
    return left.name.localeCompare(right.name);
  }).slice(0, 64).map(function(item) {
    return {
      "prepared": item.prepared,
      "score": detailedPreparedTagScore(item.prepared, features, item.score),
      "name": item.name,
      "count": item.count
    };
  }).sort(function(left, right) {
    if (right.score !== left.score)
      return right.score - left.score;
    if (right.count !== left.count)
      return right.count - left.count;
    return left.name.localeCompare(right.name);
  }).slice(0, 12).map(function(item) {
    return {
      "name": item.name,
      "count": item.count
    };
  });

  bucket[cacheKey] = shortlist;
  return shortlist;
}

WorkerScript.onMessage = function(message) {
  if (!message || !message.type)
    return;

  if (message.type === "setIndex") {
    setProviderIndex(String(message.providerKey || ""), String(message.marker || ""), message.suggestions || []);
    return;
  }

  if (message.type === "query") {
    var providerKey = String(message.providerKey || "");
    var query = String(message.query || "").toLowerCase();
    var suggestions = rankedSuggestions(providerKey, query, message.seedSuggestions || []);
    WorkerScript.sendMessage({
      "type": "queryResult",
      "requestId": message.requestId,
      "providerKey": providerKey,
      "query": query,
      "suggestions": suggestions
    });
  }
};
