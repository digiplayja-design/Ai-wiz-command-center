package com.korlix.capture;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.webkit.JavascriptInterface;
import android.webkit.ValueCallback;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import java.io.ByteArrayInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.nio.charset.StandardCharsets;
import org.json.JSONArray;
import org.json.JSONObject;

/** Native Android rendering fixture; not the signed production APK. */
public final class CaptureActivity extends Activity {
    private final Handler handler = new Handler(Looper.getMainLooper());
    private WebView view;
    private String screen;
    private int scrollDp;
    private int attempts;
    private boolean prepared;
    private static final String TRAINING = "Keep answers clear and practical.\nUse short steps when explaining a task.";
    private static final String MEMORY = "Our office closes at 4 PM on Fridays.";

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        screen = getIntent().getStringExtra("screen");
        if (!"home".equals(screen) && !"train".equals(screen) && !"memory".equals(screen) && !"brain".equals(screen)) screen = "home";
        scrollDp = Math.max(0, Math.min(500, getIntent().getIntExtra("scroll", 0)));
        new File(getFilesDir(), "capture-state.json").delete();
        getWindow().setStatusBarColor(0xff08070d);
        getWindow().setNavigationBarColor(0xff08070d);
        getWindow().getDecorView().setSystemUiVisibility(0);
        view = new WebView(this);
        view.setBackgroundColor(0xff08070d);
        WebSettings settings = view.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(true);
        settings.setAllowContentAccess(false);
        settings.setBlockNetworkLoads(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setSupportZoom(false);
        settings.setTextZoom(100);
        view.addJavascriptInterface(new Bridge(), "Korlix");
        view.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView v, WebResourceRequest request) {
                return !request.getUrl().toString().startsWith("file:///android_asset/");
            }
            @Override public WebResourceResponse shouldInterceptRequest(WebView v, WebResourceRequest request) {
                String scheme = request.getUrl().getScheme();
                if ("http".equals(scheme) || "https".equals(scheme)) return new WebResourceResponse("text/plain", "UTF-8", new ByteArrayInputStream(new byte[0]));
                return null;
            }
            @Override public void onPageFinished(WebView v, String url) {
                if (!prepared) {
                    prepared = true;
                    handler.postDelayed(new Runnable() { @Override public void run() { waitForLoaded(); } }, 6000);
                }
            }
        });
        setContentView(view);
        view.loadUrl("file:///android_asset/web/index.html");
    }

    private void waitForLoaded() {
        view.evaluateJavascript("document.querySelector('#cinema-kb-account-status')?.textContent==='Account connected' && document.fonts.status==='loaded' && document.querySelector('.kb-product')?.dataset.boot==='ready'", new ValueCallback<String>() {
            @Override public void onReceiveValue(String ready) {
                if (!"true".equals(ready)) {
                    if (++attempts > 60) { writeState("Page did not finish loading"); return; }
                    handler.postDelayed(new Runnable() { @Override public void run() { waitForLoaded(); } }, 500);
                    return;
                }
                String navigation = "home".equals(screen) ? "void 0" : "document.querySelector('section[data-screen=\"home\"] [data-go=\"" + screen + "\"]').click()";
                view.evaluateJavascript(navigation, null);
                handler.postDelayed(new Runnable() { @Override public void run() { prepareCapture(); } }, 1200);
            }
        });
    }

    private void prepareCapture() {
        // Exercise the existing form and motion controls; do not rewrite layout or CSS.
        String js = "(()=>{const motion=document.getElementById('cinema-kb-motion-toggle');if(motion?.getAttribute('aria-pressed')==='false')motion.click();";
        if ("memory".equals(screen)) js += "const input=document.getElementById('cinema-kb-memory');input.value=" + JSONObject.quote(MEMORY) + ";input.dispatchEvent(new Event('input',{bubbles:true}));";
        js += "document.activeElement?.blur();return document.querySelector('section[data-screen]:not([hidden])')?.dataset.screen;})()";
        view.evaluateJavascript(js, new ValueCallback<String>() {
            @Override public void onReceiveValue(String actual) {
                if (!JSONObject.quote(screen).equals(actual)) { writeState("Unexpected screen: " + actual); return; }
                // Native WebView scroll, preserving the app's original layout.
                view.scrollTo(0, Math.round(scrollDp * getResources().getDisplayMetrics().density));
                handler.postDelayed(new Runnable() { @Override public void run() { writeState(null); } }, 800);
            }
        });
    }

    private void writeState(final String error) {
        view.evaluateJavascript("JSON.stringify({screen:document.querySelector('section[data-screen]:not([hidden])')?.dataset.screen,account:document.getElementById('cinema-kb-account-status')?.textContent,viewport:{width:innerWidth,height:innerHeight,dpr:devicePixelRatio,scrollY:scrollY},fonts:document.fonts.status,title:document.title})", new ValueCallback<String>() {
            @Override public void onReceiveValue(String raw) {
                try {
                    JSONObject result = new JSONObject();
                    result.put("captureType", "native-android-webview-with-local-fixture-data");
                    result.put("productionApkRuntime", false);
                    result.put("screen", screen);
                    result.put("requestedScrollDp", scrollDp);
                    result.put("nativeScrollPixels", view.getScrollY());
                    result.put("webView", WebView.getCurrentWebViewPackage().versionName);
                    result.put("page", new JSONArray("[" + raw + "]").getString(0));
                    if (error != null) result.put("error", error);
                    try (FileOutputStream out = openFileOutput("capture-state.json", MODE_PRIVATE)) { out.write(result.toString(2).getBytes(StandardCharsets.UTF_8)); }
                } catch (Exception exception) { android.util.Log.e("KorlixCapture", "Could not write capture state", exception); }
            }
        });
    }

    public final class Bridge {
        @JavascriptInterface public void postMessage(String raw) {
            try {
                JSONObject request = new JSONObject(raw);
                JSONObject reply = new JSONObject();
                reply.put("type", "reply"); reply.put("id", request.getString("id"));
                String action = request.getString("action");
                if ("load".equals(action)) {
                    JSONObject memory = new JSONObject();
                    memory.put("id", "sample-office-hours"); memory.put("content", MEMORY); memory.put("source", "Typed entry");
                    JSONObject snapshot = new JSONObject();
                    snapshot.put("training", TRAINING); snapshot.put("memories", new JSONArray().put(memory)); snapshot.put("canUndo", false);
                    reply.put("data", snapshot);
                } else if ("listSavedTranscripts".equals(action)) reply.put("data", new JSONArray());
                else if ("welcomeState".equals(action)) reply.put("data", new JSONObject().put("native", true).put("automatic", false).put("foreground", true));
                else if ("stopWelcome".equals(action) || "stopDictation".equals(action) || "welcomeHeard".equals(action)) reply.put("data", JSONObject.NULL);
                else reply.put("error", "This offline screenshot fixture does not execute " + action + ".");
                final String script = "window.KorlixBrainReceive(" + reply.toString() + ")";
                handler.post(new Runnable() { @Override public void run() { view.evaluateJavascript(script, null); } });
            } catch (Exception exception) { android.util.Log.e("KorlixCapture", "Invalid bridge message", exception); }
        }
    }
}
