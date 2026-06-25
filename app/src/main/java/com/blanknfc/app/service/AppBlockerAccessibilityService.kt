package com.blanknfc.app.service

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.accessibility.AccessibilityEvent
import com.blanknfc.app.BlankApp
import com.blanknfc.app.analytics.BlankEvent
import com.blanknfc.app.analytics.BlankEvents
import com.blanknfc.app.ui.BlockActivity
import com.blanknfc.app.util.CriticalPackages
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class AppBlockerAccessibilityService : AccessibilityService() {

    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (event?.eventType != AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) return
        val packageName = event.packageName?.toString() ?: return

        if (packageName == this.packageName) return
        if (CriticalPackages.shouldNeverBlock(packageName)) return

        val sessionManager = BlankApp.get(this).container.sessionManager
        serviceScope.launch {
            if (sessionManager.isAppBlockedAfterLoad(packageName)) {
                showBlockScreen(packageName)
            }
        }
    }

    private fun showBlockScreen(packageName: String) {
        BlankApp.get(this).container.analyticsTracker.track(
            BlankEvent(BlankEvents.BLOCK_SCREEN_SHOWN)
        )
        val intent = Intent(this, BlockActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra(BlockActivity.EXTRA_BLOCKED_PACKAGE, packageName)
        }
        startActivity(intent)
    }

    override fun onInterrupt() {
        // Required override, no-op
    }

    override fun onDestroy() {
        serviceScope.cancel()
        super.onDestroy()
    }
}
