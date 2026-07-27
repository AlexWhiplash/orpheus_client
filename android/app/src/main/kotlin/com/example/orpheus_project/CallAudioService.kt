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
        // v3: ОБЩИЕ id и канал с сервисом доставки. История: 18.07 канал сделали
        // IMPORTANCE_MIN, чтобы второе уведомление не было заметным, а 19.07 текст
        // обезличили до «Orpheus / In call» (утечка префикса ключа в шторку). В сумме
        // это сделало два уведомления НЕОТЛИЧИМЫМИ — и на device-тесте 27.07 они снова
        // прочитались как задвоение, теперь буквальное: одинаковый заголовок, текст и
        // иконка, разные только id.
        //
        // Тихость проблему не решает — решает то, что уведомление должно быть ОДНО.
        // Android держит уведомление, пока его удерживает хотя бы один сервис, а id и
        // канал общеприложенческие, а не «свои у каждого сервиса». Поэтому микрофонный
        // сервис переиспользует id/канал сервиса доставки: в шторке одна строка,
        // которую сервис доставки через ≤1 с перепишет на «<имя> / длительность».
        const val CHANNEL_ID = "orpheus_connection_v3"
        const val NOTIFICATION_ID = 887
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
                .setPriority(NotificationCompat.PRIORITY_MIN)
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
                    NotificationManager.IMPORTANCE_MIN
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
                // DETACH, а не REMOVE: уведомление 887 общее с постоянным сервисом
                // доставки, и REMOVE снёс бы то, что тот обязан держать дальше.
                stopForeground(STOP_FOREGROUND_DETACH)
            } else {
                @Suppress("DEPRECATION")
                stopForeground(true)
            }
        } catch (e: Exception) {
            Log.w(TAG, "stopForeground failed: ${e.message}")
        }
    }
}
