package net.yoshida.morebettergakujo

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Notification
import android.app.PendingIntent
import android.content.ContentProviderOperation
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.CalendarContract
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.CookieManager
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Calendar
import java.util.GregorianCalendar
import java.util.Locale
import java.util.TimeZone

internal data class GakujoCalendarEventData(
    val id: String,
    val uidNamespace: String?,
    val title: String,
    val startMillis: Long,
    val endMillis: Long,
    val description: String,
    val location: String
)

internal data class ExistingGakujoCalendarEvent(
    val id: Long,
    val startMillis: Long,
    val description: String,
    val calendarId: Long = 0L
)

internal data class CalendarEventReplacementRange(
    val startMillis: Long,
    val endMillis: Long
)

internal enum class GakujoCalendarIdentity {
    NORMAL,
    VALIDATION
}

internal object GakujoCalendarIdentityPolicy {
    private const val VALIDATION_CALENDAR_TITLE = "More Better Gakujo 検証"
    private const val VALIDATION_UID_NAMESPACE = "calendar-validation"

    fun forSync(
        calendarTitle: String,
        events: List<GakujoCalendarEventData>
    ): GakujoCalendarIdentity {
        val namespace = events.firstOrNull()?.uidNamespace
        if (namespace != null) {
            if (namespace == VALIDATION_UID_NAMESPACE) {
                return GakujoCalendarIdentity.VALIDATION
            }
            require(calendarTitle != VALIDATION_CALENDAR_TITLE) {
                "「$VALIDATION_CALENDAR_TITLE」は検証用に予約されたカレンダー名です"
            }
            return GakujoCalendarIdentity.NORMAL
        }
        return forTitle(calendarTitle)
    }

    fun forTitle(calendarTitle: String): GakujoCalendarIdentity {
        return if (calendarTitle == VALIDATION_CALENDAR_TITLE) {
            GakujoCalendarIdentity.VALIDATION
        } else {
            GakujoCalendarIdentity.NORMAL
        }
    }

    fun preferenceKey(identity: GakujoCalendarIdentity): String {
        return when (identity) {
            GakujoCalendarIdentity.NORMAL -> "calendar_id_normal"
            GakujoCalendarIdentity.VALIDATION -> "calendar_id_validation"
        }
    }

    fun preferredReusableId(
        rememberedWritableId: Long?,
        findByTitle: () -> Long?
    ): Long? {
        return rememberedWritableId ?: findByTitle()
    }

    fun forMarkerDescription(description: String): GakujoCalendarIdentity? {
        val eventId = GakujoCalendarEventPolicy.eventIdFromDescription(description)
            ?: return null
        return if (GakujoCalendarEventPolicy.uidNamespaceFromId(eventId) == VALIDATION_UID_NAMESPACE) {
            GakujoCalendarIdentity.VALIDATION
        } else {
            GakujoCalendarIdentity.NORMAL
        }
    }

    fun uniqueMigrationId(
        identitiesByCalendarId: Map<Long, Set<GakujoCalendarIdentity>>,
        targetIdentity: GakujoCalendarIdentity
    ): Long? {
        return identitiesByCalendarId.entries
            .filter { it.value == setOf(targetIdentity) }
            .map { it.key }
            .singleOrNull()
    }
}

internal object GakujoDownloadFilePolicy {
    fun uniqueName(existingNames: Set<String>, desiredName: String): String {
        if (!existingNames.contains(desiredName)) {
            return desiredName
        }

        val dot = desiredName.lastIndexOf('.')
        val hasExtension = dot > 0 && dot < desiredName.length - 1
        val base = if (hasExtension) desiredName.substring(0, dot) else desiredName
        val extension = if (hasExtension) desiredName.substring(dot) else ""
        var index = 1
        while (true) {
            val candidate = "$base ($index)$extension"
            if (!existingNames.contains(candidate)) {
                return candidate
            }
            index += 1
        }
    }

    fun resolvedName(providerName: String?, allocatedName: String): String {
        return providerName ?: allocatedName
    }
}

internal object GakujoCalendarEventPolicy {
    const val EVENT_MARKER = "MBG_UID:"

    fun parse(event: Map<*, *>): GakujoCalendarEventData? {
        val title = event["title"]?.toString()?.takeIf { it.isNotBlank() } ?: return null
        val start = longValue(event["startMillis"]) ?: return null
        val end = longValue(event["endMillis"]) ?: return null
        if (end <= start) {
            return null
        }
        val id = event["id"]?.toString()?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        val teacher = event["teacher"]?.toString()?.takeIf { it.isNotBlank() }
        val notes = event["notes"]?.toString()?.takeIf { it.isNotBlank() }
        val description = buildString {
            if (notes != null) {
                append(notes)
            } else if (teacher != null) {
                append("担当教員: ")
                append(teacher)
            }
            if (isNotEmpty()) {
                append("\n\n")
            }
            append(EVENT_MARKER)
            append(id)
        }
        return GakujoCalendarEventData(
            id = id,
            uidNamespace = uidNamespaceFromId(id),
            title = title,
            startMillis = start,
            endMillis = end,
            description = description,
            location = event["location"]?.toString().orEmpty()
        )
    }

    fun replacementNamespaces(events: List<GakujoCalendarEventData>): Set<String> {
        if (events.isEmpty() || events.any { it.uidNamespace == null }) {
            return emptySet()
        }
        return events.mapNotNull { it.uidNamespace }.toSet()
    }

    fun parseEventsForSync(rawEvents: Any?): List<GakujoCalendarEventData> {
        val events = rawEvents as? List<*>
            ?: throw IllegalArgumentException("カレンダー予定を取得できませんでした")
        require(events.isNotEmpty()) { "追加可能なカレンダー予定がありません" }
        val parsedEvents = events.mapIndexed { index, rawEvent ->
            val event = rawEvent as? Map<*, *>
                ?: throw IllegalArgumentException("カレンダー予定${index + 1}件目が不正です")
            parse(event)
                ?: throw IllegalArgumentException("カレンダー予定${index + 1}件目が不正です")
        }
        val namespaces = parsedEvents.map { it.uidNamespace }
        val hasLegacyEvents = namespaces.any { it == null }
        val namedNamespaces = namespaces.filterNotNull().toSet()
        require(!(hasLegacyEvents && namedNamespaces.isNotEmpty())) {
            "namespaceあり・なしのカレンダー予定を同時に同期できません"
        }
        require(namedNamespaces.size <= 1) {
            "異なるnamespaceのカレンダー予定を同時に同期できません"
        }
        return parsedEvents
    }

    fun eventIdsToReplace(
        existingEvents: List<ExistingGakujoCalendarEvent>,
        namespaces: Set<String>,
        replacementRange: CalendarEventReplacementRange
    ): List<Long> {
        if (namespaces.isNotEmpty()) {
            return existingEvents
                .filter { uidNamespaceFromDescription(it.description) in namespaces }
                .map { it.id }
        }
        return existingEvents
            .filter {
                it.startMillis >= replacementRange.startMillis &&
                    it.startMillis < replacementRange.endMillis
            }
            .map { it.id }
    }

    fun eventIdsForNamespaceCleanup(
        existingEvents: List<ExistingGakujoCalendarEvent>,
        writableCalendarIds: Set<Long>,
        namespaces: Set<String>,
        targetCalendarId: Long,
        includeForeignCalendars: Boolean
    ): List<Long> {
        if (namespaces.isEmpty()) {
            return emptyList()
        }
        return existingEvents
            .filter {
                it.calendarId == targetCalendarId ||
                    (includeForeignCalendars && it.calendarId in writableCalendarIds)
            }
            .filter { event ->
                val eventId = if (event.calendarId == targetCalendarId) {
                    eventIdFromDescription(event.description)
                } else {
                    eventIdFromFinalMarkerDescription(event.description)
                }
                val existingNamespace = eventId?.let(::uidNamespaceFromId)
                    ?: return@filter false
                namespaces.any { incomingNamespace ->
                    namespacesMatchForCleanup(existingNamespace, incomingNamespace)
                }
            }
            .map { it.id }
    }

    fun eventIdsForExplicitLegacyDelete(
        existingEvents: List<ExistingGakujoCalendarEvent>,
        writableCalendarIds: Set<Long>,
        replacementRange: CalendarEventReplacementRange
    ): List<Long> {
        return existingEvents
            .filter { it.calendarId in writableCalendarIds }
            .filter {
                it.startMillis >= replacementRange.startMillis &&
                    it.startMillis < replacementRange.endMillis
            }
            .filter { eventIdFromFinalMarkerDescription(it.description) != null }
            .map { it.id }
    }

    internal fun namespacesMatchForCleanup(
        existingNamespace: String,
        incomingNamespace: String
    ): Boolean {
        if (existingNamespace == incomingNamespace) {
            return true
        }
        val incomingBucket = niigataTermBucket(incomingNamespace) ?: return false
        val existingBucket = legacyManualBucket(existingNamespace) ?: return false
        return existingBucket == incomingBucket
    }

    private fun niigataTermBucket(namespace: String): ManualCalendarBucket? {
        val match = Regex("^niigata-([0-9]{4})-第([1-4])ターム$")
            .matchEntire(namespace)
            ?: return null
        val academicYear = match.groupValues[1].toIntOrNull() ?: return null
        val termIdentity = when (match.groupValues[2]) {
            "1" -> "first"
            "2" -> "second"
            "3" -> "third"
            else -> "fourth"
        }
        return ManualCalendarBucket(academicYear, termIdentity)
    }

    private fun legacyManualBucket(namespace: String): ManualCalendarBucket? {
        val match = Regex("^manual-([0-9]{8})-([0-9]{8})$")
            .matchEntire(namespace)
            ?: return null
        val start = utcDateMillis(match.groupValues[1]) ?: return null
        val end = utcDateMillis(match.groupValues[2]) ?: return null
        if (end < start) {
            return null
        }
        val startCalendar = GregorianCalendar(TimeZone.getTimeZone("UTC")).apply {
            timeInMillis = start
        }
        val midpointCalendar = GregorianCalendar(TimeZone.getTimeZone("UTC")).apply {
            timeInMillis = start + ((end - start) / 2L)
        }
        val startYear = startCalendar.get(Calendar.YEAR)
        val startMonth = startCalendar.get(Calendar.MONTH) + 1
        val midpointMonth = midpointCalendar.get(Calendar.MONTH) + 1
        val academicYear = if (startMonth >= 4) startYear else startYear - 1
        val termIdentity = when (midpointMonth) {
            4, 5 -> "first"
            6, 7, 8, 9 -> "second"
            10, 11 -> "third"
            else -> "fourth"
        }
        return ManualCalendarBucket(academicYear, termIdentity)
    }

    private fun utcDateMillis(compactDate: String): Long? {
        if (!Regex("^[0-9]{8}$").matches(compactDate)) {
            return null
        }
        val year = compactDate.substring(0, 4).toIntOrNull() ?: return null
        val month = compactDate.substring(4, 6).toIntOrNull() ?: return null
        val day = compactDate.substring(6, 8).toIntOrNull() ?: return null
        return runCatching {
            GregorianCalendar(TimeZone.getTimeZone("UTC")).apply {
                isLenient = false
                clear()
                set(year, month - 1, day, 0, 0, 0)
            }.timeInMillis
        }.getOrNull()
    }

    private data class ManualCalendarBucket(
        val academicYear: Int,
        val termIdentity: String
    )

    fun unionRange(
        current: CalendarEventReplacementRange,
        previous: CalendarEventReplacementRange?
    ): CalendarEventReplacementRange {
        if (previous == null) {
            return current
        }
        return CalendarEventReplacementRange(
            startMillis = minOf(current.startMillis, previous.startMillis),
            endMillis = maxOf(current.endMillis, previous.endMillis)
        )
    }

    internal fun uidNamespaceFromId(id: String): String? {
        val separator = id.indexOf('|')
        if (separator <= 0) {
            return null
        }
        return id.substring(0, separator).takeIf { it.isNotBlank() }
    }

    internal fun eventIdFromDescription(description: String): String? {
        return description.lineSequence()
            .mapNotNull(::eventIdFromMarkerLine)
            .firstOrNull()
    }

    internal fun eventIdFromFinalMarkerDescription(description: String): String? {
        val finalLine = description.trimEnd()
            .lineSequence()
            .lastOrNull()
            ?: return null
        return eventIdFromMarkerLine(finalLine)
    }

    private fun eventIdFromMarkerLine(line: String): String? {
        val trimmedLine = line.trim()
        if (!trimmedLine.startsWith(EVENT_MARKER)) {
            return null
        }
        return trimmedLine
            .substring(EVENT_MARKER.length)
            .trim()
            .takeIf { it.isNotEmpty() }
    }

    private fun uidNamespaceFromDescription(description: String): String? {
        return eventIdFromDescription(description)?.let(::uidNamespaceFromId)
    }

    private fun longValue(value: Any?): Long? {
        return when (value) {
            is Number -> value.toLong()
            is String -> value.toLongOrNull()
            else -> null
        }
    }
}

class MainActivity : FlutterActivity() {
    private var pendingPickRootResult: MethodChannel.Result? = null
    private var pendingPickFileResult: MethodChannel.Result? = null
    private var pendingPickFileArgs: Map<*, *>? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var pendingCalendarPermissionResult: MethodChannel.Result? = null
    private var pendingCalendarCall: MethodCall? = null
    private var notificationsChannel: MethodChannel? = null
    private var pendingNotificationUrl: String? = null
    private val downloadFolderLock = Any()
    private val calendarOperationLock = Any()

    override fun onCreate(savedInstanceState: Bundle?) {
        pendingNotificationUrl = notificationUrlFromIntent(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val url = notificationUrlFromIntent(intent) ?: return
        pendingNotificationUrl = url
        notificationsChannel?.invokeMethod(
            "deadlineNotificationTapped",
            mapOf("url" to url),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    if (result == true && pendingNotificationUrl == url) {
                        pendingNotificationUrl = null
                    }
                }

                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) = Unit

                override fun notImplemented() = Unit
            }
        )
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEBUG_LAUNCH_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDebugLaunchConfig" -> result.success(debugLaunchConfig())
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DOWNLOADS_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDownloadRoot" -> result.success(downloadRootState())
                "pickDownloadRoot" -> pickDownloadRoot(result)
                "clearDownloadRoot" -> {
                    clearDownloadRoot()
                    result.success(downloadRootState())
                }
                "downloadToCourseFolder",
                "downloadToConfiguredFolder" -> downloadToConfiguredFolder(call, result)
                "downloadToPickedFile" -> downloadToPickedFile(call, result)
                else -> result.notImplemented()
            }
        }

        notificationsChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATIONS_CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPermission" -> requestNotificationPermission(result)
                    "notifyDeadline" -> {
                        result.success(showDeadlineNotification(call))
                    }
                    "takePendingNotificationUrl" -> {
                        val url = pendingNotificationUrl
                        pendingNotificationUrl = null
                        result.success(url)
                    }
                    else -> result.notImplemented()
                }
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CALENDAR_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "syncEvents" -> syncCalendarEvents(call, result)
                "deleteAddedEvents" -> deleteCalendarEvents(call, result)
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_CALENDAR_PERMISSION) {
            val result = pendingCalendarPermissionResult ?: return
            val call = pendingCalendarCall
            pendingCalendarPermissionResult = null
            pendingCalendarCall = null
            val granted = grantResults.isNotEmpty() &&
                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            if (!granted || call == null) {
                result.error("calendar_permission_denied", "カレンダーへのアクセスが許可されませんでした", null)
                return
            }
            when (call.method) {
                "syncEvents" -> performCalendarSync(call, result)
                "deleteAddedEvents" -> performCalendarDelete(call, result)
                else -> result.notImplemented()
            }
            return
        }
        if (requestCode != REQUEST_POST_NOTIFICATIONS) {
            return
        }
        val result = pendingNotificationPermissionResult ?: return
        pendingNotificationPermissionResult = null
        result.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
    }

    @Deprecated("Used for ACTION_OPEN_DOCUMENT_TREE result handling.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        when (requestCode) {
            REQUEST_PICK_DOWNLOAD_ROOT -> handlePickDownloadRootResult(resultCode, data)
            REQUEST_CREATE_DOWNLOAD_FILE -> handleCreateDownloadFileResult(resultCode, data)
        }
    }

    private fun pickDownloadRoot(result: MethodChannel.Result) {
        if (pendingPickRootResult != null || pendingPickFileResult != null) {
            result.error("picker_active", "フォルダ選択がすでに開いています", null)
            return
        }

        pendingPickRootResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_PICK_DOWNLOAD_ROOT)
    }

    private fun handlePickDownloadRootResult(resultCode: Int, data: Intent?) {
        val result = pendingPickRootResult ?: return
        pendingPickRootResult = null

        if (resultCode != Activity.RESULT_OK) {
            result.success(downloadRootState())
            return
        }

        val uri = data?.data
        if (uri == null) {
            result.error("missing_root_uri", "保存先フォルダを取得できませんでした", null)
            return
        }

        try {
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            contentResolver.takePersistableUriPermission(uri, data.flags and flags)
            prefs().edit().putString(KEY_DOWNLOAD_ROOT_URI, uri.toString()).apply()
            result.success(downloadRootState())
        } catch (error: SecurityException) {
            Log.e(TAG, "Failed to persist download root permission", error)
            result.error(
                "root_permission_failed",
                "保存先フォルダの権限を保持できませんでした",
                null
            )
        }
    }

    private fun handleCreateDownloadFileResult(resultCode: Int, data: Intent?) {
        val result = pendingPickFileResult ?: return
        val args = pendingPickFileArgs
        pendingPickFileResult = null
        pendingPickFileArgs = null

        if (resultCode != Activity.RESULT_OK) {
            result.error("cancelled", "保存をキャンセルしました", null)
            return
        }

        val uri = data?.data
        if (uri == null || args == null) {
            result.error("missing_file_uri", "保存先ファイルを取得できませんでした", null)
            return
        }

        Thread {
            try {
                val saved = performDownloadToUri(args, uri)
                runOnUiThread {
                    result.success(
                        mapOf(
                            "fileName" to saved.fileName,
                            "courseName" to saved.courseName,
                            "location" to saved.location
                        )
                    )
                }
            } catch (error: Exception) {
                Log.e(TAG, "Download failed", error)
                runOnUiThread {
                    result.error("download_failed", error.message ?: "保存できませんでした", null)
                }
            }
        }.start()
    }

    private fun downloadToConfiguredFolder(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        if (args == null) {
            result.error("missing_arguments", "ダウンロード情報を取得できませんでした", null)
            return
        }
        val rawUrl = args["url"]?.toString()
        if (!isAllowedGakujoUrl(rawUrl)) {
            result.error("blocked_url", "Gakujo以外のダウンロードをブロックしました", null)
            return
        }

        val root = downloadRootFile()
        if (root == null) {
            Log.w(TAG, "Download blocked: missing download root")
            result.error("missing_root", "ダウンロード保存先が未設定です", null)
            return
        }

        val downloadArgs = args
        val autoSortByCourse = args["autoSortByCourse"] as? Boolean ?: true
        Thread {
            try {
                val saved = performDownload(downloadArgs, root, autoSortByCourse)
                runOnUiThread {
                    result.success(
                        mapOf(
                            "fileName" to saved.fileName,
                            "courseName" to saved.courseName,
                            "location" to saved.location
                        )
                    )
                }
            } catch (error: Exception) {
                Log.e(TAG, "Download failed", error)
                runOnUiThread {
                    result.error("download_failed", error.message ?: "保存できませんでした", null)
                }
            }
        }.start()
    }

    private fun downloadToPickedFile(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        if (args == null) {
            result.error("missing_arguments", "ダウンロード情報を取得できませんでした", null)
            return
        }
        val rawUrl = args["url"]?.toString()
        if (!isAllowedGakujoUrl(rawUrl)) {
            result.error("blocked_url", "Gakujo以外のダウンロードをブロックしました", null)
            return
        }
        if (pendingPickFileResult != null || pendingPickRootResult != null) {
            result.error("picker_active", "保存先選択がすでに開いています", null)
            return
        }

        val requestedFileName = sanitizeName(args["fileName"]?.toString())
        val suggestedName = chooseFileName(
            requestedName = requestedFileName,
            dispositionName = null,
            url = rawUrl.orEmpty(),
            mimeType = "application/octet-stream"
        )
        pendingPickFileResult = result
        pendingPickFileArgs = args
        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "application/octet-stream"
            putExtra(Intent.EXTRA_TITLE, suggestedName)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }
        @Suppress("DEPRECATION")
        startActivityForResult(intent, REQUEST_CREATE_DOWNLOAD_FILE)
    }

    private fun performDownload(
        args: Map<*, *>,
        root: DocumentFile,
        autoSortByCourse: Boolean
    ): SavedDownload {
        val originalUrl = args["url"].toString()
        val method = args["method"]?.toString()?.uppercase(Locale.ROOT) ?: "GET"
        val formFields = (args["formFields"] as? Map<*, *>).orEmpty()
        val requestedCourseName = sanitizeName(args["courseName"]?.toString()).ifBlank { "未分類" }
        val requestedFileName = sanitizeName(args["fileName"]?.toString())
        val userAgent = args["userAgent"]?.toString()?.takeIf { it.isNotBlank() }

        val url = if (method == "GET" && formFields.isNotEmpty()) {
            appendQuery(originalUrl, formFields)
        } else {
            originalUrl
        }

        if (isDebuggable()) {
            Log.i(
                TAG,
                "Download start method=$method url=${redactSession(url)} fields=${formFields.keys.joinToString(",")}"
            )
        }

        val connection = openAllowedDownloadConnection(
            initialUrl = url,
            initialMethod = method,
            formFields = formFields,
            userAgent = userAgent
        )

        try {
            val responseCode = connection.responseCode
            if (isDebuggable()) {
                Log.i(
                    TAG,
                    "Download response code=$responseCode finalUrl=${redactSession(connection.url.toString())} " +
                        "contentType=${connection.contentType.orEmpty()} " +
                        "disposition=${connection.getHeaderField("Content-Disposition").orEmpty()}"
                )
            }
            if (responseCode !in 200..299) {
                throw IllegalStateException("ダウンロードに失敗しました HTTP $responseCode")
            }
            val finalUrl = connection.url.toString()
            if (!isAllowedGakujoUrl(finalUrl)) {
                throw IllegalStateException("Gakujo以外へのリダイレクトをブロックしました")
            }

            val mimeType = connection.contentType?.substringBefore(';')?.ifBlank { null }
                ?: "application/octet-stream"
            val dispositionName = fileNameFromContentDisposition(connection.getHeaderField("Content-Disposition"))
            val desiredName = chooseFileName(
                requestedName = requestedFileName,
                dispositionName = dispositionName,
                url = finalUrl,
                mimeType = mimeType
            )
            val courseName = if (autoSortByCourse) {
                chooseCourseFolderName(requestedCourseName, desiredName)
            } else {
                requestedCourseName
            }
            val parent = if (autoSortByCourse) ensureDirectory(root, courseName) else root
            val (file, finalName) = synchronized(downloadFolderLock) {
                val allocatedName = uniqueName(
                    parent = parent,
                    desiredName = desiredName
                )
                val createdFile = parent.createFile(mimeType, allocatedName)
                    ?: throw IllegalStateException("ファイルを作成できませんでした")
                createdFile to allocatedName
            }
            val savedFileName = GakujoDownloadFilePolicy.resolvedName(file.name, finalName)
            val output = contentResolver.openOutputStream(file.uri)
                ?: throw IllegalStateException("ファイルを書き込めませんでした")

            BufferedInputStream(connection.inputStream).use { input ->
                output.use { input.copyTo(it) }
            }
            val savedCourseName = if (autoSortByCourse) courseName else ""
            if (isDebuggable()) {
                Log.i(TAG, "Download saved course=$savedCourseName file=$savedFileName")
            }
            return SavedDownload(
                fileName = savedFileName,
                courseName = savedCourseName,
                location = file.uri.toString()
            )
        } finally {
            connection.disconnect()
        }
    }

    private fun performDownloadToUri(args: Map<*, *>, destination: Uri): SavedDownload {
        val originalUrl = args["url"].toString()
        val method = args["method"]?.toString()?.uppercase(Locale.ROOT) ?: "GET"
        val formFields = (args["formFields"] as? Map<*, *>).orEmpty()
        val requestedFileName = sanitizeName(args["fileName"]?.toString())
        val userAgent = args["userAgent"]?.toString()?.takeIf { it.isNotBlank() }

        val url = if (method == "GET" && formFields.isNotEmpty()) {
            appendQuery(originalUrl, formFields)
        } else {
            originalUrl
        }

        if (isDebuggable()) {
            Log.i(
                TAG,
                "Download start method=$method url=${redactSession(url)} fields=${formFields.keys.joinToString(",")}"
            )
        }

        val connection = openAllowedDownloadConnection(
            initialUrl = url,
            initialMethod = method,
            formFields = formFields,
            userAgent = userAgent
        )

        try {
            val responseCode = connection.responseCode
            if (isDebuggable()) {
                Log.i(
                    TAG,
                    "Download response code=$responseCode finalUrl=${redactSession(connection.url.toString())} " +
                        "contentType=${connection.contentType.orEmpty()} " +
                        "disposition=${connection.getHeaderField("Content-Disposition").orEmpty()}"
                )
            }
            if (responseCode !in 200..299) {
                throw IllegalStateException("ダウンロードに失敗しました HTTP $responseCode")
            }
            val finalUrl = connection.url.toString()
            if (!isAllowedGakujoUrl(finalUrl)) {
                throw IllegalStateException("Gakujo以外へのリダイレクトをブロックしました")
            }

            val mimeType = connection.contentType?.substringBefore(';')?.ifBlank { null }
                ?: "application/octet-stream"
            val dispositionName = fileNameFromContentDisposition(connection.getHeaderField("Content-Disposition"))
            val finalName = displayName(destination)
                ?: chooseFileName(
                    requestedName = requestedFileName,
                    dispositionName = dispositionName,
                    url = finalUrl,
                    mimeType = mimeType
                )
            val output = contentResolver.openOutputStream(destination)
                ?: throw IllegalStateException("ファイルを書き込めませんでした")

            BufferedInputStream(connection.inputStream).use { input ->
                output.use { input.copyTo(it) }
            }
            if (isDebuggable()) {
                Log.i(TAG, "Download saved file=$finalName")
            }
            return SavedDownload(
                fileName = finalName,
                courseName = "",
                location = destination.toString()
            )
        } finally {
            connection.disconnect()
        }
    }

    private fun chooseFileName(
        requestedName: String,
        dispositionName: String?,
        url: String,
        mimeType: String
    ): String {
        val primary = requestedName
            .ifBlank { null }
            ?.takeUnless { it.equals("campussquare.do", ignoreCase = true) }
        val fromUrl = Uri.parse(url).lastPathSegment
            ?.let { sanitizeName(decodeUrlComponentOrRaw(it)) }
            ?.takeUnless { it.equals("campussquare.do", ignoreCase = true) }
        val base = primary ?: sanitizeName(dispositionName).ifBlank { fromUrl.orEmpty() }.ifBlank { "document" }
        return if (hasUsefulExtension(base)) {
            base
        } else {
            val extension = extensionFromName(fromUrl) ?: extensionFromMime(mimeType)
            if (extension == null) base else "$base.$extension"
        }
    }

    private fun openAllowedDownloadConnection(
        initialUrl: String,
        initialMethod: String,
        formFields: Map<*, *>,
        userAgent: String?
    ): HttpURLConnection {
        var currentUrl = initialUrl
        var currentMethod = if (initialMethod == "POST") "POST" else "GET"

        for (redirectCount in 0..GakujoDownloadRedirectPolicy.maxRedirects) {
            if (!GakujoDownloadRedirectPolicy.isAllowedUrl(currentUrl)) {
                throw IllegalStateException("Gakujo以外へのリダイレクトをブロックしました")
            }

            val connection = (URL(currentUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = currentMethod
                instanceFollowRedirects = false
                connectTimeout = 30_000
                readTimeout = 60_000
                setRequestProperty("Accept", "*/*")
                CookieManager.getInstance().getCookie(currentUrl)
                    ?.takeIf { it.isNotBlank() }
                    ?.let { setRequestProperty("Cookie", it) }
                userAgent?.let { setRequestProperty("User-Agent", it) }

                if (currentMethod == "POST") {
                    doOutput = true
                    setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                    outputStream.use { output ->
                        output.write(encodeForm(formFields).toByteArray(Charsets.UTF_8))
                    }
                }
            }

            val responseCode = try {
                connection.responseCode
            } catch (error: Exception) {
                connection.disconnect()
                throw error
            }
            if (!GakujoDownloadRedirectPolicy.isRedirectStatus(responseCode)) {
                if (responseCode !in 200..299) {
                    connection.disconnect()
                    throw IllegalStateException("ダウンロードに失敗しました HTTP $responseCode")
                }
                return connection
            }

            val location = connection.getHeaderField("Location")
            if (location.isNullOrBlank()) {
                connection.disconnect()
                throw IllegalStateException("リダイレクト先を取得できませんでした HTTP $responseCode")
            }
            val nextUrl = GakujoDownloadRedirectPolicy.resolveAllowedRedirect(
                currentUrl,
                location
            )
            connection.disconnect()
            if (nextUrl == null) {
                throw IllegalStateException("Gakujo以外へのリダイレクトをブロックしました")
            }
            if (redirectCount == GakujoDownloadRedirectPolicy.maxRedirects) {
                throw IllegalStateException("リダイレクト回数が上限を超えました")
            }

            currentUrl = nextUrl
            currentMethod = GakujoDownloadRedirectPolicy.redirectedMethod(
                responseCode,
                currentMethod
            )
        }

        throw IllegalStateException("リダイレクト回数が上限を超えました")
    }

    private fun chooseCourseFolderName(requestedCourseName: String, fileName: String): String {
        if (isUsefulCourseName(requestedCourseName)) {
            return requestedCourseName
        }
        return inferCourseNameFromFileName(fileName) ?: "未分類"
    }

    private fun isUsefulCourseName(name: String): Boolean {
        if (name.isBlank() || name == "未分類") {
            return false
        }
        val genericPageLabels = setOf(
            "開設一覧",
            "連絡通知",
            "掲示一覧",
            "授業ポートフォリオ",
            "レポート・小テスト・アンケート提出",
            "レポート提出",
            "小テスト",
            "アンケート",
            "年度 開講所属 開講番号 科目名",
            "タイトル"
        )
        if (name in genericPageLabels) {
            return false
        }
        val lower = name.lowercase(Locale.ROOT)
        return !lower.contains("campussquare") &&
            !lower.contains("more better gakujo") &&
            !name.contains("学務情報システム")
    }

    private fun inferCourseNameFromFileName(fileName: String): String? {
        var base = fileName.substringBeforeLast('.')
            .replace(Regex("\\s+"), " ")
            .trim()
        if (base.isBlank()) {
            return null
        }

        base = base
            .replace(Regex("^[0-9０-９]+\\s*[_＿\\-－ー.．]\\s*"), "")
            .trim()

        val separators = listOf("_", "＿", " - ", " – ", " — ", "：", ":", "／", "/")
        val firstSeparatedPart = separators
            .mapNotNull { separator ->
                val index = base.indexOf(separator)
                if (index > 0) base.substring(0, index).trim() else null
            }
            .minByOrNull { it.length }
        if (!firstSeparatedPart.isNullOrBlank()) {
            base = firstSeparatedPart
        }

        base = base
            .replace(Regex("^第\\s*[0-9０-９]+\\s*回\\s*"), "")
            .replace(Regex("^(講義|授業|資料|課題)\\s*"), "")
            .trim()

        if (base.isBlank() || base.length < 3) {
            return null
        }
        if (Regex("^[0-9A-Za-z_ -]+$").matches(base)) {
            return null
        }
        return sanitizeName(base).takeIf { it.isNotBlank() }
    }

    private fun ensureDirectory(root: DocumentFile, name: String): DocumentFile {
        synchronized(downloadFolderLock) {
            findDirectoryWithCloudRetry(root, name)?.let { return it }

            val created = root.createDirectory(name)
                ?: throw IllegalStateException("授業フォルダを作成できませんでした")
            return findDirectory(root, name) ?: created
        }
    }

    private fun findDirectoryWithCloudRetry(root: DocumentFile, name: String): DocumentFile? {
        val delays = listOf(0L, 250L, 750L, 1500L)
        for (delay in delays) {
            if (delay > 0) {
                Thread.sleep(delay)
            }
            findDirectory(root, name)?.let { return it }
        }
        return null
    }

    private fun findDirectory(root: DocumentFile, name: String): DocumentFile? {
        return root.listFiles()
            .firstOrNull { it.isDirectory && it.name == name }
    }

    private fun uniqueName(parent: DocumentFile, desiredName: String): String {
        val existing = parent.listFiles().mapNotNull { it.name }.toSet()
        return GakujoDownloadFilePolicy.uniqueName(existing, desiredName)
    }

    private fun downloadRootState(): Map<String, Any?> {
        val root = downloadRootFile()
        val rawUri = prefs().getString(KEY_DOWNLOAD_ROOT_URI, null)
        return mapOf(
            "isConfigured" to (root != null),
            "displayName" to root?.name,
            "path" to rawUri
        )
    }

    private fun downloadRootFile(): DocumentFile? {
        val rawUri = prefs().getString(KEY_DOWNLOAD_ROOT_URI, null) ?: return null
        val uri = Uri.parse(rawUri)
        return DocumentFile.fromTreeUri(this, uri)?.takeIf { it.exists() && it.canWrite() }
    }

    private fun displayName(uri: Uri): String? {
        return contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) cursor.getString(index) else null
                } else {
                    null
                }
            }
            ?.let { sanitizeName(it) }
            ?.ifBlank { null }
    }

    private fun clearDownloadRoot() {
        val rawUri = prefs().getString(KEY_DOWNLOAD_ROOT_URI, null)
        if (rawUri != null) {
            runCatching {
                contentResolver.releasePersistableUriPermission(
                    Uri.parse(rawUri),
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                )
            }
        }
        prefs().edit().remove(KEY_DOWNLOAD_ROOT_URI).apply()
    }

    private fun isAllowedGakujoUrl(rawUrl: String?): Boolean {
        return GakujoDownloadRedirectPolicy.isAllowedUrl(rawUrl)
    }

    private fun redactSession(rawUrl: String): String {
        return rawUrl.replace(Regex(";jsessionid=[^?#]+", RegexOption.IGNORE_CASE), ";jsessionid=<redacted>")
    }

    private fun appendQuery(rawUrl: String, fields: Map<*, *>): String {
        val separator = if (rawUrl.contains("?")) "&" else "?"
        return rawUrl + separator + encodeForm(fields)
    }

    private fun encodeForm(fields: Map<*, *>): String {
        return fields.entries.joinToString("&") { entry ->
            "${URLEncoder.encode(entry.key.toString(), "UTF-8")}=${
                URLEncoder.encode(entry.value?.toString().orEmpty(), "UTF-8")
            }"
        }
    }

    private fun sanitizeName(raw: String?): String {
        return raw.orEmpty()
            .replace(Regex("[\\x00-\\x1F\\x7F]"), "")
            .replace(Regex("""[\\/:*?"<>|]"""), "")
            .replace(Regex("\\.{2,}"), ".")
            .replace(Regex("\\s+"), " ")
            .trim()
            .trim('.')
            .takeUnless { it == "." || it == ".." }
            .orEmpty()
    }

    private fun hasUsefulExtension(name: String): Boolean {
        val extension = extensionFromName(name) ?: return false
        return extension != "do"
    }

    private fun extensionFromName(name: String?): String? {
        if (name.isNullOrBlank()) {
            return null
        }
        val dot = name.lastIndexOf('.')
        if (dot <= 0 || dot == name.length - 1) {
            return null
        }
        val extension = name.substring(dot + 1).lowercase(Locale.ROOT)
        return extension.takeIf { Regex("^[a-z0-9]{1,8}$").matches(it) }
    }

    private fun extensionFromMime(mimeType: String): String? {
        return when (mimeType.substringBefore(';').lowercase(Locale.ROOT)) {
            "application/pdf" -> "pdf"
            "text/plain" -> "txt"
            "text/csv" -> "csv"
            "application/zip" -> "zip"
            "application/msword" -> "doc"
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document" -> "docx"
            "application/vnd.ms-excel" -> "xls"
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" -> "xlsx"
            "application/vnd.ms-powerpoint" -> "ppt"
            "application/vnd.openxmlformats-officedocument.presentationml.presentation" -> "pptx"
            "image/jpeg" -> "jpg"
            "image/png" -> "png"
            else -> null
        }
    }

    private fun fileNameFromContentDisposition(header: String?): String? {
        if (header.isNullOrBlank()) {
            return null
        }

        Regex("""filename\*\s*=\s*"?([^'";]*)'[^']*'([^";]+)"?""", RegexOption.IGNORE_CASE)
            .find(header)
            ?.let { match ->
                val charset = match.groupValues.getOrNull(1)?.trim()?.lowercase(Locale.ROOT)
                val encodedName = match.groupValues.getOrNull(2)?.trim()?.trim('"')
                if (encodedName != null) {
                    return if (charset.isNullOrEmpty() || charset == "utf-8") {
                        decodeUrlComponentOrRaw(encodedName)
                    } else {
                        encodedName
                    }
                }
            }

        Regex("""filename="?([^";]+)"?""", RegexOption.IGNORE_CASE)
            .find(header)
            ?.groupValues
            ?.getOrNull(1)
            ?.let { return it }

        return null
    }

    private fun decodeUrlComponentOrRaw(value: String): String {
        return runCatching {
            Uri.decode(value) ?: value
        }.getOrElse {
            value
        }
    }

    private fun debugLaunchConfig(): Map<String, String> {
        if (!isDebuggable()) {
            return emptyMap()
        }

        val extras = intent?.extras ?: return emptyMap()
        return buildMap {
            extras.getString(EXTRA_DEBUG_URL)
                ?.takeIf { it.isNotBlank() }
                ?.let { put("startUrl", it) }
            extras.getString(EXTRA_DEBUG_2FA_SECRET)
                ?.takeIf { it.isNotBlank() }
                ?.let { put("twoFactorSecret", it) }
        }
    }

    private fun isDebuggable(): Boolean {
        return (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        val permission = android.Manifest.permission.POST_NOTIFICATIONS
        if (checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        if (pendingNotificationPermissionResult != null) {
            result.error("permission_request_active", "通知権限の確認がすでに開いています", null)
            return
        }
        pendingNotificationPermissionResult = result
        requestPermissions(arrayOf(permission), REQUEST_POST_NOTIFICATIONS)
    }

    private fun showDeadlineNotification(call: MethodCall): Boolean {
        ensureNotificationChannel()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }

        val title = call.argument<String>("title")?.takeIf { it.isNotBlank() } ?: "課題期限"
        val body = call.argument<String>("body")?.takeIf { it.isNotBlank() } ?: "提出期限を検出しました"
        val url = call.argument<String>("url").orEmpty()
        val notificationId = "$title\n$body\n$url".hashCode()
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: Intent(this, MainActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        intent.putExtra(EXTRA_NOTIFICATION_URL, url)
        val pendingIntent = PendingIntent.getActivity(
            this,
            notificationId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, DEADLINE_CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(notificationId, notification)
        return true
    }

    private fun notificationUrlFromIntent(intent: Intent?): String? {
        return intent?.getStringExtra(EXTRA_NOTIFICATION_URL)?.takeIf { it.isNotBlank() }
    }

    private fun ensureNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            DEADLINE_CHANNEL_ID,
            "課題期限",
            NotificationManager.IMPORTANCE_DEFAULT
        )
        manager.createNotificationChannel(channel)
    }

    private fun syncCalendarEvents(call: MethodCall, result: MethodChannel.Result) {
        if (!hasCalendarPermission()) {
            if (pendingCalendarPermissionResult != null) {
                result.error("permission_request_active", "カレンダー権限の確認がすでに開いています", null)
                return
            }
            pendingCalendarPermissionResult = result
            pendingCalendarCall = call
            requestPermissions(
                arrayOf(
                    android.Manifest.permission.READ_CALENDAR,
                    android.Manifest.permission.WRITE_CALENDAR
                ),
                REQUEST_CALENDAR_PERMISSION
            )
            return
        }
        performCalendarSync(call, result)
    }

    private fun deleteCalendarEvents(call: MethodCall, result: MethodChannel.Result) {
        if (!hasCalendarPermission()) {
            if (pendingCalendarPermissionResult != null) {
                result.error("permission_request_active", "カレンダー権限の確認がすでに開いています", null)
                return
            }
            pendingCalendarPermissionResult = result
            pendingCalendarCall = call
            requestPermissions(
                arrayOf(
                    android.Manifest.permission.READ_CALENDAR,
                    android.Manifest.permission.WRITE_CALENDAR
                ),
                REQUEST_CALENDAR_PERMISSION
            )
            return
        }
        performCalendarDelete(call, result)
    }

    private fun hasCalendarPermission(): Boolean {
        return checkSelfPermission(android.Manifest.permission.READ_CALENDAR) == PackageManager.PERMISSION_GRANTED &&
            checkSelfPermission(android.Manifest.permission.WRITE_CALENDAR) == PackageManager.PERMISSION_GRANTED
    }

    private fun performCalendarSync(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        if (args == null) {
            result.error("missing_arguments", "カレンダー情報を取得できませんでした", null)
            return
        }
        Thread {
            try {
                val calendarTitle = args["calendarTitle"]?.toString()?.takeIf { it.isNotBlank() }
                    ?: "More Better Gakujo 授業"
                val rangeStart = (args["rangeStartMillis"] as? Number)?.toLong() ?: 0L
                val rangeEnd = (args["rangeEndMillis"] as? Number)?.toLong() ?: Long.MAX_VALUE
                val events = GakujoCalendarEventPolicy.parseEventsForSync(args["events"])
                val calendarIdentity = GakujoCalendarIdentityPolicy.forSync(calendarTitle, events)
                val syncResult = synchronized(calendarOperationLock) {
                    val calendarId = writableCalendarId(calendarTitle, calendarIdentity)
                        ?: throw IllegalStateException(
                            "「$calendarTitle」カレンダーを作成できませんでした"
                        )
                    applyCalendarSyncBatch(
                        calendarId = calendarId,
                        rangeStart = rangeStart,
                        rangeEnd = rangeEnd,
                        events = events
                    )
                }
                runOnUiThread {
                    result.success(
                        mapOf(
                            "added" to syncResult.added,
                            "removed" to syncResult.removed,
                            "openedFallback" to false
                        )
                    )
                }
            } catch (error: Exception) {
                Log.e(TAG, "Calendar sync failed", error)
                runOnUiThread {
                    result.error("calendar_sync_failed", error.message ?: "カレンダーに追加できませんでした", null)
                }
            }
        }.start()
    }

    private fun performCalendarDelete(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        if (args == null) {
            result.error("missing_arguments", "カレンダー情報を取得できませんでした", null)
            return
        }
        Thread {
            try {
                val calendarTitle = args["calendarTitle"]?.toString()?.takeIf { it.isNotBlank() }
                val rangeStart = (args["rangeStartMillis"] as? Number)?.toLong() ?: 0L
                val rangeEnd = (args["rangeEndMillis"] as? Number)?.toLong() ?: Long.MAX_VALUE
                val removed = synchronized(calendarOperationLock) {
                    val calendarId = calendarTitle?.let {
                        existingCalendarId(
                            calendarTitle = it,
                            identity = GakujoCalendarIdentityPolicy.forTitle(it)
                        )
                    }
                    if (calendarTitle != null && calendarId == null) {
                        deleteLegacyGakujoEventsFromWritableCalendars(rangeStart, rangeEnd)
                    } else {
                        deleteExistingGakujoEvents(rangeStart, rangeEnd, calendarId)
                    }
                }
                runOnUiThread {
                    result.success(mapOf("removed" to removed))
                }
            } catch (error: Exception) {
                Log.e(TAG, "Calendar delete failed", error)
                runOnUiThread {
                    result.error("calendar_delete_failed", error.message ?: "カレンダー予定を削除できませんでした", null)
                }
            }
        }.start()
    }

    private fun writableCalendarId(
        calendarTitle: String,
        identity: GakujoCalendarIdentity
    ): Long? {
        existingCalendarId(calendarTitle, identity)?.let { return it }
        return createLocalCalendar(calendarTitle)?.also { calendarId ->
            rememberCalendarId(identity, calendarId)
        }
    }

    private fun existingCalendarId(
        calendarTitle: String,
        identity: GakujoCalendarIdentity
    ): Long? {
        val rememberedId = rememberedCalendarId(identity)
        var rememberedWritableId: Long? = null
        if (rememberedId != null) {
            val rememberedCalendar = writableDedicatedCalendar(rememberedId)
            if (rememberedCalendar != null) {
                if (renameDedicatedCalendar(rememberedCalendar, calendarTitle)) {
                    rememberedWritableId = rememberedCalendar.id
                }
            }
            if (rememberedWritableId == null) {
                forgetCalendarId(identity)
            }
        }
        val calendarId = GakujoCalendarIdentityPolicy.preferredReusableId(
            rememberedWritableId = rememberedWritableId,
            findByTitle = { calendarIdMatchingTitle(calendarTitle) }
        )
        if (calendarId != null) {
            rememberCalendarId(identity, calendarId)
            return calendarId
        }
        val migrationId = calendarIdMatchingIdentityMarkers(identity) ?: return null
        val migrationCalendar = writableDedicatedCalendar(migrationId) ?: return null
        if (!renameDedicatedCalendar(migrationCalendar, calendarTitle)) {
            return null
        }
        rememberCalendarId(identity, migrationId)
        return migrationId
    }

    private fun calendarIdMatchingTitle(calendarTitle: String): Long? {
        val projection = arrayOf(CalendarContract.Calendars._ID)
        val selection =
            "${CalendarContract.Calendars.CALENDAR_DISPLAY_NAME}=? AND " +
                "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL}>=? AND " +
                "${CalendarContract.Calendars.ACCOUNT_NAME}=? AND " +
                "${CalendarContract.Calendars.ACCOUNT_TYPE}=?"
        val matchingIds = mutableListOf<Long>()
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            selection,
            arrayOf(
                calendarTitle,
                CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString(),
                packageName,
                CalendarContract.ACCOUNT_TYPE_LOCAL
            ),
            null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                matchingIds.add(cursor.getLong(0))
            }
        }
        return matchingIds.singleOrNull()
    }

    private fun calendarIdMatchingIdentityMarkers(
        identity: GakujoCalendarIdentity
    ): Long? {
        val identitiesByCalendarId = ownedWritableCalendars().associate { calendar ->
            calendar.id to markerIdentities(calendar.id)
        }
        return GakujoCalendarIdentityPolicy.uniqueMigrationId(
            identitiesByCalendarId = identitiesByCalendarId,
            targetIdentity = identity
        )
    }

    private fun ownedWritableCalendars(): List<DedicatedCalendar> {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME
        )
        val selection =
            "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL}>=? AND " +
                "${CalendarContract.Calendars.ACCOUNT_NAME}=? AND " +
                "${CalendarContract.Calendars.ACCOUNT_TYPE}=?"
        val calendars = mutableListOf<DedicatedCalendar>()
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            selection,
            arrayOf(
                CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString(),
                packageName,
                CalendarContract.ACCOUNT_TYPE_LOCAL
            ),
            null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                calendars.add(
                    DedicatedCalendar(
                        id = cursor.getLong(0),
                        displayName = cursor.getString(1).orEmpty()
                    )
                )
            }
        }
        return calendars
    }

    private fun markerIdentities(calendarId: Long): Set<GakujoCalendarIdentity> {
        val identities = mutableSetOf<GakujoCalendarIdentity>()
        contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            arrayOf(CalendarContract.Events.DESCRIPTION),
            "${CalendarContract.Events.CALENDAR_ID}=? AND " +
                "${CalendarContract.Events.DESCRIPTION} LIKE ?",
            arrayOf(
                calendarId.toString(),
                "%${GakujoCalendarEventPolicy.EVENT_MARKER}%"
            ),
            null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                GakujoCalendarIdentityPolicy.forMarkerDescription(
                    cursor.getString(0).orEmpty()
                )?.let(identities::add)
            }
        }
        return identities
    }

    private fun writableDedicatedCalendar(calendarId: Long): DedicatedCalendar? {
        val projection = arrayOf(
            CalendarContract.Calendars._ID,
            CalendarContract.Calendars.CALENDAR_DISPLAY_NAME
        )
        val selection =
            "${CalendarContract.Calendars._ID}=? AND " +
                "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL}>=? AND " +
                "${CalendarContract.Calendars.ACCOUNT_NAME}=? AND " +
                "${CalendarContract.Calendars.ACCOUNT_TYPE}=?"
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            selection,
            arrayOf(
                calendarId.toString(),
                CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString(),
                packageName,
                CalendarContract.ACCOUNT_TYPE_LOCAL
            ),
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return DedicatedCalendar(
                    id = cursor.getLong(0),
                    displayName = cursor.getString(1).orEmpty()
                )
            }
        }
        return null
    }

    private fun renameDedicatedCalendar(
        calendar: DedicatedCalendar,
        calendarTitle: String
    ): Boolean {
        if (calendar.displayName == calendarTitle) {
            return true
        }
        val values = ContentValues().apply {
            put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, calendarTitle)
        }
        val uri = ContentUris.withAppendedId(CalendarContract.Calendars.CONTENT_URI, calendar.id)
            .buildUpon()
            .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
            .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, packageName)
            .appendQueryParameter(
                CalendarContract.Calendars.ACCOUNT_TYPE,
                CalendarContract.ACCOUNT_TYPE_LOCAL
            )
            .build()
        return try {
            contentResolver.update(uri, values, null, null) > 0
        } catch (error: SecurityException) {
            Log.w(TAG, "Remembered calendar is no longer writable", error)
            false
        }
    }

    private fun rememberedCalendarId(identity: GakujoCalendarIdentity): Long? {
        val key = GakujoCalendarIdentityPolicy.preferenceKey(identity)
        return if (prefs().contains(key)) prefs().getLong(key, 0L) else null
    }

    private fun rememberCalendarId(identity: GakujoCalendarIdentity, calendarId: Long) {
        prefs().edit()
            .putLong(GakujoCalendarIdentityPolicy.preferenceKey(identity), calendarId)
            .apply()
    }

    private fun forgetCalendarId(identity: GakujoCalendarIdentity) {
        prefs().edit()
            .remove(GakujoCalendarIdentityPolicy.preferenceKey(identity))
            .apply()
    }

    private fun createLocalCalendar(calendarTitle: String): Long? {
        return try {
            val values = ContentValues().apply {
                put(CalendarContract.Calendars.ACCOUNT_NAME, packageName)
                put(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
                put(CalendarContract.Calendars.NAME, calendarTitle)
                put(CalendarContract.Calendars.CALENDAR_DISPLAY_NAME, calendarTitle)
                put(CalendarContract.Calendars.CALENDAR_COLOR, 0xff2e7d32.toInt())
                put(CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL, CalendarContract.Calendars.CAL_ACCESS_OWNER)
                put(CalendarContract.Calendars.OWNER_ACCOUNT, packageName)
                put(CalendarContract.Calendars.VISIBLE, 1)
                put(CalendarContract.Calendars.SYNC_EVENTS, 1)
            }
            val uri = CalendarContract.Calendars.CONTENT_URI.buildUpon()
                .appendQueryParameter(CalendarContract.CALLER_IS_SYNCADAPTER, "true")
                .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_NAME, packageName)
                .appendQueryParameter(CalendarContract.Calendars.ACCOUNT_TYPE, CalendarContract.ACCOUNT_TYPE_LOCAL)
                .build()
            contentResolver.insert(uri, values)?.lastPathSegment?.toLongOrNull()
        } catch (error: Exception) {
            Log.w(TAG, "Failed to create local calendar", error)
            null
        }
    }

    private fun deleteExistingGakujoEvents(rangeStart: Long, rangeEnd: Long, calendarId: Long? = null): Int {
        val existingEvents = existingGakujoEvents(calendarId)
        val eventIds = GakujoCalendarEventPolicy.eventIdsToReplace(
            existingEvents = existingEvents,
            namespaces = emptySet(),
            replacementRange = CalendarEventReplacementRange(rangeStart, rangeEnd)
        )
        return deleteCalendarEventIds(eventIds)
    }

    private fun deleteLegacyGakujoEventsFromWritableCalendars(
        rangeStart: Long,
        rangeEnd: Long
    ): Int {
        val eventIds = GakujoCalendarEventPolicy.eventIdsForExplicitLegacyDelete(
            existingEvents = existingGakujoEvents(),
            writableCalendarIds = writableCalendarIds(),
            replacementRange = CalendarEventReplacementRange(rangeStart, rangeEnd)
        )
        return deleteCalendarEventIds(eventIds)
    }

    private fun deleteCalendarEventIds(eventIds: List<Long>): Int {
        if (eventIds.isEmpty()) {
            return 0
        }
        val operations = ArrayList<ContentProviderOperation>(eventIds.size)
        eventIds.forEach { eventId ->
            operations.add(
                ContentProviderOperation.newDelete(
                    ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId)
                ).build()
            )
        }
        return contentResolver.applyBatch(CalendarContract.AUTHORITY, operations)
            .sumOf { it.count ?: 0 }
    }

    private fun applyCalendarSyncBatch(
        calendarId: Long,
        rangeStart: Long,
        rangeEnd: Long,
        events: List<GakujoCalendarEventData>
    ): CalendarSyncBatchResult {
        val namespaces = GakujoCalendarEventPolicy.replacementNamespaces(events)
        val currentRange = CalendarEventReplacementRange(rangeStart, rangeEnd)
        val replacementRange = if (namespaces.isEmpty()) {
            GakujoCalendarEventPolicy.unionRange(
                current = currentRange,
                previous = previousCalendarSyncRange(calendarId)
            )
        } else {
            currentRange
        }
        val eventIds = if (namespaces.isNotEmpty()) {
            val namespace = namespaces.single()
            val includeForeignCalendars = needsNamespaceCleanup(namespace)
            GakujoCalendarEventPolicy.eventIdsForNamespaceCleanup(
                existingEvents = if (includeForeignCalendars) {
                    existingGakujoEvents()
                } else {
                    existingGakujoEvents(calendarId)
                },
                writableCalendarIds = if (includeForeignCalendars) {
                    writableCalendarIds()
                } else {
                    emptySet()
                },
                namespaces = namespaces,
                targetCalendarId = calendarId,
                includeForeignCalendars = includeForeignCalendars
            )
        } else {
            GakujoCalendarEventPolicy.eventIdsToReplace(
                existingEvents = existingGakujoEvents(calendarId),
                namespaces = emptySet(),
                replacementRange = replacementRange
            )
        }
        val operations = ArrayList<ContentProviderOperation>(eventIds.size + events.size)
        eventIds.forEach { eventId ->
            operations.add(
                ContentProviderOperation.newDelete(
                    ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, eventId)
                ).build()
            )
        }
        events.forEach { event ->
            operations.add(
                ContentProviderOperation.newInsert(CalendarContract.Events.CONTENT_URI)
                    .withValues(calendarEventValues(calendarId, event))
                    .build()
            )
        }
        if (operations.isEmpty()) {
            rememberCalendarSyncRange(calendarId, currentRange)
            namespaces.singleOrNull()?.let(::rememberNamespaceCleanup)
            return CalendarSyncBatchResult(added = 0, removed = 0)
        }
        val batchResults = contentResolver.applyBatch(CalendarContract.AUTHORITY, operations)
        val removed = batchResults
            .take(eventIds.size)
            .sumOf { it.count ?: 0 }
        rememberCalendarSyncRange(calendarId, currentRange)
        namespaces.singleOrNull()?.let(::rememberNamespaceCleanup)
        return CalendarSyncBatchResult(added = events.size, removed = removed)
    }

    private fun existingGakujoEvents(calendarId: Long? = null): List<ExistingGakujoCalendarEvent> {
        val projection = arrayOf(
            CalendarContract.Events._ID,
            CalendarContract.Events.DTSTART,
            CalendarContract.Events.DESCRIPTION,
            CalendarContract.Events.CALENDAR_ID
        )
        val selectionParts = mutableListOf(
            "${CalendarContract.Events.DESCRIPTION} LIKE ?"
        )
        val selectionArgs = mutableListOf("%${GakujoCalendarEventPolicy.EVENT_MARKER}%")
        if (calendarId != null) {
            selectionParts.add("${CalendarContract.Events.CALENDAR_ID}=?")
            selectionArgs.add(calendarId.toString())
        }
        val events = mutableListOf<ExistingGakujoCalendarEvent>()
        contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection,
            selectionParts.joinToString(" AND "),
            selectionArgs.toTypedArray(),
            null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                events.add(
                    ExistingGakujoCalendarEvent(
                        id = cursor.getLong(0),
                        startMillis = cursor.getLong(1),
                        description = cursor.getString(2).orEmpty(),
                        calendarId = cursor.getLong(3)
                    )
                )
            }
        }
        return events
    }

    private fun writableCalendarIds(): Set<Long> {
        val calendarIds = mutableSetOf<Long>()
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            arrayOf(CalendarContract.Calendars._ID),
            "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL}>=?",
            arrayOf(CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString()),
            null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                calendarIds.add(cursor.getLong(0))
            }
        }
        return calendarIds
    }

    private fun needsNamespaceCleanup(namespace: String): Boolean {
        return !prefs().getBoolean("$KEY_CALENDAR_NAMESPACE_CLEANUP_PREFIX$namespace", false)
    }

    private fun rememberNamespaceCleanup(namespace: String) {
        prefs().edit()
            .putBoolean("$KEY_CALENDAR_NAMESPACE_CLEANUP_PREFIX$namespace", true)
            .apply()
    }

    private fun previousCalendarSyncRange(calendarId: Long): CalendarEventReplacementRange? {
        val preferences = prefs()
        val startKey = "$KEY_CALENDAR_SYNC_RANGE_PREFIX${calendarId}_start"
        val endKey = "$KEY_CALENDAR_SYNC_RANGE_PREFIX${calendarId}_end"
        if (!preferences.contains(startKey) || !preferences.contains(endKey)) {
            return null
        }
        return CalendarEventReplacementRange(
            startMillis = preferences.getLong(startKey, 0L),
            endMillis = preferences.getLong(endKey, 0L)
        )
    }

    private fun rememberCalendarSyncRange(
        calendarId: Long,
        range: CalendarEventReplacementRange
    ) {
        prefs().edit()
            .putLong("$KEY_CALENDAR_SYNC_RANGE_PREFIX${calendarId}_start", range.startMillis)
            .putLong("$KEY_CALENDAR_SYNC_RANGE_PREFIX${calendarId}_end", range.endMillis)
            .apply()
    }

    private fun calendarEventValues(
        calendarId: Long,
        event: GakujoCalendarEventData
    ): ContentValues {
        return ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.TITLE, event.title)
            put(CalendarContract.Events.DTSTART, event.startMillis)
            put(CalendarContract.Events.DTEND, event.endMillis)
            put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getTimeZone("Asia/Tokyo").id)
            put(CalendarContract.Events.DESCRIPTION, event.description)
            put(CalendarContract.Events.EVENT_LOCATION, event.location)
            put(CalendarContract.Events.AVAILABILITY, CalendarContract.Events.AVAILABILITY_BUSY)
        }
    }

    private fun prefs(): SharedPreferences {
        return getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
    }

    private data class SavedDownload(
        val fileName: String,
        val courseName: String,
        val location: String
    )

    private data class CalendarSyncBatchResult(
        val added: Int,
        val removed: Int
    )

    private data class DedicatedCalendar(
        val id: Long,
        val displayName: String
    )

    private companion object {
        const val TAG = "MoreBetterGakujo"
        const val DEBUG_LAUNCH_CHANNEL = "net.yoshida.morebettergakujo/debug_launch"
        const val DOWNLOADS_CHANNEL = "net.yoshida.morebettergakujo/downloads"
        const val NOTIFICATIONS_CHANNEL = "net.yoshida.morebettergakujo/notifications"
        const val CALENDAR_CHANNEL = "net.yoshida.morebettergakujo/calendar"
        const val DEADLINE_CHANNEL_ID = "gakujo_deadlines"
        const val EXTRA_DEBUG_URL = "net.yoshida.morebettergakujo.DEBUG_URL"
        const val EXTRA_DEBUG_2FA_SECRET = "net.yoshida.morebettergakujo.DEBUG_2FA_SECRET"
        const val EXTRA_NOTIFICATION_URL = "net.yoshida.morebettergakujo.NOTIFICATION_URL"
        const val REQUEST_PICK_DOWNLOAD_ROOT = 2001
        const val REQUEST_CREATE_DOWNLOAD_FILE = 2002
        const val REQUEST_POST_NOTIFICATIONS = 2003
        const val REQUEST_CALENDAR_PERMISSION = 2004
        const val PREFS_NAME = "morebettergakujo_downloads"
        const val KEY_DOWNLOAD_ROOT_URI = "download_root_uri"
        const val KEY_CALENDAR_SYNC_RANGE_PREFIX = "calendar_sync_range_"
        const val KEY_CALENDAR_NAMESPACE_CLEANUP_PREFIX = "calendar_namespace_cleanup_"
    }
}
