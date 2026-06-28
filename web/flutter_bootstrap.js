{{flutter_js}}
{{flutter_build_config}}

(function () {
  const korlixFlutterConfig = {
    renderer: "canvaskit",
    useLocalCanvasKit: true,
    canvasKitBaseUrl: "canvaskit/"
  };

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
        "max-height:55vh",
        "overflow:auto",
        "white-space:pre-wrap",
        "background:" + (isError ? "#160207" : "#050b16"),
        "color:#ffffff",
        "font:13px/1.35 system-ui, -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif",
        "padding:14px 16px",
        "border-bottom:3px solid " + (isError ? "#ff4d6d" : "#69d9e8")
      ].join(";");

      document.documentElement.appendChild(box);
    }

    box.textContent = message;
  }

  function korlixRemoveBootStatusSoon() {
    window.setTimeout(function () {
      const box = document.getElementById("korlix-web-boot-status");

      if (box && box.parentNode) {
        box.parentNode.removeChild(box);
      }
    }, 700);
  }

  window.addEventListener("error", function (event) {
    korlixBootStatus(
      "KORLIX WEB BOOT ERROR\n\n" +
        (event.message || "Unknown JavaScript error") +
        "\n\nsource: " + (event.filename || "") +
        "\nline: " + (event.lineno || "") +
        "\ncolumn: " + (event.colno || "") +
        "\n\n" + ((event.error && event.error.stack) || ""),
      true
    );
  });

  window.addEventListener("unhandledrejection", function (event) {
    const reason = event.reason;
    korlixBootStatus(
      "KORLIX WEB BOOT PROMISE ERROR\n\n" +
        (reason && reason.stack ? reason.stack : String(reason)),
      true
    );
  });

  korlixBootStatus("Starting Korlix AI web app…", false);

  _flutter.loader
    .load({
      config: korlixFlutterConfig,
      onEntrypointLoaded: async function (engineInitializer) {
        korlixBootStatus("Loading Korlix AI engine…", false);

        const appRunner = await engineInitializer.initializeEngine(
          korlixFlutterConfig
        );

        korlixBootStatus("Painting Korlix AI…", false);

        await appRunner.runApp();

        korlixRemoveBootStatusSoon();
      }
    })
    .catch(function (error) {
      korlixBootStatus(
        "KORLIX WEB LOADER FAILED\n\n" +
          (error && error.stack ? error.stack : String(error)),
        true
      );
    });

  window.setTimeout(function () {
    const hasFlutterView =
      document.querySelector("flt-glass-pane") ||
      document.querySelector("flutter-view") ||
      document.querySelector("canvas");

    const bootBox = document.getElementById("korlix-web-boot-status");

    if (!hasFlutterView && bootBox) {
      korlixBootStatus(
        "KORLIX WEB STILL WAITING\n\n" +
          "The HTML and JavaScript loaded, but Flutter has not painted yet.\n" +
          "This usually means the engine renderer failed before the app frame.\n\n" +
          "Renderer: local CanvasKit\n" +
          "CanvasKit path: /canvaskit/\n" +
          "URL: " + window.location.href,
        true
      );
    }
  }, 10000);
})();
