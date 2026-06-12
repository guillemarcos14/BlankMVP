package com.brickmvp.app.ui.screens

import android.content.Intent
import android.net.Uri
import android.nfc.NfcAdapter
import android.provider.Settings
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.brickmvp.app.R
import com.brickmvp.app.data.SessionManager
import com.brickmvp.app.ui.theme.BrickGreen
import com.brickmvp.app.util.AccessibilityHelper

@Composable
fun SetupScreen(
    sessionManager: SessionManager,
    onSetupComplete: () -> Unit,
    onNavigateToAppSelector: () -> Unit
) {
    val context = LocalContext.current
    val blockedPackages by sessionManager.blockedPackages.collectAsState()
    var currentStep by remember { mutableIntStateOf(0) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Text(
            text = stringResource(R.string.setup_title),
            style = MaterialTheme.typography.headlineLarge,
            color = MaterialTheme.colorScheme.onBackground
        )

        Spacer(modifier = Modifier.height(48.dp))

        when (currentStep) {
            0 -> SetupStep(
                title = stringResource(R.string.setup_step_nfc),
                description = stringResource(R.string.setup_step_nfc_desc),
                buttonText = stringResource(R.string.setup_enable),
                onAction = {
                    val adapter = NfcAdapter.getDefaultAdapter(context)
                    if (adapter != null && !adapter.isEnabled) {
                        context.startActivity(Intent(Settings.ACTION_NFC_SETTINGS))
                    }
                    currentStep = 1
                }
            )
            1 -> SetupStep(
                title = stringResource(R.string.setup_step_accessibility),
                description = stringResource(R.string.setup_step_accessibility_desc),
                buttonText = stringResource(R.string.setup_enable),
                onAction = {
                    AccessibilityHelper.openAccessibilitySettings(context)
                    currentStep = 2
                }
            )
            2 -> SetupStep(
                title = stringResource(R.string.setup_step_battery),
                description = stringResource(R.string.setup_step_battery_desc),
                buttonText = stringResource(R.string.setup_enable),
                onAction = {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:${context.packageName}")
                    }
                    context.startActivity(intent)
                    currentStep = 3
                }
            )
            3 -> SetupStep(
                title = stringResource(R.string.setup_step_apps),
                description = stringResource(R.string.setup_step_apps_desc),
                buttonText = if (blockedPackages.isEmpty())
                    stringResource(R.string.setup_select_apps)
                else
                    stringResource(R.string.setup_done),
                onAction = {
                    if (blockedPackages.isEmpty()) {
                        onNavigateToAppSelector()
                    } else {
                        currentStep = 4
                    }
                }
            )
            4 -> {
                Text(
                    text = stringResource(R.string.setup_complete),
                    style = MaterialTheme.typography.headlineMedium,
                    color = BrickGreen,
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.height(24.dp))
                Button(
                    onClick = onSetupComplete,
                    colors = ButtonDefaults.buttonColors(containerColor = BrickGreen),
                    modifier = Modifier.fillMaxWidth()
                ) {
                    Text(stringResource(R.string.setup_finish))
                }
            }
        }

        Spacer(modifier = Modifier.height(32.dp))

        // Step indicator
        if (currentStep < 4) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                repeat(4) { index ->
                    Box(
                        modifier = Modifier.size(8.dp)
                    ) {
                        Surface(
                            modifier = Modifier.fillMaxSize(),
                            shape = MaterialTheme.shapes.small,
                            color = if (index <= currentStep)
                                MaterialTheme.colorScheme.primary
                            else
                                MaterialTheme.colorScheme.surface
                        ) {}
                    }
                }
            }
        }
    }
}

@Composable
private fun SetupStep(
    title: String,
    description: String,
    buttonText: String,
    onAction: () -> Unit
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier.fillMaxWidth()
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.headlineMedium,
            color = MaterialTheme.colorScheme.onBackground,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(16.dp))
        Text(
            text = description,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.7f),
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(32.dp))
        Button(
            onClick = onAction,
            modifier = Modifier.fillMaxWidth(),
            colors = ButtonDefaults.buttonColors(
                containerColor = MaterialTheme.colorScheme.primary
            )
        ) {
            Text(buttonText, style = MaterialTheme.typography.labelLarge)
        }
    }
}
