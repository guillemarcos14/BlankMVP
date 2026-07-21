package com.blanknfc.app.ui.screens

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle.Event.ON_RESUME
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.blanknfc.app.data.SessionManager
import com.blanknfc.app.ui.theme.BlankBackground
import com.blanknfc.app.ui.theme.BlankGray
import com.blanknfc.app.ui.theme.BlankGreen
import com.blanknfc.app.ui.theme.BlankLine
import com.blanknfc.app.ui.theme.BlankOnSurface
import com.blanknfc.app.ui.theme.BlankSurface
import com.blanknfc.app.util.AccessibilityHelper
import com.blanknfc.app.util.BatteryHelper
import com.blanknfc.app.util.NfcHelper
import com.blanknfc.app.util.findActivity

@Composable
fun SetupScreen(
    sessionManager: SessionManager,
    onSetupComplete: () -> Unit,
    onSelectApps: () -> Unit,
    onNavigateToPrivacy: () -> Unit
) {
    val context = LocalContext.current
    val activity = context.findActivity()
    val lifecycleOwner = LocalLifecycleOwner.current
    val nfcTagUid by sessionManager.nfcTagUid.collectAsStateWithLifecycle()
    val blockedPackages by sessionManager.blockedPackages.collectAsStateWithLifecycle()
    var currentStep by remember { mutableIntStateOf(0) }
    var message by remember { mutableStateOf<String?>(null) }
    var nfcEnabled by remember { mutableStateOf(activity?.let { NfcHelper.isNfcEnabled(it) } ?: false) }
    var nfcAvailable by remember { mutableStateOf(activity?.let { NfcHelper.isNfcAvailable(it) } ?: false) }
    var accessibilityEnabled by remember { mutableStateOf(AccessibilityHelper.isServiceEnabled(context)) }
    var batteryOptimizedIgnored by remember { mutableStateOf(BatteryHelper.isIgnoringBatteryOptimizations(context)) }

    fun refreshSystemState() {
        nfcAvailable = activity?.let { NfcHelper.isNfcAvailable(it) } ?: false
        nfcEnabled = activity?.let { NfcHelper.isNfcEnabled(it) } ?: false
        accessibilityEnabled = AccessibilityHelper.isServiceEnabled(context)
        batteryOptimizedIgnored = BatteryHelper.isIgnoringBatteryOptimizations(context)
    }

    LaunchedEffect(nfcTagUid) {
        if (currentStep == 1 && nfcTagUid != null) {
            currentStep = 2
            message = "NFC tag registered."
        }
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == ON_RESUME) refreshSystemState()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BlankBackground)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text(
            text = "Setup Blank",
            style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Bold),
            color = BlankOnSurface,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.weight(1f))

        when (currentStep) {
            0 -> SetupStep(
                title = "Authorize Accessibility",
                description = if (accessibilityEnabled) {
                    "Accessibility authorization is approved."
                } else {
                    "Blank needs Accessibility access to detect and block the apps you choose."
                },
                buttonTitle = if (accessibilityEnabled) "Continue" else "Authorize",
                onAction = {
                    if (accessibilityEnabled) {
                        currentStep = 1
                        message = null
                    } else {
                        AccessibilityHelper.openAccessibilitySettings(context)
                    }
                },
                secondaryTitle = if (batteryOptimizedIgnored) null else "Allow Battery Background Access",
                onSecondary = if (batteryOptimizedIgnored) null else {
                    {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:${context.packageName}")
                        }
                        context.startActivity(intent)
                    }
                }
            )
            1 -> SetupStep(
                title = "Pair NFC Tag",
                description = when {
                    nfcTagUid != null -> "NFC tag registered. Continue to app selection."
                    !nfcAvailable -> "NFC is not available on this Android device."
                    !nfcEnabled -> "Enable NFC, return to Blank, then hold your physical Blank tag near this phone."
                    else -> "Hold your physical Blank NFC tag near this phone to pair it."
                },
                buttonTitle = when {
                    nfcTagUid != null -> "Continue"
                    !nfcEnabled && nfcAvailable -> "Open NFC Settings"
                    else -> "Waiting for NFC Tag"
                },
                buttonEnabled = nfcTagUid != null || (!nfcEnabled && nfcAvailable),
                onAction = {
                    when {
                        nfcTagUid != null -> currentStep = 2
                        !nfcEnabled && nfcAvailable -> context.startActivity(Intent(Settings.ACTION_NFC_SETTINGS))
                        else -> refreshSystemState()
                    }
                }
            )
            2 -> SetupStep(
                title = "Select Apps",
                description = if (blockedPackages.isNotEmpty()) {
                    "${blockedPackages.size} selected"
                } else {
                    "Choose the apps to block when Blank mode is active."
                },
                buttonTitle = if (blockedPackages.isNotEmpty()) "Continue" else "Select Apps",
                onAction = {
                    if (blockedPackages.isNotEmpty()) currentStep = 3 else onSelectApps()
                }
            )
            else -> SetupStep(
                title = "Setup Complete",
                description = "Blank is ready on this Android phone.",
                buttonTitle = "Finish Setup",
                onAction = onSetupComplete
            )
        }

        if (message != null) {
            Spacer(modifier = Modifier.height(18.dp))
            Text(
                text = message.orEmpty(),
                style = MaterialTheme.typography.bodyMedium,
                color = BlankGray,
                textAlign = TextAlign.Center
            )
        }

        Spacer(modifier = Modifier.weight(1f))

        TextButton(onClick = onNavigateToPrivacy) {
            Text("Privacy details", color = BlankGray)
        }

        Spacer(modifier = Modifier.height(10.dp))
        StepIndicator(currentStep = currentStep.coerceIn(0, 3))
    }
}

@Composable
private fun SetupStep(
    title: String,
    description: String,
    buttonTitle: String,
    onAction: () -> Unit,
    buttonEnabled: Boolean = true,
    secondaryTitle: String? = null,
    onSecondary: (() -> Unit)? = null
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(18.dp)
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.SemiBold),
            color = BlankOnSurface,
            textAlign = TextAlign.Center
        )
        Text(
            text = description,
            style = MaterialTheme.typography.bodyLarge,
            color = BlankGray,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth()
        )
        Button(
            onClick = onAction,
            enabled = buttonEnabled,
            shape = RoundedCornerShape(8.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = BlankGreen,
                contentColor = Color.White,
                disabledContainerColor = BlankSurface,
                disabledContentColor = BlankGray
            ),
            modifier = Modifier
                .fillMaxWidth()
                .height(54.dp)
        ) {
            Text(buttonTitle, style = MaterialTheme.typography.labelLarge)
        }
        if (secondaryTitle != null && onSecondary != null) {
            OutlinedButton(
                onClick = onSecondary,
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = BlankOnSurface),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp)
            ) {
                Text(secondaryTitle, style = MaterialTheme.typography.labelLarge)
            }
        }
    }
}

@Composable
private fun StepIndicator(currentStep: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        repeat(4) { index ->
            Surface(
                modifier = Modifier.size(8.dp),
                shape = CircleShape,
                color = if (index <= currentStep) BlankGreen else BlankLine
            ) {}
        }
    }
}
