pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  visible: false

  property Component booruResponseDataComponent: BooruResponseData {}

  signal tagSuggestion(string query, var suggestions)
  signal providerTagIndexLoaded(string providerKey, var suggestions)
  signal responseFinished()

  property string failMessage: "That didn't work. Tips:\n- Check your tags and safe-mode setting\n- If you don't have a tag in mind, try a page number"
  property var responses: []
  property int runningRequests: 0
  property string defaultUserAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"
  property string currentProvider: "yandere"
  property string curlAcceptHeader: "Accept: application/json"
  property string danbooruRequestStdout: ""
  property string danbooruRequestStderr: ""
  property var activeDanbooruApiRequest: null
  property var pendingDanbooruApiRequest: null
  property string danbooruTagStdout: ""
  property string danbooruTagStderr: ""
  property var activeDanbooruTagRequest: null
  property string pendingDanbooruTagQuery: ""
  property string danbooruTagIndexStdout: ""
  property string danbooruTagIndexStderr: ""
  property var activeDanbooruTagIndexRequest: null

  function absoluteUrl(baseUrl, value) {
    var raw = String(value || "").trim();
    if (raw === "")
      return "";
    if (/^https?:\/\//i.test(raw))
      return raw;
    var base = String(baseUrl || "").replace(/\/$/, "");
    if (base === "")
      return raw;
    if (raw.indexOf("//") === 0)
      return "https:" + raw;
    if (raw.charAt(0) === "/")
      return base + raw;
    return base + "/" + raw;
  }

  property var providers: ({
      "yandere": {
        "name": "yande.re",
        "url": "https://yande.re",
        "api": "https://yande.re/post.json",
        "postUrlTemplate": "https://yande.re/post/show/{{id}}",
        "safeTag": "rating:safe",
        "description": "All-rounder | Good quality, decent quantity",
        "mapFunc": function (response) {
          return response.map(function (item) {
            return {
              "id": item.id,
              "width": item.width,
              "height": item.height,
              "aspect_ratio": item.width / item.height,
              "tags": item.tags,
              "rating": item.rating,
              "is_nsfw": (item.rating !== "s"),
              "md5": item.md5,
              "preview_url": root.absoluteUrl("https://yande.re", item.preview_url),
              "sample_url": root.absoluteUrl("https://yande.re", item.sample_url ? item.sample_url : item.file_url),
              "file_url": root.absoluteUrl("https://yande.re", item.file_url),
              "file_ext": item.file_ext,
              "source": root.getWorkingImageSource(item.source) || item.file_url
            };
          });
        },
        "tagSearchTemplate": "https://yande.re/tag.json?order=count&limit=50&name_pattern={{query}}*",
        "tagListUrl": "https://yande.re/tag.json?order=count&limit=0",
        "tagMapFunc": function (response) {
          return response.map(function (item) {
            return { "name": item.name, "count": item.count };
          });
        }
      },
      "konachan": {
        "name": "Konachan",
        "url": "https://konachan.net",
        "api": "https://konachan.net/post.json",
        "postUrlTemplate": "https://konachan.net/post/show/{{id}}",
        "safeTag": "rating:safe",
        "description": "For desktop wallpapers | Good quality",
        "mapFunc": function (response) {
          return response.map(function (item) {
            return {
              "id": item.id,
              "width": item.width,
              "height": item.height,
              "aspect_ratio": item.width / item.height,
              "tags": item.tags,
              "rating": item.rating,
              "is_nsfw": (item.rating !== "s"),
              "md5": item.md5,
              "preview_url": root.absoluteUrl("https://konachan.net", item.preview_url),
              "sample_url": root.absoluteUrl("https://konachan.net", item.sample_url ? item.sample_url : item.file_url),
              "file_url": root.absoluteUrl("https://konachan.net", item.file_url),
              "file_ext": item.file_ext,
              "source": root.getWorkingImageSource(item.source) || item.file_url
            };
          });
        },
        "tagSearchTemplate": "https://konachan.net/tag.json?order=count&limit=50&name_pattern={{query}}*",
        "tagListUrl": "https://konachan.net/tag.json?order=count&limit=0",
        "tagMapFunc": function (response) {
          return response.map(function (item) {
            return { "name": item.name, "count": item.count };
          });
        }
      },
      "danbooru": {
        "name": "Danbooru",
        "url": "https://donmai.moe",
        "api": "https://donmai.moe/posts.json",
        "postUrlTemplate": "https://donmai.moe/posts/{{id}}",
        "safeTag": "rating:g",
        "useRandomParam": true,
        "tagListPageSize": 1000,
        "description": "Huge tag catalog | Broad anime and illustration coverage",
        "mapFunc": function (response) {
          return response.map(function (item) {
            var width = item.image_width || item.width || 0;
            var height = item.image_height || item.height || 0;
            var tags = item.tag_string || [item.tag_string_general, item.tag_string_copyright, item.tag_string_character, item.tag_string_artist, item.tag_string_meta].filter(function (part) {
              return !!part;
            }).join(" ");
            return {
              "id": item.id,
              "width": width,
              "height": height,
              "aspect_ratio": (width > 0 && height > 0) ? (width / height) : 1,
              "tags": tags,
              "rating": item.rating,
              "is_nsfw": !(item.rating === "g" || item.rating === "s"),
              "md5": item.md5,
              "preview_url": root.absoluteUrl("https://donmai.moe", item.preview_file_url || item.preview_url),
              "sample_url": root.absoluteUrl("https://donmai.moe", item.large_file_url || item.sample_url || item.file_url),
              "file_url": root.absoluteUrl("https://donmai.moe", item.file_url || item.large_file_url || item.sample_url || item.preview_file_url || item.preview_url),
              "file_ext": item.file_ext,
              "source": root.getWorkingImageSource(item.source) || root.absoluteUrl("https://donmai.moe", "/posts/" + item.id)
            };
          });
        },
        "tagSearchTemplate": "https://donmai.moe/tags.json?limit=50&search[is_empty]=false&search[order]=count&search[name_or_alias_matches]={{query}}*",
        "tagListPageTemplate": "https://donmai.moe/tags.json?limit={{limit}}&search[is_empty]=false&search[order]=count&page={{page}}",
        "tagMapFunc": function (response) {
          return response.map(function (item) {
            return { "name": item.name, "count": item.post_count || 0 };
          });
        }
      }
    })

  readonly property var providerList: Object.keys(providers)

  function getWorkingImageSource(url) {
    if (!url || typeof url !== "string")
      return url;
    if (url.indexOf("pximg.net") !== -1) {
      return "https://www.pixiv.net/en/artworks/" + url.substring(url.lastIndexOf("/") + 1).replace(/_p\d+\.(png|jpg|jpeg|gif)$/i, "");
    }
    return url;
  }

  function isDanbooruProvider(providerKey) {
    return String(providerKey || currentProvider || "") === "danbooru";
  }

  function buildCurlJsonCommand(url) {
    return ["curl", "-L", "--fail", "--silent", "--show-error", "-A", root.defaultUserAgent, "-H", root.curlAcceptHeader, String(url || "")];
  }

  function clearResponses() {
    responses = [];
  }

  function addSystemMessage(message) {
    responses = [...responses, root.booruResponseDataComponent.createObject(null, {
      "provider": "system",
      "tags": [],
      "page": -1,
      "images": [],
      "message": String(message)
    })];
  }

  function constructRequestUrl(tags, nsfw, limit, page, randomOrder) {
    var provider = providers[currentProvider];
    var url = provider.api;
    var normalizedTags = (tags || []).slice();

    if (randomOrder && !provider.useRandomParam)
      normalizedTags.push("order:random");

    if (!nsfw)
      normalizedTags.push(String(provider.safeTag || "rating:safe"));

    var params = [];
    params.push("tags=" + encodeURIComponent(normalizedTags.join(" ")));
    params.push("limit=" + limit);
    if (randomOrder && provider.useRandomParam)
      params.push("random=true");
    if (!randomOrder)
      params.push("page=" + page);

    if (randomOrder || currentProvider === "yandere")
      params.push("_=" + Date.now());

    if (url.indexOf("?") === -1)
      return url + "?" + params.join("&");
    return url + "&" + params.join("&");
  }

  function danbooruSearchTagCount(tags) {
    return (tags || []).filter(function (tag) {
      var value = String(tag || "").trim();
      return value !== "" && value.indexOf(":") === -1;
    }).length;
  }

  function isDanbooruAnonymousTagLimitExceeded(tags) {
    return currentProvider === "danbooru" && danbooruSearchTagCount(tags) > 2;
  }

  function makeRequest(tags, nsfw, limit, page, randomOrder) {
    var requestTags = tags || [];
    var requestPage = page || 1;
    var requestLimit = limit || 20;
    var requestRandomOrder = randomOrder === true;
    var providerKey = currentProvider;
    var provider = providers[providerKey];
    var url = constructRequestUrl(requestTags, nsfw === true, requestLimit, requestPage, requestRandomOrder);

    const newResponse = root.booruResponseDataComponent.createObject(null, {
      "provider": providerKey,
      "tags": requestTags,
      "page": requestPage,
      "images": [],
      "message": ""
    });

    if (providerKey === "danbooru" && isDanbooruAnonymousTagLimitExceeded(requestTags)) {
      newResponse.message = "Danbooru allows up to 2 non-meta search tags for anonymous users.";
      root.responses = [...root.responses, newResponse];
      root.responseFinished();
      return;
    }

    if (isDanbooruProvider(providerKey)) {
      if (activeDanbooruApiRequest || danbooruApiProcess.running) {
        pendingDanbooruApiRequest = {
          "url": url,
          "newResponse": newResponse,
          "providerKey": providerKey,
          "provider": provider
        };
        return;
      }
      activeDanbooruApiRequest = {
        "url": url,
        "newResponse": newResponse,
        "providerKey": providerKey,
        "provider": provider
      };
      danbooruRequestStdout = "";
      danbooruRequestStderr = "";
      danbooruApiProcess.command = root.buildCurlJsonCommand(url);
      root.runningRequests += 1;
      danbooruApiProcess.running = true;
      return;
    }

    var xhr = new XMLHttpRequest();
    xhr.open("GET", url);
    xhr.onreadystatechange = function () {
      if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
        try {
          var response = JSON.parse(xhr.responseText);
          response = provider.mapFunc(response).map(function (item) {
            item.provider = providerKey;
            return item;
          });
          newResponse.images = response;
          newResponse.message = response.length > 0 ? "" : root.failMessage;
        } catch (e) {
          console.log("[Booru] Failed to parse response:", e);
          newResponse.message = root.failMessage;
        } finally {
          root.runningRequests = Math.max(0, root.runningRequests - 1);
          root.responses = [...root.responses, newResponse];
          root.responseFinished();
        }
      } else if (xhr.readyState === XMLHttpRequest.DONE) {
        console.log("[Booru] Request failed with status:", xhr.status);
        newResponse.message = root.failMessage;
        root.runningRequests = Math.max(0, root.runningRequests - 1);
        root.responses = [...root.responses, newResponse];
        root.responseFinished();
      }
    };

    try {
      root.runningRequests += 1;
      xhr.send();
    } catch (error) {
      root.runningRequests = Math.max(0, root.runningRequests - 1);
      newResponse.message = root.failMessage;
      root.responses = [...root.responses, newResponse];
      root.responseFinished();
    }
  }

  property var currentTagRequest: null
  property var currentTagIndexRequests: ({})

  function updateTagIndexRequestState(providerKey, active) {
    var next = Object.assign({}, currentTagIndexRequests || {});
    if (active)
      next[providerKey] = true;
    else
      delete next[providerKey];
    currentTagIndexRequests = next;
  }

  function danbooruTagIndexPageUrl(provider, page) {
    var limit = parseInt(provider && provider.tagListPageSize || 1000, 10) || 1000;
    var template = String(provider && provider.tagListPageTemplate || "");
    return template.replace("{{limit}}", String(limit)).replace("{{page}}", String(page));
  }

  function fetchPagedProviderTagIndex(providerKey, provider) {
    var resolvedProviderKey = String(providerKey || currentProvider || "");
    var pageSize = parseInt(provider && provider.tagListPageSize || 1000, 10) || 1000;
    var state = {
      "page": 1,
      "collected": []
    };

    function finish() {
      updateTagIndexRequestState(resolvedProviderKey, false);
      root.providerTagIndexLoaded(resolvedProviderKey, state.collected);
    }

    function fail(status) {
      updateTagIndexRequestState(resolvedProviderKey, false);
      console.log("[Booru] Provider tag index fetch failed for", resolvedProviderKey, "status", status);
    }

    function fetchNextPage() {
      var pageUrl = danbooruTagIndexPageUrl(provider, state.page) + "&_=" + Date.now();
      if (isDanbooruProvider(resolvedProviderKey)) {
        activeDanbooruTagIndexRequest = {
          "providerKey": resolvedProviderKey,
          "provider": provider,
          "pageSize": pageSize,
          "state": state,
          "finish": finish,
          "fail": fail,
          "next": fetchNextPage,
          "url": pageUrl
        };
        danbooruTagIndexStdout = "";
        danbooruTagIndexStderr = "";
        danbooruTagIndexProcess.command = root.buildCurlJsonCommand(pageUrl);
        danbooruTagIndexProcess.running = true;
        return;
      }

      var xhr = new XMLHttpRequest();
      xhr.open("GET", pageUrl);
      xhr.onreadystatechange = function () {
        if (xhr.readyState !== XMLHttpRequest.DONE)
          return;

        if (xhr.status === 200) {
          try {
            var response = JSON.parse(xhr.responseText);
            response = provider.tagMapFunc(response);
            state.collected = state.collected.concat(response);
            if (response.length < pageSize) {
              finish();
              return;
            }
            state.page += 1;
            fetchNextPage();
          } catch (e) {
            console.log("[Booru] Failed to parse provider tag index:", e);
            fail("parse");
          }
        } else {
          fail(xhr.status);
        }
      };

      try {
        xhr.send();
      } catch (error) {
        fail("send");
      }
    }

    updateTagIndexRequestState(resolvedProviderKey, true);
    fetchNextPage();
  }

  function fetchProviderTagIndex(providerKey) {
    var resolvedProviderKey = String(providerKey || currentProvider || "");
    var provider = providers[resolvedProviderKey];
    if (!provider || (!provider.tagListUrl && !provider.tagListPageTemplate))
      return;
    if (currentTagIndexRequests[resolvedProviderKey])
      return;

    if (provider.tagListPageTemplate) {
      fetchPagedProviderTagIndex(resolvedProviderKey, provider);
      return;
    }

    var xhr = new XMLHttpRequest();
    updateTagIndexRequestState(resolvedProviderKey, true);
    xhr.open("GET", provider.tagListUrl + (provider.tagListUrl.indexOf("?") === -1 ? "?" : "&") + "_=" + Date.now());
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE)
        return;

      updateTagIndexRequestState(resolvedProviderKey, false);

      if (xhr.status === 200) {
        try {
          var response = JSON.parse(xhr.responseText);
          response = provider.tagMapFunc(response);
          root.providerTagIndexLoaded(resolvedProviderKey, response);
        } catch (e) {
          console.log("[Booru] Failed to parse provider tag index:", e);
        }
      } else {
        console.log("[Booru] Provider tag index fetch failed for", resolvedProviderKey, "status", xhr.status);
      }
    };

    try {
      xhr.send();
    } catch (error) {
      updateTagIndexRequestState(resolvedProviderKey, false);
    }
  }

  function triggerTagSearch(query) {
    if (currentTagRequest)
      currentTagRequest.abort();

    var provider = providers[currentProvider];
    if (!provider.tagSearchTemplate)
      return;

    var url = provider.tagSearchTemplate.replace("{{query}}", encodeURIComponent(query));
    if (isDanbooruProvider(currentProvider)) {
      pendingDanbooruTagQuery = String(query || "");
      if (danbooruTagProcess.running)
        return;
      activeDanbooruTagRequest = {
        "query": pendingDanbooruTagQuery,
        "provider": provider,
        "url": url
      };
      pendingDanbooruTagQuery = "";
      danbooruTagStdout = "";
      danbooruTagStderr = "";
      danbooruTagProcess.command = root.buildCurlJsonCommand(url);
      danbooruTagProcess.running = true;
      return;
    }

    var xhr = new XMLHttpRequest();
    currentTagRequest = xhr;
    xhr.open("GET", url);
    xhr.onreadystatechange = function () {
      if (xhr.readyState === XMLHttpRequest.DONE && xhr.status === 200) {
        currentTagRequest = null;
        try {
          var response = JSON.parse(xhr.responseText);
          response = provider.tagMapFunc(response);
          root.tagSuggestion(query, response);
        } catch (e) {
          console.log("[Booru] Failed to parse tag response:", e);
        }
      } else if (xhr.readyState === XMLHttpRequest.DONE) {
        currentTagRequest = null;
      }
    };

    try {
      xhr.send();
    } catch (error) {
      currentTagRequest = null;
    }
  }

  Process {
    id: danbooruApiProcess

    stdout: StdioCollector {
      onStreamFinished: root.danbooruRequestStdout = text || ""
    }

    stderr: StdioCollector {
      onStreamFinished: root.danbooruRequestStderr = text || ""
    }

    onExited: function (exitCode) {
      var request = root.activeDanbooruApiRequest;
      root.activeDanbooruApiRequest = null;
      if (!request)
        return;

      var newResponse = request.newResponse;
      if (exitCode === 0) {
        try {
          var response = JSON.parse(root.danbooruRequestStdout || "[]");
          response = request.provider.mapFunc(response).map(function (item) {
            item.provider = request.providerKey;
            return item;
          });
          newResponse.images = response;
          newResponse.message = response.length > 0 ? "" : root.failMessage;
        } catch (e) {
          console.log("[Booru] Failed to parse Danbooru response:", e);
          newResponse.message = root.failMessage;
        }
      } else {
        console.log("[Booru] Danbooru request failed:", root.danbooruRequestStderr || "curl exited " + exitCode);
        newResponse.message = root.failMessage;
      }

      root.runningRequests = Math.max(0, root.runningRequests - 1);
      root.responses = [...root.responses, newResponse];
      root.responseFinished();

      if (root.pendingDanbooruApiRequest) {
        var pending = root.pendingDanbooruApiRequest;
        root.pendingDanbooruApiRequest = null;
        root.activeDanbooruApiRequest = pending;
        root.danbooruRequestStdout = "";
        root.danbooruRequestStderr = "";
        danbooruApiProcess.command = root.buildCurlJsonCommand(pending.url);
        root.runningRequests += 1;
        danbooruApiProcess.running = true;
      }
    }
  }

  Process {
    id: danbooruTagProcess

    stdout: StdioCollector {
      onStreamFinished: root.danbooruTagStdout = text || ""
    }

    stderr: StdioCollector {
      onStreamFinished: root.danbooruTagStderr = text || ""
    }

    onExited: function (exitCode) {
      var request = root.activeDanbooruTagRequest;
      root.activeDanbooruTagRequest = null;
      if (request && exitCode === 0) {
        try {
          var response = JSON.parse(root.danbooruTagStdout || "[]");
          response = request.provider.tagMapFunc(response);
          root.tagSuggestion(request.query, response);
        } catch (e) {
          console.log("[Booru] Failed to parse Danbooru tag response:", e);
        }
      } else if (request && exitCode !== 0) {
        console.log("[Booru] Danbooru tag request failed:", root.danbooruTagStderr || "curl exited " + exitCode);
      }

      if (root.pendingDanbooruTagQuery !== "") {
        var provider = root.providers[root.currentProvider];
        if (provider && root.isDanbooruProvider(root.currentProvider)) {
          var nextQuery = root.pendingDanbooruTagQuery;
          root.pendingDanbooruTagQuery = "";
          root.activeDanbooruTagRequest = {
            "query": nextQuery,
            "provider": provider,
            "url": provider.tagSearchTemplate.replace("{{query}}", encodeURIComponent(nextQuery))
          };
          root.danbooruTagStdout = "";
          root.danbooruTagStderr = "";
          danbooruTagProcess.command = root.buildCurlJsonCommand(root.activeDanbooruTagRequest.url);
          danbooruTagProcess.running = true;
        }
      }
    }
  }

  Process {
    id: danbooruTagIndexProcess

    stdout: StdioCollector {
      onStreamFinished: root.danbooruTagIndexStdout = text || ""
    }

    stderr: StdioCollector {
      onStreamFinished: root.danbooruTagIndexStderr = text || ""
    }

    onExited: function (exitCode) {
      var request = root.activeDanbooruTagIndexRequest;
      if (!request)
        return;

      if (exitCode === 0) {
        try {
          var response = JSON.parse(root.danbooruTagIndexStdout || "[]");
          response = request.provider.tagMapFunc(response);
          request.state.collected = request.state.collected.concat(response);
          if (response.length < request.pageSize) {
            root.activeDanbooruTagIndexRequest = null;
            request.finish();
            return;
          }
          request.state.page += 1;
          root.activeDanbooruTagIndexRequest = null;
          request.next();
          return;
        } catch (e) {
          root.activeDanbooruTagIndexRequest = null;
          console.log("[Booru] Failed to parse Danbooru tag index:", e);
          request.fail("parse");
          return;
        }
      }

      root.activeDanbooruTagIndexRequest = null;
      console.log("[Booru] Danbooru tag index request failed:", root.danbooruTagIndexStderr || "curl exited " + exitCode);
      request.fail(exitCode);
    }
  }
}
