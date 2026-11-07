package com.example.kazumi

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller

/**
 * 接收 [PackageInstaller] 的安装结果回调并转交给 [ApkInstallHandler]。
 *
 * 注册为静态广播接收器（manifest 内 exported=false），因为安装会话完成时
 * MainActivity 可能已被系统回收。
 */
class InstallResultReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent == null) return
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE
        )
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
        val sessionId = intent.getIntExtra(PackageInstaller.EXTRA_SESSION_ID, -1)
        // STATUS_PENDING_USER_ACTION 时会附带系统安装界面的启动 Intent，
        // 必须由接收方启动，否则安装不会继续。
        @Suppress("DEPRECATION")
        val confirmation = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
        InstallResultBridge.dispatch(sessionId, status, message, confirmation)
    }
}

/** 静态接收器无法拿到 Activity 实例，用一个极小的桥接对象转交。 */
object InstallResultBridge {
    var handler: ApkInstallHandler? = null

    fun dispatch(
        sessionId: Int,
        status: Int,
        message: String?,
        confirmationIntent: Intent?
    ) {
        handler?.onInstallResult(sessionId, status, message, confirmationIntent)
    }
}
