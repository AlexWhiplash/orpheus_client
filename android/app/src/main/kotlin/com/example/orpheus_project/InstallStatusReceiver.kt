package com.example.orpheus_project

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.util.Log
import java.io.File

/// Receives PackageInstaller session status from installApk (MainActivity).
///
/// The critical branch is STATUS_PENDING_USER_ACTION: the system does NOT show the
/// install confirmation dialog itself. It hands us a ready-made Intent in
/// EXTRA_INTENT, and the app must launch it. Without this the session stays pending
/// forever and nothing installs (the old empty-ACTION_VIEW bug).
///
/// A FAILURE (signature mismatch, no space, corrupted APK, ...) does NOT kill the
/// process, so it used to vanish silently into logcat and the user was stuck in a
/// silent update loop (incident 19.07, SM-S948B: 37 -> 40 by круг). We now drop a
/// one-line marker file that the Dart side drains on the next update check to write
/// the exact reason into the debug log (readable via "Поделиться", no cable) and to
/// tell the user what happened. See UpdateService._reportPendingInstallFailure.
///
/// Declared exported="false": it is triggered only by our own PendingIntent.
class InstallStatusReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, Int.MIN_VALUE)) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirmIntent = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
                if (confirmIntent != null) {
                    // FLAG_ACTIVITY_NEW_TASK is required: startActivity from a receiver
                    // has no activity context of its own.
                    confirmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    try {
                        context.startActivity(confirmIntent)
                    } catch (e: Exception) {
                        Log.e("APK_INSTALL", "Failed to launch install confirm: ${e.message}", e)
                    }
                } else {
                    Log.e("APK_INSTALL", "PENDING_USER_ACTION without EXTRA_INTENT")
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                // Rarely observed for self-update: the process is usually killed at the
                // package-replace step before this arrives. Recovery after the update is
                // handled by PackageReplacedReceiver (ACTION_MY_PACKAGE_REPLACED).
                Log.i("APK_INSTALL", "Install reported success")
            }
            else -> {
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                Log.w("APK_INSTALL", "Install status=$status message=$message")
                persistFailure(context, status, message)
            }
        }
    }

    /// Персистим отказ установки в маркер-файл во внутренней files-папке
    /// (== getApplicationSupportDirectory у Dart). Одна строка `status|message`,
    /// перезаписывается. Best-effort: сбой записи не должен ничего ронять.
    private fun persistFailure(context: Context, status: Int, message: String?) {
        try {
            val marker = File(context.filesDir, "last_install_failure.txt")
            marker.writeText("$status|${message ?: ""}")
        } catch (e: Exception) {
            Log.e("APK_INSTALL", "persistFailure failed: ${e.message}")
        }
    }
}
