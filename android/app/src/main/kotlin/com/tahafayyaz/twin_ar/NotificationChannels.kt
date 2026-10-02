package com.tahafayyaz.twin_ar

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

/**
 * FCM notification channels (26_FCM_NOTIFICATIONS_PLAN.md, Stage S4, plan
 * 4.5).
 *
 * FCM only auto-creates a generic "Miscellaneous" channel; a payload's
 * `channel_id` must already exist on the device or the OS falls back to it.
 * So the four channels the server targets are created here at app start
 * (idempotent: re-creating an existing channel is a no-op and NEVER changes
 * its importance/name once the user has seen it - pick final values before
 * the first physical install, or clear app data / reinstall to change them).
 *
 * Ids MUST match functions/src/lib/notifications/constants.ts (CHANNEL_*) and
 * the manifest's default channel; test/features/notifications/
 * notification_android_config_test.dart enforces it.
 *
 * Creating a channel never shows anything and never needs the Android 13+
 * POST_NOTIFICATIONS permission; it is requested separately, contextually,
 * from Dart (Stage S5).
 */
object NotificationChannels {
    const val ORDERS = "orders"
    const val ACCOUNT = "account"
    const val ADMIN_OPS = "admin_ops"
    const val ADMIN_STOCK = "admin_stock"

    fun ensureCreated(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
                ?: return

        fun channel(
            id: String,
            name: String,
            description: String,
            importance: Int,
        ) = NotificationChannel(id, name, importance).apply {
            this.description = description
        }

        manager.createNotificationChannels(
            listOf(
                channel(
                    ORDERS,
                    "Order updates",
                    "Confirmed, shipped, delivered and cancelled orders, and payment refunds.",
                    NotificationManager.IMPORTANCE_HIGH,
                ),
                // D6: review moderation is deliberately low priority (silent tray entry).
                channel(
                    ACCOUNT,
                    "Account & reviews",
                    "Updates about your reviews.",
                    NotificationManager.IMPORTANCE_LOW,
                ),
                channel(
                    ADMIN_OPS,
                    "Store alerts",
                    "New orders and payment issues (store admin only).",
                    NotificationManager.IMPORTANCE_HIGH,
                ),
                channel(
                    ADMIN_STOCK,
                    "Stock & moderation",
                    "Low or out-of-stock products and flagged reviews (store admin only).",
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            ),
        )
    }
}
