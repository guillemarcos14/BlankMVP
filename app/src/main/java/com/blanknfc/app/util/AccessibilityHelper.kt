package com.blanknfc.app.util

import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import com.blanknfc.app.service.AppBlockerAccessibilityService

object AccessibilityHelper {

    fun isServiceEnabled(context: Context): Boolean {
        val expected = ComponentName(context, AppBlockerAccessibilityService::class.java)
        val enabledSetting = Settings.Secure.getString(
            context.contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        )
        if (enabledSetting
                ?.split(':')
                ?.mapNotNull(ComponentName::unflattenFromString)
                ?.any { it == expected } == true
        ) {
            return true
        }

        val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE) as AccessibilityManager
        val enabledServices = am.getEnabledAccessibilityServiceList(
            AccessibilityServiceInfo.FEEDBACK_GENERIC
        )
        return enabledServices.any { service ->
            ComponentName.unflattenFromString(service.id) == expected
        }
    }

    fun openAccessibilitySettings(context: Context) {
        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }
}
