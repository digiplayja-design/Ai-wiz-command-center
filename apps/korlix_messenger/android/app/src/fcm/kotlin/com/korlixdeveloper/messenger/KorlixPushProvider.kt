package com.korlixdeveloper.messenger

import android.content.Context
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

object KorlixPushProvider {
    const val configured = true
    private var tail: Task<Void> = Tasks.forResult(null)

    private fun messaging(context: Context): FirebaseMessaging {
        FirebaseApp.initializeApp(context.applicationContext)
        return FirebaseMessaging.getInstance().also { it.isAutoInitEnabled = false }
    }

    // Serialize deletion and subsequent registration across fast account switches.
    @Synchronized fun token(context: Context, completion: (String?) -> Unit) {
        try {
            val task = tail.continueWithTask { messaging(context).token }
            tail = task.continueWith<Void> { null }
            task.addOnCompleteListener { completion(if (it.isSuccessful) it.result else null) }
        } catch (_: Exception) { completion(null) }
    }

    @Synchronized fun delete(context: Context, completion: () -> Unit) {
        try {
            val task = tail.continueWithTask { messaging(context).deleteToken() }
            tail = task.continueWith<Void> { null }
            task.addOnCompleteListener { completion() }
        } catch (_: Exception) { completion() }
    }
}

class KorlixFirebaseMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        KorlixSocialNative.tokenChanged(applicationContext, token)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        // Server sends data-only pushes. Notification payloads could bypass the
        // local account/binding checks when Android displays them automatically.
        if (message.notification != null) return
        KorlixSocialNative.receive(applicationContext, message.data)
    }
}
