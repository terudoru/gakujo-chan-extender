package net.yoshida.morebettergakujo

import android.app.Activity
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.ApplicationInfo
import android.net.Uri
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
import java.net.URLDecoder
import java.net.URLEncoder
import java.util.Locale

class MainActivity : FlutterActivity() {
    private var pendingPickRootResult: MethodChannel.Result? = null
    private var pendingPickFileResult: MethodChannel.Result? = null
    private var pendingPickFileArgs: Map<*, *>? = null

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
        if (pendingPickRootResult != null) {
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

        val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
        contentResolver.takePersistableUriPermission(uri, data.flags and flags)
        prefs().edit().putString(KEY_DOWNLOAD_ROOT_URI, uri.toString()).apply()
        result.success(downloadRootState())
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
                            "courseName" to saved.courseName
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
                            "courseName" to saved.courseName
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
        if (pendingPickFileResult != null) {
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

        Log.i(
            TAG,
            "Download start method=$method url=${redactSession(url)} fields=${formFields.keys.joinToString(",")}"
        )

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

        val responseCode = connection.responseCode
        Log.i(
            TAG,
            "Download response code=$responseCode finalUrl=${redactSession(connection.url.toString())} " +
                "contentType=${connection.contentType.orEmpty()} " +
                "disposition=${connection.getHeaderField("Content-Disposition").orEmpty()}"
        )
        if (responseCode !in 200..299) {
            throw IllegalStateException("ダウンロードに失敗しました HTTP $responseCode")
        }

        val mimeType = connection.contentType?.substringBefore(';')?.ifBlank { null }
            ?: "application/octet-stream"
        val dispositionName = fileNameFromContentDisposition(connection.getHeaderField("Content-Disposition"))
        val desiredName = chooseFileName(
            requestedName = requestedFileName,
            dispositionName = dispositionName,
            url = connection.url.toString(),
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
        connection.disconnect()
        val savedCourseName = if (autoSortByCourse) courseName else ""
        Log.i(TAG, "Download saved course=$savedCourseName file=$finalName")
        return SavedDownload(fileName = finalName, courseName = savedCourseName)
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

        Log.i(
            TAG,
            "Download start method=$method url=${redactSession(url)} fields=${formFields.keys.joinToString(",")}"
        )

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

        val responseCode = connection.responseCode
        Log.i(
            TAG,
            "Download response code=$responseCode finalUrl=${redactSession(connection.url.toString())} " +
                "contentType=${connection.contentType.orEmpty()} " +
                "disposition=${connection.getHeaderField("Content-Disposition").orEmpty()}"
        )
        if (responseCode !in 200..299) {
            throw IllegalStateException("ダウンロードに失敗しました HTTP $responseCode")
        }

        val mimeType = connection.contentType?.substringBefore(';')?.ifBlank { null }
            ?: "application/octet-stream"
        val dispositionName = fileNameFromContentDisposition(connection.getHeaderField("Content-Disposition"))
        val finalName = displayName(destination)
            ?: chooseFileName(
                requestedName = requestedFileName,
                dispositionName = dispositionName,
                url = connection.url.toString(),
                mimeType = mimeType
            )
        val output = contentResolver.openOutputStream(destination)
            ?: throw IllegalStateException("ファイルを書き込めませんでした")

        BufferedInputStream(connection.inputStream).use { input ->
            output.use { input.copyTo(it) }
        }
        connection.disconnect()
        Log.i(TAG, "Download saved file=$finalName")
        return SavedDownload(fileName = finalName, courseName = "")
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
            ?.let { sanitizeName(URLDecoder.decode(it, "UTF-8")) }
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
        root.findFile(name)?.takeIf { it.isDirectory }?.let { return it }
        return root.createDirectory(name) ?: throw IllegalStateException("授業フォルダを作成できませんでした")
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
        return mapOf(
            "isConfigured" to (root != null),
            "displayName" to root?.name
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
            .replace(Regex("\\s+"), " ")
            .trim()
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

        Regex("filename\\*=UTF-8''([^;]+)", RegexOption.IGNORE_CASE)
            .find(header)
            ?.groupValues
            ?.getOrNull(1)
            ?.let { return URLDecoder.decode(it.trim('"'), "UTF-8") }

        Regex("""filename="?([^";]+)"?""", RegexOption.IGNORE_CASE)
            .find(header)
            ?.groupValues
            ?.getOrNull(1)
            ?.let { return it }

        return null
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

    private fun prefs(): SharedPreferences {
        return getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
    }

    private data class SavedDownload(
        val fileName: String,
        val courseName: String
    )

    private companion object {
        const val TAG = "MoreBetterGakujo"
        const val DEBUG_LAUNCH_CHANNEL = "net.yoshida.morebettergakujo/debug_launch"
        const val DOWNLOADS_CHANNEL = "net.yoshida.morebettergakujo/downloads"
        const val EXTRA_DEBUG_URL = "net.yoshida.morebettergakujo.DEBUG_URL"
        const val EXTRA_DEBUG_2FA_SECRET = "net.yoshida.morebettergakujo.DEBUG_2FA_SECRET"
        const val REQUEST_PICK_DOWNLOAD_ROOT = 2001
        const val REQUEST_CREATE_DOWNLOAD_FILE = 2002
        const val PREFS_NAME = "morebettergakujo_downloads"
        const val KEY_DOWNLOAD_ROOT_URI = "download_root_uri"
    }
}
