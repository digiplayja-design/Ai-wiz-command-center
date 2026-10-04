package com.korlixdeveloper.korlixai

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/** Holds an explicitly started call, never starts capture or answers a call. */
class KorlixSocialCallService : Service() {
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
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(NotificationChannel(CHANNEL, "Active Social calls", NotificationManager.IMPORTANCE_LOW))
            }
            val open = Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val openIntent = PendingIntent.getActivity(this, 4815, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val end = Intent(this, KorlixSocialCallService::class.java).setAction("stop").putExtra("id", id)
            val endIntent = PendingIntent.getService(this, 4816, end, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
            val notification = builder.setSmallIcon(android.R.drawable.sym_action_call)
                .setContentTitle("KORLIX call in progress")
                .setContentText("Audio call active. Tap to return to KORLIX.")
                .setContentIntent(openIntent).setOngoing(true).setCategory(Notification.CATEGORY_CALL)
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .addAction(Notification.Action.Builder(null, "End call", endIntent).build()).build()
            if (Build.VERSION.SDK_INT >= 30) {
                startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else if (Build.VERSION.SDK_INT >= 29) {
                startForeground(NOTIFICATION, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else { startForeground(NOTIFICATION, notification) }
            activeId = id
            onStarted?.invoke(id, true)
        } catch (_: Exception) {
            authorized.remove(id)
            onStarted?.invoke(id, false)
            stopSelf()
        }
        return START_NOT_STICKY
    }
    override fun onTaskRemoved(rootIntent: Intent?) { stopSelf(); super.onTaskRemoved(rootIntent) }
    override fun onDestroy() {
        val id = activeId
        activeId = null
        if (id != null) authorized.remove(id)
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else stopForeground(true)
        if (id != null) onStopped?.invoke(id)
        super.onDestroy()
    }
}
