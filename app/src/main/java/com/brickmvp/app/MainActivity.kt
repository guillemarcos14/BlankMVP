package com.brickmvp.app

import android.content.Intent
import android.nfc.NfcAdapter
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.navigation.compose.rememberNavController
import com.brickmvp.app.data.SessionManager
import com.brickmvp.app.ui.navigation.NavGraph
import com.brickmvp.app.ui.navigation.Routes
import com.brickmvp.app.ui.theme.BrickTheme
import com.brickmvp.app.util.NfcHelper

class MainActivity : ComponentActivity() {

    private val sessionManager: SessionManager
        get() = BrickApp.get(this).container.sessionManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Handle NFC intent that launched the activity
        if (intent != null) {
            handleNfcIntent(intent)
        }

        setContent {
            BrickTheme {
                val setupComplete by sessionManager.setupComplete.collectAsState()
                val navController = rememberNavController()

                val startDestination = if (setupComplete) Routes.HOME else Routes.SETUP

                NavGraph(
                    navController = navController,
                    sessionManager = sessionManager,
                    startDestination = startDestination
                )
            }
        }
    }

    override fun onResume() {
        super.onResume()
        NfcHelper.enableForegroundDispatch(this)
    }

    override fun onPause() {
        super.onPause()
        NfcHelper.disableForegroundDispatch(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleNfcIntent(intent)
    }

    private fun handleNfcIntent(intent: Intent) {
        if (intent.action != NfcAdapter.ACTION_TAG_DISCOVERED &&
            intent.action != NfcAdapter.ACTION_NDEF_DISCOVERED &&
            intent.action != NfcAdapter.ACTION_TECH_DISCOVERED
        ) return

        val uid = NfcHelper.extractUidFromIntent(intent) ?: return

        val result = sessionManager.handleNfcTag(uid)
        val messageRes = when (result) {
            SessionManager.NfcResult.TAG_REGISTERED -> R.string.nfc_tag_registered
            SessionManager.NfcResult.BRICKED -> R.string.session_activated
            SessionManager.NfcResult.UNBRICKED -> R.string.session_deactivated
            SessionManager.NfcResult.WRONG_TAG -> return // silently ignore wrong tags
        }
        Toast.makeText(this, messageRes, Toast.LENGTH_SHORT).show()
    }
}
