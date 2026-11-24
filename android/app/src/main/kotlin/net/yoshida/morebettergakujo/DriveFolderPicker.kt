package net.yoshida.morebettergakujo

import android.accounts.Account
import android.app.Activity
import android.content.Intent
import android.os.Bundle
import androidx.lifecycle.Lifecycle
import com.google.android.gms.auth.api.identity.AuthorizationRequest
import com.google.android.gms.auth.api.identity.AuthorizationRequest.ResourceParameter
import com.google.android.gms.auth.api.identity.AuthorizationResult
import com.google.android.gms.auth.api.identity.Identity
import com.google.android.gms.common.api.ApiException
import com.google.android.gms.common.api.CommonStatusCodes
import com.google.android.gms.common.api.Scope
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

private const val NEXT_REQUEST_CODE = "driveFolderPicker.nextRequestCode"
private const val FIRST_REQUEST_CODE = 0x4d420000

internal class DriveFolderPicker(
    private val activity: FlutterActivity,
    savedState: Bundle?,
    private val isPickerActive: () -> Boolean,
) {
    private val requests = DriveFolderPickRequests(
        savedState?.getInt(NEXT_REQUEST_CODE, FIRST_REQUEST_CODE) ?: FIRST_REQUEST_CODE,
    )
    private val client by lazy { Identity.getAuthorizationClient(activity) }
    private var channel: MethodChannel? = null

    val isActive get() = requests.activeCode != null

    fun saveState(outState: Bundle) {
        // Android can deliver the old picker result to the recreated activity.
        outState.putInt(NEXT_REQUEST_CODE, requests.nextCode)
    }

    fun attach(messenger: BinaryMessenger) {
        detach()
        channel = MethodChannel(messenger, "net.yoshida.morebettergakujo/drive_folder_picker").apply {
            setMethodCallHandler { call, reply ->
                when (call.method) {
                    "pickFolder" -> {
                        val email = (call.arguments as? Map<*, *>)?.get("email") as? String
                        val rawIds = (call.arguments as? Map<*, *>)?.get("fileIds")
                        val fileIds = (rawIds as? List<*>)?.mapNotNull { it as? String }
                        if (rawIds != null && (fileIds == null || fileIds.isEmpty() ||
                            fileIds.size != (rawIds as List<*>).size ||
                            fileIds.any { !it.matches(Regex("^[A-Za-z0-9_-]+$")) })) {
                            reply.error("invalid_file_ids", null, null)
                        } else {
                            pick(email?.trim(), fileIds, reply)
                        }
                    }
                    "cancelPick" -> {
                        requests.cancelPending(activity::finishActivity)
                        reply.success(null)
                    }
                    else -> reply.notImplemented()
                }
            }
        }
    }

    fun detach() {
        channel?.setMethodCallHandler(null)
        channel = null
        requests.interrupt()
    }

    private fun pick(email: String?, fileIds: List<String>?, reply: MethodChannel.Result) {
        if (email.isNullOrEmpty()) {
            reply.error("invalid_account", "Google アカウントを確認できませんでした。", null)
            return
        }
        val code = requests.begin(reply, isPickerActive(), fileIds) ?: return
        try {
            val builder = AuthorizationRequest.builder()
                .setAccount(Account(email, "com.google"))
                .setRequestedScopes(listOf(Scope("https://www.googleapis.com/auth/drive.file")))
                .setOptOutIncludingGrantedScopes(true)
                .setPrompt(AuthorizationRequest.Prompt.CONSENT)
                .addResourceParameter(ResourceParameter.PICKER_OAUTH_TRIGGER, "true")
                .addResourceParameter(ResourceParameter.PICKER_ALLOW_FOLDER_SELECTION, "true")
                .addResourceParameter(ResourceParameter.PICKER_MIMETYPES, "application/vnd.google-apps.folder")
                .addResourceParameter(ResourceParameter.PICKER_ALLOW_MULTIPLE, "false")
            if (fileIds != null) {
                builder.addResourceParameter(ResourceParameter.PICKER_FILE_IDS, fileIds.joinToString(","))
            }
            val request = builder.build()
            // Activity-scoped listeners are removed on stop and could leave Dart waiting.
            client.authorize(request).addOnCompleteListener { task ->
                if (requests.activeCode != code) return@addOnCompleteListener
                when {
                    task.isCanceled -> requests.cancel(code)
                    !task.isSuccessful -> requests.failed(code, task.exception)
                    else -> handleAuthorization(code, task.result)
                }
            }
        } catch (error: Exception) {
            requests.failed(code, error)
        }
    }

    private fun handleAuthorization(code: Int, result: AuthorizationResult) {
        try {
            if (!result.hasResolution()) {
                requests.selected(code, result.tokenResponseParams?.getString("picked_file_ids"))
                return
            }
            if (activity.isFinishing || !activity.lifecycle.currentState.isAtLeast(Lifecycle.State.STARTED)) {
                requests.interrupt()
                return
            }
            requests.launchResolution(code) {
                val sender = requireNotNull(result.pendingIntent).intentSender
                activity.startIntentSenderForResult(sender, code, null, 0, 0, 0)
            }
        } catch (error: Exception) {
            requests.failed(code, error)
        }
    }

    fun onActivityResult(code: Int, resultCode: Int, data: Intent?) {
        if (requests.activeCode != code) return
        try {
            // Play services can attach an API error even when its activity returns RESULT_CANCELED.
            if (resultCode == Activity.RESULT_CANCELED && data?.extras?.isEmpty != false) {
                requests.cancel(code)
                return
            }
            if (resultCode != Activity.RESULT_OK && resultCode != Activity.RESULT_CANCELED) {
                requests.failed(code, null)
                return
            }
            val result = client.getAuthorizationResultFromIntent(data)
            if (resultCode == Activity.RESULT_CANCELED) {
                requests.cancel(code)
            } else {
                requests.selected(code, result.tokenResponseParams?.getString("picked_file_ids"))
            }
        } catch (error: Exception) {
            requests.failed(code, error)
        }
    }
}

internal class DriveFolderPickRequests(initialCode: Int = FIRST_REQUEST_CODE) {
    private class Pick(val code: Int, val reply: MethodChannel.Result, val fileIds: List<String>?, var resolutionLaunched: Boolean = false)
    private var pending: Pick? = null
    val activeCode get() = pending?.code
    var nextCode = initialCode
        private set

    fun begin(reply: MethodChannel.Result, pickerActive: Boolean, fileIds: List<String>? = null): Int? {
        if (pending != null || pickerActive) {
            reply.error("picker_busy", "別の選択画面が開いています。", null)
            return null
        }
        val code = nextCode
        nextCode = if (code == Int.MAX_VALUE) FIRST_REQUEST_CODE else code + 1
        pending = Pick(code, reply, fileIds)
        return code
    }

    private fun take(code: Int): MethodChannel.Result? {
        val pick = pending ?: return null
        if (code != pick.code) return null
        pending = null
        return pick.reply
    }

    fun interrupt() {
        val code = activeCode ?: return
        take(code)?.error("picker_interrupted", "選択画面を開き直してください。", null)
    }

    fun cancel(code: Int) {
        take(code)?.success(null)
    }

    fun launchResolution(code: Int, launch: () -> Unit) {
        val pick = pending ?: return
        if (pick.code != code || pick.resolutionLaunched) return
        pick.resolutionLaunched = true
        launch()
    }

    fun cancelPending(finishActivity: (Int) -> Unit) {
        val pick = pending ?: return
        cancel(pick.code)
        if (pick.resolutionLaunched) {
            try {
                finishActivity(pick.code)
            } catch (_: RuntimeException) {
                // Closing external UI is best-effort. Its request code is already retired.
            }
        }
    }

    fun failed(code: Int, error: Exception?) {
        val reply = take(code) ?: return
        val status = (error as? ApiException)?.statusCode
        if (status == CommonStatusCodes.CANCELED) {
            reply.success(null)
        } else {
            reply.error("drive_picker_failed", "Google ドライブのフォルダを選択できませんでした。", status)
        }
    }

    fun selected(code: Int, ids: String?) {
        val fileIds = pending?.takeIf { it.code == code }?.fileIds
        val reply = take(code) ?: return
        val id = ids?.trim()
        if (id.isNullOrEmpty() || !id.matches(Regex("^[A-Za-z0-9_-]+$")) ||
            (fileIds != null && id !in fileIds)) {
            reply.error("invalid_picker_result", "フォルダを 1 件取得できませんでした。", null)
        } else {
            reply.success(id)
        }
    }
}
