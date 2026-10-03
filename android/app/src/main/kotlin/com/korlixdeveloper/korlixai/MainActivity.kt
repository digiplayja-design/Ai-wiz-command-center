package com.korlixdeveloper.korlixai

import android.media.AudioAttributes
import android.media.SoundPool
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private var soundEffects: KorlixSoundEffects? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        soundEffects = KorlixSoundEffects(
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "korlix/sound_effects"),
            cacheDir
        )
    }

    override fun onResume() {
        super.onResume()
        soundEffects?.foreground = true
    }

    override fun onPause() {
        soundEffects?.pause()
        super.onPause()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        soundEffects?.close()
        soundEffects = null
        super.cleanUpFlutterEngine(flutterEngine)
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
                .setUsage(AudioAttributes.USAGE_ASSISTANCE_SONIFICATION)
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
                val prepareBudget = ((call.argument<Number>("prepareDeadlineEpochMs")?.toLong() ?: 0) - nowEpoch).coerceAtMost(250)
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
