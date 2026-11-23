package net.yoshida.morebettergakujo

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.util.Locale
import java.util.UUID
import java.util.concurrent.Executors

internal class IncomingAttachmentReceiver {
    private val main = Handler(Looper.getMainLooper())

    @Volatile
    private var revision = 0
    private var channel: MethodChannel? = null
    private var pending: Map<String, String>? = null

    fun register(context: Context, messenger: BinaryMessenger) {
        val root = rootDirectory(context.applicationContext)
        channel = MethodChannel(messenger, CHANNEL).also { bridge ->
            bridge.setMethodCallHandler { call, result ->
                when (call.method) {
                    "takePendingAttachment" -> {
                        val attachment = pending
                        pending = null
                        result.success(attachment)
                    }
                    "discardAttachment" -> {
                        val id = call.arguments as? String
                        if (id != null && cacheId.matches(id)) {
                            worker.execute { File(root, id).deleteRecursively() }
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun detach() {
        revision++
        channel?.setMethodCallHandler(null)
        channel = null
        discard(pending)
        pending = null
    }

    fun prune(context: Context) {
        val root = rootDirectory(context.applicationContext)
        worker.execute {
            val cutoff = System.currentTimeMillis() - CACHE_LIFETIME_MILLIS
            root.listFiles()?.filter {
                cacheId.matches(it.name) && it.lastModified() < cutoff
            }?.forEach { it.deleteRecursively() }
        }
    }

    fun receive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_SEND) return
        val request = ++revision
        if (intent.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION == 0) {
            publish(request, error("unavailable"))
            return
        }
        val uri = try {
            streamUri(intent)?.takeIf {
                it.scheme == "content" && !it.authority.isNullOrEmpty() &&
                    context.checkUriPermission(
                        it,
                        Process.myPid(),
                        Process.myUid(),
                        Intent.FLAG_GRANT_READ_URI_PERMISSION,
                    ) == PackageManager.PERMISSION_GRANTED
            }
        } catch (_: RuntimeException) {
            null
        }
        if (uri == null) {
            publish(request, error("unavailable"))
            return
        }
        val app = context.applicationContext
        worker.execute {
            if (request != revision) return@execute
            val received = try {
                copy(app, uri)
            } catch (_: TooLarge) {
                error("too_large")
            } catch (_: IOException) {
                error("unavailable")
            } catch (_: RuntimeException) {
                error("unavailable")
            }
            main.post { publish(request, received) }
        }
    }

    private fun publish(request: Int, data: Map<String, String>) {
        if (request != revision) {
            discard(data)
            return
        }
        discard(pending)
        pending = data
        channel?.invokeMethod("attachmentAvailable", null)
    }

    private fun discard(data: Map<String, String>?) {
        // Only unclaimed copies stay in the native slot. Flutter can still be
        // reading a copy after taking it, so its lifetime is tracked separately.
        val path = data?.get("path") ?: return
        val file = File(path)
        worker.execute {
            file.delete()
            file.parentFile?.delete()
        }
    }

    @Suppress("DEPRECATION")
    private fun streamUri(intent: Intent): Uri? {
        val stream = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
        val clip = intent.clipData ?: return stream
        if (clip.itemCount != 1) return null
        val item = clip.getItemAt(0).uri
        return if (stream == null || stream == item) item else null
    }

    private fun copy(context: Context, uri: Uri): Map<String, String> {
        val resolver = context.contentResolver
        val name = resolver.query(
            uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE),
            null, null, null,
        )?.use { cursor ->
            if (!cursor.moveToFirst()) return@use null
            val sizeIndex = cursor.getColumnIndex(OpenableColumns.SIZE)
            if (sizeIndex >= 0 && !cursor.isNull(sizeIndex) &&
                cursor.getLong(sizeIndex) > MAX_BYTES
            ) throw TooLarge()
            val nameIndex = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (nameIndex < 0) null else cursor.getString(nameIndex)
        }.orEmpty()
        val extension = name.substringAfterLast('.', "")
        val suffix = extension.ifEmpty {
            val providerMime = resolver.getType(uri)?.lowercase(Locale.ROOT)
            mimeTypes.entries.firstOrNull { it.value == providerMime }?.key
                ?: throw IOException()
        }
        val mime = mimeTypes[suffix.lowercase(Locale.ROOT)] ?: throw IOException()
        val stem = name.substringBeforeLast('.').map {
            if (it.code < 32 || it.code == 127 || it in "<>:\"/\\|?*") '_' else it
        }.joinToString("").trim().take(64).trimEnd { it.isHighSurrogate() }
        val fileName = stem.ifEmpty { "添付ファイル" } + "." + suffix
        val directory = File(rootDirectory(context), UUID.randomUUID().toString())
        if (!directory.mkdirs()) throw IOException()
        val destination = File(directory, fileName)
        var copied = false
        try {
            val stream = resolver.openInputStream(uri) ?: throw IOException()
            stream.use { input ->
                destination.outputStream().use { output ->
                    val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                    var total = 0L
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        total += count
                        if (total > MAX_BYTES) throw TooLarge()
                        output.write(buffer, 0, count)
                    }
                    if (total == 0L) throw IOException()
                }
            }
            copied = true
            return mapOf("path" to destination.path, "name" to fileName, "mimeType" to mime)
        } finally {
            if (!copied) directory.deleteRecursively()
        }
    }

    private class TooLarge : IOException()

    companion object {
        private const val CHANNEL = "net.yoshida.morebettergakujo/incoming_attachment"
        private const val MAX_BYTES = 64L * 1024 * 1024
        private const val CACHE_LIFETIME_MILLIS = 24L * 60 * 60 * 1000
        private val cacheId = Regex("[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}")
        private val worker = Executors.newSingleThreadExecutor()

        private val mimeTypes = mapOf(
            "pdf" to "application/pdf",
            "jpg" to "image/jpeg",
            "jpeg" to "image/jpeg",
            "png" to "image/png",
            "webp" to "image/webp",
            "gif" to "image/gif",
            "heic" to "image/heic",
            "heif" to "image/heif",
            "doc" to "application/msword",
            "docx" to "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
            "xls" to "application/vnd.ms-excel",
            "xlsx" to "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "ppt" to "application/vnd.ms-powerpoint",
            "pptx" to "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        )

        private fun rootDirectory(context: Context) = File(context.cacheDir, "mbg-incoming-attachments")

        private fun error(code: String) = mapOf("error" to code)
    }
}
