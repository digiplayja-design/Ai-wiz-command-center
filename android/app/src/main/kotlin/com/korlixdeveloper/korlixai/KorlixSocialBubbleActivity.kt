package com.korlixdeveloper.korlixai

import android.os.Bundle
import android.content.Intent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Dedicated, isolated UI: never reuses the main FlutterEngine or its account binding. */
class KorlixSocialBubbleActivity : FlutterActivity() {
    private var socialNative: KorlixSocialNativeChannel? = null
    override fun getDartEntrypointFunctionName(): String = "socialBubbleMain"

    override fun onCreate(savedInstanceState: Bundle?) {
        val validLaunch = KorlixSocialNative.launchAction(this, intent) != null
        // Hide the authenticated chat in screenshots/recents and on lock screens.
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        super.onCreate(savedInstanceState)
        if (!validLaunch) { finish(); return }
        KorlixSocialNative.attachBubble(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        socialNative = KorlixSocialNativeChannel(this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KorlixSocialNative.CHANNEL), false)
    }

    override fun onResume() {
        super.onResume()
        if (KorlixSocialNative.launchAction(this, intent) == null) finish()
    }

    fun invalidateAccount() {
        socialNative?.invalidateAccount()
        finish()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (KorlixSocialNative.launchAction(this, intent) == null) finish() else recreate()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        socialNative?.close()
        socialNative = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
