package com.korlixdeveloper.messenger

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log
import android.media.MediaMetadata
import android.media.session.MediaSession
import android.media.session.PlaybackState

/** Holds an explicitly started call, never starts capture or answers a call. */
class KorlixSocialCallService : Service() {
    private var mediaSession: MediaSession? = null
    private var callWakeLock: PowerManager.WakeLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private val renewWakeLock = object : Runnable {
        override fun run() {
            if (activeId == null) return
            // Bound every acquisition and renew only while the foreground call
            // is alive. This keeps signaling timers running with the screen off.
            callWakeLock?.acquire(10 * 60 * 1000L)
            handler.postDelayed(this, 5 * 60 * 1000L)
        }
    }
    companion object {
        const val CHANNEL = "korlix_social_active_call"
        const val NOTIFICATION = 4815
        var activeId: String? = null
        val authorized = mutableSetOf<String>()
        var onStarted: ((String, Boolean) -> Unit)? = null
        var onStopped: ((String) -> Unit)? = null
    }
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val id = intent?.getStringExtra("id") ?: return START_NOT_STICKY
        if (intent.action == "stop") {
            if (activeId == id) stopSelf()
            return START_NOT_STICKY
        }
        if (!authorized.contains(id) || !id.matches(Regex("[A-Za-z0-9-]{1,80}")) || activeId != null && activeId != id) {
            onStarted?.invoke(id, false)
            if (activeId == null) stopSelf()
            return START_NOT_STICKY
        }
        try {
            val rici = intent.getStringExtra("kind") == "rici"
            val channel = if (rici) "korlix_rici_voice" else CHANNEL
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(NotificationChannel(channel, if (rici) "Rici voice conversations" else "Active Social calls", NotificationManager.IMPORTANCE_LOW))
            }
            val open = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val openIntent = PendingIntent.getActivity(this, 4815, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val end = Intent(this, KorlixSocialCallService::class.java).setAction("stop").putExtra("id", id)
            val endIntent = PendingIntent.getService(this, 4816, end, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channel) else Notification.Builder(this)
            if (rici) {
                mediaSession?.release()
                mediaSession = MediaSession(this, "KorlixRici").apply {
                    setCallback(object : MediaSession.Callback() {
                        override fun onStop() { stopSelf() }
                        override fun onPause() { stopSelf() }
                    })
                    setMetadata(MediaMetadata.Builder().putString(MediaMetadata.METADATA_KEY_TITLE, "Rici live voice").build())
                    setPlaybackState(PlaybackState.Builder()
                        .setActions(PlaybackState.ACTION_STOP or PlaybackState.ACTION_PAUSE)
                        .setState(PlaybackState.STATE_PLAYING, PlaybackState.PLAYBACK_POSITION_UNKNOWN, 1f).build())
                    isActive = true
                }
                builder.setStyle(Notification.MediaStyle().setMediaSession(mediaSession!!.sessionToken).setShowActionsInCompactView(0))
            }
            val notification = builder.setSmallIcon(android.R.drawable.sym_action_call)
                .setContentTitle(if (rici) "Rici voice is active" else "KORLIX call in progress")
                .setContentText(if (rici) "Voice conversation continues with the screen locked." else "Audio call active. Tap to return to KORLIX.")
                .setContentIntent(openIntent).setOngoing(true).setCategory(Notification.CATEGORY_CALL)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .addAction(Notification.Action.Builder(android.R.drawable.ic_media_pause, if (rici) "Stop voice" else "End call", endIntent).build()).build()
            if (Build.VERSION.SDK_INT >= 30) {
                startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else { startForeground(NOTIFICATION, notification) }
            activeId = id
            if (callWakeLock == null) {
                callWakeLock = getSystemService(PowerManager::class.java)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "KORLIX:activeCall")
                    .apply { setReferenceCounted(false) }
            }
            handler.removeCallbacks(renewWakeLock)
            renewWakeLock.run()
            onStarted?.invoke(id, true)
        } catch (error: Exception) {
            Log.w("KorlixCall", "Unable to start foreground call service", error)
            authorized.remove(id)
            onStarted?.invoke(id, false)
            stopSelf()
        }
        return START_NOT_STICKY
    }
    override fun onTaskRemoved(rootIntent: Intent?) { stopSelf(); super.onTaskRemoved(rootIntent) }
    override fun onDestroy() {
        handler.removeCallbacks(renewWakeLock)
        callWakeLock?.let { if (it.isHeld) it.release() }
        callWakeLock = null
        mediaSession?.release()
        mediaSession = null
        val id = activeId
        activeId = null
        if (id != null) authorized.remove(id)
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else stopForeground(true)
        if (id != null) onStopped?.invoke(id)
        super.onDestroy()
    }
}
