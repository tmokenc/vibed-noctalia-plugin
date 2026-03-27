pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  signal searchFinished(var payload)
  signal searchFailed(string message)
  signal detailFinished(var payload)
  signal detailFailed(string animeId, string message)

  property string defaultUserAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
  property string apiBaseUrl: "https://api.animethemes.moe"

  property string searchStdout: ""
  property string searchStderr: ""
  property var activeSearchRequest: null
  property var pendingSearchRequest: null

  property string detailStdout: ""
  property string detailStderr: ""
  property var activeDetailRequest: null
  property var pendingDetailRequest: null

  property var searchCache: ({})
  property var detailCache: ({})

  function searchCacheKey(query, pageSize) {
    return String(query || "").trim().toLowerCase() + "::" + String(pageSize || 12);
  }

  function detailCacheKey(anilistId) {
    return String(anilistId || "");
  }

  function buildSearchCommand(query, pageSize) {
    var code = [
      "import json, sys, urllib.request",
      "query = sys.argv[1]",
      "page_size = max(1, int(sys.argv[2]))",
      "user_agent = sys.argv[3]",
      "ani_base = 'https://graphql.anilist.co'",
      "headers = {'User-Agent': user_agent, 'Accept': 'application/json', 'Content-Type': 'application/json'}",
      "payload = json.dumps({",
      "  'query': 'query ($search: String, $page: Int, $perPage: Int) { Page(page: $page, perPage: $perPage) { media(search: $search, type: ANIME, sort: SEARCH_MATCH) { id siteUrl title { romaji english native } synonyms season seasonYear format status description(asHtml: false) episodes duration averageScore meanScore popularity favourites genres countryOfOrigin hashtag bannerImage coverImage { large medium } startDate { year month day } endDate { year month day } studios(isMain: true) { nodes { name } } } } }',",
      "  'variables': {'search': query, 'page': 1, 'perPage': page_size}",
      "}).encode('utf-8')",
      "request = urllib.request.Request(ani_base, data=payload, headers=headers)",
      "with urllib.request.urlopen(request, timeout=30) as response:",
      "    data = json.loads(response.read().decode('utf-8'))",
      "media = (((data or {}).get('data') or {}).get('Page') or {}).get('media') or []",
      "print(json.dumps({'results': media}))"
    ].join('\n');

    return ['python3', '-c', code, String(query || '').trim(), String(Math.max(1, parseInt(pageSize || 12, 10) || 12)), defaultUserAgent];
  }

  function buildDetailCommand(anilistId) {
    var code = [
      "import json, sys, urllib.parse, urllib.request",
      "anilist_id = sys.argv[1]",
      "user_agent = sys.argv[2]",
      "api_base = sys.argv[3].rstrip('/')",
      "include = 'images,resources,animethemes.song.artists,animethemes.animethemeentries.videos,animethemes.group'",
      "params = [",
      "  ('filter[has]', 'resources'),",
      "  ('filter[site]', 'AniList'),",
      "  ('filter[external_id]', str(anilist_id)),",
      "  ('include', include),",
      "]",
      "url = api_base + '/anime?' + urllib.parse.urlencode(params)",
      "headers = {'User-Agent': user_agent, 'Accept': 'application/json', 'Content-Type': 'application/json'}",
      "request = urllib.request.Request(url, headers=headers)",
      "with urllib.request.urlopen(request, timeout=30) as response:",
      "    themes_data = json.loads(response.read().decode('utf-8'))",
      "characters = {}",
      "try:",
      "    ani_query = json.dumps({",
      "      'query': 'query ($id: Int) { Media(id: $id, type: ANIME) { characters(page: 1, perPage: 25) { edges { role node { id name { full native } image { large medium } siteUrl } voiceActors { id name { full native } image { large medium } siteUrl primaryOccupations } } } } }',",
      "      'variables': {'id': int(anilist_id)}",
      "    }).encode('utf-8')",
      "    ani_req = urllib.request.Request('https://graphql.anilist.co', data=ani_query, headers=headers)",
      "    with urllib.request.urlopen(ani_req, timeout=30) as response:",
      "        anilist_data = json.loads(response.read().decode('utf-8'))",
      "    characters = (((anilist_data or {}).get('data') or {}).get('Media') or {}).get('characters') or {}",
      "except Exception:",
      "    characters = {}",
      "print(json.dumps({'anilistId': anilist_id, 'themes': themes_data, 'characters': characters}))"
    ].join('\n');

    return ['python3', '-c', code, String(anilistId || ''), defaultUserAgent, apiBaseUrl];
  }

  function absoluteUrl(value, fallbackHost) {
    var raw = String(value || "").trim();
    if (raw === "")
      return "";
    if (/^https?:\/\//i.test(raw))
      return raw;
    if (raw.indexOf("//") === 0)
      return "https:" + raw;
    var base = String(fallbackHost || "https://animethemes.moe").replace(/\/$/, "");
    if (raw.charAt(0) === "/")
      return base + raw;
    return base + "/" + raw;
  }

  function supportedImageUrl(value, fallbackHost) {
    var resolved = absoluteUrl(value, fallbackHost || apiBaseUrl);
    if (resolved === "")
      return "";
    if (/\.avif(?:$|[?#])/i.test(resolved))
      return "";
    return resolved;
  }

  function pickImage(images, fallbackUrl) {
    var list = Array.isArray(images) ? images : [];
    for (var i = 0; i < list.length; ++i) {
      var item = list[i];
      if (!item)
        continue;
      if (typeof item === "string") {
        var direct = supportedImageUrl(item, apiBaseUrl);
        if (direct !== "")
          return direct;
        continue;
      }
      var candidates = [];
      if (item.link)
        candidates.push(item.link);
      if (item.url)
        candidates.push(item.url);
      if (item.source)
        candidates.push(item.source);
      if (item.original)
        candidates.push(item.original);
      if (item.facets) {
        if (item.facets.large)
          candidates.push(item.facets.large);
        if (item.facets.medium)
          candidates.push(item.facets.medium);
        if (item.facets.small)
          candidates.push(item.facets.small);
      }
      for (var j = 0; j < candidates.length; ++j) {
        var candidate = supportedImageUrl(candidates[j], apiBaseUrl);
        if (candidate !== "")
          return candidate;
      }
    }
    return supportedImageUrl(fallbackUrl, apiBaseUrl);
  }

  function normalizeEpisodes(value) {
    if (value === null || value === undefined)
      return "";
    var text = String(value).trim();
    if (text === "")
      return "";
    if (text.toLowerCase() === "all")
      return "All episodes";
    return text;
  }

  function videoSortScore(video) {
    var resolution = parseInt(video && video.resolution || 0, 10) || 0;
    var lyricsPenalty = video && video.lyrics ? -2000 : 0;
    var ncBonus = video && video.nc ? 50 : 0;
    return resolution + lyricsPenalty + ncBonus;
  }

  function titleFromMedia(media) {
    var title = media && media.title ? media.title : {};
    return String(title.english || title.romaji || title.native || "Unknown anime");
  }

  function mapSearchMedia(media) {
    var anilistId = String(media && media.id || "");
    if (anilistId === "")
      return null;
    var cover = media && media.coverImage ? (media.coverImage.large || media.coverImage.medium || "") : "";
    var pageUrl = "https://anilist.co/anime/" + anilistId;
    return {
      "id": anilistId,
      "anilistId": anilistId,
      "slug": "",
      "name": titleFromMedia(media),
      "year": parseInt(media && media.seasonYear || 0, 10) || 0,
      "season": String(media && media.season || ""),
      "mediaFormat": String(media && media.format || "").replace(/_/g, " "),
      "synopsis": String(media && media.description || ""),
      "coverUrl": supportedImageUrl(cover, apiBaseUrl),
      "pageUrl": pageUrl,
      "studios": [],
      "resources": [{ "site": "AniList", "externalId": anilistId, "link": pageUrl }],
      "animethemes": [],
      "characters": [],
      "openingCount": 0,
      "endingCount": 0,
      "themeCount": 0,
      "detailsLoaded": false,
      "detailsLoading": false,
      "detailsError": ""
    };
  }

  function simplifyTheme(theme, animePageUrl) {
    var entries = Array.isArray(theme && theme.animethemeentries) ? theme.animethemeentries : [];
    var entryItems = [];
    for (var entryIndex = 0; entryIndex < entries.length; ++entryIndex) {
      var entry = entries[entryIndex] || {};
      var videos = Array.isArray(entry.videos) ? entry.videos : [];
      var simplifiedVideos = videos.map(function(video) {
        return {
          "id": String(video && (video.id || video.basename || video.filename) || ""),
          "link": absoluteUrl(video && (video.link || video.url || video.path), "https://v.animethemes.moe"),
          "resolution": parseInt(video && (video.resolution || video.height || 0), 10) || 0,
          "lyrics": !!(video && video.lyrics),
          "nc": !!(video && (video.nc || video.overlap === "None")),
          "source": String(video && (video.source || video.basename || "") || "")
        };
      }).filter(function(video) {
        return video.link !== "";
      }).sort(function(a, b) {
        return videoSortScore(b) - videoSortScore(a);
      });

      entryItems.push({
        "episodes": normalizeEpisodes(entry && entry.episodes),
        "notes": String(entry && entry.notes || ""),
        "nsfw": !!(entry && entry.nsfw),
        "spoiler": !!(entry && entry.spoiler),
        "videos": simplifiedVideos
      });
    }

    var song = theme && theme.song ? theme.song : {};
    var artists = Array.isArray(song.artists) ? song.artists.map(function(artist) {
      return String(artist && artist.name || "");
    }).filter(function(name) {
      return name !== "";
    }) : [];

    var bestVideo = null;
    for (var i = 0; i < entryItems.length; ++i) {
      if (entryItems[i].videos.length > 0) {
        bestVideo = entryItems[i].videos[0];
        break;
      }
    }

    return {
      "id": String(theme && (theme.id || theme.slug || ((theme.type || "TH") + (theme.sequence || ""))) || ""),
      "slug": String(theme && theme.slug || ""),
      "type": String(theme && theme.type || "").toUpperCase(),
      "sequence": parseInt(theme && theme.sequence || 0, 10) || 0,
      "groupName": String(theme && theme.group && theme.group.name || ""),
      "songTitle": String(song && song.title || ""),
      "artists": artists,
      "entries": entryItems,
      "bestVideoUrl": bestVideo ? bestVideo.link : "",
      "bestVideoResolution": bestVideo ? bestVideo.resolution : 0,
      "hasLyricsVideo": !!(bestVideo && bestVideo.lyrics),
      "pageUrl": String(theme && (theme.link || theme.site_url) || animePageUrl || ""),
      "displayName": String(theme && theme.type || "Theme") + ((parseInt(theme && theme.sequence || 0, 10) || 0) > 0 ? String(parseInt(theme.sequence, 10)) : "")
    };
  }

  function anilistIdFromResources(resources) {
    var list = Array.isArray(resources) ? resources : [];
    for (var i = 0; i < list.length; ++i) {
      var resource = list[i] || {};
      if (String(resource.site || "").toLowerCase() === "anilist")
        return String(resource.external_id || resource.externalId || "");
    }
    return "";
  }

  function mapCharacterEntries(edges) {
    var list = Array.isArray(edges) ? edges : [];
    return list.map(function(edge) {
      var character = edge && edge.node ? edge.node : {};
      var voiceActors = Array.isArray(edge && edge.voiceActors) ? edge.voiceActors : [];
      return {
        "id": String(character && character.id || ""),
        "name": String(character && character.name && character.name.full || "Unknown character"),
        "nativeName": String(character && character.name && character.name.native || ""),
        "imageUrl": supportedImageUrl(character && character.image && (character.image.large || character.image.medium) || "", apiBaseUrl),
        "pageUrl": String(character && character.siteUrl || ""),
        "role": String(edge && edge.role || ""),
        "voiceActors": voiceActors.map(function(actor) {
          return {
            "id": String(actor && actor.id || ""),
            "name": String(actor && actor.name && actor.name.full || "Unknown VA"),
            "nativeName": String(actor && actor.name && actor.name.native || ""),
            "imageUrl": supportedImageUrl(actor && actor.image && (actor.image.large || actor.image.medium) || "", apiBaseUrl),
            "pageUrl": String(actor && actor.siteUrl || ""),
            "primaryOccupations": Array.isArray(actor && actor.primaryOccupations) ? actor.primaryOccupations : []
          };
        })
      };
    }).filter(function(entry) {
      return entry.id !== "" || entry.name !== "";
    });
  }

  function mapAnimeDetail(item) {
    var slug = String(item && item.slug || "");
    var animePageUrl = item && (item.link || item.site_url) ? String(item.link || item.site_url) : (slug !== "" ? ("https://animethemes.moe/anime/" + slug) : "");
    var animethemes = Array.isArray(item && item.animethemes) ? item.animethemes.map(function(theme) {
      return simplifyTheme(theme, animePageUrl);
    }) : [];

    animethemes = animethemes.filter(function(theme) {
      return theme.bestVideoUrl !== "" || theme.entries.some(function(entry) {
        return (entry.videos || []).length > 0;
      });
    }).sort(function(a, b) {
      var typeA = a.type === "OP" ? 0 : (a.type === "ED" ? 1 : 2);
      var typeB = b.type === "OP" ? 0 : (b.type === "ED" ? 1 : 2);
      if (typeA !== typeB)
        return typeA - typeB;
      return (a.sequence || 0) - (b.sequence || 0);
    });

    var openings = animethemes.filter(function(theme) { return theme.type === "OP"; }).length;
    var endings = animethemes.filter(function(theme) { return theme.type === "ED"; }).length;
    var resources = Array.isArray(item && item.resources) ? item.resources : [];
    var studios = Array.isArray(item && item.studios) ? item.studios.map(function(studio) {
      return String(studio && studio.name || "");
    }).filter(function(name) { return name !== ""; }) : [];
    var anilistId = anilistIdFromResources(resources);

    return {
      "id": anilistId !== "" ? anilistId : String(item && (item.id || item.slug || item.name) || ""),
      "anilistId": anilistId,
      "slug": slug,
      "name": String(item && (item.name || item.slug || "Unknown anime") || "Unknown anime"),
      "titleRomaji": "",
      "titleEnglish": "",
      "titleNative": "",
      "synonyms": [],
      "year": parseInt(item && item.year || 0, 10) || 0,
      "season": String(item && item.season || ""),
      "mediaFormat": String(item && (item.media_format || item.type || item.kind) || ""),
      "status": "",
      "episodes": 0,
      "duration": 0,
      "averageScore": 0,
      "meanScore": 0,
      "popularity": 0,
      "favourites": 0,
      "genres": [],
      "countryOfOrigin": "",
      "hashtag": "",
      "startDate": null,
      "endDate": null,
      "synopsis": String(item && (item.synopsis || item.description || "") || ""),
      "coverUrl": pickImage(item && item.images, item && item._fallback_cover),
      "bannerUrl": "",
      "pageUrl": animePageUrl,
      "studios": studios,
      "resources": resources.map(function(resource) {
        return {
          "site": String(resource && resource.site || ""),
          "externalId": String(resource && resource.external_id || ""),
          "link": absoluteUrl(resource && (resource.link || resource.as || resource.url), apiBaseUrl)
        };
      }),
      "animethemes": animethemes,
      "characters": [],
      "openingCount": openings,
      "endingCount": endings,
      "themeCount": animethemes.length,
      "detailsLoaded": true,
      "detailsLoading": false,
      "detailsError": ""
    };
  }

  function parseSearchResponse(rawText) {
    var parsed = JSON.parse(String(rawText || "{}"));
    var mediaList = Array.isArray(parsed && parsed.results) ? parsed.results : [];
    return mediaList.map(function(media) {
      return mapSearchMedia(media);
    }).filter(function(item) {
      return !!item;
    });
  }

  function parseDetailResponse(rawText) {
    var parsed = JSON.parse(String(rawText || "{}"));
    var themesPayload = parsed && parsed.themes ? parsed.themes : parsed;
    var characterEdges = parsed && parsed.characters && Array.isArray(parsed.characters.edges) ? parsed.characters.edges : [];
    var animeList = [];
    if (Array.isArray(themesPayload && themesPayload.anime))
      animeList = themesPayload.anime;
    else if (Array.isArray(themesPayload && themesPayload.data))
      animeList = themesPayload.data;
    var anime = null;
    if (animeList && animeList.length > 0) {
      anime = mapAnimeDetail(animeList[0]);
    } else {
      anime = {
        "id": String(parsed && parsed.anilistId || ""),
        "anilistId": String(parsed && parsed.anilistId || ""),
        "animethemes": [],
        "characters": [],
        "openingCount": 0,
        "endingCount": 0,
        "themeCount": 0,
        "detailsLoaded": true,
        "detailsLoading": false,
        "detailsError": ""
      };
    }
    anime.characters = mapCharacterEntries(characterEdges);
    return anime;
  }

  function searchAnime(query, pageSize) {
    var normalizedQuery = String(query || "").trim();
    if (normalizedQuery === "") {
      root.searchFailed("Enter an anime title to search.");
      return;
    }

    var request = {
      "query": normalizedQuery,
      "pageSize": Math.max(1, parseInt(pageSize || 12, 10) || 12),
      "cacheKey": searchCacheKey(normalizedQuery, pageSize)
    };

    if (root.searchCache[request.cacheKey]) {
      Qt.callLater(function() {
        root.searchFinished({
          "query": request.query,
          "pageSize": request.pageSize,
          "results": root.searchCache[request.cacheKey],
          "cached": true
        });
      });
      return;
    }

    if (searchProcess.running) {
      pendingSearchRequest = request;
      return;
    }

    activeSearchRequest = request;
    searchStdout = "";
    searchStderr = "";
    searchProcess.command = buildSearchCommand(request.query, request.pageSize);
    searchProcess.running = true;
  }

  function loadAnimeDetails(animeId, anilistId) {
    var resolvedAnimeId = String(animeId || anilistId || "");
    var resolvedAnilistId = String(anilistId || animeId || "");
    if (resolvedAnilistId === "") {
      root.detailFailed(resolvedAnimeId, "Missing AniList ID for this anime.");
      return;
    }

    var request = {
      "animeId": resolvedAnimeId,
      "anilistId": resolvedAnilistId,
      "cacheKey": detailCacheKey(resolvedAnilistId)
    };

    if (root.detailCache[request.cacheKey]) {
      Qt.callLater(function() {
        root.detailFinished({
          "animeId": request.animeId,
          "anime": root.detailCache[request.cacheKey],
          "cached": true
        });
      });
      return;
    }

    if (detailProcess.running) {
      pendingDetailRequest = request;
      return;
    }

    activeDetailRequest = request;
    detailStdout = "";
    detailStderr = "";
    detailProcess.command = buildDetailCommand(request.anilistId);
    detailProcess.running = true;
  }

  Process {
    id: searchProcess

    stdout: StdioCollector {
      onStreamFinished: root.searchStdout = text || ""
    }

    stderr: StdioCollector {
      onStreamFinished: root.searchStderr = text || ""
    }

    onExited: function(exitCode) {
      var request = root.activeSearchRequest;
      root.activeSearchRequest = null;

      if (request) {
        if (exitCode === 0) {
          try {
            var results = root.parseSearchResponse(root.searchStdout);
            root.searchCache[request.cacheKey] = results;
            root.searchFinished({
              "query": request.query,
              "pageSize": request.pageSize,
              "results": results
            });
          } catch (error) {
            console.log("[AnimeThemes] Failed to parse search response:", error);
            root.searchFailed("AnimeThemes search returned data in an unexpected format.");
          }
        } else {
          console.log("[AnimeThemes] Search failed:", root.searchStderr || ("search exited " + exitCode));
          root.searchFailed("AnimeThemes search failed. Check your network connection or try again.");
        }
      }

      if (root.pendingSearchRequest) {
        var next = root.pendingSearchRequest;
        root.pendingSearchRequest = null;
        root.searchAnime(next.query, next.pageSize);
      }
    }
  }

  Process {
    id: detailProcess

    stdout: StdioCollector {
      onStreamFinished: root.detailStdout = text || ""
    }

    stderr: StdioCollector {
      onStreamFinished: root.detailStderr = text || ""
    }

    onExited: function(exitCode) {
      var request = root.activeDetailRequest;
      root.activeDetailRequest = null;

      if (request) {
        if (exitCode === 0) {
          try {
            var anime = root.parseDetailResponse(root.detailStdout);
            if (anime) {
              root.detailCache[request.cacheKey] = anime;
              root.detailFinished({
                "animeId": request.animeId,
                "anime": anime
              });
            } else {
              root.detailFailed(request.animeId, "No AnimeThemes data found for this anime.");
            }
          } catch (error) {
            console.log("[AnimeThemes] Failed to parse detail response:", error);
            root.detailFailed(request.animeId, "AnimeThemes detail data returned in an unexpected format.");
          }
        } else {
          console.log("[AnimeThemes] Detail fetch failed:", root.detailStderr || ("detail exited " + exitCode));
          root.detailFailed(request.animeId, "Failed to load AnimeThemes details for this anime.");
        }
      }

      if (root.pendingDetailRequest) {
        var next = root.pendingDetailRequest;
        root.pendingDetailRequest = null;
        root.loadAnimeDetails(next.animeId, next.anilistId);
      }
    }
  }
}
