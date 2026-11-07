package com.example.kazumi

import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.Uri
import android.os.Build
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 应用内更新安装。
 *
 * 两件事：
 * 1. 用 [PackageInstaller] 把 APK 交给系统安装器。相比 ACTION_VIEW，
 *    它不需要 FileProvider 与「未知来源」临时授权之外的额外步骤，且能在
 *    安装完成后拿到结果（成功/用户取消/失败），从而区分「装好了」和
 *    「点错了取消」。
 * 2. 返回「是否已授予本应用安装未知应用权限」。未授予时由 Dart 侧引导
 *    用户去系统设置打开——这是 Android 的硬性要求，无法绕过。
 *
 * 注意：普通应用无法做到真正的「零交互静默安装」，必须经过系统安装器
 * 确认页（用户点一次「安装」）。只有系统签名或 root 才行，这里不做越权。
 */
class ApkInstallHandler(private val activity: MainActivity) {
    companion object {
        const val CHANNEL = "com.predidit.kazumi/install"
        private const val REQUEST_INSTALL_PERMISSION = 0x4C49
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingSessionId = -1

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canRequestPackageInstalls" -> result.success(canRequestPackageInstalls())
            "requestInstallPermission" -> {
                requestInstallPermission()
                result.success(null)
            }
            "installApk" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("INVALID_ARGUMENT", "path is required", null)
                    return
                }
                installApk(path, result)
            }
            else -> result.notImplemented()
        }
    }

    /** 是否已允许本应用安装 APK（Android 8.0+ 需要用户手动开启）。 */
    private fun canRequestPackageInstalls(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return true
        }
        return activity.packageManager.canRequestPackageInstalls()
    }

    /** 跳到「安装未知应用」授权页；没有对应页面的设备退回到应用详情页。 */
    private fun requestInstallPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        if (canRequestPackageInstalls()) {
            return
        }
        val intents = listOf(
            Intent(
                android.provider.Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}")
            ),
            Intent(
                android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${activity.packageName}")
            ),
        )
        for (intent in intents) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                activity.startActivityForResult(intent, REQUEST_INSTALL_PERMISSION)
                return
            } catch (_: Exception) {
                // 试下一个；部分 ROM 缺少某个设置页。
            }
        }
    }

    private fun installApk(path: String, result: MethodChannel.Result) {
        if (!canRequestPackageInstalls()) {
            result.error("NO_PERMISSION", "需要允许安装未知应用", null)
            return
        }
        val file = File(path)
        if (!file.isFile || file.length() <= 0) {
            result.error("FILE_MISSING", "安装包不存在或为空：$path", null)
            return
        }
        // 同一时间只处理一次安装请求，避免旧的结果回调被覆盖。
        pendingResult?.error("BUSY", "已有安装进行中", null)
        pendingResult = result

        try {
            val installer = activity.packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(
                PackageInstaller.SessionParams.MODE_FULL_INSTALL
            )
            // 与 open_filex 的 provider 无关：这里直接把字节流交给系统。
            params.setAppPackageName(activity.packageName)
            val sessionId = installer.createSession(params)
            pendingSessionId = sessionId
            installer.openSession(sessionId).use { session ->
                file.inputStream().use { input ->
                    session.openWrite("app.apk", 0, file.length()).use { output ->
                        input.copyTo(output)
                        session.fsync(output)
                    }
                }
                val callbackIntent = Intent(activity, InstallResultReceiver::class.java)
                val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
                } else {
                    PendingIntent.FLAG_UPDATE_CURRENT
                }
                val pending = PendingIntent.getBroadcast(
                    activity,
                    sessionId,
                    callbackIntent,
                    flags
                )
                session.commit(pending.intentSender)
            }
        } catch (e: Exception) {
            finishWithError("INSTALL_FAILED", e.message ?: e.toString())
        }
    }

    /**
     * 由 [InstallResultReceiver] 回调。
     *
     * [STATUS_PENDING_USER_ACTION] 表示系统安装器要求用户确认。此时系统在
     * 结果 Intent 里附带一个 `Intent.EXTRA_INTENT`，**必须由我们启动它**，
     * 否则安装会一直停在「等待确认」状态。
     */
    fun onInstallResult(
        sessionId: Int,
        status: Int,
        message: String?,
        confirmationIntent: Intent?
    ) {
        if (sessionId != pendingSessionId) {
            return
        }
        pendingSessionId = -1
        when (status) {
            PackageInstaller.STATUS_SUCCESS ->
                finishWithSuccess()
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                if (confirmationIntent != null) {
                    try {
                        // 接收器可能在 Activity 不可见时触发，必须带 NEW_TASK。
                        confirmationIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        activity.startActivity(confirmationIntent)
                    } catch (e: Exception) {
                        finishWithError(
                            "INSTALL_FAILED",
                            e.message ?: "无法打开系统安装界面"
                        )
                        return
                    }
                }
                // 系统确认页已由我们拉起，用户需要在那边点一次「安装」。
                finishWithSuccess(pendingUserAction = true)
            }
            PackageInstaller.STATUS_FAILURE_ABORTED ->
                finishWithError("ABORTED", message ?: "已取消安装")
            else ->
                finishWithError("INSTALL_FAILED", message ?: "安装失败（$status）")
        }
    }

    private fun finishWithSuccess(pendingUserAction: Boolean = false) {
        val result = pendingResult ?: return
        pendingResult = null
        result.success(mapOf("pendingUserAction" to pendingUserAction))
    }

    private fun finishWithError(code: String, message: String) {
        val result = pendingResult ?: return
        pendingResult = null
        result.error(code, message, null)
    }
}
