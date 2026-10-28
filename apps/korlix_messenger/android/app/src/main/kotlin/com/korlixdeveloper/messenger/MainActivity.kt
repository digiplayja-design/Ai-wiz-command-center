package com.korlixdeveloper.messenger

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.google.android.play.core.review.ReviewManagerFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private var soundEffects: KorlixSoundEffects? = null
    private var socialCalls: MethodChannel? = null
    private var foreground = false
    private val callKinds = mutableMapOf<String, String>()
    private val pendingProjections = mutableMapOf<String, MethodChannel.Result>()
    private val pendingCalls = mutableMapOf<String, MethodChannel.Result>()
    private var approvedCall: String? = null
    private var storeReviews: MethodChannel? = null
    private var pendingStoreReview: MethodChannel.Result? = null
    private var storeReviewLaunched = false
    private val storeReviewHandler = Handler(Looper.getMainLooper())
    private var storeReviewDeadline: Runnable? = null
    private var socialNative: KorlixSocialNativeChannel? = null

    private fun finishStoreReview(result: MethodChannel.Result, accepted: Boolean) {
        if (pendingStoreReview !== result) return
        storeReviewDeadline?.let(storeReviewHandler::removeCallbacks)
        storeReviewDeadline = null
        pendingStoreReview = null
        storeReviewLaunched = false
        result.success(accepted)
    }

    private fun requestStoreReview(result: MethodChannel.Result) {
        if (!foreground || isFinishing || isDestroyed || pendingStoreReview != null) {
            result.success(false)
            return
        }
        pendingStoreReview = result
        storeReviewLaunched = false
        // A late preparation response must not surface on an unrelated screen
        // after the neutral pause that initiated the request has passed.
        storeReviewDeadline = Runnable { finishStoreReview(result, false) }
            .also { storeReviewHandler.postDelayed(it, 15000) }
        try {
            val manager = ReviewManagerFactory.create(this)
            manager.requestReviewFlow().addOnCompleteListener { preparation ->
                if (pendingStoreReview !== result) return@addOnCompleteListener
                if (!preparation.isSuccessful || !foreground || isFinishing || isDestroyed) {
                    finishStoreReview(result, false)
                    return@addOnCompleteListener
                }
                try {
                    storeReviewLaunched = true
                    storeReviewDeadline?.let(storeReviewHandler::removeCallbacks)
                    storeReviewDeadline = null
                    manager.launchReviewFlow(this, preparation.result)
                        .addOnCompleteListener { flow ->
                            // Successful completion does not reveal whether
                            // Play displayed its UI or collected any review.
                            finishStoreReview(result, flow.isSuccessful)
                        }
                } catch (_: Exception) {
                    finishStoreReview(result, false)
                }
            }
        } catch (_: Exception) {
            finishStoreReview(result, false)
        }
    }

    private fun launchSocialCall(id: String) {
        if (!pendingCalls.containsKey(id) || !KorlixSocialCallService.authorized.contains(id)) return
        if (!foreground) { approvedCall = id; return }
        approvedCall = null
        try {
            val intent = Intent(this, KorlixSocialCallService::class.java).putExtra("id", id)
                .putExtra("kind", callKinds[id] ?: "social")
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
        } catch (_: Exception) {
            KorlixSocialCallService.authorized.remove(id)
            pendingCalls.remove(id)?.success(false)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        socialNative = KorlixSocialNativeChannel(this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KorlixSocialNative.CHANNEL), true)
        KorlixSocialNative.acceptIntent(this, intent)
        storeReviews = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "korlix/store_review")
        storeReviews?.setMethodCallHandler { call, result ->
            if (call.method == "requestReview") requestStoreReview(result)
            else if (call.method == "cancelPendingReview") {
                if (!storeReviewLaunched) pendingStoreReview?.let { finishStoreReview(it, false) }
                result.success(null)
            }
            else result.notImplemented()
        }
        soundEffects = KorlixSoundEffects(
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "korlix/sound_effects"),
            cacheDir
        )
        socialCalls = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "korlix/social_call_background")
        KorlixSocialCallService.onStarted = { id, ready -> pendingCalls.remove(id)?.success(ready); callKinds.remove(id) }
        KorlixSocialCallService.onProjectionChanged = { id, ready -> pendingProjections.remove(id)?.success(ready) }
        KorlixSocialCallService.onScreenStopRequested = { id -> socialCalls?.invokeMethod("stopScreenSharing", mapOf("id" to id)) }
        KorlixSocialCallService.onStopped = { id ->
            pendingProjections.remove(id)?.success(false)
            socialCalls?.invokeMethod("stopped", mapOf("id" to id))
        }
        socialCalls?.setMethodCallHandler { call, result ->
            val id = call.argument<String>("id")
            if (id == null || !id.matches(Regex("[A-Za-z0-9-]{1,80}"))) {
                result.success(false)
            } else if (call.method == "stop") {
                KorlixSocialCallService.authorized.remove(id)
                callKinds.remove(id)
                if (approvedCall == id) approvedCall = null
                pendingCalls.remove(id)?.success(false)
                pendingProjections.remove(id)?.success(false)
                if (KorlixSocialCallService.activeId == id) stopService(Intent(this, KorlixSocialCallService::class.java))
                result.success(true)
            } else if (call.method == "screenSharing") {
                if (KorlixSocialCallService.activeId != id || !KorlixSocialCallService.authorized.contains(id) || pendingProjections.containsKey(id)) {
                    result.success(false)
                } else {
                    pendingProjections[id] = result
                    Handler(Looper.getMainLooper()).postDelayed({
                        if (pendingProjections[id] === result) pendingProjections.remove(id)?.success(false)
                    }, 8000)
                    try {
                        startService(Intent(this, KorlixSocialCallService::class.java).setAction("projection")
                            .putExtra("id", id).putExtra("screenSharing", call.argument<Boolean>("active") == true))
                    } catch (_: Exception) { pendingProjections.remove(id)?.success(false) }
                }
            } else if (call.method == "start") {
                // Start while the Activity is visible, after getUserMedia has
                // granted RECORD_AUDIO. POST_NOTIFICATIONS is not required to
                // start an FGS; waiting for that prompt can strand an active call.
                val kind = call.argument<String>("kind") ?: "social"
                val microphone = checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
                if (kind !in setOf("social", "rici") || !foreground || !microphone || pendingCalls.containsKey(id)) {
                    result.success(false)
                } else {
                    callKinds[id] = kind
                    pendingCalls[id] = result
                    KorlixSocialCallService.authorized.add(id)
                    launchSocialCall(id)
                }
            } else { result.notImplemented() }
        }
    }

    override fun onResume() {
        super.onResume()
        foreground = true
        socialNative?.foreground = true
        approvedCall?.let(::launchSocialCall)
        soundEffects?.foreground = true
    }

    override fun onPause() {
        foreground = false
        socialNative?.foreground = false
        // The Play UI itself can pause us. Only cancel before it is launched.
        if (!storeReviewLaunched) pendingStoreReview?.let { finishStoreReview(it, false) }
        soundEffects?.pause()
        super.onPause()
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        socialNative?.onPermissionResult(requestCode, grantResults)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        socialNative?.close()
        socialNative = null
        pendingStoreReview?.let { finishStoreReview(it, false) }
        storeReviews?.setMethodCallHandler(null)
        storeReviews = null
        pendingCalls.values.forEach { it.success(false) }
        pendingCalls.clear()
        pendingProjections.values.forEach { it.success(false) }
        pendingProjections.clear()
        KorlixSocialCallService.onProjectionChanged = null
        KorlixSocialCallService.onScreenStopRequested = null
        callKinds.clear()
        approvedCall = null
        KorlixSocialCallService.authorized.clear()
        stopService(Intent(this, KorlixSocialCallService::class.java))
        KorlixSocialCallService.onStarted = null
        KorlixSocialCallService.onStopped = null
        socialCalls?.setMethodCallHandler(null)
        socialCalls = null
        soundEffects?.close()
        soundEffects = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        KorlixSocialNative.acceptIntent(this, intent)
    }
}

/** SoundPool mixes short effects without requesting focus or changing routing. */
private class KorlixSoundEffects(
    private val channel: MethodChannel,
    private val cacheDir: File
) {
    private val handler = Handler(Looper.getMainLooper())
    private val names = setOf("effect", "ring", "preview")
    private var owner: String? = null
    private var pool: SoundPool? = null
    private val revisions = mutableMapOf<String, Long>()
    private val playing = mutableMapOf<String, Cue>()
    private val pending = mutableMapOf<Int, Cue>()
    var foreground = false

    private class Cue(
        val owner: String,
        val name: String,
        val revision: Long,
        val file: File,
        val volume: Float,
        val loop: Boolean,
        val expires: Long,
        val prepareDeadline: Long,
        val duration: Long,
        var result: MethodChannel.Result?
    ) {
        var sample = 0
        var stream = 0
        var timeout: Runnable? = null
        fun complete(value: Boolean) {
            val callback = result
            result = null
            callback?.success(value)
        }
    }

    init { channel.setMethodCallHandler(::handle) }

    private fun initialize() {
        if (pool != null) return
        val next = SoundPool.Builder().setMaxStreams(3).setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
        ).build()
        pool = next
        next.setOnLoadCompleteListener { source, sample, status ->
            handler.post {
                // A callback from a disposed pool cannot claim a new pool's ID.
                if (source !== pool) return@post
                val cue = pending.remove(sample) ?: return@post
                cue.file.delete()
                if (playing[cue.name] !== cue || owner != cue.owner || !foreground ||
                    revisions[cue.name] != cue.revision ||
                    SystemClock.uptimeMillis() >= cue.prepareDeadline ||
                    (cue.loop && SystemClock.uptimeMillis() >= cue.expires)) {
                    if (playing[cue.name] === cue) stop(cue.name)
                    else source.unload(sample)
                    cue.complete(true)
                    return@post
                }
                if (status != 0) {
                    cue.complete(false)
                    stop(cue.name)
                    return@post
                }
                cue.stream = source.play(sample, cue.volume, cue.volume, 1, if (cue.loop) -1 else 0, 1f)
                if (cue.stream != 0) {
                    // A short effect gets its full duration after loading.
                    // Ringing still ends at the original absolute deadline.
                    arm(cue, if (cue.loop) cue.expires - SystemClock.uptimeMillis() else cue.duration)
                }
                cue.complete(cue.stream != 0)
                if (cue.stream == 0) stop(cue.name)
            }
        }
    }

    private fun arm(cue: Cue, milliseconds: Long) {
        cue.timeout?.let(handler::removeCallbacks)
        cue.timeout = Runnable {
            if (playing[cue.name] === cue) stop(cue.name)
        }.also { handler.postDelayed(it, milliseconds.coerceIn(0, 45000)) }
    }

    private fun stop(name: String) {
        val cue = playing.remove(name) ?: return
        pending.remove(cue.sample)
        cue.timeout?.let(handler::removeCallbacks)
        if (cue.stream != 0) pool?.stop(cue.stream)
        if (cue.sample != 0) pool?.unload(cue.sample)
        cue.file.delete()
        // Cancellation is intentional, not a playback permission failure.
        cue.complete(true)
    }

    private fun stopAll() { names.forEach(::stop) }

    fun pause() {
        foreground = false
        stopAll()
    }

    fun close() {
        stopAll()
        pool?.release()
        pool = null
        owner = null
        channel.setMethodCallHandler(null)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val requestOwner = call.argument<String>("owner") ?: run { result.success(false); return }
        if (call.method == "activate") {
            stopAll()
            owner = requestOwner
            revisions.clear()
            try {
                initialize()
                result.success(foreground)
            } catch (_: Exception) { result.success(false) }
            return
        }
        if (requestOwner != owner) { result.success(false); return }
        when (call.method) {
            "stopAll", "dispose" -> {
                stopAll()
                call.argument<Map<String, Number>>("revisions")?.forEach { (name, revision) ->
                    if (name in names) revisions[name] = maxOf(revisions[name] ?: 0, revision.toLong())
                }
                if (call.method == "dispose") {
                    pool?.release()
                    pool = null
                    owner = null
                }
                result.success(true)
            }
            "stop", "play" -> {
                val name = call.argument<String>("channel")
                val revision = call.argument<Number>("revision")?.toLong()
                if (name !in names || revision == null || revision <= (revisions[name] ?: 0)) {
                    result.success(false); return
                }
                val validName = name!!
                revisions[validName] = revision
                stop(validName)
                if (call.method == "stop") { result.success(true); return }
                val wav = call.argument<ByteArray>("wav")
                val volume = call.argument<Number>("volume")?.toFloat()
                val duration = call.argument<Number>("durationMs")?.toLong() ?: 0
                val activePool = pool
                val nowEpoch = System.currentTimeMillis()
                val prepareBudget = ((call.argument<Number>("prepareDeadlineEpochMs")?.toLong() ?: 0) - nowEpoch).coerceAtMost(if (validName == "ring") 1500L else 500L)
                val ringBudget = ((call.argument<Number>("expiresEpochMs")?.toLong() ?: 0) - nowEpoch).coerceAtMost(45000)
                val loop = call.argument<Boolean>("loop") == true
                if (!foreground || activePool == null || wav == null || wav.size !in 44..200000 ||
                    !wav.copyOfRange(0, 4).contentEquals(byteArrayOf(82, 73, 70, 70)) ||
                    volume == null || !volume.isFinite() || volume <= 0 || duration <= 0) {
                    result.success(false); return
                }
                if (prepareBudget <= 0 || (loop && ringBudget <= 0)) {
                    result.success(true); return
                }
                val requestedAt = SystemClock.uptimeMillis()
                var file: File? = null
                try {
                    file = File.createTempFile("korlix-cue-", ".wav", cacheDir)
                    file.writeBytes(wav)
                    val cue = Cue(requestOwner, validName, revision, file, volume.coerceIn(0f, 1f),
                        loop, requestedAt + ringBudget,
                        requestedAt + prepareBudget, duration.coerceAtMost(5000), result)
                    playing[validName] = cue
                    arm(cue, minOf(cue.prepareDeadline, if (loop) cue.expires else cue.prepareDeadline) - SystemClock.uptimeMillis())
                    cue.sample = activePool.load(file.absolutePath, 1)
                    if (cue.sample == 0) {
                        cue.complete(false)
                        stop(validName)
                    } else pending[cue.sample] = cue
                } catch (_: Exception) {
                    file?.delete()
                    val cue = playing[validName]
                    if (cue != null) {
                        cue.complete(false)
                        stop(validName)
                    } else result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }
}
