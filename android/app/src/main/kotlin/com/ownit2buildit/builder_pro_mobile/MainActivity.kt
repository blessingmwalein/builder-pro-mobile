package com.ownit2buildit.builder_pro_mobile

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createAlertsChannel()
    }

    /**
     * The channel push alerts arrive on. Its id is the one named in
     * AndroidManifest.xml (default_notification_channel_id). High importance, so an
     * alert pops up instead of waiting silently in the tray. Creating a channel
     * that already exists changes nothing, so this is safe on every start.
     */
    private fun createAlertsChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            ALERTS_CHANNEL_ID,
            "Alerts",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Messages, tasks and project updates"
        }
        getSystemService(NotificationManager::class.java)
            ?.createNotificationChannel(channel)
    }

    companion object {
        private const val ALERTS_CHANNEL_ID = "ownit2buildit_alerts"
    }
}
