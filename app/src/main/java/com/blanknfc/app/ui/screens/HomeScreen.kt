package com.blanknfc.app.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.animation.togetherWith
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.health.connect.client.PermissionController
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.blanknfc.app.BlankApp
import com.blanknfc.app.R
import com.blanknfc.app.analytics.BlankEvent
import com.blanknfc.app.analytics.BlankEvents
import com.blanknfc.app.data.DigitalWellnessEngine
import com.blanknfc.app.data.DigitalWellnessPlan
import com.blanknfc.app.data.DigitalWellnessRemoteStore
import com.blanknfc.app.data.FocusActivityDay
import com.blanknfc.app.data.BlankMode
import com.blanknfc.app.data.FocusSchedule
import com.blanknfc.app.data.FocusStats
import com.blanknfc.app.data.HealthConnectStore
import com.blanknfc.app.data.PlayPurchaseStore
import com.blanknfc.app.data.ReferralStore
import com.blanknfc.app.data.SessionManager
import com.blanknfc.app.service.BlankSchedule
import com.blanknfc.app.ui.theme.BlankGray
import com.blanknfc.app.ui.theme.BlankOnSurface
import com.blanknfc.app.ui.theme.BlankSurface
import com.blanknfc.app.util.AccessibilityHelper
import com.blanknfc.app.util.AppInfo
import com.blanknfc.app.util.BatteryHelper
import com.blanknfc.app.util.PackageHelper
import java.util.Calendar
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject

private enum class HomePanel {
    HOME,
    SETTINGS,
    MODES,
    STATS,
    SCHEDULE,
    RELINK,
    FORGET,
    BLOCK,
    EMERGENCY
}

private data class ConfigIssue(
    val title: String,
    val body: String,
    val action: String?,
    val onAction: () -> Unit = {}
)

private data class ProgressPeriodSummary(
    val label: String,
    val value: String,
    val caption: String
)

private const val HomeTagline = "Your plan adapts\nbefore the scroll\npulls you back."
private val HomeGlassScrim = Color.Black.copy(alpha = 0.18f)

private fun homeCapsuleBorder(): BorderStroke = BorderStroke(
    width = 1.dp,
    brush = Brush.linearGradient(
        colors = listOf(
            Color.White.copy(alpha = 0.42f),
            Color.White.copy(alpha = 0.16f),
            Color.White.copy(alpha = 0.04f),
            Color.White.copy(alpha = 0.00f)
        ),
        start = Offset(0f, 0f),
        end = Offset(180f, 180f)
    )
)

private fun homeCapsuleReflection(center: Offset, radius: Float): Brush = Brush.radialGradient(
    colors = listOf(
        Color.White.copy(alpha = 0.16f),
        Color.White.copy(alpha = 0.04f),
        Color.White.copy(alpha = 0.00f)
    ),
    center = center,
    radius = radius
)

@Composable
fun HomeScreen(
    sessionManager: SessionManager,
    purchaseStore: PlayPurchaseStore,
    healthConnectStore: HealthConnectStore,
    digitalWellnessStore: DigitalWellnessRemoteStore,
    referralStore: ReferralStore,
    onRelinkTag: () -> Unit,
    onForgetTag: () -> Unit
) {
    val context = LocalContext.current
    val appContainer = remember(context) { BlankApp.get(context).container }
    val analyticsTracker = appContainer.analyticsTracker
    val backendClient = appContainer.backendClient
    val lifecycleOwner = LocalLifecycleOwner.current
    val isBlankActive by sessionManager.isBlankActive.collectAsState()
    val modes by sessionManager.modes.collectAsState()
    val currentModeId by sessionManager.currentModeId.collectAsState()
    val stats by sessionManager.stats.collectAsState()
    val emergencyUnlocksRemaining by sessionManager.emergencyUnlocksRemaining.collectAsState()
    val schedule by sessionManager.schedule.collectAsState()
    val purchaseState by purchaseStore.state.collectAsState()
    val healthSummary by healthConnectStore.summary.collectAsState()
    val remoteAiPlan by digitalWellnessStore.plan.collectAsState()
    val referralState by referralStore.state.collectAsState()
    val hasPremiumAccess = purchaseState.hasPremiumAccess || referralStore.hasReferralProAccess || referralState.rewardUnlocked
    val currentMode = modes.firstOrNull { it.id == currentModeId } ?: modes.first()
    val localAiPlan = DigitalWellnessEngine.build(
        stats = stats,
        selectedAppCount = currentMode.packages.size,
        emergencyUnlocksRemaining = emergencyUnlocksRemaining,
        schedule = schedule,
        healthSummary = healthSummary
    )
    val aiPlan = remoteAiPlan ?: localAiPlan
    val buttonLight = !isBlankActive
    val apps = remember { PackageHelper.getInstalledApps(context) }
    var panel by remember { mutableStateOf(HomePanel.HOME) }
    var modeBeingEdited by remember { mutableStateOf<BlankMode?>(null) }
    var showCreateMode by remember { mutableStateOf(false) }
    var accessibilityEnabled by remember { mutableStateOf(AccessibilityHelper.isServiceEnabled(context)) }
    var batteryOptimizedIgnored by remember { mutableStateOf(BatteryHelper.isIgnoringBatteryOptimizations(context)) }

    fun refreshSystemConfig() {
        accessibilityEnabled = AccessibilityHelper.isServiceEnabled(context)
        batteryOptimizedIgnored = BatteryHelper.isIgnoringBatteryOptimizations(context)
    }

    DisposableEffect(lifecycleOwner, context) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                refreshSystemConfig()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    LaunchedEffect(stats, currentMode.packages.size, emergencyUnlocksRemaining, schedule, healthSummary) {
        digitalWellnessStore.refresh(
            localPlan = localAiPlan,
            stats = stats,
            selectedAppCount = currentMode.packages.size,
            emergencyUnlocksRemaining = emergencyUnlocksRemaining,
            schedule = schedule,
            healthSummary = healthSummary
        )
        referralStore.refreshStatus()
    }

    LaunchedEffect(healthSummary) {
        val status = healthSourceStatus(healthSummary)
        if (status == "Connected" || status == "Partial" || status == "Stale") {
            val baseProperties = mapOf(
                "source" to "health_connect",
                "status" to status.lowercase(),
                "health_days" to healthSummary.daysWithAnySignal.toString(),
                "signal_coverage_percent" to (
                    healthSummary.daysWithAnySignal * 100 / healthSummary.daysRequested.coerceAtLeast(1)
                    ).toString(),
                "raw_health_samples_sent" to "false"
            )
            analyticsTracker.track(
                BlankEvent(
                    if (status == "Stale") BlankEvents.STALE_HEALTH_DATA else BlankEvents.HEALTH_DATA_AVAILABLE,
                    baseProperties
                )
            )
            analyticsTracker.track(
                BlankEvent(
                    if (status == "Stale") BlankEvents.WEARABLE_DATA_STALE else BlankEvents.WEARABLE_DATA_AVAILABLE,
                    baseProperties + ("provider" to "health_connect")
                )
            )
        }
    }

    val configIssues = buildList {
        if (!accessibilityEnabled) {
            add(
                ConfigIssue(
                    title = "Accessibility pending",
                    body = "Enable Blanked in Accessibility so Android can detect protected apps.",
                    action = "Open Accessibility",
                    onAction = { AccessibilityHelper.openAccessibilitySettings(context) }
                )
            )
        }
        if (!batteryOptimizedIgnored) {
            add(
                ConfigIssue(
                    title = "Battery restricted",
                    body = "Allow Blanked to keep running in the background so blocks stay stable.",
                    action = "Open Battery",
                    onAction = { BatteryHelper.openBatteryOptimizationSettings(context) }
                )
            )
        }
    }

    AppBackground(
        isBlankActive = isBlankActive,
        isDark = panel == HomePanel.BLOCK || panel == HomePanel.EMERGENCY
    ) {
        AnimatedContent(
            targetState = panel,
            transitionSpec = {
                fadeIn(animationSpec = tween(260)) togetherWith fadeOut(animationSpec = tween(180))
            },
            label = "blank_panel_transition"
        ) { currentPanel ->
        when (currentPanel) {
            HomePanel.HOME -> HomePanelContent(
                isBlankActive = isBlankActive,
                configIssues = configIssues,
                aiPlan = aiPlan,
                hasPremiumAccess = hasPremiumAccess,
                onSettings = { panel = HomePanel.SETTINGS },
                onStats = { panel = HomePanel.STATS },
                onMode = { panel = HomePanel.MODES },
                onTimer = { panel = HomePanel.SCHEDULE },
                onStartAIPlan = {
                    if (currentMode.packages.isEmpty()) {
                        modeBeingEdited = currentMode
                    } else if (!AccessibilityHelper.isServiceEnabled(context)) {
                        AccessibilityHelper.openAccessibilitySettings(context)
                    } else {
                        sessionManager.activateBlank()
                    }
                },
                onMainAction = {
                    if (currentMode.packages.isEmpty()) {
                        modeBeingEdited = currentMode
                    } else if (!AccessibilityHelper.isServiceEnabled(context)) {
                        AccessibilityHelper.openAccessibilitySettings(context)
                    } else {
                        sessionManager.activateBlank()
                    }
                }
            )

            HomePanel.SETTINGS -> SettingsPanel(
                buttonLight = buttonLight,
                onBack = { panel = HomePanel.HOME },
                onModes = { panel = HomePanel.MODES },
                onSchedule = {
                    panel = HomePanel.SCHEDULE
                },
                onStats = {
                    panel = HomePanel.STATS
                },
                onEmergency = {
                    panel = HomePanel.EMERGENCY
                }
            )

            HomePanel.MODES -> ModesPanel(
                modes = modes,
                currentModeId = currentModeId,
                buttonLight = buttonLight,
                onBack = { panel = HomePanel.HOME },
                onSelect = sessionManager::selectMode,
                onCreate = { showCreateMode = true },
                onRename = sessionManager::renameMode,
                onEditApps = { modeBeingEdited = it },
                onDelete = sessionManager::deleteMode
            )

            HomePanel.RELINK -> CenterActionPanel(
                topTitle = "NFC",
                label = "Nueva etiqueta",
                title = "Vincula una nueva pieza.",
                body = "Blanked will keep your protected apps and replace only the optional unlock key.",
                action = "Open pairing",
                buttonLight = buttonLight,
                onBack = { panel = HomePanel.SETTINGS },
                onAction = onRelinkTag
            )

            HomePanel.FORGET -> ForgetConfirmPanel(
                buttonLight = buttonLight,
                onBack = { panel = HomePanel.SETTINGS },
                onConfirm = onForgetTag
            )

            HomePanel.STATS -> StatsPanel(
                stats = stats,
                emergencyUnlocksRemaining = emergencyUnlocksRemaining,
                aiPlan = aiPlan,
                hasPremiumAccess = hasPremiumAccess,
                healthConnectStore = healthConnectStore,
                onTrack = analyticsTracker::track,
                onStartWearableOAuth = { provider ->
                    val body = backendClient.commonEnvelope(JSONObject().apply { put("provider", provider) })
                    val response = backendClient.post("wearable-oauth-start", body)
                    response.optString("authorization_url").takeIf { it.isNotBlank() }?.let { url ->
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                    }
                },
                buttonLight = buttonLight,
                onBack = { panel = HomePanel.HOME }
            )

            HomePanel.SCHEDULE -> SchedulePanel(
                schedule = schedule,
                buttonLight = buttonLight,
                onBack = { panel = HomePanel.SETTINGS },
                onSave = { updatedSchedule ->
                    sessionManager.updateSchedule(updatedSchedule)
                    BlankSchedule.schedule(context, updatedSchedule)
                    sessionManager.applyScheduleWindow()
                    panel = HomePanel.SETTINGS
                }
            )

            HomePanel.BLOCK -> BlockPanel(
                onEmergency = { panel = HomePanel.EMERGENCY }
            )

            HomePanel.EMERGENCY -> EmergencyPanel(
                emergencyUnlocksRemaining = emergencyUnlocksRemaining,
                onBack = {
                    panel = if (isBlankActive) HomePanel.BLOCK else HomePanel.SETTINGS
                },
                onUnlock = {
                    if (sessionManager.deactivateForEmergency()) {
                        panel = HomePanel.HOME
                    }
                }
            )
        }
        }
    }

    modeBeingEdited?.let { mode ->
        ModeAppsDialog(
            mode = mode,
            apps = apps,
            buttonLight = buttonLight,
            onDismiss = { modeBeingEdited = null },
            onSave = { packages ->
                sessionManager.updateModePackages(mode.id, packages)
                modeBeingEdited = null
            }
        )
    }

    if (showCreateMode) {
        CreateModeDialog(
            apps = apps,
            buttonLight = buttonLight,
            onDismiss = { showCreateMode = false },
            onCreate = { name, packages ->
                sessionManager.createMode(name, packages)
                showCreateMode = false
            }
        )
    }
}

@Composable
private fun AppBackground(
    isBlankActive: Boolean,
    isDark: Boolean,
    content: @Composable () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(if (isDark) Color.Black else Color(0xFFE7E7E2))
    ) {
        if (!isDark) {
            Crossfade(
                targetState = if (isBlankActive) R.drawable.blank_home_background_active else R.drawable.blank_home_background_idle,
                animationSpec = tween(durationMillis = 520),
                label = "blank_background_image"
            ) { backgroundImageResId ->
                Image(
                    painter = painterResource(backgroundImageResId),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier
                        .fillMaxSize()
                )
            }
        }
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp, vertical = 42.dp)
        ) {
            content()
        }
    }
}

@Composable
private fun HomePanelContent(
    isBlankActive: Boolean,
    configIssues: List<ConfigIssue>,
    aiPlan: DigitalWellnessPlan,
    hasPremiumAccess: Boolean,
    onSettings: () -> Unit,
    onStats: () -> Unit,
    onMode: () -> Unit,
    onTimer: () -> Unit,
    onStartAIPlan: () -> Unit,
    onMainAction: () -> Unit
) {
    Box(modifier = Modifier.fillMaxSize()) {
        HomeTopNav(
            onSettings = onSettings,
            onStats = onStats,
            onMode = onMode,
            onTimer = onTimer,
            modifier = Modifier.align(Alignment.TopCenter)
        )
        if (configIssues.isNotEmpty()) {
            ConfigIssuesCard(
                issues = configIssues,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 62.dp)
            )
        } else if (!isBlankActive && hasPremiumAccess) {
            AiPlanHomeCard(
                aiPlan = aiPlan,
                onStart = onStartAIPlan,
                onOpenReport = onStats,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 62.dp)
            )
        }
        Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = Alignment.Center
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text(
                    text = HomeTagline,
                    style = MaterialTheme.typography.titleLarge.copy(
                        fontWeight = FontWeight.Bold,
                        fontSize = 34.sp,
                        lineHeight = 39.sp,
                        letterSpacing = (-1.9).sp
                    ),
                    color = Color.White,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(24.dp))
                HomeBlankearButton(
                    text = if (isBlankActive) "Blanked active" else "Start Blanked",
                    enabled = !isBlankActive,
                    modifier = Modifier.widthIn(max = if (isBlankActive) 342.dp else 178.dp),
                    onClick = onMainAction
                )
            }
        }
    }
}

@Composable
private fun AiPlanHomeCard(
    aiPlan: DigitalWellnessPlan,
    onStart: () -> Unit,
    onOpenReport: () -> Unit,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.widthIn(max = 330.dp),
        color = Color.White.copy(alpha = 0.74f),
        shape = RoundedCornerShape(18.dp),
        onClick = onOpenReport
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Blanked AI now",
                    style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold),
                    color = BlankOnSurface.copy(alpha = 0.74f)
                )
                Text(
                    text = "${aiPlan.recommendedDurationMinutes} min before ${aiPlan.riskWindow}",
                    style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                    color = BlankOnSurface
                )
            }
            Surface(
                color = BlankOnSurface,
                contentColor = Color.White,
                shape = RoundedCornerShape(999.dp),
                onClick = onStart
            ) {
                Text(
                    text = "Start",
                    style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold),
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)
                )
            }
        }
    }

}

@Composable
private fun HomeTopNav(
    onSettings: () -> Unit,
    onStats: () -> Unit,
    onMode: () -> Unit,
    onTimer: () -> Unit,
    modifier: Modifier = Modifier
) {
    val logoReflection = homeCapsuleReflection(center = Offset(12f, 8f), radius = 52f)
    val capsuleReflection = homeCapsuleReflection(center = Offset(34f, 8f), radius = 132f)
    val topNavBorder = homeCapsuleBorder()

    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Surface(
            modifier = Modifier.shadow(
                elevation = 5.dp,
                shape = RoundedCornerShape(50.dp),
                clip = false,
                ambientColor = Color.Black.copy(alpha = 0.05f),
                spotColor = Color.Black.copy(alpha = 0.04f)
            ),
            color = HomeGlassScrim,
            shape = RoundedCornerShape(50.dp),
            border = topNavBorder,
            onClick = onSettings
        ) {
            Box(
                modifier = Modifier
                    .size(47.dp)
                    .background(logoReflection, RoundedCornerShape(50.dp)),
                contentAlignment = Alignment.Center
            ) {
                Image(
                    painter = painterResource(R.drawable.blank_logo_white),
                    contentDescription = "Settings",
                    modifier = Modifier.size(31.dp)
                )
            }
        }
        Spacer(modifier = Modifier.size(8.dp))
        Surface(
            modifier = Modifier.shadow(
                elevation = 5.dp,
                shape = RoundedCornerShape(50.dp),
                clip = false,
                ambientColor = Color.Black.copy(alpha = 0.05f),
                spotColor = Color.Black.copy(alpha = 0.04f)
            ),
            color = HomeGlassScrim,
            shape = RoundedCornerShape(50.dp),
            border = topNavBorder
        ) {
            Row(
                modifier = Modifier
                    .height(47.dp)
                    .background(capsuleReflection, RoundedCornerShape(50.dp))
                    .padding(horizontal = 22.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                HomeTopNavButton("Stats", onStats)
                HomeTopNavButton("Plan", onMode)
                HomeTopNavButton("Timer", onTimer)
            }
        }
    }
}

@Composable
private fun HomeTopNavButton(label: String, onClick: () -> Unit) {
    Box(
        modifier = Modifier
            .height(47.dp)
            .widthIn(min = 64.dp)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
            color = Color.White,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun ConfigIssuesCard(issues: List<ConfigIssue>, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        color = Color.White.copy(alpha = 0.78f),
        shape = RoundedCornerShape(22.dp)
    ) {
        Column(
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text(
                text = "Review setup",
                style = MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.Medium),
                color = BlankOnSurface
            )
            issues.forEach { issue ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(text = issue.title, style = MaterialTheme.typography.bodyLarge, color = BlankOnSurface)
                        Text(
                            text = issue.body,
                            style = MaterialTheme.typography.bodySmall,
                            color = BlankOnSurface.copy(alpha = 0.64f)
                        )
                    }
                    if (issue.action != null) {
                        TextButton(onClick = issue.onAction) {
                            Text(text = issue.action, color = BlankOnSurface)
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TopBar(
    left: @Composable () -> Unit,
    right: @Composable () -> Unit,
    modifier: Modifier = Modifier
) {
    Row(
        modifier = modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        left()
        right()
    }
}

@Composable
private fun ModeChipAligned(name: String, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .height(44.dp)
            .clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = name,
            style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Medium),
            color = BlankOnSurface
        )
        MinimalChevron(color = BlankOnSurface, modifier = Modifier.padding(start = 5.dp))
    }
}

@Composable
private fun IconDotsAligned(onClick: () -> Unit, modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .size(44.dp)
            .clickable(onClick = onClick),
        contentAlignment = Alignment.Center
    ) {
        VerticalDotsIcon(color = BlankOnSurface)
    }
}

@Composable
private fun MinimalChevron(color: Color, modifier: Modifier = Modifier) {
    Canvas(modifier = modifier.size(width = 8.dp, height = 6.dp)) {
        drawArc(
            color = color.copy(alpha = 0.74f),
            startAngle = 20f,
            sweepAngle = 140f,
            useCenter = false,
            topLeft = Offset(0f, -size.height * 0.45f),
            size = Size(size.width, size.height * 1.6f),
            style = Stroke(width = 1.15.dp.toPx(), cap = StrokeCap.Round)
        )
    }
}

@Composable
private fun VerticalDotsIcon(color: Color) {
    Canvas(modifier = Modifier.size(width = 4.dp, height = 18.dp)) {
        val radius = 1.45.dp.toPx()
        val centerX = size.width / 2f
        val dotColor = color.copy(alpha = 0.78f)
        drawCircle(color = dotColor, radius = radius, center = Offset(centerX, radius))
        drawCircle(color = dotColor, radius = radius, center = Offset(centerX, size.height / 2f))
        drawCircle(color = dotColor, radius = radius, center = Offset(centerX, size.height - radius))
    }
}

@Composable
private fun ModeChip(name: String, onClick: () -> Unit) {
    Column(
        modifier = Modifier
            .clickable(onClick = onClick)
            .padding(vertical = 2.dp)
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = name,
                style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Medium),
                color = BlankOnSurface
            )
            Text(text = "⌄", color = BlankOnSurface, fontSize = 15.sp, modifier = Modifier.padding(start = 4.dp))
        }
    }
}

@Composable
private fun IconDots(onClick: () -> Unit) {
    TextButton(onClick = onClick, modifier = Modifier.size(44.dp)) {
        Text(text = "⋮", color = BlankOnSurface, fontSize = 24.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun SettingsPanel(
    buttonLight: Boolean,
    onBack: () -> Unit,
    onModes: () -> Unit,
    onSchedule: () -> Unit,
    onStats: () -> Unit,
    onEmergency: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(title = "Settings", onBack = onBack)
        Spacer(modifier = Modifier.height(58.dp))
        Text(text = "Settings", style = MaterialTheme.typography.headlineLarge, color = BlankOnSurface)
        Spacer(modifier = Modifier.height(28.dp))
        val items = buildList {
            add(MenuItem("Plan", "Apps", onModes))
            add(MenuItem("Timer", "Daily", onSchedule))
            add(MenuItem("Stats", "Time", onStats))
            add(MenuItem("Emergency", "Exit", onEmergency, destructive = true))
        }
        MenuList(
            buttonLight = buttonLight,
            items = items
        )
    }
}

private data class MenuItem(
    val label: String,
    val meta: String,
    val action: () -> Unit,
    val destructive: Boolean = false
)

@Composable
private fun MenuList(buttonLight: Boolean, items: List<MenuItem>) {
    val buttonBackground = if (buttonLight) Color.White else Color.Black
    val buttonContent = if (buttonLight) Color.Black else Color.White
    val metaColor = buttonContent.copy(alpha = 0.72f)
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        items.forEach { item ->
            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = buttonBackground,
                shape = RoundedCornerShape(22.dp),
                onClick = item.action
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 18.dp, vertical = 16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    val labelColor = if (item.destructive) Color(0xFFB3261E) else buttonContent
                    Text(text = item.label, color = labelColor, modifier = Modifier.weight(1f))
                    Text(text = item.meta, color = metaColor, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }
    }
}

@Composable
private fun StatsPanel(
    stats: FocusStats,
    emergencyUnlocksRemaining: Int,
    aiPlan: DigitalWellnessPlan,
    hasPremiumAccess: Boolean,
    healthConnectStore: HealthConnectStore,
    onTrack: (BlankEvent) -> Unit,
    onStartWearableOAuth: (String) -> Unit,
    buttonLight: Boolean,
    onBack: () -> Unit
) {
    val savedMs = estimatedSavedMs(stats)
    val insight = progressInsight(stats, savedMs)
    var showDetail by remember { mutableStateOf(false) }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            ScreenHeader(title = "Stats", onBack = onBack)
            Spacer(modifier = Modifier.height(38.dp))
        }
        item {
            ProgressMinimalHero(
                stats = stats,
                savedMs = savedMs,
                insight = insight,
                buttonLight = buttonLight
            )
        }
        item {
            WeeklySummaryCard(
                stats = stats,
                emergencyUnlocksRemaining = emergencyUnlocksRemaining,
                buttonLight = buttonLight
            )
        }
        item {
            DigitalWellnessReportCard(
                aiPlan = aiPlan,
                hasPremiumAccess = hasPremiumAccess,
                buttonLight = buttonLight
            )
        }
        item {
            HealthContextCard(
                aiPlan = aiPlan,
                healthConnectStore = healthConnectStore,
                onTrack = onTrack,
                onStartWearableOAuth = onStartWearableOAuth,
                buttonLight = buttonLight
            )
        }
        item {
            NextStepCard(
                stats = stats,
                buttonLight = buttonLight
            )
        }
        item {
            ProgressDetailCard(
                stats = stats,
                emergencyUnlocksRemaining = emergencyUnlocksRemaining,
                buttonLight = buttonLight,
                expanded = showDetail,
                onToggle = { showDetail = !showDetail }
            )
        }
    }
}

@Composable
private fun ProgressMinimalHero(
    stats: FocusStats,
    savedMs: Long,
    insight: String,
    buttonLight: Boolean
) {
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = Color.Transparent
    ) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Text(
                text = formatProtectedTime(savedMs),
                style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Medium),
                color = BlankOnSurface,
                textAlign = TextAlign.Center
            )
            Text(
                text = "tiempo recuperado",
                style = MaterialTheme.typography.bodyLarge,
                color = BlankOnSurface.copy(alpha = 0.68f),
                textAlign = TextAlign.Center
            )
            Text(
                text = insight,
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium),
                color = BlankOnSurface.copy(alpha = 0.74f),
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )
            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = if (buttonLight) Color.White.copy(alpha = 0.86f) else Color.Black.copy(alpha = 0.72f),
                shape = RoundedCornerShape(26.dp)
            ) {
                ProgressLineChart(
                    title = "Weekly trend",
                    values = savedChartValues(stats),
                    buttonLight = buttonLight,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(142.dp)
                        .padding(18.dp)
                )
            }
        }
    }
}

@Composable
private fun WeeklySummaryCard(
    stats: FocusStats,
    emergencyUnlocksRemaining: Int,
    buttonLight: Boolean
) {
    val rowColor = if (buttonLight) Color.White else Color.Black
    val textColor = progressTextColor(buttonLight)
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = rowColor,
        shape = RoundedCornerShape(22.dp)
    ) {
        Column(modifier = Modifier.padding(horizontal = 18.dp, vertical = 18.dp)) {
            Text(text = "This week", color = textColor, style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.height(12.dp))
            SummaryLine("Protected", formatProtectedTime(stats.protectedMsThisWeek), "Time in Blanked", textColor)
            ProgressDivider(textColor)
            SummaryLine("Sessions", stats.sessionsThisWeek.toString(), "Focus blocks", textColor)
            ProgressDivider(textColor)
            SummaryLine("Emergency", emergencyUnlocksRemaining.toString(), "Left", textColor)
        }
    }
}

@Composable
private fun DigitalWellnessReportCard(
    aiPlan: DigitalWellnessPlan,
    hasPremiumAccess: Boolean,
    buttonLight: Boolean
) {
    val rowColor = if (buttonLight) Color.White else Color.Black
    val textColor = progressTextColor(buttonLight)
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = rowColor,
        shape = RoundedCornerShape(22.dp)
    ) {
        Column(modifier = Modifier.padding(horizontal = 18.dp, vertical = 18.dp)) {
            Text(text = "Digital Wellness Report", color = textColor, style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.height(12.dp))
            SummaryLine("AI Focus Plan", aiPlan.archetype, aiPlan.primaryAction, textColor)
            ProgressDivider(textColor)
            SummaryLine("Early Risk", "${aiPlan.riskScore}/100", aiPlan.riskWindow, textColor)
            ProgressDivider(textColor)
            SummaryLine("Wellness Score", "${aiPlan.score}/100", aiPlan.reportInsight, textColor)
            if (!hasPremiumAccess) {
                ProgressDivider(textColor)
                Text(
                    text = "Pro includes AI reports, adaptive plans, Health insights and preventive alerts.",
                    color = textColor.copy(alpha = 0.64f),
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}

@Composable
private fun HealthContextCard(
    aiPlan: DigitalWellnessPlan,
    healthConnectStore: HealthConnectStore,
    onTrack: (BlankEvent) -> Unit,
    onStartWearableOAuth: (String) -> Unit,
    buttonLight: Boolean
) {
    val healthSummary by healthConnectStore.summary.collectAsState()
    val scope = rememberCoroutineScope()
    var oauthError by remember { mutableStateOf<String?>(null) }
    val launcher = rememberLauncherForActivityResult(
        PermissionController.createRequestPermissionResultContract()
    ) {
        healthConnectStore.refresh()
        val grantedCount = it.size
        if (grantedCount > 0) {
            onTrack(
                BlankEvent(
                    BlankEvents.WEARABLE_CONNECTED,
                    mapOf(
                        "provider" to "health_connect",
                        "granted_count" to grantedCount.toString()
                    )
                )
            )
            onTrack(
                BlankEvent(
                    BlankEvents.PERMISSION_GRANTED,
                    mapOf(
                        "source" to "health_connect",
                        "permission" to "health",
                        "granted_count" to grantedCount.toString()
                    )
                )
            )
        }
    }
    val rowColor = if (buttonLight) Color.White else Color.Black
    val textColor = progressTextColor(buttonLight)
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = rowColor,
        shape = RoundedCornerShape(22.dp)
    ) {
        Column(modifier = Modifier.padding(horizontal = 18.dp, vertical = 18.dp)) {
            Text(
                text = "Health Sources",
                color = textColor,
                style = MaterialTheme.typography.titleMedium
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = aiPlan.healthContext,
                color = textColor.copy(alpha = 0.66f),
                style = MaterialTheme.typography.bodyMedium
            )
            if (healthSummary.permissionGranted) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "${healthSourceStatus(healthSummary)} · ${healthSummary.daysWithAnySignal}/${healthSummary.daysRequested} days · ${healthSummary.recoveryTrend}",
                    color = textColor.copy(alpha = 0.52f),
                    style = MaterialTheme.typography.bodySmall
                )
            } else if (healthSummary.partialPermission) {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Partial permission · ${healthSummary.grantedPermissionCount}/${healthSummary.requestedPermissionCount} signals",
                    color = textColor.copy(alpha = 0.52f),
                    style = MaterialTheme.typography.bodySmall
                )
            }
            Spacer(modifier = Modifier.height(12.dp))
            WearableProviderList(
                healthSummary = healthSummary,
                textColor = textColor,
                onConnect = { provider ->
                    oauthError = null
                    onTrack(BlankEvent(BlankEvents.WEARABLE_CONNECT_STARTED, mapOf("provider" to provider)))
                    scope.launch {
                        runCatching {
                            withContext(Dispatchers.IO) { onStartWearableOAuth(provider) }
                        }.onFailure { error ->
                            oauthError = if (provider == "garmin") "Garmin requires partner access." else error.message?.take(90)
                        }
                    }
                }
            )
            oauthError?.let {
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = it,
                    color = textColor.copy(alpha = 0.58f),
                    style = MaterialTheme.typography.bodySmall
                )
            }
            Spacer(modifier = Modifier.height(12.dp))
            Surface(
                color = textColor,
                contentColor = if (buttonLight) Color.White else Color.Black,
                shape = RoundedCornerShape(999.dp),
                onClick = {
                    onTrack(
                        BlankEvent(
                            BlankEvents.WEARABLE_CONNECT_STARTED,
                            mapOf("provider" to "health_connect")
                        )
                    )
                    onTrack(
                        BlankEvent(
                            BlankEvents.PERMISSION_REQUESTED,
                            mapOf("source" to "health_connect", "permission" to "health")
                        )
                    )
                    launcher.launch(healthConnectStore.permissions)
                }
            ) {
                Text(
                    text = if (healthSummary.permissionGranted) "Refresh Health" else "Connect Health",
                    style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold),
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 9.dp)
                )
            }
        }
    }
}

@Composable
private fun WearableProviderList(
    healthSummary: com.blanknfc.app.data.HealthConnectSummary,
    textColor: Color,
    onConnect: (String) -> Unit
) {
    val providers = listOf(
        WearableProvider("Health Connect", "health_connect", healthSourceStatus(healthSummary), "Sleep, activity, heart and recovery context.", false),
        WearableProvider("Oura", "oura", "Connect", "Readiness, sleep contributors and recovery signals.", true),
        WearableProvider("WHOOP", "whoop", "Connect", "Recovery, strain, sleep debt and cycle signals.", true),
        WearableProvider("Garmin", "garmin", "Partner gated", "Body Battery, stress, training readiness and HRV status.", false),
        WearableProvider("Google Health / Fitbit", "fitbit_google_health", "Connect", "Fitbit, Pixel Watch and Google Health metrics.", true),
        WearableProvider("Withings", "withings", "Connect", "Weight, body composition, blood pressure and temperature context.", true)
    )
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        providers.forEach { provider ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(enabled = provider.canConnect) { onConnect(provider.id) },
                verticalAlignment = Alignment.Top
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = provider.name,
                        color = textColor.copy(alpha = 0.86f),
                        style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.SemiBold)
                    )
                    Text(
                        text = provider.detail,
                        color = textColor.copy(alpha = 0.52f),
                        style = MaterialTheme.typography.bodySmall
                    )
                }
                Text(
                    text = provider.status,
                    color = textColor.copy(alpha = 0.58f),
                    style = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.SemiBold)
                )
            }
        }
    }
}

private data class WearableProvider(
    val name: String,
    val id: String,
    val status: String,
    val detail: String,
    val canConnect: Boolean
)

private fun healthSourceStatus(summary: com.blanknfc.app.data.HealthConnectSummary): String {
    return when {
        !summary.available -> "Unavailable"
        summary.partialPermission -> "Partial"
        !summary.permissionGranted -> "Not connected"
        summary.latestSignalAgeHours != null && summary.latestSignalAgeHours > 72 -> "Stale"
        summary.daysWithAnySignal == 0 -> "No data"
        else -> "Connected"
    }
}

@Composable
private fun NextStepCard(stats: FocusStats, buttonLight: Boolean) {
    val rowColor = if (buttonLight) Color.White else Color.Black
    val textColor = progressTextColor(buttonLight)
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = rowColor,
        shape = RoundedCornerShape(22.dp)
    ) {
        Column(modifier = Modifier.padding(horizontal = 18.dp, vertical = 18.dp)) {
            Text(text = "Next improvement", color = textColor, style = MaterialTheme.typography.titleMedium)
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = nextStepText(stats),
                color = textColor.copy(alpha = 0.66f),
                style = MaterialTheme.typography.bodyMedium
            )
        }
    }
}

@Composable
private fun ProgressDetailCard(
    stats: FocusStats,
    emergencyUnlocksRemaining: Int,
    buttonLight: Boolean,
    expanded: Boolean,
    onToggle: () -> Unit
) {
    val rowColor = if (buttonLight) Color.White else Color.Black
    val textColor = progressTextColor(buttonLight)
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = rowColor,
        shape = RoundedCornerShape(22.dp),
        onClick = onToggle
    ) {
        Column(modifier = Modifier.padding(horizontal = 18.dp, vertical = 16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = "View details",
                    color = textColor,
                    style = MaterialTheme.typography.bodyLarge.copy(fontWeight = FontWeight.Medium),
                    modifier = Modifier.weight(1f)
                )
                Text(
                    text = if (expanded) "Hide" else "Open",
                    color = textColor.copy(alpha = 0.58f),
                    style = MaterialTheme.typography.bodySmall
                )
            }
            if (expanded) {
                Spacer(modifier = Modifier.height(10.dp))
                SummaryLine("Blanked time", formatProtectedTime(stats.totalProtectedMs), "Total protected", textColor)
                ProgressDivider(textColor)
                SummaryLine("Best day", bestDayValue(stats.activityDays), bestDayCaption(stats.activityDays), textColor)
                ProgressDivider(textColor)
                SummaryLine("Unlocks used", "${usedEmergencyUnlocks(emergencyUnlocksRemaining)}/3", emergencyCaption(emergencyUnlocksRemaining), textColor)
                ProgressDivider(textColor)
                SummaryLine("Urges stopped", stats.blockedAttemptsThisWeek.toString(), "Pauses created this week", textColor)
            }
        }
    }
}

@Composable
private fun SummaryLine(label: String, value: String, caption: String, textColor: Color) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(text = label, color = textColor, style = MaterialTheme.typography.bodyLarge)
            Text(text = caption, color = textColor.copy(alpha = 0.62f), style = MaterialTheme.typography.bodySmall)
        }
        Text(text = value, color = textColor, style = MaterialTheme.typography.titleLarge)
    }
}

@Composable
private fun ProgressDivider(textColor: Color) {
    Spacer(
        modifier = Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(textColor.copy(alpha = 0.08f))
    )
}

@Composable
private fun ProgressHeroCarousel(
    selectedPage: Int,
    onPageChange: (Int) -> Unit,
    stats: FocusStats,
    savedMs: Long,
    buttonLight: Boolean
) {
    val values = if (selectedPage == 0) {
        savedChartValues(stats)
    } else {
        focusChartValues(stats.activityDays, stats.protectedMsThisWeek)
    }
    val label = if (selectedPage == 0) "Time saved" else "Time in Blanked"
    val value = if (selectedPage == 0) formatProtectedTime(savedMs) else formatProtectedTime(stats.totalProtectedMs)
    val description = if (selectedPage == 0) "Recovered from your life with Blanked" else "Protected with Blanked"
    val chartTitle = if (selectedPage == 0) "Estimated saved" else "Blanked mode"

    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = if (buttonLight) Color.White.copy(alpha = 0.86f) else Color.Black.copy(alpha = 0.72f),
        shape = RoundedCornerShape(26.dp)
    ) {
        Column(
            modifier = Modifier.padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ProgressTab("Time saved", selectedPage == 0, buttonLight) { onPageChange(0) }
                ProgressTab("Time in Blanked", selectedPage == 1, buttonLight) { onPageChange(1) }
            }
            Text(
                text = label,
                style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Medium),
                color = progressTextColor(buttonLight).copy(alpha = 0.64f)
            )
            Text(
                text = value,
                style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Medium),
                color = progressTextColor(buttonLight)
            )
            Text(
                text = description,
                style = MaterialTheme.typography.bodyMedium,
                color = progressTextColor(buttonLight).copy(alpha = 0.68f)
            )
            ProgressLineChart(
                title = chartTitle,
                values = values,
                buttonLight = buttonLight,
                modifier = Modifier
                    .fillMaxWidth()
                    .height(150.dp)
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.Center
            ) {
                ProgressDot(active = selectedPage == 0, buttonLight = buttonLight)
                Spacer(modifier = Modifier.size(7.dp))
                ProgressDot(active = selectedPage == 1, buttonLight = buttonLight)
            }
        }
    }
}

@Composable
private fun ProgressTab(text: String, selected: Boolean, buttonLight: Boolean, onClick: () -> Unit) {
    Surface(
        color = if (selected) progressTextColor(buttonLight) else progressTextColor(buttonLight).copy(alpha = 0.08f),
        contentColor = if (selected) {
            if (buttonLight) Color.White else Color.Black
        } else {
            progressTextColor(buttonLight).copy(alpha = 0.72f)
        },
        shape = RoundedCornerShape(999.dp),
        onClick = onClick
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Medium),
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp)
        )
    }
}

@Composable
private fun ProgressDot(active: Boolean, buttonLight: Boolean) {
    val color = progressTextColor(buttonLight)
    Canvas(modifier = Modifier.size(width = if (active) 18.dp else 6.dp, height = 6.dp)) {
        drawRoundRect(
            color = color.copy(alpha = if (active) 0.8f else 0.2f),
            cornerRadius = androidx.compose.ui.geometry.CornerRadius(size.height / 2f, size.height / 2f)
        )
    }
}

@Composable
private fun ProgressLineChart(title: String, values: List<Long>, buttonLight: Boolean, modifier: Modifier = Modifier) {
    val textColor = progressTextColor(buttonLight)
    val scale = roundedChartScale(values.maxOrNull() ?: 0L)
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(text = title, style = MaterialTheme.typography.bodySmall, color = textColor.copy(alpha = 0.58f), modifier = Modifier.weight(1f))
            Text(text = formatProtectedTime(scale), style = MaterialTheme.typography.bodySmall, color = textColor.copy(alpha = 0.46f))
        }
        Canvas(modifier = Modifier.fillMaxSize()) {
            val left = 2.dp.toPx()
            val right = size.width - 2.dp.toPx()
            val top = 10.dp.toPx()
            val bottom = size.height - 10.dp.toPx()
            val maxValue = scale.coerceAtLeast(1L).toFloat()
            val points = values.ifEmpty { listOf(0L) }
            for (i in 0..2) {
                val y = top + ((bottom - top) * i / 2f)
                drawLine(
                    color = textColor.copy(alpha = 0.08f),
                    start = Offset(left, y),
                    end = Offset(right, y),
                    strokeWidth = 1.dp.toPx()
                )
            }
            if (points.size == 1) {
                val y = bottom - ((points.first().toFloat() / maxValue) * (bottom - top))
                drawCircle(color = textColor.copy(alpha = 0.84f), radius = 3.dp.toPx(), center = Offset(left, y))
            } else {
                val step = (right - left) / (points.size - 1).coerceAtLeast(1)
                val offsets = points.mapIndexed { index, value ->
                    val x = left + step * index
                    val y = bottom - ((value.toFloat() / maxValue) * (bottom - top))
                    Offset(x, y)
                }
                offsets.zipWithNext().forEach { (start, end) ->
                    drawLine(
                        color = textColor.copy(alpha = 0.84f),
                        start = start,
                        end = end,
                        strokeWidth = 2.dp.toPx(),
                        cap = StrokeCap.Round
                    )
                }
                offsets.forEach { point ->
                    drawCircle(color = textColor.copy(alpha = 0.9f), radius = 2.5.dp.toPx(), center = point)
                }
            }
        }
    }
}

@Composable
private fun ProgressPeriodGrid(
    stats: FocusStats,
    buttonLight: Boolean
) {
    val summaries = progressPeriodSummaries(stats)
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        summaries.chunked(2).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.fillMaxWidth()) {
                row.forEach { summary ->
                    PeriodCard(
                        summary = summary,
                        buttonLight = buttonLight,
                        modifier = Modifier.weight(1f)
                    )
                }
                if (row.size == 1) {
                    Spacer(modifier = Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun PeriodCard(
    summary: ProgressPeriodSummary,
    buttonLight: Boolean,
    modifier: Modifier = Modifier
) {
    val rowColor = if (buttonLight) Color.White else Color.Black
    val textColor = if (buttonLight) Color.Black else Color.White
    Surface(
        modifier = modifier,
        color = rowColor,
        shape = RoundedCornerShape(22.dp)
    ) {
        Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 14.dp)) {
            Text(text = summary.label, color = textColor.copy(alpha = 0.62f), style = MaterialTheme.typography.bodySmall)
            Spacer(modifier = Modifier.height(6.dp))
            Text(text = summary.value, color = textColor, style = MaterialTheme.typography.titleLarge)
            Spacer(modifier = Modifier.height(2.dp))
            Text(text = summary.caption, color = textColor.copy(alpha = 0.62f), style = MaterialTheme.typography.bodySmall)
        }
    }
}

@Composable
private fun ProgressInsightCards(
    stats: FocusStats,
    emergencyUnlocksRemaining: Int,
    buttonLight: Boolean
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        StatRow(
            label = "Risk moment",
            value = riskMomentValue(stats),
            caption = riskMomentCaption(stats),
            buttonLight = buttonLight
        )
        StatRow(
            label = "Protection quality",
            value = "${protectionQualityScore(stats, emergencyUnlocksRemaining)}/100",
            caption = protectionQualityCaption(stats, emergencyUnlocksRemaining),
            buttonLight = buttonLight
        )
        StatRow(
            label = "Control recovered",
            value = controlRecoveryValue(stats, emergencyUnlocksRemaining),
            caption = controlRecoveryCaption(stats, emergencyUnlocksRemaining),
            buttonLight = buttonLight
        )
    }
}

@Composable
private fun ProgressMetricList(
    stats: FocusStats,
    emergencyUnlocksRemaining: Int,
    buttonLight: Boolean
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        StatRow("Sessions", stats.sessionsThisWeek.toString(), "Completed", buttonLight)
        StatRow("Average protected", formatProtectedTime(averageSessionMs(stats)), "Per real session", buttonLight)
        StatRow("Streak", "${currentStreakDays(stats.activityDays)}d", "Days with Blanked", buttonLight)
        StatRow("Best day", bestDayValue(stats.activityDays), bestDayCaption(stats.activityDays), buttonLight)
        StatRow("Urges stopped", stats.blockedAttemptsThisWeek.toString(), "Times Blanked created a pause", buttonLight)
        StatRow("Emergency", "${usedEmergencyUnlocks(emergencyUnlocksRemaining)}/3", emergencyCaption(emergencyUnlocksRemaining), buttonLight)
    }
}

@Composable
private fun StatRow(label: String, value: String, caption: String, buttonLight: Boolean) {
    val rowColor = if (buttonLight) Color.White else Color.Black
    val textColor = if (buttonLight) Color.Black else Color.White
    val metaColor = textColor.copy(alpha = 0.64f)
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = rowColor,
        shape = RoundedCornerShape(22.dp)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 18.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(text = label, color = textColor, style = MaterialTheme.typography.bodyLarge)
                Text(text = caption, color = metaColor, style = MaterialTheme.typography.bodySmall)
            }
            Text(text = value, color = textColor, style = MaterialTheme.typography.titleLarge)
        }
    }
}

@Composable
private fun SchedulePanel(
    schedule: FocusSchedule,
    buttonLight: Boolean,
    onBack: () -> Unit,
    onSave: (FocusSchedule) -> Unit
) {
    var enabled by remember(schedule) { mutableStateOf(schedule.enabled) }
    var startMinute by remember(schedule) { mutableStateOf(schedule.startMinute) }
    var endMinute by remember(schedule) { mutableStateOf(schedule.endMinute) }

    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(title = "Timer", onBack = onBack)
        Spacer(modifier = Modifier.height(46.dp))
        Text(text = "Daily window", style = MaterialTheme.typography.headlineLarge, color = BlankOnSurface)
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Blanked can turn on automatically during this window. Emergency unlock stays available when needed.",
            style = MaterialTheme.typography.bodyLarge,
            color = BlankOnSurface
        )
        Spacer(modifier = Modifier.height(24.dp))
        ToggleRow(
            label = "Enable daily schedule",
            checked = enabled,
            buttonLight = buttonLight,
            onCheckedChange = { enabled = it }
        )
        Spacer(modifier = Modifier.height(10.dp))
        TimeDropdown(label = "Start", minute = startMinute, buttonLight = buttonLight, onMinuteChange = { startMinute = it })
        Spacer(modifier = Modifier.height(10.dp))
        TimeDropdown(label = "End", minute = endMinute, buttonLight = buttonLight, onMinuteChange = { endMinute = it })
        Spacer(modifier = Modifier.height(16.dp))
        Surface(
            modifier = Modifier.fillMaxWidth(),
            color = if (buttonLight) Color.White.copy(alpha = 0.86f) else Color.Black,
            shape = RoundedCornerShape(22.dp)
        ) {
            Column(modifier = Modifier.padding(horizontal = 18.dp, vertical = 16.dp)) {
                Text(
                    text = "Active window",
                    color = progressTextColor(buttonLight).copy(alpha = 0.62f),
                    style = MaterialTheme.typography.bodySmall
                )
                Spacer(modifier = Modifier.height(6.dp))
                Text(
                    text = "${formatMinute(startMinute)} - ${formatMinute(endMinute)}",
                    color = progressTextColor(buttonLight),
                    style = MaterialTheme.typography.titleLarge
                )
            }
        }
        Spacer(modifier = Modifier.weight(1f))
        MainActionButton(
            text = "Save schedule",
            light = buttonLight,
            onClick = {
                onSave(
                    FocusSchedule(
                        enabled = enabled,
                        startMinute = startMinute,
                        endMinute = endMinute
                    )
                )
            }
        )
    }
}

@Composable
private fun ToggleRow(
    label: String,
    checked: Boolean,
    buttonLight: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    val rowColor = if (buttonLight) Color.White else Color.Black
    val textColor = if (buttonLight) Color.Black else Color.White
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = rowColor,
        shape = RoundedCornerShape(22.dp)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 18.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(text = label, color = textColor, modifier = Modifier.weight(1f))
            Switch(checked = checked, onCheckedChange = onCheckedChange)
        }
    }
}

@Composable
private fun TimeDropdown(
    label: String,
    minute: Int,
    buttonLight: Boolean,
    onMinuteChange: (Int) -> Unit
) {
    var expanded by remember { mutableStateOf(false) }
    val rowColor = if (buttonLight) Color.White else Color.Black
    val textColor = if (buttonLight) Color.Black else Color.White
    Box {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { expanded = true },
            color = rowColor,
            shape = RoundedCornerShape(22.dp)
        ) {
            Row(
                modifier = Modifier.padding(horizontal = 18.dp, vertical = 16.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(text = label, color = textColor, modifier = Modifier.weight(1f))
                Text(text = formatMinute(minute), color = textColor, style = MaterialTheme.typography.titleMedium)
                Text(text = "⌄", color = textColor.copy(alpha = 0.62f), modifier = Modifier.padding(start = 8.dp))
            }
        }
        DropdownMenu(expanded = expanded, onDismissRequest = { expanded = false }) {
            timeOptions().forEach { option ->
                DropdownMenuItem(
                    text = { Text(formatMinute(option)) },
                    onClick = {
                        onMinuteChange(option)
                        expanded = false
                    }
                )
            }
        }
    }
}

@Composable
private fun ModesPanel(
    modes: List<BlankMode>,
    currentModeId: String,
    buttonLight: Boolean,
    onBack: () -> Unit,
    onSelect: (String) -> Unit,
    onCreate: () -> Unit,
    onRename: (String, String) -> Unit,
    onEditApps: (BlankMode) -> Unit,
    onDelete: (String) -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(title = "Plan", onBack = onBack)
        Spacer(modifier = Modifier.height(46.dp))
        Text(text = "Choose a mode", style = MaterialTheme.typography.headlineLarge, color = BlankOnSurface)
        Spacer(modifier = Modifier.height(24.dp))
        LazyColumn(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            items(modes, key = { it.id }) { mode ->
                ModeRow(
                    mode = mode,
                    selected = mode.id == currentModeId,
                    canDelete = modes.size > 1,
                    buttonLight = buttonLight,
                    onSelect = { onSelect(mode.id) },
                    onRename = { name -> onRename(mode.id, name) },
                    onEditApps = { onEditApps(mode) },
                    onDelete = { onDelete(mode.id) }
                )
            }
        }
        MainActionButton(text = "Create mode", light = buttonLight, onClick = onCreate)
    }
}

@Composable
private fun ModeRow(
    mode: BlankMode,
    selected: Boolean,
    canDelete: Boolean,
    buttonLight: Boolean,
    onSelect: () -> Unit,
    onRename: (String) -> Unit,
    onEditApps: () -> Unit,
    onDelete: () -> Unit
) {
    var menuOpen by remember { mutableStateOf(false) }
    var editing by remember { mutableStateOf(false) }
    var name by remember(mode.id, mode.name) { mutableStateOf(mode.name) }
    val rowColor = if (buttonLight) Color.White else Color.Black
    val textColor = if (buttonLight) Color.Black else Color.White
    val metaColor = textColor.copy(alpha = 0.72f)
    val border = if (selected) BorderStroke(1.5.dp, textColor) else null

    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = rowColor,
        shape = RoundedCornerShape(22.dp),
        border = border,
        onClick = {
            if (!editing) onSelect()
        }
    ) {
        Column(modifier = Modifier.padding(horizontal = 18.dp, vertical = 16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (editing) {
                    OutlinedTextField(
                        value = name,
                        onValueChange = { name = it },
                        singleLine = true,
                        modifier = Modifier.weight(1f),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedContainerColor = Color.Transparent,
                            unfocusedContainerColor = Color.Transparent,
                            focusedTextColor = textColor,
                            unfocusedTextColor = textColor,
                            focusedBorderColor = metaColor,
                            unfocusedBorderColor = metaColor
                        )
                    )
                } else {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(text = mode.name, color = textColor, style = MaterialTheme.typography.bodyLarge)
                        Text(text = "${mode.packages.size} apps", color = metaColor, style = MaterialTheme.typography.bodyMedium)
                    }
                }
                Box {
                    TextButton(onClick = { menuOpen = true }) {
                        Text(text = "⋮", color = textColor, fontSize = 22.sp, fontWeight = FontWeight.Medium)
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text("Edit name") },
                            onClick = {
                                menuOpen = false
                                editing = true
                                onSelect()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Edit apps") },
                            onClick = {
                                menuOpen = false
                                onSelect()
                                onEditApps()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Delete") },
                            enabled = canDelete,
                            onClick = {
                                menuOpen = false
                                onDelete()
                            }
                        )
                    }
                }
            }
            if (editing) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 12.dp)) {
                    TextButton(
                        onClick = {
                            onRename(name)
                            editing = false
                        }
                    ) {
                        Text("Save", color = textColor)
                    }
                    TextButton(
                        onClick = {
                            name = mode.name
                            editing = false
                        }
                    ) {
                        Text("Cancel", color = metaColor)
                    }
                }
            }
        }
    }
}

@Composable
private fun ModeAppsDialog(
    mode: BlankMode,
    apps: List<AppInfo>,
    buttonLight: Boolean,
    onDismiss: () -> Unit,
    onSave: (Set<String>) -> Unit
) {
    var selected by remember(mode.id) { mutableStateOf(mode.packages) }
    ModeSetupDialog(
        title = "Edit apps",
        name = mode.name,
        apps = apps,
        selected = selected,
        onSelectedChange = { selected = it },
        buttonLight = buttonLight,
        onDismiss = onDismiss,
        onPrimary = { onSave(selected) },
        primaryText = "Save apps"
    )
}

@Composable
private fun CreateModeDialog(
    apps: List<AppInfo>,
    buttonLight: Boolean,
    onDismiss: () -> Unit,
    onCreate: (String, Set<String>) -> Unit
) {
    var name by remember { mutableStateOf("") }
    var selected by remember { mutableStateOf(emptySet<String>()) }
    ModeSetupDialog(
        title = "Set up mode",
        name = name,
        nameEditable = true,
        apps = apps,
        selected = selected,
        onNameChange = { name = it },
        onSelectedChange = { selected = it },
        buttonLight = buttonLight,
        onDismiss = onDismiss,
        onPrimary = { onCreate(name, selected) },
        primaryText = "Save mode"
    )
}

@Composable
private fun ModeSetupDialog(
    title: String,
    name: String,
    apps: List<AppInfo>,
    selected: Set<String>,
    onSelectedChange: (Set<String>) -> Unit,
    buttonLight: Boolean,
    onDismiss: () -> Unit,
    onPrimary: () -> Unit,
    primaryText: String,
    nameEditable: Boolean = false,
    onNameChange: (String) -> Unit = {}
) {
    Dialog(onDismissRequest = onDismiss) {
        Surface(color = BlankSurface, shape = RoundedCornerShape(28.dp)) {
            Column(modifier = Modifier.padding(20.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(text = title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                    TextButton(onClick = onDismiss) { Text("×", fontSize = 22.sp, color = BlankOnSurface) }
                }
                Spacer(modifier = Modifier.height(10.dp))
                if (nameEditable) {
                    OutlinedTextField(
                        value = name,
                        onValueChange = onNameChange,
                        label = { Text("Name") },
                        placeholder = { Text("Deep work") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                } else {
                    Text(text = name, style = MaterialTheme.typography.bodyLarge, color = BlankGray)
                }
                Spacer(modifier = Modifier.height(12.dp))
                AppPickerContent(
                    apps = apps,
                    selected = selected,
                    onSelectedChange = onSelectedChange,
                    listMaxHeight = 360.dp
                )
                Spacer(modifier = Modifier.height(14.dp))
                MainActionButton(text = primaryText, light = buttonLight, onClick = onPrimary)
            }
        }
    }
}

@Composable
private fun TextPanel(
    title: String,
    backLabel: String,
    onBack: () -> Unit,
    blocks: List<Pair<String, String>>
) {
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(title = title, backLabel = backLabel, onBack = onBack)
        Spacer(modifier = Modifier.height(52.dp))
        Column(verticalArrangement = Arrangement.spacedBy(24.dp)) {
            blocks.forEach { (heading, body) ->
                Column {
                    Text(text = heading, style = MaterialTheme.typography.headlineMedium, color = BlankOnSurface)
                    Spacer(modifier = Modifier.height(8.dp))
                    Text(text = body, style = MaterialTheme.typography.bodyLarge, color = BlankOnSurface)
                }
            }
        }
    }
}

@Composable
private fun CenterActionPanel(
    topTitle: String,
    label: String,
    title: String,
    body: String,
    action: String,
    buttonLight: Boolean,
    onBack: () -> Unit,
    onAction: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(title = topTitle, onBack = onBack)
        Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(text = label, color = BlankOnSurface, style = MaterialTheme.typography.labelLarge)
                Spacer(modifier = Modifier.height(12.dp))
                Text(text = title, style = MaterialTheme.typography.headlineLarge, color = BlankOnSurface, textAlign = TextAlign.Center)
                Spacer(modifier = Modifier.height(12.dp))
                Text(text = body, style = MaterialTheme.typography.bodyLarge, color = BlankOnSurface, textAlign = TextAlign.Center)
            }
        }
        MainActionButton(text = action, light = buttonLight, onClick = onAction)
    }
}

@Composable
private fun ForgetConfirmPanel(
    buttonLight: Boolean,
    onBack: () -> Unit,
    onConfirm: () -> Unit
) {
    var confirmed by remember { mutableStateOf(false) }
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(title = "Reset NFC", onBack = onBack)
        Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(text = "Confirmation", color = BlankOnSurface, style = MaterialTheme.typography.labelLarge)
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = "Forget my Blanked key.",
                    style = MaterialTheme.typography.headlineLarge,
                    color = BlankOnSurface,
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = "Blanked will turn off, the optional key will be removed, and onboarding will restart.",
                    style = MaterialTheme.typography.bodyLarge,
                    color = BlankOnSurface,
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.height(18.dp))
                Surface(color = if (buttonLight) Color.White else Color.Black, shape = RoundedCornerShape(22.dp)) {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { confirmed = !confirmed }
                            .padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Checkbox(checked = confirmed, onCheckedChange = { confirmed = it })
                        Text(
                            text = "I understand I will need to pair Blanked again.",
                            color = progressTextColor(buttonLight),
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
            }
        }
        MainActionButton(
            text = "Yes, forget Blanked",
            enabled = confirmed,
            light = buttonLight,
            onClick = onConfirm
        )
    }
}

@Composable
private fun BlockPanel(onEmergency: () -> Unit) {
    Column(modifier = Modifier.fillMaxSize()) {
        Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(text = "Instagram", color = BlankSurface.copy(alpha = 0.72f), style = MaterialTheme.typography.labelLarge)
                Spacer(modifier = Modifier.height(12.dp))
                Text(text = "App blocked", style = MaterialTheme.typography.headlineLarge, color = BlankSurface, textAlign = TextAlign.Center)
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = stringResource(R.string.block_message),
                    style = MaterialTheme.typography.bodyLarge,
                    color = BlankSurface.copy(alpha = 0.72f),
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = stringResource(R.string.block_reinforcement),
                    style = MaterialTheme.typography.bodyMedium,
                    color = BlankSurface.copy(alpha = 0.54f),
                    textAlign = TextAlign.Center
                )
            }
        }
        TextButton(onClick = onEmergency, modifier = Modifier.align(Alignment.CenterHorizontally)) {
            Text(text = stringResource(R.string.emergency_start), color = BlankSurface.copy(alpha = 0.74f))
        }
    }
}

@Composable
private fun EmergencyPanel(
    emergencyUnlocksRemaining: Int,
    onBack: () -> Unit,
    onUnlock: () -> Unit
) {
    var phrase by remember { mutableStateOf("") }
    val expected = stringResource(R.string.emergency_phrase)
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(title = "Emergency", onBack = onBack, dark = true)
        Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(text = "Unlock", color = BlankSurface.copy(alpha = 0.72f), style = MaterialTheme.typography.labelLarge)
                Spacer(modifier = Modifier.height(12.dp))
                Text(text = "Type the full phrase.", style = MaterialTheme.typography.headlineLarge, color = BlankSurface, textAlign = TextAlign.Center)
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = if (emergencyUnlocksRemaining > 0)
                        "$emergencyUnlocksRemaining emergency unlocks left this week."
                    else
                        "You have used all 3 emergency unlocks this week.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = BlankSurface.copy(alpha = 0.72f),
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.height(16.dp))
                Text(text = expected, style = MaterialTheme.typography.bodyLarge, color = BlankSurface.copy(alpha = 0.72f), textAlign = TextAlign.Center)
                Spacer(modifier = Modifier.height(16.dp))
                OutlinedTextField(
                    value = phrase,
                    onValueChange = { phrase = it },
                    modifier = Modifier.fillMaxWidth(),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedTextColor = BlankSurface,
                        unfocusedTextColor = BlankSurface,
                        focusedBorderColor = BlankSurface.copy(alpha = 0.64f),
                        unfocusedBorderColor = BlankSurface.copy(alpha = 0.32f)
                    )
                )
            }
        }
        MainActionButton(
            text = stringResource(R.string.emergency_unlock),
            light = true,
            enabled = emergencyUnlocksRemaining > 0 && phrase.trim() == expected,
            onClick = onUnlock
        )
    }
}

@Composable
private fun ScreenHeader(
    title: String,
    backLabel: String = "Back",
    onBack: () -> Unit,
    dark: Boolean = false
) {
    val color = if (dark) BlankSurface else BlankOnSurface
    Row(modifier = Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .height(44.dp)
                .clickable(onClick = onBack),
            contentAlignment = Alignment.CenterStart
        ) {
            Text(text = backLabel, color = color, style = MaterialTheme.typography.bodyLarge)
        }
        Text(
            text = title,
            color = color,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.weight(1f),
            textAlign = TextAlign.End
        )
    }
}

@Composable
private fun HomeBlankearButton(
    text: String,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    val capsuleReflection = homeCapsuleReflection(center = Offset(34f, 8f), radius = 132f)
    Surface(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(999.dp),
        color = HomeGlassScrim,
        contentColor = Color.White,
        border = homeCapsuleBorder(),
        modifier = modifier
            .fillMaxWidth()
            .height(47.dp)
            .shadow(
                elevation = 5.dp,
                shape = RoundedCornerShape(999.dp),
                ambientColor = Color.Black.copy(alpha = 0.05f),
                spotColor = Color.Black.copy(alpha = 0.04f)
            )
            .background(capsuleReflection, RoundedCornerShape(999.dp))
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(capsuleReflection, RoundedCornerShape(999.dp)),
            contentAlignment = Alignment.Center
        ) {
            Text(text = text, style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold))
        }
    }
}

@Composable
private fun MainActionButton(
    text: String,
    enabled: Boolean = true,
    light: Boolean = false,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(999.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = if (light) Color.White else Color.Black,
            contentColor = if (light) Color.Black else Color.White,
            disabledContainerColor = Color(0xFFD8D8D5),
            disabledContentColor = BlankGray
        ),
        modifier = modifier
            .fillMaxWidth()
            .height(54.dp)
            .shadow(
                elevation = if (enabled) 14.dp else 0.dp,
                shape = RoundedCornerShape(999.dp),
                ambientColor = Color.Black.copy(alpha = 0.12f),
                spotColor = Color.Black.copy(alpha = 0.12f)
            )
    ) {
        Text(text = text, style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Medium))
    }
}

private fun formatProtectedTime(ms: Long): String {
    val totalMinutes = (ms / 60000L).coerceAtLeast(0L)
    val hours = totalMinutes / 60
    val minutes = totalMinutes % 60
    return when {
        hours > 0L && minutes > 0L -> "${hours}h ${minutes}m"
        hours > 0L -> "${hours}h"
        else -> "${minutes}m"
    }
}

private fun estimatedSavedMs(stats: FocusStats): Long {
    val estimated = stats.totalSessions * 15L * 60L * 1000L
    return estimated.coerceAtMost(stats.totalProtectedMs).coerceAtLeast(0L)
}

private fun savedTimeExplanation(stats: FocusStats): String {
    val saved = formatProtectedTime(estimatedSavedMs(stats))
    val protected = formatProtectedTime(stats.totalProtectedMs)
    return "Time saved: $saved estimated from completed sessions, capped at $protected real time in Blanked."
}

private fun averageSessionMs(stats: FocusStats): Long {
    if (stats.sessionsThisWeek <= 0) return 0L
    return stats.protectedMsThisWeek / stats.sessionsThisWeek
}

private fun focusChartValues(days: List<FocusActivityDay>, fallbackWeekMs: Long): List<Long> {
    val values = days.sortedBy { it.key }.takeLast(28).map { it.protectedMs }
    return values.ifEmpty { listOf(fallbackWeekMs) }
}

private fun savedChartValues(stats: FocusStats): List<Long> {
    val values = stats.activityDays.sortedBy { it.key }.takeLast(28).map { day ->
        (day.sessions * 15L * 60L * 1000L).coerceAtMost(day.protectedMs)
    }
    return values.ifEmpty { listOf(estimatedSavedMs(stats)) }
}

private fun progressPeriodSummaries(stats: FocusStats): List<ProgressPeriodSummary> {
    val calendar = Calendar.getInstance().apply {
        firstDayOfWeek = Calendar.MONDAY
        minimalDaysInFirstWeek = 4
    }
    val todayOrdinal = calendar.get(Calendar.YEAR) * 400 + calendar.get(Calendar.DAY_OF_YEAR)
    val monthStartOrdinal = startOrdinal(calendar, Calendar.DAY_OF_MONTH)
    val yearStartOrdinal = calendar.get(Calendar.YEAR) * 400 + 1

    fun daysSince(startOrdinal: Int): List<FocusActivityDay> {
        return stats.activityDays.filter { day ->
            val ordinal = dayOrdinal(day.key) ?: return@filter false
            ordinal in startOrdinal..todayOrdinal
        }
    }

    return listOf(
        periodSummary("Today", daysSince(todayOrdinal)),
        ProgressPeriodSummary(
            label = "Week",
            value = formatProtectedTime(stats.protectedMsThisWeek),
            caption = if (stats.sessionsThisWeek == 1) "1 session" else "${stats.sessionsThisWeek} sessions"
        ),
        periodSummary("Month", daysSince(monthStartOrdinal)),
        periodSummary("Year", daysSince(yearStartOrdinal))
    )
}

private fun periodSummary(label: String, days: List<FocusActivityDay>): ProgressPeriodSummary {
    val protectedMs = days.sumOf { it.protectedMs }
    val sessions = days.sumOf { it.sessions }
    return ProgressPeriodSummary(
        label = label,
        value = formatProtectedTime(protectedMs),
        caption = if (sessions == 1) "1 session" else "$sessions sessions"
    )
}

private fun startOrdinal(calendar: Calendar, field: Int): Int {
    val copy = calendar.clone() as Calendar
    if (field == Calendar.DAY_OF_WEEK) {
        while (copy.get(Calendar.DAY_OF_WEEK) != Calendar.MONDAY) {
            copy.add(Calendar.DAY_OF_YEAR, -1)
        }
    } else {
        copy.set(field, 1)
    }
    return copy.get(Calendar.YEAR) * 400 + copy.get(Calendar.DAY_OF_YEAR)
}

private fun roundedChartScale(valuesMax: Long): Long {
    val minutes = ((valuesMax / 60000L) + 1L).coerceAtLeast(15L)
    val roundedMinutes = when {
        minutes <= 30L -> 30L
        minutes <= 60L -> 60L
        minutes <= 120L -> 120L
        else -> ((minutes + 59L) / 60L) * 60L
    }
    return roundedMinutes * 60000L
}

private fun currentStreakDays(days: List<FocusActivityDay>): Int {
    val activeDays = days
        .filter { it.sessions > 0 || it.protectedMs > 0L }
        .sortedByDescending { it.key }
    var expected: Int? = null
    var streak = 0
    activeDays.forEach { day ->
        val ordinal = dayOrdinal(day.key) ?: return@forEach
        if (expected == null || ordinal == expected) {
            streak += 1
            expected = ordinal - 1
        } else {
            return streak
        }
    }
    return streak
}

private fun dayOrdinal(key: String): Int? {
    val parts = key.split("-")
    if (parts.size != 2) return null
    val year = parts[0].toIntOrNull() ?: return null
    val day = parts[1].toIntOrNull() ?: return null
    return year * 400 + day
}

private fun bestDay(days: List<FocusActivityDay>): FocusActivityDay? {
    val best = days.maxByOrNull { it.protectedMs + (it.sessions * 60000L) }
    return if (best == null || (best.protectedMs <= 0L && best.sessions <= 0)) null else best
}

private fun bestDayValue(days: List<FocusActivityDay>): String {
    return bestDay(days)?.let { dayName(it.dayOfWeek) } ?: "No data"
}

private fun bestDayCaption(days: List<FocusActivityDay>): String {
    val day = bestDay(days) ?: return "This week"
    val details = mutableListOf<String>()
    if (day.protectedMs > 0L) details += formatProtectedTime(day.protectedMs)
    if (day.blockedAttempts == 0) {
        details += "No urges"
    } else {
        details += "${day.blockedAttempts} urges stopped"
    }
    return details.joinToString(" · ")
}

private fun dayName(dayOfWeek: Int): String {
    return when (dayOfWeek) {
        Calendar.MONDAY -> "Monday"
        Calendar.TUESDAY -> "Tuesday"
        Calendar.WEDNESDAY -> "Wednesday"
        Calendar.THURSDAY -> "Thursday"
        Calendar.FRIDAY -> "Friday"
        Calendar.SATURDAY -> "Saturday"
        Calendar.SUNDAY -> "Sunday"
        else -> "No data"
    }
}

private fun riskMomentValue(stats: FocusStats): String {
    val riskyDay = riskiestDay(stats.activityDays)
    return riskyDay?.let { dayName(it.dayOfWeek) } ?: "No pattern"
}

private fun riskMomentCaption(stats: FocusStats): String {
    val riskyDay = riskiestDay(stats.activityDays)
        ?: return "Your vulnerable window will appear after more sessions"
    if (riskyDay.blockedAttempts > 0) {
        return "${riskyDay.blockedAttempts} urges stopped that day"
    }
    if (riskyDay.sessions > 0) {
        return "The day you use Blanked most"
    }
    return "No risk signals yet"
}

private fun riskiestDay(days: List<FocusActivityDay>): FocusActivityDay? {
    return days
        .filter { it.blockedAttempts > 0 || it.sessions > 0 || it.protectedMs > 0L }
        .maxWithOrNull(
            compareBy<FocusActivityDay> { it.blockedAttempts }
                .thenBy { it.sessions }
                .thenBy { it.protectedMs }
        )
}

private fun protectionQualityScore(stats: FocusStats, emergencyUnlocksRemaining: Int): Int {
    if (stats.sessionsThisWeek <= 0 && stats.protectedMsThisWeek <= 0L) return 0
    val usedEmergencies = usedEmergencyUnlocks(emergencyUnlocksRemaining)
    val attemptsPerSession = if (stats.sessionsThisWeek > 0) {
        stats.blockedAttemptsThisWeek.toFloat() / stats.sessionsThisWeek
    } else {
        stats.blockedAttemptsThisWeek.toFloat()
    }
    val averageMinutes = averageSessionMs(stats) / 60000L
    val durationBonus = when {
        averageMinutes >= 60L -> 12
        averageMinutes >= 30L -> 8
        averageMinutes >= 15L -> 4
        else -> 0
    }
    val attemptPenalty = (attemptsPerSession * 10f).toInt().coerceAtMost(35)
    val emergencyPenalty = usedEmergencies * 12
    val streakBonus = currentStreakDays(stats.activityDays).coerceAtMost(5) * 3
    return (76 + durationBonus + streakBonus - attemptPenalty - emergencyPenalty).coerceIn(0, 100)
}

private fun protectionQualityCaption(stats: FocusStats, emergencyUnlocksRemaining: Int): String {
    if (stats.sessionsThisWeek <= 0) return "Complete a session to measure it"
    val usedEmergencies = usedEmergencyUnlocks(emergencyUnlocksRemaining)
    return when {
        usedEmergencies == 0 && stats.blockedAttemptsThisWeek == 0 -> "Clean sessions, no exits or urges"
        usedEmergencies == 0 -> "Urges appeared, but Blanked held"
        usedEmergencies < 3 -> "Improves as emergency use goes down"
        else -> "Fragile week: all emergency unlocks used"
    }
}

private fun controlRecoveryValue(stats: FocusStats, emergencyUnlocksRemaining: Int): String {
    val usedEmergencies = usedEmergencyUnlocks(emergencyUnlocksRemaining)
    return when {
        stats.blockedAttemptsThisWeek > 0 -> "${stats.blockedAttemptsThisWeek} pauses"
        usedEmergencies == 0 && stats.sessionsThisWeek > 0 -> "Stable"
        usedEmergencies < 3 -> "${3 - usedEmergencies} left"
        else -> "Limit"
    }
}

private fun controlRecoveryCaption(stats: FocusStats, emergencyUnlocksRemaining: Int): String {
    val usedEmergencies = usedEmergencyUnlocks(emergencyUnlocksRemaining)
    return when {
        stats.blockedAttemptsThisWeek > 0 && usedEmergencies == 0 -> "Urges stopped without emergency unlocks"
        stats.blockedAttemptsThisWeek > 0 -> "Blanked surfaced the urge before action"
        usedEmergencies == 0 && stats.sessionsThisWeek > 0 -> "No emergency unlocks needed this week"
        usedEmergencies < 3 -> "Emergency unlocks left this week"
        else -> "Emergency limit reached"
    }
}

private fun usedEmergencyUnlocks(emergencyUnlocksRemaining: Int): Int {
    return (3 - emergencyUnlocksRemaining).coerceIn(0, 3)
}

private fun emergencyCaption(emergencyUnlocksRemaining: Int): String {
    val used = usedEmergencyUnlocks(emergencyUnlocksRemaining)
    return when {
        used == 0 -> "No unlocks this week"
        emergencyUnlocksRemaining > 0 -> "$emergencyUnlocksRemaining still available"
        else -> "Weekly limit reached"
    }
}

private fun nextStepText(stats: FocusStats): String {
    val riskyDay = riskiestDay(stats.activityDays)
        ?: return "Complete a few more sessions and Blanked will detect which moment needs support."
    val day = dayName(riskyDay.dayOfWeek).lowercase()
    return when {
        riskyDay.blockedAttempts > 0 -> "Your risk moment is usually $day. Schedule Blanked before that window."
        riskyDay.sessions > 1 -> "$day is when you use Blanked most. Reinforce that routine before opening apps."
        else -> "$day was your most sensitive point. Reinforce that window before the urge appears."
    }
}

private fun progressInsight(stats: FocusStats, savedMs: Long): String {
    return when {
        stats.totalSessions == 0 -> "After your first session, Blanked will start building weekly progress."
        protectionQualityScore(stats, 3) >= 90 -> "Your sessions are clean: low urge pressure and strong protected time."
        stats.blockedAttemptsThisWeek >= 5 -> "Your pattern is visible: Blanked is intercepting urges before they take over."
        savedMs >= 60L * 60L * 1000L -> "You have recovered more than one hour of attention with Blanked."
        stats.sessionsThisWeek >= 3 -> "Repetition is starting to count: several sessions completed this week."
        stats.blockedAttemptsThisWeek > 0 -> "Blanked has already intercepted automatic urges. That pause is the product."
        else -> "One completed session is one less automatic interruption."
    }
}

@Composable
private fun progressTextColor(buttonLight: Boolean): Color {
    return if (buttonLight) Color.Black else Color.White
}

private fun formatMinute(minuteOfDay: Int): String {
    val hour = (minuteOfDay / 60).coerceIn(0, 23)
    val minute = (minuteOfDay % 60).coerceIn(0, 59)
    return hour.toString().padStart(2, '0') + ":" + minute.toString().padStart(2, '0')
}

private fun timeOptions(): List<Int> {
    return (0..47).map { it * 30 }
}

private fun parseMinute(value: String): Int? {
    val parts = value.trim().split(":")
    if (parts.size != 2) return null
    val hour = parts[0].toIntOrNull() ?: return null
    val minute = parts[1].toIntOrNull() ?: return null
    if (hour !in 0..23 || minute !in 0..59) return null
    return hour * 60 + minute
}
