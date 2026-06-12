package com.brickmvp.app.service

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import com.brickmvp.app.BrickApp
import com.brickmvp.app.ui.BlockActivity

class AppBlockerAccessibilityService : AccessibilityService() {

    private val ignoredPackages = setOf(
        "com.android.systemui",
        "com.android.launcher3",
        "com.google.android.apps.nexuslauncher",
        "com.sec.android.app.launcher",
        "com.miui.home",
        "com.huawei.android.launcher",
        "com.oppo.launcher",
        "com.android.settings",
        "com.android.dialer",
        "com.android.contacts",
        "com.google.android.dialer",
        "com.android.emergency",
        "com.android.phone",
        "com.google.android.apps.messaging",
        "com.android.mms"
    )

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val packageName = event.packageName?.toString() ?: return

        if (packageName == this.packageName) return
        if (packageName in ignoredPackages) return

        val sessionManager = BrickApp.get(this).container.sessionManager
        if (sessionManager.isAppBlocked(packageName)) {
            val intent = Intent(this, BlockActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
                addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                putExtra(BlockActivity.EXTRA_BLOCKED_PACKAGE, packageName)
            }
            startActivity(intent)
        }
    }

    override fun onInterrupt() {
        // Required override, no-op
    }
}
