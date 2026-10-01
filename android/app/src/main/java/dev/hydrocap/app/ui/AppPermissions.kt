package dev.hydrocap.app.ui

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.content.ContextCompat

/** Runtime permissions HydroCap needs for BLE + notifications, per API level. */
@SuppressLint("InlinedApi") // POST_NOTIFICATIONS is a compile-time constant, guarded by SDK_INT checks
object AppPermissions {

    fun required(): List<String> = buildList {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            add(Manifest.permission.BLUETOOTH_SCAN)
            add(Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            add(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    /** Permissions without which BLE cannot work at all (notifications are optional). */
    fun essential(): List<String> = required().filterNot { it == Manifest.permission.POST_NOTIFICATIONS }

    fun missing(context: Context): List<String> = required().filterNot { isGranted(context, it) }

    fun hasEssential(context: Context): Boolean = essential().all { isGranted(context, it) }

    fun isGranted(context: Context, permission: String): Boolean =
        ContextCompat.checkSelfPermission(context, permission) == PackageManager.PERMISSION_GRANTED
}
