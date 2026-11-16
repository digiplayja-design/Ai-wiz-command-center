package com.korlixdeveloper.esha

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var selfieDetector: SelfieFaceDetector? = null
    private var selfieChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val detector = SelfieFaceDetector()
        selfieDetector = detector
        selfieChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.korlixdeveloper.esha/selfie",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "detectFaces" -> detector.detectFaces(call.arguments, result)
                    "temporaryDirectory" -> {
                        try {
                            result.success(applicationContext.cacheDir.canonicalPath)
                        } catch (_: Exception) {
                            result.error("temporary_directory_unavailable", "Temporary photo storage is unavailable.", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        selfieChannel?.setMethodCallHandler(null)
        selfieChannel = null
        selfieDetector?.close()
        selfieDetector = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
