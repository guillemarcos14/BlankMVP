package com.blanknfc.app.data

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

@OptIn(ExperimentalCoroutinesApi::class)
class SessionManagerTest {

    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun firstNfcTagRegistersTag() = runTest {
        val manager = createManager(backgroundScope)

        val result = manager.handleNfcTag("A1B2")
        advanceUntilIdle()

        assertEquals(SessionManager.NfcResult.TAG_REGISTERED, result)
        assertEquals("A1B2", manager.nfcTagUid.first())
    }

    @Test
    fun activateBlankStartsBrickModeWhenAppsAreSelected() = runTest {
        val manager = createManager(backgroundScope)

        manager.handleNfcTag("A1B2")
        manager.setBlockedPackages(setOf("com.example.blocked"))
        advanceUntilIdle()

        assertEquals(SessionManager.NfcResult.BRICKED, manager.activateBlank())
        advanceUntilIdle()
        assertTrue(manager.isBlankActive.first())
        assertTrue(manager.isAppBlocked("com.example.blocked"))
    }

    @Test
    fun matchingNfcTagUnlocksOnlyWhenBlankIsActive() = runTest {
        val manager = createManager(backgroundScope)

        manager.handleNfcTag("A1B2")
        manager.setBlockedPackages(setOf("com.example.blocked"))
        manager.activateBlank()
        advanceUntilIdle()

        assertEquals(SessionManager.NfcResult.UNBRICKED, manager.handleNfcTag("A1B2"))
        advanceUntilIdle()
        assertFalse(manager.isBlankActive.first())
    }

    @Test
    fun wrongTagDoesNotToggleBrickMode() = runTest {
        val manager = createManager(backgroundScope)

        manager.handleNfcTag("A1B2")
        manager.setBlockedPackages(setOf("com.example.blocked"))
        advanceUntilIdle()

        assertEquals(SessionManager.NfcResult.WRONG_TAG, manager.handleNfcTag("FFFF"))
        advanceUntilIdle()
        assertFalse(manager.isBlankActive.first())
    }

    @Test
    fun activateBlankWithoutSelectedAppsDoesNotStartBrickMode() = runTest {
        val manager = createManager(backgroundScope)

        manager.handleNfcTag("A1B2")
        advanceUntilIdle()

        assertEquals(SessionManager.NfcResult.NO_APPS_SELECTED, manager.activateBlank())
        advanceUntilIdle()
        assertFalse(manager.isBlankActive.first())
    }

    @Test
    fun matchingNfcTagWhenBlankIsInactiveDoesNotStartBrickMode() = runTest {
        val manager = createManager(backgroundScope)

        manager.handleNfcTag("A1B2")
        manager.setBlockedPackages(setOf("com.example.blocked"))
        advanceUntilIdle()

        assertEquals(SessionManager.NfcResult.NOT_ACTIVE, manager.handleNfcTag("A1B2"))
        advanceUntilIdle()
        assertFalse(manager.isBlankActive.first())
    }

    @Test
    fun backgroundThemeDefaultsToGreyAndCanBeChanged() = runTest {
        val manager = createManager(backgroundScope)

        assertEquals(SessionManager.DEFAULT_BACKGROUND_THEME_ID, manager.backgroundThemeId.first())

        manager.selectBackgroundTheme("mint")
        advanceUntilIdle()

        assertEquals("mint", manager.backgroundThemeId.first())
    }

    private fun createManager(scope: CoroutineScope): SessionManager {
        val file = File(temporaryFolder.newFolder(), "prefs.preferences_pb")
        val dataStore = PreferenceDataStoreFactory.create(
            scope = scope,
            produceFile = { file }
        )
        return SessionManager(dataStore, scope)
    }
}
