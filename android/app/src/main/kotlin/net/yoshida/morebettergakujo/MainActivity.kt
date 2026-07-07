package net.yoshida.morebettergakujo

import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Notification
import android.app.PendingIntent
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
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
import java.util.Locale
import java.util.TimeZone

class MainActivity : FlutterActivity() {
    private var pendingPickRootResult: MethodChannel.Result? = null
    private var pendingPickFileResult: MethodChannel.Result? = null
    private var pendingPickFileArgs: Map<*, *>? = null
    private var pendingNotificationPermissionResult: MethodChannel.Result? = null
    private var pendingCalendarPermissionResult: MethodChannel.Result? = null
    private var pendingCalendarCall: MethodCall? = null
    private val downloadFolderLock = Any()

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

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATIONS_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> requestNotificationPermission(result)
                "notifyDeadline" -> {
                    result.success(showDeadlineNotification(call))
                }
                else -> result.notImplemented()
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

        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = if (method == "POST") "POST" else "GET"
            instanceFollowRedirects = true
            connectTimeout = 30_000
            readTimeout = 60_000
            setRequestProperty("Cookie", CookieManager.getInstance().getCookie(originalUrl).orEmpty())
            userAgent?.let { setRequestProperty("User-Agent", it) }

            if (method == "POST") {
                doOutput = true
                setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                outputStream.use { output ->
                    output.write(encodeForm(formFields).toByteArray(Charsets.UTF_8))
                }
            }
        }

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
            val finalName = uniqueName(
                parent = parent,
                desiredName = desiredName
            )
            val file = parent.createFile(mimeType, finalName)
                ?: throw IllegalStateException("ファイルを作成できませんでした")
            val output = contentResolver.openOutputStream(file.uri)
                ?: throw IllegalStateException("ファイルを書き込めませんでした")

            BufferedInputStream(connection.inputStream).use { input ->
                output.use { input.copyTo(it) }
            }
            val savedCourseName = if (autoSortByCourse) courseName else ""
            if (isDebuggable()) {
                Log.i(TAG, "Download saved course=$savedCourseName file=$finalName")
            }
            return SavedDownload(
                fileName = finalName,
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

        val connection = (URL(url).openConnection() as HttpURLConnection).apply {
            requestMethod = if (method == "POST") "POST" else "GET"
            instanceFollowRedirects = true
            connectTimeout = 30_000
            readTimeout = 60_000
            setRequestProperty("Cookie", CookieManager.getInstance().getCookie(originalUrl).orEmpty())
            userAgent?.let { setRequestProperty("User-Agent", it) }

            if (method == "POST") {
                doOutput = true
                setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
                outputStream.use { output ->
                    output.write(encodeForm(formFields).toByteArray(Charsets.UTF_8))
                }
            }
        }

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
        if (!existing.contains(desiredName)) {
            return desiredName
        }

        val dot = desiredName.lastIndexOf('.')
        val hasExtension = dot > 0 && dot < desiredName.length - 1
        val base = if (hasExtension) desiredName.substring(0, dot) else desiredName
        val extension = if (hasExtension) desiredName.substring(dot) else ""
        var index = 1
        while (true) {
            val candidate = "$base ($index)$extension"
            if (!existing.contains(candidate)) {
                return candidate
            }
            index += 1
        }
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
        if (rawUrl.isNullOrBlank()) {
            return false
        }
        val uri = runCatching { Uri.parse(rawUrl) }.getOrNull() ?: return false
        return uri.scheme == "https" && uri.host == "gakujo.iess.niigata-u.ac.jp"
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
                val calendarId = writableCalendarId(calendarTitle)
                    ?: throw IllegalStateException("書き込み可能なカレンダーが見つかりません")
                val removed = deleteExistingGakujoEvents(rangeStart, rangeEnd, calendarId)
                val events = args["events"] as? List<*> ?: emptyList<Any>()
                var added = 0
                for (rawEvent in events) {
                    val event = rawEvent as? Map<*, *> ?: continue
                    if (insertCalendarEvent(calendarId, event)) {
                        added += 1
                    }
                }
                runOnUiThread {
                    result.success(
                        mapOf(
                            "added" to added,
                            "removed" to removed,
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
                val calendarId = calendarTitle?.let { existingCalendarId(it) }
                if (calendarTitle != null && calendarId == null) {
                    runOnUiThread {
                        result.success(mapOf("removed" to 0))
                    }
                    return@Thread
                }
                val rangeStart = (args["rangeStartMillis"] as? Number)?.toLong() ?: 0L
                val rangeEnd = (args["rangeEndMillis"] as? Number)?.toLong() ?: Long.MAX_VALUE
                val removed = deleteExistingGakujoEvents(rangeStart, rangeEnd, calendarId)
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

    private fun writableCalendarId(calendarTitle: String): Long? {
        existingCalendarId(calendarTitle)?.let { return it }
        createLocalCalendar(calendarTitle)?.let { return it }
        return firstWritableCalendarId()
    }

    private fun existingCalendarId(calendarTitle: String): Long? {
        val projection = arrayOf(CalendarContract.Calendars._ID)
        val selection = "${CalendarContract.Calendars.CALENDAR_DISPLAY_NAME}=?"
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            selection,
            arrayOf(calendarTitle),
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getLong(0)
            }
        }
        return null
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

    private fun firstWritableCalendarId(): Long? {
        val projection = arrayOf(CalendarContract.Calendars._ID)
        val selection = "${CalendarContract.Calendars.CALENDAR_ACCESS_LEVEL}>=?"
        val owner = CalendarContract.Calendars.CAL_ACCESS_CONTRIBUTOR.toString()
        contentResolver.query(
            CalendarContract.Calendars.CONTENT_URI,
            projection,
            selection,
            arrayOf(owner),
            null
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                return cursor.getLong(0)
            }
        }
        return null
    }

    private fun deleteExistingGakujoEvents(rangeStart: Long, rangeEnd: Long, calendarId: Long? = null): Int {
        val projection = arrayOf(CalendarContract.Events._ID)
        val selectionParts = mutableListOf(
            "${CalendarContract.Events.DTSTART}>=?",
            "${CalendarContract.Events.DTSTART}<=?",
            "${CalendarContract.Events.DESCRIPTION} LIKE ?"
        )
        val selectionArgs = mutableListOf(
            rangeStart.toString(),
            rangeEnd.toString(),
            "%$CALENDAR_EVENT_MARKER%"
        )
        if (calendarId != null) {
            selectionParts.add("${CalendarContract.Events.CALENDAR_ID}=?")
            selectionArgs.add(calendarId.toString())
        }
        var removed = 0
        contentResolver.query(
            CalendarContract.Events.CONTENT_URI,
            projection,
            selectionParts.joinToString(" AND "),
            selectionArgs.toTypedArray(),
            null
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val uri = ContentUris.withAppendedId(CalendarContract.Events.CONTENT_URI, cursor.getLong(0))
                removed += contentResolver.delete(uri, null, null)
            }
        }
        return removed
    }

    private fun insertCalendarEvent(calendarId: Long, event: Map<*, *>): Boolean {
        val title = event["title"]?.toString()?.takeIf { it.isNotBlank() } ?: return false
        val start = longValue(event["startMillis"]) ?: return false
        val end = longValue(event["endMillis"]) ?: return false
        val id = event["id"]?.toString().orEmpty()
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
            append(CALENDAR_EVENT_MARKER)
            append(id)
        }
        val values = ContentValues().apply {
            put(CalendarContract.Events.CALENDAR_ID, calendarId)
            put(CalendarContract.Events.TITLE, title)
            put(CalendarContract.Events.DTSTART, start)
            put(CalendarContract.Events.DTEND, end)
            put(CalendarContract.Events.EVENT_TIMEZONE, TimeZone.getTimeZone("Asia/Tokyo").id)
            put(CalendarContract.Events.DESCRIPTION, description)
            put(CalendarContract.Events.EVENT_LOCATION, event["location"]?.toString().orEmpty())
            put(CalendarContract.Events.AVAILABILITY, CalendarContract.Events.AVAILABILITY_BUSY)
        }
        contentResolver.insert(CalendarContract.Events.CONTENT_URI, values)
            ?: throw IllegalStateException("予定を追加できませんでした")
        return true
    }

    private fun longValue(value: Any?): Long? {
        return when (value) {
            is Number -> value.toLong()
            is String -> value.toLongOrNull()
            else -> null
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

    private companion object {
        const val TAG = "MoreBetterGakujo"
        const val DEBUG_LAUNCH_CHANNEL = "net.yoshida.morebettergakujo/debug_launch"
        const val DOWNLOADS_CHANNEL = "net.yoshida.morebettergakujo/downloads"
        const val NOTIFICATIONS_CHANNEL = "net.yoshida.morebettergakujo/notifications"
        const val CALENDAR_CHANNEL = "net.yoshida.morebettergakujo/calendar"
        const val CALENDAR_EVENT_MARKER = "MBG_UID:"
        const val DEADLINE_CHANNEL_ID = "gakujo_deadlines"
        const val EXTRA_DEBUG_URL = "net.yoshida.morebettergakujo.DEBUG_URL"
        const val EXTRA_DEBUG_2FA_SECRET = "net.yoshida.morebettergakujo.DEBUG_2FA_SECRET"
        const val REQUEST_PICK_DOWNLOAD_ROOT = 2001
        const val REQUEST_CREATE_DOWNLOAD_FILE = 2002
        const val REQUEST_POST_NOTIFICATIONS = 2003
        const val REQUEST_CALENDAR_PERMISSION = 2004
        const val PREFS_NAME = "morebettergakujo_downloads"
        const val KEY_DOWNLOAD_ROOT_URI = "download_root_uri"
    }
}
