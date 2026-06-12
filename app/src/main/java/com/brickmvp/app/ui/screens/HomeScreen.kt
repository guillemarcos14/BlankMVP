package com.brickmvp.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.brickmvp.app.R
import com.brickmvp.app.data.SessionManager
import com.brickmvp.app.ui.theme.*
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.*

@Composable
fun HomeScreen(
    sessionManager: SessionManager,
    onEditApps: () -> Unit
) {
    val isBricked by sessionManager.isBricked.collectAsState()
    val brickedSince by sessionManager.brickedSince.collectAsState()
    val blockedPackages by sessionManager.blockedPackages.collectAsState()

    val backgroundColor = if (isBricked) BrickRedDark else BrickBackground

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(backgroundColor)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        // Status
        Text(
            text = if (isBricked)
                stringResource(R.string.home_bricked)
            else
                stringResource(R.string.home_unbricked),
            style = MaterialTheme.typography.displayLarge,
            color = BrickOnSurface,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(16.dp))

        // Instruction
        Text(
            text = if (isBricked)
                stringResource(R.string.home_tap_to_unbrick)
            else
                stringResource(R.string.home_tap_to_brick),
            style = MaterialTheme.typography.bodyLarge,
            color = BrickOnSurface.copy(alpha = 0.7f),
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(32.dp))

        // Timer when bricked
        if (isBricked && brickedSince > 0) {
            BrickedTimer(brickedSince = brickedSince)
            Spacer(modifier = Modifier.height(8.dp))

            val dateFormat = remember { SimpleDateFormat("HH:mm", Locale.getDefault()) }
            Text(
                text = stringResource(
                    R.string.home_bricked_since,
                    dateFormat.format(Date(brickedSince))
                ),
                style = MaterialTheme.typography.bodyMedium,
                color = BrickOnSurface.copy(alpha = 0.5f)
            )
        }

        Spacer(modifier = Modifier.height(48.dp))

        // Blocked apps count
        if (blockedPackages.isNotEmpty()) {
            Text(
                text = stringResource(R.string.home_blocked_apps, blockedPackages.size),
                style = MaterialTheme.typography.bodyLarge,
                color = BrickOnSurface.copy(alpha = 0.7f)
            )
            Spacer(modifier = Modifier.height(16.dp))
        }

        // Edit apps button (only when unbricked)
        if (!isBricked) {
            OutlinedButton(
                onClick = onEditApps,
                colors = ButtonDefaults.outlinedButtonColors(
                    contentColor = BrickOnSurface
                )
            ) {
                Text(
                    text = if (blockedPackages.isEmpty())
                        stringResource(R.string.home_no_apps_selected)
                    else
                        stringResource(R.string.home_edit_apps)
                )
            }
        }
    }
}

@Composable
private fun BrickedTimer(brickedSince: Long) {
    var elapsed by remember { mutableLongStateOf(System.currentTimeMillis() - brickedSince) }

    LaunchedEffect(brickedSince) {
        while (true) {
            elapsed = System.currentTimeMillis() - brickedSince
            delay(1000)
        }
    }

    val hours = (elapsed / 3_600_000).toInt()
    val minutes = ((elapsed % 3_600_000) / 60_000).toInt()
    val seconds = ((elapsed % 60_000) / 1_000).toInt()

    Text(
        text = "%02d:%02d:%02d".format(hours, minutes, seconds),
        style = MaterialTheme.typography.headlineLarge,
        color = BrickOnSurface
    )
}
