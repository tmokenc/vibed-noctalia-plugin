pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  signal searchFinished(var payload)
  signal searchFailed(string message)

  property string defaultUserAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
  property string apiBaseUrl: "https://api.animethemes.moe"
  property string requestStdout: ""
  property string requestStderr: ""
  property var activeRequest: null
  property var pendingRequest: null

  function buildSearchCommand(query, pageSize) {
    var code = [
      "import concurrent.futures, json, sys, urllib.parse, urllib.request",
      "query = sys.argv[1]",
      "page_size = max(1, int(sys.argv[2]))",
      "user_agent = sys.argv[3]",
      "api_base = sys.argv[4].rstrip('/')",
      "ani_base = 'https://graphql.anilist.co'",
      "include = 'images,resources,animethemes.song.artists,animethemes.animethemeentries.videos,animethemes.group'",
      "headers = {'User-Agent': user_agent, 'Accept': 'application/json'}",
      "def request_json(url, data=None, extra_headers=None):",
      "    req_headers = dict(headers)",
      "    if extra_headers:",
      "        req_headers.update(extra_headers)",
      "    request = urllib.request.Request(url, data=data, headers=req_headers)",
      "    with urllib.request.urlopen(request, timeout=30) as response:",
      "        return json.loads(response.read().decode('utf-8'))",
      "graphql = json.dumps({",
      "    'query': 'query ($search: String, $page: Int, $perPage: Int) { Page(page: $page, perPage: $perPage) { media(search: $search, type: ANIME, sort: SEARCH_MATCH) { id title { romaji english native } season seasonYear format description(asHtml: false) coverImage { large medium } } } }',",
      "    'variables': {'search': query, 'page': 1, 'perPage': page_size}",
      "}).encode('utf-8')",
      "search_payload = request_json(ani_base, graphql, {'Content-Type': 'application/json', 'Accept': 'application/json'})",
      "media_items = (((search_payload or {}).get('data') or {}).get('Page') or {}).get('media') or []",
      "def fetch_media(media):",
      "    media_id = media.get('id')",
      "    if not media_id:",
      "        return None",
      "    params = [",
      "        ('filter[has]', 'resources'),",
      "        ('filter[site]', 'AniList'),",
      "        ('filter[external_id]', str(media_id)),",
      "        ('include', include),",
      "    ]",
      "    url = api_base + '/anime?' + urllib.parse.urlencode(params)",
      "    payload = request_json(url)",
      "    anime_list = payload.get('anime') if isinstance(payload, dict) else None",
      "    if not isinstance(anime_list, list):",
      "        anime_list = payload.get('data') if isinstance(payload, dict) else None",
      "    if not anime_list:",
      "        return None",
      "    item = anime_list[0]",
      "    if not isinstance(item, dict):",
      "        return None",
      "    if not item.get('name'):",
      "        title = media.get('title') or {}",
      "        item['name'] = title.get('english') or title.get('romaji') or title.get('native') or ''",
      "    if not item.get('year') and media.get('seasonYear'):",
      "        item['year'] = media.get('seasonYear')",
      "    if not item.get('season') and media.get('season'):",
      "        item['season'] = str(media.get('season')).title()",
      "    if not item.get('media_format') and media.get('format'):",
      "        item['media_format'] = str(media.get('format')).replace('_', ' ').title()",
      "    if not item.get('synopsis') and media.get('description'):",
      "        item['synopsis'] = media.get('description')",
      "    cover = None",
      "    if isinstance(media.get('coverImage'), dict):",
      "        cover = media['coverImage'].get('large') or media['coverImage'].get('medium')",
      "    if cover:",
      "        item['_fallback_cover'] = cover",
      "    if (not item.get('images')) and cover:",
      "        item['images'] = [{'link': cover}]",
      "    return item",
      "results = []",
      "with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:",
      "    futures = [executor.submit(fetch_media, media) for media in media_items]",
      "    for future in concurrent.futures.as_completed(futures):",
      "        item = future.result()",
      "        if item is not None:",
      "            results.append(item)",
      "# preserve AniList search order",
      "order = {}",
      "for index, media in enumerate(media_items):",
      "    media_id = str(media.get('id') or '')",
      "    if media_id:",
      "        order[media_id] = index",
      "def result_index(item):",
      "    resources = item.get('resources') or []",
      "    for resource in resources:",
      "        if str(resource.get('site') or '').lower() == 'anilist':",
      "            return order.get(str(resource.get('external_id') or ''), 10**9)",
      "    return 10**9",
      "results.sort(key=result_index)",
      "print(json.dumps({'anime': results}))"
    ].join('\n');
    return ['python3', '-c', code, String(query || '').trim(), String(Math.max(1, parseInt(pageSize || 12, 10) || 12)), defaultUserAgent, apiBaseUrl];
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
        var facets = item.facets;
        if (facets.large)
          candidates.push(facets.large);
        if (facets.medium)
          candidates.push(facets.medium);
        if (facets.small)
          candidates.push(facets.small);
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

  function mapAnimeItem(item) {
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

    return {
      "id": String(item && (item.id || item.slug || item.name) || ""),
      "slug": slug,
      "name": String(item && (item.name || item.slug || "Unknown anime") || "Unknown anime"),
      "year": parseInt(item && item.year || 0, 10) || 0,
      "season": String(item && item.season || ""),
      "mediaFormat": String(item && (item.media_format || item.type || item.kind) || ""),
      "synopsis": String(item && (item.synopsis || item.description || "") || ""),
      "coverUrl": pickImage(item && item.images, item && item._fallback_cover),
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
      "openingCount": openings,
      "endingCount": endings,
      "themeCount": animethemes.length
    };
  }

  function parseSearchResponse(rawText) {
    var parsed = JSON.parse(String(rawText || "{}"));
    var animeList = [];
    if (Array.isArray(parsed && parsed.anime))
      animeList = parsed.anime;
    else if (Array.isArray(parsed && parsed.data))
      animeList = parsed.data;

    return animeList.map(function(item) {
      return mapAnimeItem(item);
    }).filter(function(item) {
      return item.id !== "" && item.themeCount > 0;
    });
  }

  function searchAnime(query, pageSize) {
    var normalizedQuery = String(query || "").trim();
    if (normalizedQuery === "") {
      root.searchFailed("Enter an anime title to search.");
      return;
    }

    var request = {
      "query": normalizedQuery,
      "pageSize": Math.max(1, parseInt(pageSize || 12, 10) || 12)
    };

    if (searchProcess.running) {
      pendingRequest = request;
      return;
    }

    activeRequest = request;
    requestStdout = "";
    requestStderr = "";
    searchProcess.command = buildSearchCommand(request.query, request.pageSize);
    searchProcess.running = true;
  }

  Process {
    id: searchProcess

    stdout: StdioCollector {
      onStreamFinished: root.requestStdout = text || ""
    }

    stderr: StdioCollector {
      onStreamFinished: root.requestStderr = text || ""
    }

    onExited: function(exitCode) {
      var request = root.activeRequest;
      root.activeRequest = null;
      if (request) {
        if (exitCode === 0) {
          try {
            var results = root.parseSearchResponse(root.requestStdout);
            root.searchFinished({
              "query": request.query,
              "pageSize": request.pageSize,
              "results": results
            });
          } catch (error) {
            console.log("[AnimeThemes] Failed to parse response:", error);
            root.searchFailed("AnimeThemes returned data in an unexpected format.");
          }
        } else {
          console.log("[AnimeThemes] Search failed:", root.requestStderr || ("search exited " + exitCode));
          root.searchFailed("AnimeThemes search failed. Check your network connection or try again.");
        }
      }

      if (root.pendingRequest) {
        var next = root.pendingRequest;
        root.pendingRequest = null;
        root.searchAnime(next.query, next.pageSize);
      }
    }
  }
}
