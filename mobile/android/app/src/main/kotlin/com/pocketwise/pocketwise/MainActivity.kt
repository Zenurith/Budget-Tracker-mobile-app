package com.pocketwise.pocketwise

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.Manifest
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings

class MainActivity : FlutterActivity() {
    private var permissionResult: MethodChannel.Result? = null
    private val permissionRequest = 4201
    private val permissionHistory by lazy { getSharedPreferences("notification_permission", MODE_PRIVATE) }

    private fun notificationStatus(): String {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        if (manager.areNotificationsEnabled()) return "granted"
        if (Build.VERSION.SDK_INT < 33) return "blocked"
        if (shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS)) return "denied"
        return if (permissionHistory.getBoolean("asked", false)) "blocked" else "notDetermined"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pocketwise/notifications")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(notificationStatus())
                    "request" -> {
                        val status = notificationStatus()
                        if (Build.VERSION.SDK_INT < 33 || status == "granted" || status == "blocked") {
                            result.success(status)
                        } else if (permissionResult != null) {
                            result.error("busy", "A permission request is already open.", null)
                        } else {
                            permissionResult = result
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), permissionRequest)
                        }
                    }
                    "openSettings" -> {
                        try {
                            val intent = if (Build.VERSION.SDK_INT >= 26) {
                                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                                    .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            } else {
                                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (_: Exception) { result.success(false) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == permissionRequest) {
            // Dismissal is not a denial. Only remember an explicit grant or a
            // denial for which Android offers a rationale (the first denial).
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED ||
                (Build.VERSION.SDK_INT >= 33 && shouldShowRequestPermissionRationale(Manifest.permission.POST_NOTIFICATIONS))) {
                permissionHistory.edit().putBoolean("asked", true).apply()
            }
            permissionResult?.success(notificationStatus())
            permissionResult = null
        }
    }

    override fun onDestroy() {
        permissionResult?.error("interrupted", "Permission request interrupted. Check permission again.", null)
        permissionResult = null
        super.onDestroy()
    }
}
