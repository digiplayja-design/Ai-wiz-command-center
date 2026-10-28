package com.korlixdeveloper.messenger

import android.media.AudioAttributes
import android.Manifest
import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Person
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import java.lang.ref.WeakReference
import java.security.MessageDigest
import java.util.UUID
import java.util.Locale
import java.util.TimeZone
import java.text.SimpleDateFormat

/** No JWT, message body, contact name or session credentials are persisted here. */
object KorlixSocialNative {
    const val CHANNEL = "korlix/social_native"
    const val NOTIFICATIONS = "korlix_social_conversations_v1"
    const val REPLY = "korlix_social_reply"
    private const val PREFIX = "korlix-social-"
    private val main = Handler(Looper.getMainLooper())
    private val bubbles = mutableListOf<WeakReference<Activity>>()
    private val events = java.util.ArrayDeque<Map<String, Any>>()
    private var listener: ((Map<String, Any>) -> Unit)? = null
    private var listening = false

    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences("korlix_social_native_v1", Context.MODE_PRIVATE)
    private fun manager(context: Context) = context.getSystemService(NotificationManager::class.java)
    fun owner(context: Context): String? = prefs(context).getString("owner", null)
    fun epoch(context: Context): String? = prefs(context).getString("epoch", null)

    fun validOwner(value: String?): Boolean = try {
        if (value == null || value.length !in 8..1024) false else {
            val parts = JSONArray(value)
            val issuer = Uri.parse(parts.getString(0))
            parts.length() == 2 && issuer.scheme == "https" && !issuer.host.isNullOrBlank() &&
                parts.getString(1).matches(Regex("[A-Za-z0-9_-]{1,128}"))
        }
    } catch (_: Exception) { false }

    fun validTarget(kind: String?, id: String?): Boolean =
        kind in setOf("peer", "group") && id != null && id.matches(Regex("[A-Za-z0-9_-]{1,128}"))

    private fun digest(value: String): String = MessageDigest.getInstance("SHA-256")
        .digest(value.toByteArray(Charsets.UTF_8)).take(16).joinToString("") { "%02x".format(it) }

    fun conversation(owner: String, kind: String, id: String) = PREFIX + digest("$owner\n$kind\n$id")
    private fun pins(context: Context) = prefs(context).getStringSet("pins", emptySet()).orEmpty().toMutableSet()

    private fun expiry(value: String?): Long? {
      return try {
        // Accept the UTC/offset ISO timestamps issued by the server on API 23 too.
        val match = Regex("^(\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2})(?:\\.(\\d{1,9}))?(Z|[+-]\\d{2}:\\d{2})$")
            .matchEntire(value.orEmpty()) ?: return null
        val fraction = match.groupValues[2].padEnd(3, '0').take(3)
        val zone = match.groupValues[3].let { if (it == "Z") "+0000" else it.replace(":", "") }
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSZ", Locale.US).apply {
            isLenient = false; timeZone = TimeZone.getTimeZone("UTC")
        }.parse("${match.groupValues[1]}.$fraction$zone")?.time
      } catch (_: Exception) { null }
    }

    @Synchronized fun activate(context: Context, next: String?): Boolean {
        if (next != null && !validOwner(next)) return false
        if (owner(context) == next) return true
        val settings = prefs(context)
        // Commit invalidation before touching notifications or asynchronous FCM.
        settings.edit().remove("owner").remove("binding").remove("token").remove("pins")
            .remove("seen").putString("epoch", UUID.randomUUID().toString())
            .apply { if (next != null) putString("owner", next) }.commit()
        events.clear()
        clearNotifications(context)
        bubbles.forEach { it.get()?.let { activity -> main.post {
            (activity as? KorlixSocialBubbleActivity)?.invalidateAccount() ?: activity.finish()
        } } }
        bubbles.clear()
        KorlixPushProvider.delete(context) {}
        return true
    }

    private fun clearNotifications(context: Context) {
        try {
            manager(context).activeNotifications.filter { it.tag?.startsWith(PREFIX) == true }
                .forEach { manager(context).cancel(it.tag, it.id) }
            if (Build.VERSION.SDK_INT >= 25) {
                val shortcuts = context.getSystemService(ShortcutManager::class.java)
                val published = if (Build.VERSION.SDK_INT >= 30) shortcuts.getShortcuts(
                    ShortcutManager.FLAG_MATCH_DYNAMIC or ShortcutManager.FLAG_MATCH_PINNED or ShortcutManager.FLAG_MATCH_CACHED)
                    else shortcuts.dynamicShortcuts + shortcuts.pinnedShortcuts
                val ids = published
                    .map { it.id }.filter { it.startsWith(PREFIX) }.distinct()
                if (ids.isNotEmpty()) {
                    shortcuts.disableShortcuts(ids)
                    shortcuts.removeDynamicShortcuts(ids)
                    if (Build.VERSION.SDK_INT >= 30) shortcuts.removeLongLivedShortcuts(ids)
                }
            }
        } catch (_: Exception) { /* Local ownership was already invalidated. */ }
    }

    @Synchronized fun attach(callback: (Map<String, Any>) -> Unit) { listener = callback; listening = false }
    @Synchronized fun detach(callback: (Map<String, Any>) -> Unit) {
        if (listener === callback) { listener = null; listening = false }
    }

    @Synchronized private fun emit(event: Map<String, Any>) {
        // The callback is only a wake-up signal. Keep open/reply actions until
        // authenticated Dart explicitly drains them with takeEvent(owner).
        if (event["type"] != "token") {
            if (events.size >= 10) events.removeFirst()
            events.addLast(event)
        }
        val callback = listener
        if (listening && callback != null) main.post { callback(event) }
    }

    @Synchronized fun takeEvent(context: Context, requestedOwner: String?): Map<String, Any>? {
        if (requestedOwner != owner(context) || !validOwner(requestedOwner)) return null
        listening = true
        while (events.isNotEmpty()) {
            val item = events.removeFirst()
            if (item["owner"] == requestedOwner) return item
        }
        return null
    }

    fun attachBubble(activity: Activity) { synchronized(this) { bubbles.add(WeakReference(activity)) } }

    fun allowed(context: Context): Boolean = Build.VERSION.SDK_INT < 24 || manager(context).areNotificationsEnabled()

    fun permission(context: Context): String {
        val runtime = Build.VERSION.SDK_INT < 33 || context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        if (runtime && allowed(context)) return "granted"
        if (Build.VERSION.SDK_INT >= 33 && !prefs(context).getBoolean("permissionAsked", false)) return "default"
        return "denied"
    }

    fun permissionAsked(context: Context) { prefs(context).edit().putBoolean("permissionAsked", true).apply() }

    @Suppress("DEPRECATION") fun bubblesAllowed(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 30 || !allowed(context)) return false
        return if (Build.VERSION.SDK_INT >= 31) manager(context).areBubblesEnabled() &&
            manager(context).bubblePreference != NotificationManager.BUBBLE_PREFERENCE_NONE
            else manager(context).areBubblesAllowed()
    }

    fun capabilities(context: Context) = mapOf(
        "bubbles" to (Build.VERSION.SDK_INT >= 30), "push" to KorlixPushProvider.configured,
        "provider" to "fcm", "permission" to permission(context), "bubbleAllowed" to bubblesAllowed(context)
    )

    fun openSettings(activity: Activity, bubble: Boolean): Boolean = try {
        val action = if (bubble && Build.VERSION.SDK_INT >= 29) Settings.ACTION_APP_NOTIFICATION_BUBBLE_SETTINGS
            else if (Build.VERSION.SDK_INT >= 26) Settings.ACTION_APP_NOTIFICATION_SETTINGS else Settings.ACTION_APPLICATION_DETAILS_SETTINGS
        val intent = Intent(action).putExtra(Settings.EXTRA_APP_PACKAGE, activity.packageName)
        if (Build.VERSION.SDK_INT < 26) intent.data = Uri.parse("package:${activity.packageName}")
        activity.startActivity(intent)
        true
    } catch (_: Exception) { false }

    @Synchronized fun current(context: Context, requestedOwner: String?): Map<String, Any>? {
        if (requestedOwner != owner(context) || !validOwner(requestedOwner) || !KorlixPushProvider.configured) return null
        val settings = prefs(context)
        val token = settings.getString("token", null) ?: return null
        val binding = settings.getString("binding", null) ?: return null
        val device = settings.getString("device", null) ?: return null
        return mapOf("device" to device, "binding" to binding,
            "subscription" to mapOf("provider" to "fcm", "token" to token,
                "app_id" to context.packageName, "environment" to "production"))
    }

    @Synchronized fun subscribe(context: Context, requestedOwner: String, completion: (Map<String, Any>?) -> Unit) {
        if (!KorlixPushProvider.configured || owner(context) != requestedOwner || permission(context) != "granted") {
            completion(null); return
        }
        val settings = prefs(context)
        val binding = settings.getString("binding", null) ?: UUID.randomUUID().toString()
        val device = settings.getString("device", null) ?: UUID.randomUUID().toString()
        val generation = epoch(context)
        settings.edit().putString("device", device).putString("binding", binding).commit()
        KorlixPushProvider.token(context) { token ->
            synchronized(this) {
                if (owner(context) != requestedOwner || epoch(context) != generation ||
                    settings.getString("binding", null) != binding || token.isNullOrBlank()) completion(null)
                else {
                    settings.edit().putString("token", token).commit()
                    completion(current(context, requestedOwner))
                }
            }
        }
    }

    @Synchronized fun unsubscribe(context: Context, requestedOwner: String?): Boolean {
        if (requestedOwner != owner(context) || !validOwner(requestedOwner)) return false
        prefs(context).edit().remove("binding").remove("token").remove("pins").remove("seen")
            .putString("epoch", UUID.randomUUID().toString()).commit()
        clearNotifications(context)
        events.clear()
        bubbles.forEach { it.get()?.let { activity -> main.post {
            (activity as? KorlixSocialBubbleActivity)?.invalidateAccount() ?: activity.finish()
        } } }
        bubbles.clear()
        KorlixPushProvider.delete(context) {}
        return true
    }

    @Synchronized fun tokenChanged(context: Context, token: String) {
        val activeOwner = owner(context) ?: return
        if (prefs(context).getString("binding", null) == null || token.isBlank()) return
        prefs(context).edit().putString("token", token).commit()
        emit(mapOf("type" to "token", "owner" to activeOwner, "requestId" to UUID.randomUUID().toString()))
    }

    fun intent(context: Context, activity: Class<out Activity>, requestedOwner: String, kind: String, id: String): Intent =
        Intent(context, activity).setAction("com.korlixdeveloper.messenger.SOCIAL")
            .setData(Uri.parse("korlix-internal://social/${conversation(requestedOwner, kind, id)}/${epoch(context)}"))
            .putExtra("socialOwner", requestedOwner).putExtra("socialEpoch", epoch(context))
            .putExtra("socialKind", kind).putExtra("socialId", id)
            .putExtra("socialRequestId", UUID.randomUUID().toString())

    @Synchronized fun launchAction(context: Context, intent: Intent?): Map<String, Any>? {
        intent ?: return null
        val requestedOwner = intent.getStringExtra("socialOwner") ?: return null
        val kind = intent.getStringExtra("socialKind") ?: return null
        val id = intent.getStringExtra("socialId") ?: return null
        if (requestedOwner != owner(context) || !validOwner(requestedOwner) || !validTarget(kind, id) ||
            intent.getStringExtra("socialEpoch") != epoch(context) || epoch(context) == null) return null
        return mapOf("type" to "open", "owner" to requestedOwner, "kind" to kind, "id" to id,
            "requestId" to (intent.getStringExtra("socialRequestId") ?: UUID.randomUUID().toString()))
    }

    @Synchronized fun acceptIntent(context: Context, intent: Intent?) {
        intent ?: return
        val event = launchAction(context, intent)?.toMutableMap() ?: return
        val reply = RemoteInput.getResultsFromIntent(intent)?.getCharSequence(REPLY)?.toString()?.trim()
        if (!reply.isNullOrEmpty()) {
            if (reply.length > 2000) return
            event["type"] = "reply"
            event["text"] = reply
        }
        emit(event)
        // Prevent rotation/recreation from replaying an already-consumed action.
        intent.removeExtra("socialOwner")
    }

    @Synchronized fun unpin(context: Context, requestedOwner: String, kind: String, id: String): Boolean {
        if (owner(context) != requestedOwner || !validTarget(kind, id)) return false
        val shortcut = conversation(requestedOwner, kind, id)
        prefs(context).edit().putStringSet("pins", pins(context).apply { remove(shortcut) }).commit()
        manager(context).cancel(shortcut, 1)
        if (Build.VERSION.SDK_INT >= 30) {
            val shortcuts = context.getSystemService(ShortcutManager::class.java)
            shortcuts.removeDynamicShortcuts(listOf(shortcut))
            shortcuts.removeLongLivedShortcuts(listOf(shortcut))
        }
        return true
    }

    @Synchronized fun pin(context: Context, requestedOwner: String, kind: String, id: String): Boolean {
        if (Build.VERSION.SDK_INT < 30 || owner(context) != requestedOwner || !validTarget(kind, id) || permission(context) != "granted") return false
        val shortcut = conversation(requestedOwner, kind, id)
        // Android's shortcut budget is deliberately bounded. Old conversations
        // remain regular notifications instead of silently exhausting the limit.
        val existing = pins(context)
        if (existing.size >= 4 && shortcut !in existing) return false
        existing.add(shortcut)
        prefs(context).edit().putStringSet("pins", existing).commit()
        return post(context, requestedOwner, kind, id, "message", explicit = true)
    }

    @Synchronized fun receive(context: Context, data: Map<String, String>) {
        val requestedOwner = data["owner"] ?: return
        val kind = data["kind"] ?: return
        val id = data["id"] ?: return
        val eventId = data["event_id"] ?: return
        val type = data["type"] ?: return
        val binding = data["binding"] ?: return
        val expires = expiry(data["expires_at"]) ?: return
        if (requestedOwner != owner(context) || !validTarget(kind, id) || type !in setOf("message", "call", "online") ||
            binding != prefs(context).getString("binding", null) || eventId.length !in 1..160 ||
            expires <= System.currentTimeMillis() || permission(context) != "granted") return
        val seen = prefs(context).getStringSet("seen", emptySet()).orEmpty().toMutableSet()
        val eventKey = digest("$binding\n$eventId")
        if (eventKey in seen) return
        if (post(context, requestedOwner, kind, id, type, explicit = false,
                silent = data["silent"] in setOf("true", "1"), expires = expires)) {
            // A bounded, body-free delivery de-duplication cache.
            if (seen.size >= 100) seen.clear()
            seen.add(eventKey)
            prefs(context).edit().putStringSet("seen", seen).commit()
        }
    }

    @Suppress("DEPRECATION")
    private fun post(context: Context, requestedOwner: String, kind: String, id: String, type: String,
                     explicit: Boolean, silent: Boolean = false, expires: Long? = null): Boolean {
      return try {
        val notifications = manager(context)
        val channelId = if (silent) "${NOTIFICATIONS}_silent" else "korlix_social_conversations_v2"
        if (Build.VERSION.SDK_INT >= 26) {
            val previous = if (!silent) notifications.getNotificationChannel(NOTIFICATIONS) else null
            val channel = NotificationChannel(channelId, if (silent) "KORLIX Messenger quiet alerts" else "KORLIX Messenger",
                if (silent) NotificationManager.IMPORTANCE_LOW else previous?.importance ?: NotificationManager.IMPORTANCE_DEFAULT)
            channel.description = "Private Social messages and conversation bubbles"
            channel.lockscreenVisibility = Notification.VISIBILITY_PRIVATE
            if (silent) { channel.setSound(null, null); channel.enableVibration(false) }
            else {
                // A new default tone must not undo a person's channel mute,
                // custom sound, importance, vibration, or lock-screen choice.
                val preserveSound = previous != null && (previous.sound == null ||
                    Build.VERSION.SDK_INT < 30 || previous.hasUserSetSound())
                channel.setSound(if (preserveSound) previous?.sound else
                    Uri.parse("android.resource://${context.packageName}/raw/korlix_message"),
                    if (preserveSound) previous?.audioAttributes else AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION).setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build())
                if (previous != null) {
                    channel.enableVibration(previous.shouldVibrate())
                    channel.vibrationPattern = previous.vibrationPattern
                    channel.enableLights(previous.shouldShowLights())
                    channel.lightColor = previous.lightColor
                    channel.lockscreenVisibility = previous.lockscreenVisibility
                }
            }
            if (Build.VERSION.SDK_INT >= 29) channel.setAllowBubbles(true)
            notifications.createNotificationChannel(channel)
            if (notifications.getNotificationChannel(channelId)?.importance == NotificationManager.IMPORTANCE_NONE) return false
        }
        val shortcutId = conversation(requestedOwner, kind, id)
        val bubbleMessage = Build.VERSION.SDK_INT >= 30 && shortcutId in pins(context) && type == "message"
        val open = intent(context, MainActivity::class.java, requestedOwner, kind, id)
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val openPending = PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channelId) else Notification.Builder(context)
        val text = when {
            explicit -> "Your floating conversation is ready."
            type == "call" -> "You have a Social call. Open Messenger to respond."
            type == "online" -> "A Social online alert is ready."
            else -> "You have a new Social message."
        }
        builder.setSmallIcon(R.drawable.ic_social_notification).setContentTitle("KORLIX Messenger")
            .setContentText(text).setContentIntent(openPending).setVisibility(Notification.VISIBILITY_PRIVATE)
            .setCategory(Notification.CATEGORY_MESSAGE).setAutoCancel(true).setOnlyAlertOnce(explicit)
        if (expires != null && Build.VERSION.SDK_INT >= 26 && !bubbleMessage) builder.setTimeoutAfter((expires - System.currentTimeMillis()).coerceAtLeast(1))
        if (Build.VERSION.SDK_INT < 26) {
            if (silent) builder.setSound(null).setVibrate(null)
            else builder.setSound(Uri.parse("android.resource://${context.packageName}/raw/korlix_message"))
        }
        if (Build.VERSION.SDK_INT >= 28) {
            val person = Person.Builder().setName("KORLIX Messenger").setKey(shortcutId).build()
            builder.setStyle(Notification.MessagingStyle(Person.Builder().setName("You").build())
                .setGroupConversation(kind == "group").addMessage(text, System.currentTimeMillis(), person)).addPerson(person)
            if (Build.VERSION.SDK_INT >= 30 && bubbleMessage) {
                val bubble = intent(context, KorlixSocialBubbleActivity::class.java, requestedOwner, kind, id)
                val icon = Icon.createWithResource(context, R.mipmap.ic_launcher)
                val shortcut = ShortcutInfo.Builder(context, shortcutId).setShortLabel("KORLIX Messenger")
                    .setLongLived(true).setPersons(arrayOf(person)).setIcon(icon).setIntent(open)
                    .setCategories(setOf("com.korlixdeveloper.messenger.SOCIAL_CONVERSATION")).build()
                val shortcuts = context.getSystemService(ShortcutManager::class.java)
                shortcuts.enableShortcuts(listOf(shortcutId))
                shortcuts.pushDynamicShortcut(shortcut)
                // Android's bubble host fills launch flags into this explicit
                // activity PendingIntent; unlike the content intent it must be mutable.
                val bubbleMutable = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
                val bubblePending = PendingIntent.getActivity(context, 1, bubble, PendingIntent.FLAG_UPDATE_CURRENT or bubbleMutable)
                val metadata = Notification.BubbleMetadata.Builder(bubblePending, icon).setDesiredHeight(600)
                    .setAutoExpandBubble(explicit).setSuppressNotification(explicit).build()
                builder.setShortcutId(shortcutId).setBubbleMetadata(metadata).setAutoCancel(false)
            }
        }
        if (!explicit && type == "message") {
            val replyIntent = Intent(open).setData(Uri.parse("korlix-internal://reply/$shortcutId/${epoch(context)}"))
            val mutable = if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
            val replyPending = PendingIntent.getActivity(context, 2, replyIntent, PendingIntent.FLAG_UPDATE_CURRENT or mutable)
            val action = Notification.Action.Builder(Icon.createWithResource(context, R.drawable.ic_social_notification), "Reply in Messenger", replyPending)
                .addRemoteInput(RemoteInput.Builder(REPLY).setLabel("Write a reply").build())
            if (Build.VERSION.SDK_INT >= 31) action.setAuthenticationRequired(true)
            builder.addAction(action.build())
        }
        notifications.notify(shortcutId, when (type) { "call" -> 2; "online" -> 3; else -> 1 }, builder.build())
        true
      } catch (_: Exception) { false }
    }
}

/** Main and bubble engines share no Dart state; only the main engine may bind an account. */
class KorlixSocialNativeChannel(private val activity: Activity, private val channel: MethodChannel, private val mainEngine: Boolean) {
    var foreground = false
    private var disposed = false
    private var afterPermission: (() -> Unit)? = null
    private var permissionResult: MethodChannel.Result? = null
    private var permissionFailure: Any? = null
    private val callback: (Map<String, Any>) -> Unit = { event ->
        if (!disposed && event["owner"] == KorlixSocialNative.owner(activity)) channel.invokeMethod("event", event)
    }

    init {
        channel.setMethodCallHandler(::handle)
        if (mainEngine) KorlixSocialNative.attach(callback)
    }

    private fun notifyPermission(result: MethodChannel.Result, failure: Any? = null, continuation: () -> Unit) {
        if (KorlixSocialNative.permission(activity) == "granted") { continuation(); return }
        if (!foreground || afterPermission != null || Build.VERSION.SDK_INT < 33) {
            result.success(failure); return
        }
        afterPermission = continuation
        permissionResult = result
        permissionFailure = failure
        KorlixSocialNative.permissionAsked(activity)
        activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 4821)
    }

    fun onPermissionResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != 4821) return false
        val continuation = afterPermission
        val result = permissionResult
        val failure = permissionFailure
        afterPermission = null
        permissionResult = null
        permissionFailure = null
        if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED && !disposed) continuation?.invoke()
        else result?.success(failure)
        return true
    }

    fun close() {
        disposed = true
        permissionResult?.success(permissionFailure)
        permissionResult = null
        permissionFailure = null
        afterPermission = null
        if (mainEngine) KorlixSocialNative.detach(callback)
        channel.setMethodCallHandler(null)
    }

    fun invalidateAccount() {
        channel.invokeMethod("event", mapOf("type" to "ownerChanged"))
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val owner = call.argument<String>("owner")
        val kind = call.argument<String>("kind")
        val id = call.argument<String>("id")
        when (call.method) {
            "capabilities" -> result.success(KorlixSocialNative.capabilities(activity))
            "launchAction" -> result.success(if (mainEngine) null else KorlixSocialNative.launchAction(activity, activity.intent))
            "closeBubble" -> {
                if (!mainEngine) {
                    KorlixSocialNative.launchAction(activity, activity.intent)?.let {
                        KorlixSocialNative.unpin(activity, it["owner"] as String, it["kind"] as String, it["id"] as String)
                    }
                    activity.finish()
                }
                result.success(null)
            }
            "openMain" -> {
                val target = if (mainEngine) null else KorlixSocialNative.launchAction(activity, activity.intent)
                if (target != null) {
                    activity.startActivity(KorlixSocialNative.intent(activity, MainActivity::class.java,
                        target["owner"] as String, target["kind"] as String, target["id"] as String)
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
                    activity.finish()
                }
                result.success(target != null)
            }
            "activate" -> result.success(mainEngine && KorlixSocialNative.activate(activity, owner?.takeIf { it.isNotBlank() }))
            "takeEvent" -> result.success(if (mainEngine) KorlixSocialNative.takeEvent(activity, owner) else null)
            "current" -> result.success(if (mainEngine) KorlixSocialNative.current(activity, owner) else null)
            "unsubscribe" -> {
                if (mainEngine) KorlixSocialNative.unsubscribe(activity, owner)
                result.success(null)
            }
            "settings" -> result.success(mainEngine && foreground && KorlixSocialNative.openSettings(activity, call.argument<Boolean>("bubbles") == true))
            "subscribe" -> {
                if (!mainEngine || owner == null || owner != KorlixSocialNative.owner(activity) || !KorlixPushProvider.configured || !foreground) result.success(null)
                else notifyPermission(result) {
                    KorlixSocialNative.subscribe(activity, owner) { value -> if (!disposed) result.success(value) }
                }
            }
            "unpin" -> result.success(mainEngine && owner != null && kind != null && id != null && KorlixSocialNative.unpin(activity, owner, kind, id))
            "pin" -> {
                if (Build.VERSION.SDK_INT < 30) { result.success(mapOf("status" to "unsupported")); return }
                if (!mainEngine || !foreground || owner == null || owner != KorlixSocialNative.owner(activity) || !KorlixSocialNative.validTarget(kind, id)) {
                    result.success(mapOf("status" to "denied")); return
                }
                notifyPermission(result, mapOf("status" to "denied")) {
                    val posted = KorlixSocialNative.pin(activity, owner, kind!!, id!!)
                    val status = if (!posted) "denied" else if (KorlixSocialNative.bubblesAllowed(activity)) "shown" else {
                        KorlixSocialNative.openSettings(activity, true); "settings"
                    }
                    result.success(mapOf("status" to status))
                }
            }
            else -> result.notImplemented()
        }
    }
}
