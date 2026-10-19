package com.korlixdeveloper.korlixai

import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder

/** Builds without a Firebase client remain usable and never register push. */
object KorlixPushProvider {
    const val configured = false
    fun token(context: Context, completion: (String?) -> Unit) = completion(null)
    fun delete(context: Context, completion: () -> Unit = {}) = completion()
}

/** Disabled manifest placeholder; keeps unconfigured builds self-contained. */
class KorlixFirebaseMessagingService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
}
