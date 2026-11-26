package com.korlixdeveloper.korlixai

import android.content.Context
import com.google.firebase.FirebaseApp
import com.google.firebase.analytics.FirebaseAnalytics
import com.google.firebase.analytics.FirebaseAnalytics.ConsentStatus
import com.google.firebase.analytics.FirebaseAnalytics.ConsentType
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

object StoreMeasurement {
    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        if (context.packageName != "com.korlixdeveloper.korlixai") { result.success(null); return }
        val prefs = context.getSharedPreferences("korlix_subscription_measurement", Context.MODE_PRIVATE)
        if (call.method == "disable" && !prefs.contains("owner")) { result.success(null); return }
        try {
            if (FirebaseApp.getApps(context).isEmpty() && FirebaseApp.initializeApp(context) == null) {
                result.success(null)
                return
            }
            val analytics = FirebaseAnalytics.getInstance(context)
            fun consent(enabled: Boolean) {
                val setting = if (enabled) ConsentStatus.GRANTED else ConsentStatus.DENIED
                analytics.setConsent(mapOf(ConsentType.ANALYTICS_STORAGE to setting, ConsentType.AD_STORAGE to setting,
                    ConsentType.AD_USER_DATA to setting, ConsentType.AD_PERSONALIZATION to ConsentStatus.DENIED))
                analytics.setAnalyticsCollectionEnabled(enabled)
            }
            val previous = prefs.getString("owner", null)
            if (call.method == "disable") {
                consent(false)
                analytics.resetAnalyticsData()
                prefs.edit().remove("owner").apply()
                result.success(null)
                return
            }
            if (call.method != "enable" && call.method != "resume") { result.notImplemented(); return }
            val owner = call.argument<String>("owner")
            if (owner == null || runCatching { UUID.fromString(owner) }.isFailure) { result.success(null); return }
            if (previous != null && previous != owner) {
                consent(false)
                analytics.resetAnalyticsData()
            }
            consent(true)
            if (previous != owner) {
                prefs.edit().putString("owner", owner).apply()
                analytics.logEvent("subscription_measurement_opt_in", null)
            }
            analytics.appInstanceId.addOnCompleteListener { task ->
                result.success(if (task.isSuccessful && prefs.getString("owner", null) == owner) task.result else null)
            }
        } catch (_: Exception) {
            result.success(null)
        }
    }
}
