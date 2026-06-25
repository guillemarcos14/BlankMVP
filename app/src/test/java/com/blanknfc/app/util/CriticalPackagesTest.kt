package com.blanknfc.app.util

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class CriticalPackagesTest {

    @Test
    fun safetyCriticalPackagesAreNeverBlocked() {
        assertTrue(CriticalPackages.shouldNeverBlock("com.android.settings"))
        assertTrue(CriticalPackages.shouldNeverBlock("com.android.phone"))
        assertTrue(CriticalPackages.shouldNeverBlock("com.google.android.dialer"))
        assertTrue(CriticalPackages.shouldNeverBlock("com.android.permissioncontroller"))
        assertTrue(CriticalPackages.shouldNeverBlock("com.android.packageinstaller"))
    }

    @Test
    fun normalAppsCanStillBeBlocked() {
        assertFalse(CriticalPackages.shouldNeverBlock("com.instagram.android"))
    }
}
