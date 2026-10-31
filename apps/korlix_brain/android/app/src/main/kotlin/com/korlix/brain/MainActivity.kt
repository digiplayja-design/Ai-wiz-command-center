package com.korlix.brain

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Build
import android.Manifest
import android.content.pm.PackageManager

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "korlix.brain/voice-lifecycle")
        BrainVoiceService.stopRequested = { channel.invokeMethod("stopRequested", null) }
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    try {
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 3041)
                        }
                        val intent = Intent(this, BrainVoiceService::class.java)
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("voice_service", "Could not keep your conversation active. Reopen the app and try again.", null)
                    }
                }
                "stop" -> { stopService(Intent(this, BrainVoiceService::class.java)); result.success(null) }
                else -> result.notImplemented()
            }
        }
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        BrainVoiceService.stopRequested = null
        stopService(Intent(this, BrainVoiceService::class.java))
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
