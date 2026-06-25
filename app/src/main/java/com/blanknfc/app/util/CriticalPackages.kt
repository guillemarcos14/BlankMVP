package com.blanknfc.app.util

object CriticalPackages {
    private val launcherPackages = setOf(
        "com.android.launcher3",
        "com.google.android.apps.nexuslauncher",
        "com.sec.android.app.launcher",
        "com.miui.home",
        "com.huawei.android.launcher",
        "com.oppo.launcher",
        "com.vivo.launcher",
        "com.oneplus.launcher",
        "com.lge.launcher3",
        "com.motorola.launcher3"
    )

    private val systemSafetyPackages = setOf(
        "com.android.systemui",
        "com.android.settings",
        "com.android.permissioncontroller",
        "com.google.android.permissioncontroller",
        "com.android.packageinstaller",
        "com.google.android.packageinstaller",
        "com.google.android.gms",
        "com.google.android.gsf",
        "com.android.vending"
    )

    private val communicationSafetyPackages = setOf(
        "com.android.dialer",
        "com.google.android.dialer",
        "com.samsung.android.dialer",
        "com.android.contacts",
        "com.google.android.contacts",
        "com.samsung.android.contacts",
        "com.android.emergency",
        "com.android.phone",
        "com.google.android.apps.messaging",
        "com.samsung.android.messaging",
        "com.android.mms"
    )

    val neverBlockPackages: Set<String> =
        launcherPackages + systemSafetyPackages + communicationSafetyPackages

    fun shouldNeverBlock(packageName: String): Boolean {
        return packageName in neverBlockPackages
    }
}
