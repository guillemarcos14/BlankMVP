package com.brickmvp.app.ui

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.brickmvp.app.R
import com.brickmvp.app.BrickApp
import com.brickmvp.app.ui.theme.BrickBlockBackground
import com.brickmvp.app.ui.theme.BrickOnSurface
import com.brickmvp.app.ui.theme.BrickRed
import com.brickmvp.app.ui.theme.BrickTheme
import kotlinx.coroutines.launch

class BlockActivity : ComponentActivity() {

    companion object {
        const val EXTRA_BLOCKED_PACKAGE = "blocked_package"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }

        val sessionManager = BrickApp.get(this).container.sessionManager
        lifecycleScope.launch {
            sessionManager.isBricked.collect { isBricked ->
                if (!isBricked) finish()
            }
        }

        setContent {
            BrickTheme {
                BlockScreen()
            }
        }
    }

    @Deprecated("Use OnBackPressedDispatcher")
    override fun onBackPressed() {
        // Stay on the blocking screen until the paired NFC tag ends the session.
    }
}

@Composable
private fun BlockScreen() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BrickBlockBackground)
            .padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = stringResource(R.string.block_title),
            style = MaterialTheme.typography.displayLarge,
            color = BrickRed,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(24.dp))

        Text(
            text = stringResource(R.string.block_message),
            style = MaterialTheme.typography.bodyLarge,
            color = BrickOnSurface.copy(alpha = 0.7f),
            textAlign = TextAlign.Center
        )
    }
}
