package com.blanknfc.app.data

import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import java.io.File
import java.util.Calendar
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

    @Test
    fun defaultModesIncludeStudyAndSleepPresets() = runTest {
        val manager = createManager(backgroundScope)
        advanceUntilIdle()

        val modeNames = manager.modes.first().map { it.name }

        assertTrue(modeNames.contains("Rutina diaria"))
        assertTrue(modeNames.contains("Estudio"))
        assertTrue(modeNames.contains("Dormir"))
    }

    @Test
    fun blockedAttemptsAreCountedInWeeklyStats() = runTest {
        val manager = createManager(backgroundScope)

        manager.recordBlockedAttempt()
        manager.recordBlockedAttempt()
        advanceUntilIdle()

        assertEquals(2, manager.stats.first().blockedAttemptsThisWeek)
    }

    @Test
    fun nfcUnlockRecordsCompletedSessionInWeeklyStats() = runTest {
        val manager = createManager(backgroundScope)

        manager.handleNfcTag("A1B2")
        manager.setBlockedPackages(setOf("com.example.blocked"))
        manager.activateBlank()
        advanceUntilIdle()

        assertEquals(SessionManager.NfcResult.UNBRICKED, manager.handleNfcTag("A1B2"))
        advanceUntilIdle()

        val stats = manager.stats.first()
        assertEquals(1, stats.sessionsThisWeek)
        assertTrue(stats.protectedMsThisWeek >= 0L)
    }

    @Test
    fun scheduleWindowActivatesAndDeactivatesBlank() = runTest {
        val manager = createManager(backgroundScope)

        manager.setBlockedPackages(setOf("com.example.blocked"))
        manager.updateSchedule(
            FocusSchedule(
                enabled = true,
                startMinute = 23 * 60,
                endMinute = 7 * 60
            )
        )
        advanceUntilIdle()

        manager.applyScheduleWindow(nowMillis = millisAt(hour = 23, minute = 30))
        advanceUntilIdle()

        assertTrue(manager.isBlankActive.first())

        manager.applyScheduleWindow(nowMillis = millisAt(hour = 12, minute = 0))
        advanceUntilIdle()

        assertFalse(manager.isBlankActive.first())
        assertEquals(1, manager.stats.first().sessionsThisWeek)
    }

    @Test
    fun scheduleTimesAreClampedBeforePersisting() = runTest {
        val manager = createManager(backgroundScope)

        manager.updateSchedule(
            FocusSchedule(
                enabled = true,
                startMinute = -12,
                endMinute = 24 * 60 + 10
            )
        )
        advanceUntilIdle()

        assertEquals(
            FocusSchedule(enabled = true, startMinute = 0, endMinute = 23 * 60 + 59),
            manager.schedule.first()
        )
    }

    private fun createManager(scope: CoroutineScope): SessionManager {
        val file = File(temporaryFolder.newFolder(), "prefs.preferences_pb")
        val dataStore = PreferenceDataStoreFactory.create(
            scope = scope,
            produceFile = { file }
        )
        return SessionManager(dataStore, scope)
    }

    private fun millisAt(hour: Int, minute: Int): Long {
        return Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, hour)
            set(Calendar.MINUTE, minute)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
    }
}
