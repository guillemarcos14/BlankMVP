package com.blanknfc.app.ui.screens

import android.content.Intent
import android.net.Uri
import android.nfc.NfcAdapter
import android.provider.Settings
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle.Event.ON_RESUME
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.blanknfc.app.R
import com.blanknfc.app.data.SessionManager
import com.blanknfc.app.ui.theme.BlankBackground
import com.blanknfc.app.ui.theme.BlankGray
import com.blanknfc.app.ui.theme.BlankLine
import com.blanknfc.app.ui.theme.BlankOnSurface
import com.blanknfc.app.ui.theme.BlankPanel
import com.blanknfc.app.ui.theme.BlankSurface
import com.blanknfc.app.util.AccessibilityHelper
import com.blanknfc.app.util.BatteryHelper
import com.blanknfc.app.util.NfcHelper
import com.blanknfc.app.util.findActivity

private const val NfcOptionsUrl = "https://getblank.netlify.app/nfc.html"

private enum class SetupError {
    NFC,
    ACCESSIBILITY,
    BATTERY
}

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
    val modes by sessionManager.modes.collectAsStateWithLifecycle()
    val currentModeId by sessionManager.currentModeId.collectAsStateWithLifecycle()
    var currentStep by remember { mutableIntStateOf(0) }
    var setupError by remember { mutableStateOf<SetupError?>(null) }
    var nfcEnabled by remember { mutableStateOf(activity?.let { NfcHelper.isNfcEnabled(it) } ?: false) }
    var nfcAvailable by remember { mutableStateOf(activity?.let { NfcHelper.isNfcAvailable(it) } ?: false) }
    var accessibilityEnabled by remember { mutableStateOf(AccessibilityHelper.isServiceEnabled(context)) }
    var batteryOptimizedIgnored by remember { mutableStateOf(BatteryHelper.isIgnoringBatteryOptimizations(context)) }
    val selectedAppCount = modes.firstOrNull { it.id == currentModeId }?.packages?.size ?: 0
    fun refreshSystemState() {
        nfcAvailable = activity?.let { NfcHelper.isNfcAvailable(it) } ?: false
        nfcEnabled = activity?.let { NfcHelper.isNfcEnabled(it) } ?: false
        accessibilityEnabled = AccessibilityHelper.isServiceEnabled(context)
        batteryOptimizedIgnored = BatteryHelper.isIgnoringBatteryOptimizations(context)
    }

    fun openNfcOptions() {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(NfcOptionsUrl)))
    }

    LaunchedEffect(currentStep, nfcTagUid) {
        if (currentStep == 1 && nfcTagUid != null) {
            setupError = null
            currentStep = 2
        }
    }

    LaunchedEffect(selectedAppCount) {
        if (currentStep == 0 && selectedAppCount > 0) {
            currentStep = 1
        }
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == ON_RESUME) {
                refreshSystemState()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(BlankBackground)
            .padding(horizontal = 24.dp, vertical = 42.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        OnboardingHeader(currentStep = currentStep.coerceIn(0, 2))

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(top = 76.dp, bottom = 40.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = Color.Transparent,
                shape = RoundedCornerShape(0.dp)
            ) {
                Column(
                    modifier = Modifier.padding(0.dp),
                    horizontalAlignment = Alignment.CenterHorizontally
                ) {
                    if (setupError != null) {
                        RecoveryStep(
                            error = setupError!!,
                            onRetry = {
                                refreshSystemState()
                                setupError = null
                            },
                            onOpenSettings = {
                                when (setupError) {
                                    SetupError.ACCESSIBILITY -> AccessibilityHelper.openAccessibilitySettings(context)
                                    SetupError.BATTERY -> {
                                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                            data = Uri.parse("package:${context.packageName}")
                                        }
                                        context.startActivity(intent)
                                    }
                                    else -> Unit
                                }
                            }
                        )
                    } else {
                        when (currentStep) {
                            0 -> MainSetupStep(
                                stepText = "Paso 1 de 3",
                                title = "Elige qu\u00E9 quieres dejar fuera.",
                                description = "Selecciona las apps que suelen romper tu foco. Blank solo necesita saber cu\u00E1les proteger.",
                                statusText = if (selectedAppCount > 0) "Apps listas" else null,
                                primaryText = stringResource(R.string.setup_select_apps),
                                secondaryText = if (selectedAppCount > 0) stringResource(R.string.setup_continue) else null,
                                onPrimary = onSelectApps,
                                onSecondary = { currentStep = 1 }
                            )
                            1 -> {
                                val nfcDescription = when {
                                    !nfcAvailable -> stringResource(R.string.setup_nfc_not_available)
                                    !nfcEnabled -> stringResource(R.string.setup_nfc_enable_desc)
                                    else -> stringResource(R.string.setup_nfc_waiting_desc)
                                }
                                MainSetupStep(
                                    stepText = "Paso 2 de 3",
                                    title = "Vincula tu pieza f\u00EDsica.",
                                    description = nfcDescription,
                                    statusText = if (nfcTagUid != null) "NFC listo" else null,
                                    primaryText = when {
                                        !nfcAvailable -> stringResource(R.string.setup_retry)
                                        !nfcEnabled -> stringResource(R.string.setup_open_nfc)
                                        else -> stringResource(R.string.setup_waiting_nfc)
                                    },
                                    primaryEnabled = !nfcAvailable || !nfcEnabled,
                                    secondaryText = "Ver opciones NFC",
                                    onPrimary = {
                                        if (!nfcAvailable) {
                                            setupError = SetupError.NFC
                                        } else if (!nfcEnabled) {
                                            context.startActivity(Intent(Settings.ACTION_NFC_SETTINGS))
                                        } else {
                                            refreshSystemState()
                                        }
                                    },
                                    onSecondary = ::openNfcOptions
                                )
                            }
                            2 -> PermissionsStep(
                                accessibilityEnabled = accessibilityEnabled,
                                batteryOptimizedIgnored = batteryOptimizedIgnored,
                                onOpenAccessibility = {
                                    AccessibilityHelper.openAccessibilitySettings(context)
                                },
                                onOpenBattery = {
                                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                        data = Uri.parse("package:${context.packageName}")
                                    }
                                    context.startActivity(intent)
                                },
                                onRetry = {
                                    refreshSystemState()
                                    setupError = when {
                                        !accessibilityEnabled -> SetupError.ACCESSIBILITY
                                        else -> null
                                    }
                                    if (setupError == null) currentStep = 3
                                },
                                onPrivacy = onNavigateToPrivacy
                            )
                            3 -> SetupCompleteStep(
                                onFinish = onSetupComplete
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(24.dp))
                    StepIndicator(currentStep = currentStep.coerceIn(0, 2))
                }
            }
        }
    }
}

@Composable
private fun OnboardingHeader(currentStep: Int) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(text = "Blank", style = MaterialTheme.typography.bodyLarge, color = BlankOnSurface)
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            repeat(3) { index ->
                Surface(
                    modifier = Modifier.size(width = if (index == currentStep) 22.dp else 8.dp, height = 8.dp),
                    shape = RoundedCornerShape(999.dp),
                    color = if (index == currentStep) BlankOnSurface else BlankLine
                ) {}
            }
        }
    }
}

@Composable
private fun SetupHero(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier,
        contentAlignment = Alignment.Center
    ) {
        Surface(
            modifier = Modifier
                .size(158.dp)
                .graphicsLayer { rotationZ = -12f },
            color = Color(0x1F202124),
            shape = RoundedCornerShape(44.dp)
        ) {}
        Image(
            painter = painterResource(R.drawable.blank_device_cutout),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier
                .width(206.dp)
                .graphicsLayer {
                    rotationZ = -12f
                    translationX = -48f
                    translationY = 20f
                }
        )
        Image(
            painter = painterResource(R.drawable.blank_phone_cutout),
            contentDescription = null,
            contentScale = ContentScale.Fit,
            modifier = Modifier
                .width(206.dp)
                .graphicsLayer {
                    rotationZ = -4f
                    translationX = 58f
                    translationY = -12f
                }
        )
    }
}

@Composable
private fun MainSetupStep(
    stepText: String? = null,
    title: String,
    description: String,
    statusText: String? = null,
    primaryText: String,
    primaryEnabled: Boolean = true,
    secondaryText: String? = null,
    onPrimary: () -> Unit,
    onSecondary: (() -> Unit)? = null
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        if (stepText != null) {
            Text(
                text = stepText,
                style = MaterialTheme.typography.labelLarge,
                color = BlankGray,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(12.dp))
        }
        Text(
            text = title,
            style = MaterialTheme.typography.headlineLarge,
            color = BlankOnSurface,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(14.dp))
        Text(
            text = description,
            style = MaterialTheme.typography.bodyLarge,
            color = BlankGray,
            textAlign = TextAlign.Center,
            modifier = Modifier.widthIn(max = 330.dp)
        )
        if (statusText != null) {
            Spacer(modifier = Modifier.height(18.dp))
            StatusPill(text = statusText)
        }
        Spacer(modifier = Modifier.height(28.dp))
        PrimaryButton(text = primaryText, enabled = primaryEnabled, onClick = onPrimary)
        if (secondaryText != null && onSecondary != null) {
            Spacer(modifier = Modifier.height(12.dp))
            SecondaryButton(text = secondaryText, onClick = onSecondary)
        }
    }
}

@Composable
private fun PermissionsStep(
    accessibilityEnabled: Boolean,
    batteryOptimizedIgnored: Boolean,
    onOpenAccessibility: () -> Unit,
    onOpenBattery: () -> Unit,
    onRetry: () -> Unit,
    onPrivacy: () -> Unit
) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = "Paso 3 de 3",
            style = MaterialTheme.typography.labelLarge,
            color = BlankGray,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = "Permite que Blank bloquee.",
            style = MaterialTheme.typography.headlineLarge,
            color = BlankOnSurface,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(12.dp))
        Text(
            text = stringResource(R.string.setup_permissions_desc),
            style = MaterialTheme.typography.bodyLarge,
            color = BlankGray,
            textAlign = TextAlign.Center,
            modifier = Modifier.widthIn(max = 330.dp)
        )
        Spacer(modifier = Modifier.height(18.dp))
        PermissionRow(
            title = stringResource(R.string.setup_accessibility_label),
            status = stringResource(R.string.setup_required),
            description = stringResource(R.string.setup_accessibility_desc),
            checked = accessibilityEnabled,
            onClick = onOpenAccessibility
        )
        Spacer(modifier = Modifier.height(10.dp))
        PermissionRow(
            title = stringResource(R.string.setup_battery_label),
            status = stringResource(R.string.setup_recommended),
            description = stringResource(R.string.setup_battery_desc),
            checked = batteryOptimizedIgnored,
            onClick = onOpenBattery
        )
        if (accessibilityEnabled) {
            Spacer(modifier = Modifier.height(18.dp))
            StatusPill(text = stringResource(R.string.setup_permissions_ready))
        }
        Spacer(modifier = Modifier.height(18.dp))
        PrimaryButton(
            text = if (accessibilityEnabled) stringResource(R.string.setup_continue) else stringResource(R.string.setup_open_accessibility),
            onClick = if (accessibilityEnabled) onRetry else onOpenAccessibility
        )
        Spacer(modifier = Modifier.height(4.dp))
        androidx.compose.material3.TextButton(onClick = onPrivacy) {
            Text(text = stringResource(R.string.privacy_open), color = BlankGray)
        }
    }
}

@Composable
private fun SetupCompleteStep(onFinish: () -> Unit) {
    Column(horizontalAlignment = Alignment.CenterHorizontally) {
        Text(
            text = stringResource(R.string.setup_complete_title),
            style = MaterialTheme.typography.headlineLarge,
            color = BlankOnSurface,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(14.dp))
        Text(
            text = stringResource(R.string.setup_complete_desc),
            style = MaterialTheme.typography.bodyLarge,
            color = BlankGray,
            textAlign = TextAlign.Center,
            modifier = Modifier.widthIn(max = 330.dp)
        )
        Spacer(modifier = Modifier.height(18.dp))
        StatusPill(text = stringResource(R.string.setup_complete_status))
        Spacer(modifier = Modifier.height(28.dp))
        PrimaryButton(
            text = stringResource(R.string.setup_first_blank),
            onClick = onFinish
        )
    }
}

@Composable
private fun StatusPill(text: String) {
    Surface(
        color = Color.White.copy(alpha = 0.72f),
        shape = RoundedCornerShape(999.dp),
        modifier = Modifier.height(42.dp)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(text = "✓", style = MaterialTheme.typography.labelLarge, color = BlankOnSurface)
            Text(text = text, style = MaterialTheme.typography.labelLarge, color = BlankOnSurface)
        }
    }
}

@Composable
private fun PermissionRow(
    title: String,
    status: String,
    description: String,
    checked: Boolean,
    onClick: () -> Unit
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = Color.White.copy(alpha = 0.74f),
        shape = RoundedCornerShape(22.dp),
        onClick = onClick
    ) {
        Row(
            modifier = Modifier.padding(14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Checkbox(checked = checked, onCheckedChange = { onClick() })
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 8.dp)
            ) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = title,
                        style = MaterialTheme.typography.labelLarge,
                        color = BlankOnSurface,
                        modifier = Modifier.weight(1f)
                    )
                    Text(
                        text = status,
                        style = MaterialTheme.typography.labelSmall,
                        color = BlankGray,
                        textAlign = TextAlign.End
                    )
                }
                Text(text = description, style = MaterialTheme.typography.bodyMedium, color = BlankGray)
            }
        }
    }
}

@Composable
private fun RecoveryStep(
    error: SetupError,
    onRetry: () -> Unit,
    onOpenSettings: () -> Unit
) {
    val title = when (error) {
        SetupError.NFC -> stringResource(R.string.setup_nfc_error_title)
        else -> stringResource(R.string.setup_permission_error_title)
    }
    val description = when (error) {
        SetupError.NFC -> stringResource(R.string.setup_nfc_error_desc)
        SetupError.ACCESSIBILITY -> stringResource(R.string.setup_accessibility_error_desc)
        SetupError.BATTERY -> stringResource(R.string.setup_battery_error_desc)
    }
    MainSetupStep(
        title = title,
        description = description,
        primaryText = when (error) {
            SetupError.NFC -> stringResource(R.string.setup_retry)
            SetupError.ACCESSIBILITY -> stringResource(R.string.setup_open_accessibility)
            SetupError.BATTERY -> stringResource(R.string.setup_open_battery)
        },
        secondaryText = if (error == SetupError.NFC) null else stringResource(R.string.setup_retry),
        onPrimary = if (error == SetupError.NFC) onRetry else onOpenSettings,
        onSecondary = if (error == SetupError.NFC) null else onRetry
    )
}

@Composable
private fun PrimaryButton(text: String, enabled: Boolean = true, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(999.dp),
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
            .shadow(
                elevation = if (enabled) 16.dp else 0.dp,
                shape = RoundedCornerShape(999.dp),
                ambientColor = Color.Black.copy(alpha = 0.12f),
                spotColor = Color.Black.copy(alpha = 0.12f)
            ),
        colors = ButtonDefaults.buttonColors(
            containerColor = BlankOnSurface,
            contentColor = BlankSurface,
            disabledContainerColor = Color(0xFFD8D8D5),
            disabledContentColor = BlankGray
        )
    ) {
        Text(text, style = MaterialTheme.typography.labelLarge)
    }
}

@Composable
private fun SecondaryButton(text: String, onClick: () -> Unit) {
    OutlinedButton(
        onClick = onClick,
        shape = RoundedCornerShape(999.dp),
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp),
        colors = ButtonDefaults.outlinedButtonColors(contentColor = BlankOnSurface)
    ) {
        Text(text, style = MaterialTheme.typography.labelLarge)
    }
}

@Composable
private fun StepIndicator(currentStep: Int) {
    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        repeat(3) { index ->
            Surface(
                modifier = Modifier.size(width = if (index == currentStep) 22.dp else 8.dp, height = 8.dp),
                shape = RoundedCornerShape(999.dp),
                color = if (index <= currentStep) BlankOnSurface else BlankLine
            ) {}
        }
    }
}
