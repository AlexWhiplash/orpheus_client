package com.example.orpheus_project

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Короткоживущий foreground-сервис типа `microphone` на время активного звонка.
 *
 * Зачем отдельный сервис (а не постоянный PushConnectionService):
 * постоянный сервис имеет тип `specialUse` и стартует в фоне/при загрузке —
 * по правилам Android 14 «while-in-use» он НЕ может держать микрофон. Захват
 * микрофона легален только если foreground-сервис типа `microphone` запущен из
 * видимого экрана (Activity). Поэтому этот сервис поднимается из CallScreen
 * (видимая Activity) в момент звонка и держит микрофон, пока приложение свёрнуто
 * во время разговора. Останавливается при завершении звонка. Паттерн Signal/Molly.
 *
 * Всё best-effort: если старт foreground отклонён системой (например, Activity
 * ещё не в foreground), сервис тихо останавливается — обычный звонок при видимом
 * экране всё равно получает микрофон через саму Activity.
 */
class CallAudioService : Service() {
    companion object {
        const val TAG = "CallAudioService"
        const val CHANNEL_ID = "orpheus_call_audio"
        const val NOTIFICATION_ID = 889
        const val ACTION_STOP = "com.example.orpheus_project.CALL_AUDIO_STOP"
        const val EXTRA_TITLE = "title"
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopForegroundCompat()
            stopSelf()
            return START_NOT_STICKY
        }

        val title = intent?.getStringExtra(EXTRA_TITLE) ?: "Orpheus"
        val started = startAsForeground(title)
        if (!started) {
            stopSelf()
            return START_NOT_STICKY
        }
        // START_STICKY: если систему прибьёт нехватка памяти во время звонка —
        // попробует пересоздать сервис.
        return START_STICKY
    }

    private fun startAsForeground(title: String): Boolean {
        return try {
            ensureChannel()
            val notification = NotificationCompat.Builder(this, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText("In call")
                .setSmallIcon(R.drawable.ic_stat_orpheus)
                .setOngoing(true)
                .setCategory(NotificationCompat.CATEGORY_CALL)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            true
        } catch (e: Exception) {
            // На Android 12+ startForeground из недопустимого состояния бросает
            // исключение — не роняем приложение, просто не поднимаем mic-сервис.
            Log.w(TAG, "startForeground(microphone) rejected: ${e.message}")
            false
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(
                    CHANNEL_ID,
                    "Call audio",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    setSound(null, null)
                    enableVibration(false)
                    setShowBadge(false)
                }
                nm.createNotificationChannel(ch)
            }
        }
    }

    private fun stopForegroundCompat() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (e: Exception) {
            Log.w(TAG, "stopForeground failed: ${e.message}")
        }
    }
}
