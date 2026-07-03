{{flutter_js}}
{{flutter_build_config}}

(function () {
  const bootStartedAt = Date.now();

  function korlixBootStatus(message, isError) {
    let box = document.getElementById("korlix-web-boot-status");

    if (!box) {
      box = document.createElement("pre");
      box.id = "korlix-web-boot-status";
      box.style.cssText = [
        "position:fixed",
        "left:0",
        "right:0",
        "top:0",
        "z-index:2147483647",
        "max-height:62vh",
        "overflow:auto",
        "white-space:pre-wrap",
        "background:" + (isError ? "#160207" : "#050b16"),
        "color:#ffffff",
        "font:13px/1.38 system-ui,-apple-system,BlinkMacSystemFont,Segoe UI,sans-serif",
        "padding:14px 16px",
        "border-bottom:3px solid " + (isError ? "#ff4d6d" : "#69d9e8"),
        "box-sizing:border-box"
      ].join(";");

      document.documentElement.appendChild(box);
    }

    box.textContent = message;
  }

  function korlixErrorDetails(prefix, eventOrError) {
    const elapsed = Date.now() - bootStartedAt;
    const url = window.location ? window.location.href : "";
    const baseUri = document.baseURI || "";
    const userAgent = navigator.userAgent || "";

    if (eventOrError && eventOrError.message !== undefined) {
      return [
        prefix,
        "",
        eventOrError.message || "Script error.",
        "",
        "source: " + (eventOrError.filename || ""),
        "line: " + (eventOrError.lineno || ""),
        "column: " + (eventOrError.colno || ""),
        "",
        (eventOrError.error && eventOrError.error.stack) || "",
        "",
        "elapsedMs: " + elapsed,
        "url: " + url,
        "baseURI: " + baseUri,
        "userAgent: " + userAgent
      ].join("\n");
    }

    return [
      prefix,
      "",
      eventOrError && eventOrError.stack
        ? eventOrError.stack
        : String(eventOrError || "Unknown error"),
      "",
      "elapsedMs: " + elapsed,
      "url: " + url,
      "baseURI: " + baseUri,
      "userAgent: " + userAgent
    ].join("\n");
  }

  function korlixRemoveBootStatusSoon() {
    window.setTimeout(function () {
      const box = document.getElementById("korlix-web-boot-status");

      if (box && box.parentNode) {
        box.parentNode.removeChild(box);
      }
    }, 900);
  }

  window.addEventListener("error", function (event) {
    korlixBootStatus(
      korlixErrorDetails("KORLIX WEB BOOT ERROR", event),
      true
    );
  });

  window.addEventListener("unhandledrejection", function (event) {
    korlixBootStatus(
      korlixErrorDetails("KORLIX WEB BOOT PROMISE ERROR", event.reason),
      true
    );
  });

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker
      .getRegistrations()
      .then(function (registrations) {
        registrations.forEach(function (registration) {
          registration.unregister().catch(function () {});
        });
      })
      .catch(function () {});
  }

  korlixBootStatus("Starting Korlix AI web app…", false);

  const urlParams = new URLSearchParams(window.location.search);
  const requestedRenderer = urlParams.get("renderer");
  const engineConfig = {};

  if (requestedRenderer) {
    engineConfig.renderer = requestedRenderer;
  }

  async function startKorlixFlutter(engineInitializer) {
    korlixBootStatus("Loading Korlix AI engine…", false);

    const appRunner = await engineInitializer.initializeEngine(engineConfig);

    korlixBootStatus("Painting Korlix AI…", false);

    await appRunner.runApp();

    korlixRemoveBootStatusSoon();
  }

  try {
    const loadOptions = {
      onEntrypointLoaded: startKorlixFlutter
    };

    if (Object.keys(engineConfig).length > 0) {
      loadOptions.config = engineConfig;
    }

    const loadResult = _flutter.loader.load(loadOptions);

    if (loadResult && typeof loadResult.catch === "function") {
      loadResult.catch(function (error) {
        korlixBootStatus(
          korlixErrorDetails("KORLIX WEB LOADER FAILED", error),
          true
        );
      });
    }
  } catch (error) {
    korlixBootStatus(
      korlixErrorDetails("KORLIX WEB LOADER THREW", error),
      true
    );
  }

  window.setTimeout(function () {
    const hasFlutterView =
      document.querySelector("flt-glass-pane") ||
      document.querySelector("flutter-view") ||
      document.querySelector("canvas");

    const bootBox = document.getElementById("korlix-web-boot-status");

    if (!hasFlutterView && bootBox) {
      korlixBootStatus(
        [
          "KORLIX WEB STILL WAITING",
          "",
          "The HTML and JavaScript loaded, but Flutter has not painted yet.",
          "This usually means the web runtime failed before the first app frame.",
          "",
          "Renderer: Flutter default" + (requestedRenderer ? " / requested " + requestedRenderer : ""),
          "URL: " + window.location.href,
          "Base URI: " + document.baseURI,
          "User agent: " + navigator.userAgent,
          "",
          "Try a hard refresh. If this remains, send this full screen text."
        ].join("\n"),
        true
      );
    }
  }, 12000);
})();
