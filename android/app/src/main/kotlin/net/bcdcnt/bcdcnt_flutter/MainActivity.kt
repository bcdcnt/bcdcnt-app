package net.bcdcnt.bcdcnt_flutter

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity (a FlutterActivity) shares its engine with the
// audio_service foreground service, so playback survives backgrounding.
class MainActivity : AudioServiceActivity() {
    // "bcdcnt/settings": open this app's notification settings (after the
    // listener said no to the permission prompt).
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "bcdcnt/settings").setMethodCallHandler { call, result ->
            if (call.method != "openNotificationSettings") return@setMethodCallHandler result.notImplemented()
            val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
            } else {
                Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
            }
            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            result.success(null)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createPushChannel()
    }

    // The API sends pushes to "bcdcnt_default" (sound + heads-up) and, in the
    // member's quiet hours, to "bcdcnt_quiet" (shade only, no sound or
    // vibration). Without them Android files pushes under "Khác".
    private fun createPushChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel("bcdcnt_default") == null) {
            nm.createNotificationChannel(NotificationChannel("bcdcnt_default", "Thông báo", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "Trả lời, lượt thích, bài gửi được duyệt, tin nhắn từ BQT"
            })
        }
        if (nm.getNotificationChannel("bcdcnt_quiet") == null) {
            nm.createNotificationChannel(NotificationChannel("bcdcnt_quiet", "Thông báo trong giờ yên lặng", NotificationManager.IMPORTANCE_LOW).apply {
                description = "Không kêu, không rung; vẫn có trong danh sách thông báo"
                setSound(null, null)
                enableVibration(false)
            })
        }
    }
}
