package net.yoshida.morebettergakujo

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import org.json.JSONArray
import org.json.JSONObject

/**
 * Reminders booked ahead of assignment deadlines. They are kept so they can
 * be booked again after a reboot, which clears every alarm.
 */
object DeadlineReminders {
    const val CHANNEL_ID = "gakujo_deadlines"
    const val EXTRA_NOTIFICATION_URL = "net.yoshida.morebettergakujo.NOTIFICATION_URL"
    private const val PREFS = "deadline_reminders"
    private const val KEY_REMINDERS = "reminders"
    private const val KEY_DELIVERED = "delivered"
    private const val EXTRA_ID = "reminder_id"
    private const val EXTRA_TITLE = "reminder_title"
    private const val EXTRA_BODY = "reminder_body"
    private const val EXTRA_URL = "reminder_url"
    private const val EARLY_WINDOW_MILLIS = 15 * 60 * 1000L
    private const val GROUP_KEY = "net.yoshida.morebettergakujo.DEADLINES"
    private const val SUMMARY_ID = 1

    data class Reminder(
        val id: Int,
        val title: String,
        val body: String,
        val url: String,
        val atMillis: Long
    )

    /** Replaces every booked reminder with [reminders]. */
    fun replace(context: Context, reminders: List<Reminder>) {
        for (old in load(context)) {
            cancel(context, old)
        }
        save(context, reminders)
        book(context, reminders)
    }

    /** Books the saved reminders again, as after a reboot. */
    fun restore(context: Context) {
        book(context, load(context))
    }

    fun parse(raw: List<*>?): List<Reminder> {
        return raw.orEmpty().mapNotNull { item ->
            val map = item as? Map<*, *> ?: return@mapNotNull null
            val id = (map["id"] as? Number)?.toInt() ?: return@mapNotNull null
            val at = (map["atMillis"] as? Number)?.toLong() ?: return@mapNotNull null
            Reminder(
                id = id,
                title = map["title"] as? String ?: "",
                body = map["body"] as? String ?: "",
                url = map["url"] as? String ?: "",
                atMillis = at
            )
        }
    }

    fun show(context: Context, intent: Intent) {
        val reminder = Reminder(
            id = intent.getIntExtra(EXTRA_ID, 0),
            title = intent.getStringExtra(EXTRA_TITLE).orEmpty(),
            body = intent.getStringExtra(EXTRA_BODY).orEmpty(),
            url = intent.getStringExtra(EXTRA_URL).orEmpty(),
            atMillis = 0L
        )
        // The other alarm booked for this reminder must not show it again.
        cancel(context, reminder)
        val delivered = loadDelivered(context)
        if (reminder.id !in delivered && show(context, reminder)) {
            val history = DeadlineReminderDelivery.record(delivered, reminder.id)
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_DELIVERED, JSONArray(history).toString())
                .apply()
        }
    }

    private fun show(context: Context, reminder: Reminder): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        post(context, reminder.id, reminder.title.ifBlank { "課題の締切" }, reminder.body, reminder.url)
        return true
    }

    /**
     * Posts a deadline notification that opens [url] when tapped. With two or
     * more, Android would otherwise group them under a summary of its own,
     * which opens the app wherever it was and clears them all; this one opens
     * the newest one's page.
     */
    fun post(context: Context, id: Int, title: String, body: String, url: String) {
        ensureChannel(context)
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.notify(id, builder(context, id, title, body, url).build())
        manager.notify(
            SUMMARY_ID,
            builder(context, SUMMARY_ID, title, body, url)
                .setGroupSummary(true)
                .build()
        )
    }

    private fun builder(
        context: Context,
        id: Int,
        title: String,
        body: String,
        url: String
    ): Notification.Builder {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java)
        launch.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        launch.putExtra(EXTRA_NOTIFICATION_URL, url)
        val contentIntent = PendingIntent.getActivity(
            context,
            id,
            launch,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL_ID)
                .setGroupAlertBehavior(Notification.GROUP_ALERT_CHILDREN)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_deadline)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setGroup(GROUP_KEY)
            // Both alarms of a reminder can go off together; sound once.
            .setOnlyAlertOnce(true)
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "課題期限", NotificationManager.IMPORTANCE_DEFAULT)
        )
    }

    private fun book(context: Context, reminders: List<Reminder>) {
        val now = System.currentTimeMillis()
        val alarms = alarmManager(context)
        val delivered = loadDelivered(context).toSet()
        for (reminder in reminders) {
            if (!DeadlineReminderDelivery.shouldBook(reminder.id, reminder.atMillis, now, delivered)) {
                continue
            }
            val pending = pendingIntent(context, reminder, whileIdle = false)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()) {
                alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, reminder.atMillis, pending)
            } else {
                // Without exact alarms the system may deliver up to an hour
                // late, after the deadline. Let it fire early instead.
                val start = maxOf(now, reminder.atMillis - EARLY_WINDOW_MILLIS)
                alarms.setWindow(
                    AlarmManager.RTC_WAKEUP,
                    start,
                    reminder.atMillis - start,
                    pending
                )
                // A window alarm waits while the phone dozes; this one does
                // not. Whichever goes off first cancels the other.
                alarms.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    start,
                    pendingIntent(context, reminder, whileIdle = true)
                )
            }
        }
    }

    private fun cancel(context: Context, reminder: Reminder) {
        val alarms = alarmManager(context)
        alarms.cancel(pendingIntent(context, reminder, whileIdle = false))
        alarms.cancel(pendingIntent(context, reminder, whileIdle = true))
    }

    private fun pendingIntent(
        context: Context,
        reminder: Reminder,
        whileIdle: Boolean
    ): PendingIntent {
        val suffix = if (whileIdle) ".IDLE" else ""
        val intent = Intent(context, DeadlineReminderReceiver::class.java).apply {
            action = "net.yoshida.morebettergakujo.REMINDER.${reminder.id}$suffix"
            putExtra(EXTRA_ID, reminder.id)
            putExtra(EXTRA_TITLE, reminder.title)
            putExtra(EXTRA_BODY, reminder.body)
            putExtra(EXTRA_URL, reminder.url)
        }
        return PendingIntent.getBroadcast(
            context,
            reminder.id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun alarmManager(context: Context): AlarmManager =
        context.getSystemService(AlarmManager::class.java)

    private fun save(context: Context, reminders: List<Reminder>) {
        val array = JSONArray()
        for (reminder in reminders) {
            array.put(
                JSONObject()
                    .put("id", reminder.id)
                    .put("title", reminder.title)
                    .put("body", reminder.body)
                    .put("url", reminder.url)
                    .put("atMillis", reminder.atMillis)
            )
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_REMINDERS, array.toString())
            .apply()
    }

    private fun load(context: Context): List<Reminder> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_REMINDERS, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { index ->
                val item = array.getJSONObject(index)
                Reminder(
                    id = item.getInt("id"),
                    title = item.optString("title"),
                    body = item.optString("body"),
                    url = item.optString("url"),
                    atMillis = item.getLong("atMillis")
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun loadDelivered(context: Context): List<Int> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_DELIVERED, null) ?: return emptyList()
        return try {
            val array = JSONArray(raw)
            (0 until array.length()).map { array.getInt(it) }
        } catch (_: Exception) {
            emptyList()
        }
    }
}

/** Shows a reminder when its alarm goes off. */
class DeadlineReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        DeadlineReminders.show(context, intent)
    }
}

/** Books reminders again after a reboot or an app update. */
class DeadlineReminderRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> DeadlineReminders.restore(context)
        }
    }
}
