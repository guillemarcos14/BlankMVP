package com.brickmvp.app.util

import android.content.Context
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.graphics.drawable.Drawable

data class AppInfo(
    val packageName: String,
    val label: String,
    val icon: Drawable
)

object PackageHelper {

    private val neverBlockPackages = setOf(
        "com.android.settings",
        "com.android.dialer",
        "com.android.contacts",
        "com.google.android.dialer",
        "com.android.emergency",
        "com.android.phone",
        "com.google.android.apps.messaging",
        "com.android.mms"
    )

    fun getInstalledApps(context: Context): List<AppInfo> {
        val pm = context.packageManager
        val mainIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val resolveInfos = pm.queryIntentActivities(mainIntent, 0)
        val ownPackage = context.packageName

        return resolveInfos
            .mapNotNull { resolveInfo ->
                val pkgName = resolveInfo.activityInfo.packageName
                if (pkgName == ownPackage) return@mapNotNull null
                if (pkgName in neverBlockPackages) return@mapNotNull null
                try {
                    val appInfo = pm.getApplicationInfo(pkgName, 0)
                    AppInfo(
                        packageName = pkgName,
                        label = pm.getApplicationLabel(appInfo).toString(),
                        icon = pm.getApplicationIcon(appInfo)
                    )
                } catch (e: PackageManager.NameNotFoundException) {
                    null
                }
            }
            .distinctBy { it.packageName }
            .sortedBy { it.label.lowercase() }
    }
}
