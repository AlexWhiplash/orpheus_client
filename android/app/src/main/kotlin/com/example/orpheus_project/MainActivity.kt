package com.example.orpheus_project

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugin.common.MethodChannel
import android.view.WindowManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.content.Context
import android.os.Bundle
import android.app.NotificationManager
import android.app.KeyguardManager
import android.os.Build.VERSION_CODES
import androidx.core.content.FileProvider
import java.io.File
import java.io.FileInputStream
import android.content.pm.PackageInstaller

class MainActivity: FlutterFragmentActivity() {
    private val BATTERY_CHANNEL = "com.example.orpheus_project/battery"
    private val SETTINGS_CHANNEL = "com.example.orpheus_project/settings"
    private val CALL_CHANNEL = "com.example.orpheus_project/call"
    private val APK_INSTALLER_CHANNEL = "com.orpheus.apk_installer"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Флаги showWhenLocked/turnScreenOn применяются runtime только во время звонков
        // (через MethodChannel), чтобы не мешать обычной работе. НО при ответе на
        // заблокированном телефоне активити стартует именно сейчас (onCreate), и если
        // не выставить showWhenLocked ДО показа окна — оно выйдет под keyguard и
        // устройство потребует PIN (ответить нельзя). Поэтому если есть активный
        // звонок (флаг в SharedPreferences от CallIdStorage), включаем режим сразу.
        if (hasActiveCall()) {
            enableCallMode()
        }
    }

    /// Есть ли активный (звонящий/идущий) звонок — читаем межизолятный флаг
    /// CallIdStorage из Flutter SharedPreferences. Нужен в onCreate, до Flutter.
    private fun hasActiveCall(): Boolean {
        return try {
            val prefs = getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE)
            val callId = prefs.getString("flutter.orpheus_active_call_id", null)
            if (callId.isNullOrEmpty()) return false
            val ts = prefs.getLong("flutter.orpheus_active_call_ts", 0L)
            (System.currentTimeMillis() - ts) < 15000L // тот же TTL, что в CallIdStorage
        } catch (e: Exception) {
            false
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent) // чтобы дальнейший getIntent()/роутинг видели accept-intent
        if (hasActiveCall()) enableCallMode()
    }

    // Ключевой хук: при ответе на звонок плагин flutter_callkit_incoming
    // переиспользует существующий singleTop MainActivity (SINGLE_TOP|REORDER_TO_FRONT|
    // CLEAR_TOP, без NEW_TASK) -> приходит onNewIntent/onStart/onResume, а onCreate НЕ
    // вызывается. onStart выполняется РАНЬШЕ onResume и на холодном, и на тёплом
    // пути, поэтому showWhenLocked успевает встать до компоновки окна над keyguard.
    // Гейт hasActiveCall() -> вне живого звонка это no-op (ничего поверх локскрина).
    override fun onStart() {
        super.onStart()
        if (hasActiveCall()) enableCallMode()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // Защита от скриншотов
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )

        // Канал для управления батареей
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestBatteryOptimization" -> {
                    requestIgnoreBatteryOptimization()
                    result.success(true)
                }
                "isBatteryOptimizationDisabled" -> {
                    result.success(isIgnoringBatteryOptimizations())
                }
                "openBatterySettings" -> {
                    openBatterySettings()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Канал для настроек устройства
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SETTINGS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openAppSettings" -> {
                    openAppSettings()
                    result.success(true)
                }
                "openNotificationSettings" -> {
                    openNotificationSettings()
                    result.success(true)
                }
                "canDrawOverlays" -> {
                    result.success(canDrawOverlays())
                }
                "requestOverlayPermission" -> {
                    requestOverlayPermission()
                    result.success(true)
                }
                "getDeviceManufacturer" -> {
                    result.success(Build.MANUFACTURER.lowercase())
                }
                "getElapsedRealtime" -> {
                    // Монотонное время с загрузки (мс), неуязвимое к смене системных
                    // часов — для тамперо-устойчивой блокировки от брутфорса PIN.
                    result.success(android.os.SystemClock.elapsedRealtime())
                }
                "isDeviceLocked" -> {
                    // Заблокирован ли экран устройства (keyguard) — чтобы на локскрине
                    // не показывать имя звонящего (приватность входящего звонка).
                    val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                    result.success(km.isKeyguardLocked)
                }
                "openAutoStartSettings" -> {
                    openAutoStartSettings()
                    result.success(true)
                }
                "openFullScreenIntentSettings" -> {
                    openFullScreenIntentSettings()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Канал для установки APK
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, APK_INSTALLER_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "installApk" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath != null) {
                        result.success(installApk(filePath))
                    } else {
                        result.error("INVALID_PATH", "filePath is required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Канал для управления поведением во время звонков
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CALL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "enableCallMode" -> {
                    enableCallMode()
                    result.success(true)
                }
                "disableCallMode" -> {
                    disableCallMode()
                    result.success(true)
                }
                "startCallAudio" -> {
                    startCallAudioService(call.argument<String>("title"))
                    result.success(true)
                }
                "stopCallAudio" -> {
                    stopCallAudioService()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    /// Поднимает микрофонный foreground-сервис на время звонка. Вызывается из
    /// видимого CallScreen (foreground), чтобы старт microphone-FGS был легален
    /// по правилам Android 14. Best-effort: сбой не роняет звонок.
    private fun startCallAudioService(title: String?) {
        try {
            val intent = Intent(this, CallAudioService::class.java).apply {
                putExtra(CallAudioService.EXTRA_TITLE, title ?: "Orpheus")
            }
            androidx.core.content.ContextCompat.startForegroundService(this, intent)
        } catch (e: Exception) {
            android.util.Log.w("MainActivity", "startCallAudioService failed: ${e.message}")
        }
    }

    private fun stopCallAudioService() {
        try {
            val intent = Intent(this, CallAudioService::class.java).apply {
                action = CallAudioService.ACTION_STOP
            }
            startService(intent)
        } catch (e: Exception) {
            android.util.Log.w("MainActivity", "stopCallAudioService failed: ${e.message}")
        }
    }

    private fun enableCallMode() {
        // Показ экрана звонка ПОВЕРХ блокировки + включение экрана только на время
        // звонка. НЕ снимаем keyguard: setShowWhenLocked показывает и делает
        // интерактивным экран звонка над локскрином (можно ответить/говорить), а
        // keyguard остаётся снизу. requestDismissKeyguard как раз показывал PIN-
        // промпт (выкидывало на пин). Ключ к тому чтобы окно вышло ПОВЕРХ локскрина
        // при ответе — вызвать это РАНО, в onCreate (см. вызов там), а не только из
        // CallScreen.initState (поздно, активити уже под keyguard).
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }

    private fun disableCallMode() {
        // Отключаем показ поверх блокировки после завершения звонка
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(false)
            setTurnScreenOn(false)
        } else {
            @Suppress("DEPRECATION")
            window.clearFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }

    private fun requestIgnoreBatteryOptimization() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val packageName = packageName
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                try {
                    val intent = Intent().apply {
                        action = Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                } catch (e: Exception) {
                    // Fallback: открыть общие настройки батареи
                    openBatterySettings()
                }
            }
        }
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            return pm.isIgnoringBatteryOptimizations(packageName)
        }
        return true
    }

    private fun openBatterySettings() {
        try {
            val intent = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
            startActivity(intent)
        } catch (e: Exception) {
            // Fallback
            val intent = Intent(Settings.ACTION_SETTINGS)
            startActivity(intent)
        }
    }

    private fun openAppSettings() {
        val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:$packageName")
        }
        startActivity(intent)
    }

    private fun openNotificationSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            }
            startActivity(intent)
        } else {
            openAppSettings()
        }
    }

    private fun openFullScreenIntentSettings() {
        // Android 14+ (API 34): Special app access → Full screen intents.
        // Без этого "большой экран" по full-screen intent может не показываться.
        try {
            if (Build.VERSION.SDK_INT >= 34) {
                val intent = Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                    data = Uri.parse("package:$packageName")
                }
                startActivity(intent)
            } else {
                // Fallback: хотя бы открыть настройки уведомлений приложения
                openNotificationSettings()
            }
        } catch (e: Exception) {
            openNotificationSettings()
        }
    }

    private fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true
        }
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        }
    }

    private fun installApk(filePath: String): Boolean {
        return try {
            val file = File(filePath)
            if (!file.exists()) {
                android.util.Log.e("APK_INSTALL", "File not found: $filePath")
                return false
            }

            val fileSize = file.length()
            android.util.Log.i("APK_INSTALL", "Installing APK: $filePath ($fileSize bytes)")

            // Use PackageInstaller API (reliable on Android 21+)
            val installer = packageManager.packageInstaller
            val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
            params.setSize(fileSize)

            val sessionId = installer.createSession(params)
            val session = installer.openSession(sessionId)

            // Stream APK into the session
            FileInputStream(file).use { input ->
                session.openWrite("orpheus_update.apk", 0, fileSize).use { output ->
                    input.copyTo(output)
                    session.fsync(output)
                }
            }

            // Create a pending intent for the install result
            val intent = Intent(Intent.ACTION_VIEW)
            val pendingIntent = android.app.PendingIntent.getActivity(
                this, sessionId, intent,
                android.app.PendingIntent.FLAG_MUTABLE
            )

            session.commit(pendingIntent.intentSender)
            android.util.Log.i("APK_INSTALL", "PackageInstaller session committed: $sessionId")
            true
        } catch (e: Exception) {
            android.util.Log.e("APK_INSTALL", "PackageInstaller failed: ${e.message}", e)
            // Fallback to Intent.ACTION_VIEW
            installApkViaIntent(filePath)
        }
    }

    private fun installApkViaIntent(filePath: String): Boolean {
        return try {
            val file = File(filePath)
            val uri = FileProvider.getUriForFile(
                this,
                "${applicationContext.packageName}.fileprovider",
                file
            )

            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }

            startActivity(intent)
            android.util.Log.i("APK_INSTALL", "Fallback intent launched for $filePath")
            true
        } catch (e: Exception) {
            android.util.Log.e("APK_INSTALL", "Fallback intent also failed: ${e.message}", e)
            false
        }
    }

    private fun openAutoStartSettings() {
        // Попытка открыть настройки автозапуска для разных производителей
        val manufacturer = Build.MANUFACTURER.lowercase()
        
        try {
            val intent = when {
                manufacturer.contains("xiaomi") -> {
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.miui.securitycenter",
                            "com.miui.permcenter.autostart.AutoStartManagementActivity"
                        )
                    }
                }
                manufacturer.contains("oppo") -> {
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.coloros.safecenter",
                            "com.coloros.safecenter.permission.startup.StartupAppListActivity"
                        )
                    }
                }
                manufacturer.contains("vivo") -> {
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.vivo.permissionmanager",
                            "com.vivo.permissionmanager.activity.BgStartUpManagerActivity"
                        )
                    }
                }
                manufacturer.contains("huawei") || manufacturer.contains("honor") -> {
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.huawei.systemmanager",
                            "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                        )
                    }
                }
                manufacturer.contains("samsung") -> {
                    Intent().apply {
                        component = android.content.ComponentName(
                            "com.samsung.android.lool",
                            "com.samsung.android.sm.ui.battery.BatteryActivity"
                        )
                    }
                }
                else -> {
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                }
            }
            startActivity(intent)
        } catch (e: Exception) {
            // Fallback: открыть настройки приложения
            openAppSettings()
        }
    }
}
