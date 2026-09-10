package com.blanknfc.app

import android.content.Intent
import android.nfc.NfcAdapter
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.lifecycle.lifecycleScope
import androidx.navigation.compose.rememberNavController
import com.blanknfc.app.data.SessionManager
import com.blanknfc.app.ui.navigation.NavGraph
import com.blanknfc.app.ui.navigation.Routes
import com.blanknfc.app.ui.theme.BlankTheme
import com.blanknfc.app.util.NfcHelper
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private val sessionManager: SessionManager
        get() = BlankApp.get(this).container.sessionManager
    private val purchaseStore
        get() = BlankApp.get(this).container.purchaseStore
    private val healthConnectStore
        get() = BlankApp.get(this).container.healthConnectStore
    private val digitalWellnessStore
        get() = BlankApp.get(this).container.digitalWellnessStore
    private val onboardingSyncStore
        get() = BlankApp.get(this).container.onboardingSyncStore
    private val referralStore
        get() = BlankApp.get(this).container.referralStore

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Handle NFC intent that launched the activity
        if (intent != null) {
            handleDeepLinkIntent(intent)
            handleNfcIntent(intent)
        }

        setContent {
            BlankTheme {
                val setupComplete by sessionManager.setupComplete.collectAsState()
                val navController = rememberNavController()

                val startDestination = if (setupComplete) Routes.HOME else Routes.SETUP

                NavGraph(
                    navController = navController,
                    sessionManager = sessionManager,
                    purchaseStore = purchaseStore,
                    healthConnectStore = healthConnectStore,
                    digitalWellnessStore = digitalWellnessStore,
                    onboardingSyncStore = onboardingSyncStore,
                    referralStore = referralStore,
                    startDestination = startDestination
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        NfcHelper.enableForegroundDispatch(this)
        NfcHelper.enableReaderMode(this) { uid ->
            runOnUiThread {
                processNfcUid(uid)
            }
        }
    }

    override fun onPause() {
        super.onPause()
        NfcHelper.disableReaderMode(this)
        NfcHelper.disableForegroundDispatch(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleDeepLinkIntent(intent)
        handleNfcIntent(intent)
    }

    private fun handleDeepLinkIntent(intent: Intent) {
        if (intent.action != Intent.ACTION_VIEW) return
        val uri = intent.data ?: return
        if (uri.scheme != "blank") return
        val action = uri.host.orEmpty()
        if (action != "mode") return
        val name = uri.getQueryParameter("name").orEmpty()
        val activate = uri.getQueryParameter("activate").equals("true", ignoreCase = true)
        lifecycleScope.launch {
            sessionManager.stateLoaded.filter { it }.first()
            val selected = sessionManager.selectBestModeMatching(name)
            if (!selected) {
                Toast.makeText(this@MainActivity, "Create $name mode first", Toast.LENGTH_SHORT).show()
                return@launch
            }
            if (activate) {
                val result = sessionManager.activateBlank()
                val messageRes = when (result) {
                    SessionManager.NfcResult.BLANKED -> R.string.session_activated
                    SessionManager.NfcResult.NO_APPS_SELECTED -> R.string.nfc_no_apps_selected
                    else -> R.string.session_activated
                }
                Toast.makeText(this@MainActivity, messageRes, Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun handleNfcIntent(intent: Intent) {
        if (intent.action != NfcAdapter.ACTION_TAG_DISCOVERED &&
            intent.action != NfcAdapter.ACTION_NDEF_DISCOVERED &&
            intent.action != NfcAdapter.ACTION_TECH_DISCOVERED
        ) return

        val uid = NfcHelper.extractUidFromIntent(intent) ?: return
        processNfcUid(uid)
    }

    private fun processNfcUid(uid: String) {
        if (sessionManager.isRelinkingNfc.value) {
            sessionManager.completeNfcRelink(uid)
            Toast.makeText(this, R.string.relink_done_title, Toast.LENGTH_SHORT).show()
            return
        }

        val result = sessionManager.handleNfcTag(uid)
        val messageRes = when (result) {
            SessionManager.NfcResult.TAG_REGISTERED -> R.string.nfc_tag_registered
            SessionManager.NfcResult.BLANKED -> R.string.session_activated
            SessionManager.NfcResult.UNBLANKED -> R.string.session_deactivated
            SessionManager.NfcResult.WRONG_TAG -> R.string.nfc_wrong_tag
            SessionManager.NfcResult.NO_APPS_SELECTED -> R.string.nfc_no_apps_selected
            SessionManager.NfcResult.NOT_ACTIVE -> R.string.nfc_not_active
        }
        Toast.makeText(this, messageRes, Toast.LENGTH_SHORT).show()
    }
}
