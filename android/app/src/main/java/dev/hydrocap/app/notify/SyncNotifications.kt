package dev.hydrocap.app.notify

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import androidx.core.app.NotificationCompat
import dev.hydrocap.app.R

/**
 * The low-importance "sync" channel and its ongoing notification, shared by
 * the manual [dev.hydrocap.app.sync.SyncService] and the periodic
 * [dev.hydrocap.app.sync.CapSyncWorker] foreground fallback.
 */
object SyncNotifications {
    const val CHANNEL_ID = "sync"

    fun ensureChannel(context: Context) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, context.getString(R.string.notification_channel_sync), NotificationManager.IMPORTANCE_LOW),
        )
    }

    fun build(context: Context, text: String): Notification {
        ensureChannel(context)
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = launch?.let {
            PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification_drop)
            .setContentTitle(context.getString(R.string.notification_sync_title))
            .setContentText(text)
            .setOngoing(true)
            .setSilent(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .apply { if (contentIntent != null) setContentIntent(contentIntent) }
            .build()
    }
}
