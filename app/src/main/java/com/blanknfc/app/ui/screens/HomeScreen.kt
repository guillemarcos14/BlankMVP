package com.blanknfc.app.ui.screens

import android.content.Intent
import android.content.Context
import android.graphics.SurfaceTexture
import android.media.MediaPlayer
import android.net.Uri
import android.provider.Settings
import android.view.Surface
import android.view.TextureView
import android.view.ViewGroup
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
import androidx.compose.animation.togetherWith
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
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
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.blanknfc.app.R
import com.blanknfc.app.data.FocusActivityDay
import com.blanknfc.app.data.BlankMode
import com.blanknfc.app.data.FocusSchedule
import com.blanknfc.app.data.FocusStats
import com.blanknfc.app.data.SessionManager
import com.blanknfc.app.service.BlankSchedule
import com.blanknfc.app.ui.theme.BlankGray
import com.blanknfc.app.ui.theme.BlankOnSurface
import com.blanknfc.app.ui.theme.BlankSurface
import com.blanknfc.app.util.AccessibilityHelper
import com.blanknfc.app.util.AppInfo
import com.blanknfc.app.util.BatteryHelper
import com.blanknfc.app.util.NfcHelper
import com.blanknfc.app.util.PackageHelper
import java.util.Calendar
import kotlin.random.Random

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

private const val BackgroundVideoAlpha = 0.72f
private const val NfcOptionsUrl = "https://getblank.netlify.app/nfc.html"

private val LightModeMessages = listOf(
    "Ya sé que solo querías mirar un par de stories.",
    "No estás perdiéndote nada.",
    "Nadie te necesita en los próximos minutos.",
    "El scroll puede esperar.",
    "Para un momento.",
    "No pasa nada si no contestas ahora.",
    "¿Hace cuánto que no miras al frente?",
    "Venga, toca.",
    "No te va a llegar nada importante.",
    "Igual hay algo mejor que hacer."
)

private val DarkModeMessages = listOf(
    "¿Ves? No pasaba nada.",
    "Nadie se ha muerto.",
    "Nada urgente. Como siempre.",
    "Bien hecho.",
    "Llevas un rato sin mirarlo. Eso es mucho.",
    "No ha llegado nada nuevo. Ya lo decía yo.",
    "Sigue un poco más.",
    "El teléfono seguirá ahí.",
    "Hoy has hecho algo difícil.",
    "Ya está."
)

@Composable
fun HomeScreen(
    sessionManager: SessionManager,
    onRelinkTag: () -> Unit,
    onForgetTag: () -> Unit
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val isBlankActive by sessionManager.isBlankActive.collectAsState()
    val modes by sessionManager.modes.collectAsState()
    val currentModeId by sessionManager.currentModeId.collectAsState()
    val stats by sessionManager.stats.collectAsState()
    val emergencyUnlocksRemaining by sessionManager.emergencyUnlocksRemaining.collectAsState()
    val schedule by sessionManager.schedule.collectAsState()
    val currentMode = modes.firstOrNull { it.id == currentModeId } ?: modes.first()
    val buttonLight = !isBlankActive
    val apps = remember { PackageHelper.getInstalledApps(context) }
    var panel by remember { mutableStateOf(HomePanel.HOME) }
    var modeBeingEdited by remember { mutableStateOf<BlankMode?>(null) }
    var showCreateMode by remember { mutableStateOf(false) }
    var accessibilityEnabled by remember { mutableStateOf(AccessibilityHelper.isServiceEnabled(context)) }
    var batteryOptimizedIgnored by remember { mutableStateOf(BatteryHelper.isIgnoringBatteryOptimizations(context)) }
    var nfcAvailable by remember { mutableStateOf(NfcHelper.isNfcAvailable(context)) }
    var nfcEnabled by remember { mutableStateOf(NfcHelper.isNfcEnabled(context)) }

    fun refreshSystemConfig() {
        accessibilityEnabled = AccessibilityHelper.isServiceEnabled(context)
        batteryOptimizedIgnored = BatteryHelper.isIgnoringBatteryOptimizations(context)
        nfcAvailable = NfcHelper.isNfcAvailable(context)
        nfcEnabled = NfcHelper.isNfcEnabled(context)
    }

    fun openNfcOptions() {
        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(NfcOptionsUrl)))
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

    val configIssues = buildList {
        if (!nfcAvailable) {
            add(
                ConfigIssue(
                    title = "NFC no disponible",
                    body = "Este móvil no tiene NFC compatible. Blank necesita NFC para desbloquear.",
                    action = "Ver opciones NFC",
                    onAction = ::openNfcOptions
                )
            )
        } else if (!nfcEnabled) {
            add(
                ConfigIssue(
                    title = "NFC desactivado",
                    body = "Activa NFC para que Blank pueda leer tu pieza física.",
                    action = "Abrir NFC",
                    onAction = { context.startActivity(Intent(Settings.ACTION_NFC_SETTINGS)) }
                )
            )
        }
        if (!accessibilityEnabled) {
            add(
                ConfigIssue(
                    title = "Accesibilidad desactivada",
                    body = "Activa Blank en Accesibilidad para detectar apps protegidas.",
                    action = "Abrir Accesibilidad",
                    onAction = { AccessibilityHelper.openAccessibilitySettings(context) }
                )
            )
        }
        if (!batteryOptimizedIgnored) {
            add(
                ConfigIssue(
                    title = "Batería restringida",
                    body = "Permite que Blank funcione en segundo plano para mantener el bloqueo estable.",
                    action = "Abrir batería",
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
                onSettings = { panel = HomePanel.SETTINGS },
                onStats = { panel = HomePanel.STATS },
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
                onRelink = {
                    panel = HomePanel.RELINK
                },
                onForget = {
                    panel = HomePanel.FORGET
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
                body = "Blank mantendrá tus apps protegidas y cambiará solo la llave física.",
                action = "Abrir vinculación NFC",
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
                targetState = if (isBlankActive) R.raw.blank_background_active else R.raw.blank_background_idle,
                animationSpec = tween(durationMillis = 520),
                label = "blank_background_video"
            ) { backgroundVideoResId ->
                BackgroundLoopVideo(
                    videoResId = backgroundVideoResId,
                    modifier = Modifier
                        .fillMaxSize()
                        .alpha(BackgroundVideoAlpha)
                )
            }
        }
        if (!isDark) {
            Canvas(modifier = Modifier.fillMaxSize()) {
                val dot = Color(0xFF969690).copy(alpha = 0.18f)
                val step = 13.dp.toPx()
                var y = 0f
                while (y < size.height) {
                    var x = 0f
                    while (x < size.width) {
                        drawCircle(dot, radius = 0.65.dp.toPx(), center = Offset(x, y))
                        x += step
                    }
                    y += step
                }
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
private fun BackgroundLoopVideo(
    videoResId: Int,
    modifier: Modifier = Modifier
) {
    val context = LocalContext.current
    AndroidView(
        modifier = modifier,
        factory = { viewContext ->
            LoopingVideoTextureView(viewContext).apply {
                layoutParams = ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                )
            }
        },
        update = { textureView ->
            textureView.play(context, videoResId)
        }
    )
}

private class LoopingVideoTextureView(context: Context) : TextureView(context), TextureView.SurfaceTextureListener {
    private var mediaPlayer: MediaPlayer? = null
    private var currentVideoResId: Int? = null
    private var currentSurface: Surface? = null

    init {
        surfaceTextureListener = this
    }

    fun play(context: Context, videoResId: Int) {
        if (currentVideoResId == videoResId && mediaPlayer != null) return
        currentVideoResId = videoResId
        if (isAvailable) {
            startPlayer(context, videoResId)
        }
    }

    private fun startPlayer(context: Context, videoResId: Int) {
        releasePlayer()
        val assetFileDescriptor = context.resources.openRawResourceFd(videoResId)
        currentSurface = Surface(surfaceTexture)
        mediaPlayer = MediaPlayer().apply {
            setDataSource(
                assetFileDescriptor.fileDescriptor,
                assetFileDescriptor.startOffset,
                assetFileDescriptor.length
            )
            assetFileDescriptor.close()
            isLooping = true
            setVolume(0f, 0f)
            setSurface(currentSurface)
            setOnPreparedListener { preparedPlayer -> preparedPlayer.start() }
            prepareAsync()
        }
    }

    private fun releasePlayer() {
        mediaPlayer?.release()
        mediaPlayer = null
        currentSurface?.release()
        currentSurface = null
    }

    override fun onSurfaceTextureAvailable(surface: SurfaceTexture, width: Int, height: Int) {
        currentVideoResId?.let { videoResId ->
            startPlayer(context, videoResId)
        }
    }

    override fun onSurfaceTextureSizeChanged(surface: SurfaceTexture, width: Int, height: Int) = Unit

    override fun onSurfaceTextureDestroyed(surface: SurfaceTexture): Boolean {
        releasePlayer()
        return true
    }

    override fun onSurfaceTextureUpdated(surface: SurfaceTexture) = Unit
}

@Composable
private fun HomePanelContent(
    isBlankActive: Boolean,
    configIssues: List<ConfigIssue>,
    onSettings: () -> Unit,
    onStats: () -> Unit,
    onMainAction: () -> Unit
) {
    Box(modifier = Modifier.fillMaxSize()) {
        IconDotsAligned(
            onClick = onSettings,
            modifier = Modifier.align(Alignment.TopCenter)
        )
        if (configIssues.isNotEmpty()) {
            ConfigIssuesCard(
                issues = configIssues,
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .padding(top = 62.dp)
            )
        }
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            AnimatedContent(
                targetState = isBlankActive,
                transitionSpec = {
                    fadeIn(animationSpec = tween(360)) togetherWith fadeOut(animationSpec = tween(220))
                },
            label = "blank_home_message"
        ) { active ->
            val messages = if (active) DarkModeMessages else LightModeMessages
            val message = remember(active) {
                messages[Random.nextInt(messages.size)]
            }

            Text(
                text = message,
                style = MaterialTheme.typography.headlineLarge.copy(fontWeight = FontWeight.Medium),
                color = BlankOnSurface,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )
        }
        }
        Crossfade(
            targetState = isBlankActive,
            animationSpec = tween(durationMillis = 260),
            label = "blank_home_action",
            modifier = Modifier.align(Alignment.BottomCenter)
        ) { active ->
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                MainActionButton(
                    text = if (active) "Escanear Blank para salir" else "Iniciar Blank",
                    enabled = !active,
                    light = !active,
                    onClick = onMainAction
                )
                Spacer(modifier = Modifier.height(12.dp))
                TextButton(onClick = onStats) {
                    Text(
                        text = "Progreso",
                        color = if (active) Color.White.copy(alpha = 0.74f) else BlankOnSurface.copy(alpha = 0.72f),
                        style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.Medium)
                    )
                }
            }
        }
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
                text = "Revisa la configuración",
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
    onRelink: () -> Unit,
    onForget: () -> Unit,
    onEmergency: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(title = "Ajustes", onBack = onBack)
        Spacer(modifier = Modifier.height(58.dp))
        Text(text = "Ajustes", style = MaterialTheme.typography.headlineLarge, color = BlankOnSurface)
        Spacer(modifier = Modifier.height(28.dp))
        val items = buildList {
            add(MenuItem("Modo", "Apps", onModes))
            add(MenuItem("Programar mi Blank", "Diario", onSchedule))
            add(MenuItem("Vincular nuevo NFC", "Etiqueta", onRelink))
            add(MenuItem("He olvidado mi Blank", "Reset", onForget))
            add(MenuItem("Emergencia", "Salida", onEmergency, destructive = true))
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
    buttonLight: Boolean,
    onBack: () -> Unit
) {
    var selectedPage by remember { mutableStateOf(0) }
    val savedMs = estimatedSavedMs(stats)
    val insight = progressInsight(stats, savedMs)

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            ScreenHeader(title = "Progreso", onBack = onBack)
            Spacer(modifier = Modifier.height(38.dp))
            Text(text = "Tu progreso", style = MaterialTheme.typography.headlineLarge, color = BlankOnSurface)
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Tiempo protegido por periodo, sin ruido.",
                style = MaterialTheme.typography.bodyLarge,
                color = BlankOnSurface.copy(alpha = 0.72f)
            )
        }
        item {
            ProgressHeroCarousel(
                selectedPage = selectedPage,
                onPageChange = { selectedPage = it },
                stats = stats,
                savedMs = savedMs,
                buttonLight = buttonLight
            )
        }
        item {
            Text(
                text = insight,
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Medium),
                color = BlankOnSurface.copy(alpha = 0.74f),
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth()
            )
        }
        item {
            ProgressPeriodGrid(
                stats = stats,
                buttonLight = buttonLight
            )
        }
    }
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
    val label = if (selectedPage == 0) "Tiempo ahorrado" else "Tiempo en Blank"
    val value = if (selectedPage == 0) formatProtectedTime(savedMs) else formatProtectedTime(stats.protectedMsThisWeek)
    val description = if (selectedPage == 0) "Recuperadas de tu vida gracias a Blank" else "Protegidas esta semana"
    val chartTitle = if (selectedPage == 0) "Ahorro estimado" else "Modo Blank"

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
                ProgressTab("Tiempo ahorrado", selectedPage == 0, buttonLight) { onPageChange(0) }
                ProgressTab("Tiempo en Blank", selectedPage == 1, buttonLight) { onPageChange(1) }
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
            label = "Momento de riesgo",
            value = riskMomentValue(stats),
            caption = riskMomentCaption(stats),
            buttonLight = buttonLight
        )
        StatRow(
            label = "Calidad de protección",
            value = "${protectionQualityScore(stats, emergencyUnlocksRemaining)}/100",
            caption = protectionQualityCaption(stats, emergencyUnlocksRemaining),
            buttonLight = buttonLight
        )
        StatRow(
            label = "Control recuperado",
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
        StatRow("Sesiones", stats.sessionsThisWeek.toString(), "Completadas", buttonLight)
        StatRow("Media protegida", formatProtectedTime(averageSessionMs(stats)), "Por sesión real", buttonLight)
        StatRow("Racha", "${currentStreakDays(stats.activityDays)}d", "Días con Blank", buttonLight)
        StatRow("Mejor día", bestDayValue(stats.activityDays), bestDayCaption(stats.activityDays), buttonLight)
        StatRow("Impulsos frenados", stats.blockedAttemptsThisWeek.toString(), "Veces que Blank creó una pausa", buttonLight)
        StatRow("Emergencias", "${usedEmergencyUnlocks(emergencyUnlocksRemaining)}/3", emergencyCaption(emergencyUnlocksRemaining), buttonLight)
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
        ScreenHeader(title = "Programar mi Blank", onBack = onBack)
        Spacer(modifier = Modifier.height(46.dp))
        Text(text = "Ventana diaria", style = MaterialTheme.typography.headlineLarge, color = BlankOnSurface)
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Blank se activa solo en esa franja. Para salir antes, sigues necesitando el NFC.",
            style = MaterialTheme.typography.bodyLarge,
            color = BlankOnSurface
        )
        Spacer(modifier = Modifier.height(24.dp))
        ToggleRow(
            label = "Activar horario diario",
            checked = enabled,
            buttonLight = buttonLight,
            onCheckedChange = { enabled = it }
        )
        Spacer(modifier = Modifier.height(10.dp))
        TimeDropdown(label = "Inicio", minute = startMinute, buttonLight = buttonLight, onMinuteChange = { startMinute = it })
        Spacer(modifier = Modifier.height(10.dp))
        TimeDropdown(label = "Fin", minute = endMinute, buttonLight = buttonLight, onMinuteChange = { endMinute = it })
        Spacer(modifier = Modifier.height(16.dp))
        Surface(
            modifier = Modifier.fillMaxWidth(),
            color = if (buttonLight) Color.White.copy(alpha = 0.86f) else Color.Black,
            shape = RoundedCornerShape(22.dp)
        ) {
            Column(modifier = Modifier.padding(horizontal = 18.dp, vertical = 16.dp)) {
                Text(
                    text = "Ventana activa",
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
            text = "Guardar horario",
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
        ScreenHeader(title = "Modos", onBack = onBack)
        Spacer(modifier = Modifier.height(46.dp))
        Text(text = "Elige un modo", style = MaterialTheme.typography.headlineLarge, color = BlankOnSurface)
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
        MainActionButton(text = "Crear modo", light = buttonLight, onClick = onCreate)
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
                            text = { Text("Editar nombre") },
                            onClick = {
                                menuOpen = false
                                editing = true
                                onSelect()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Editar apps") },
                            onClick = {
                                menuOpen = false
                                onSelect()
                                onEditApps()
                            }
                        )
                        DropdownMenuItem(
                            text = { Text("Eliminar") },
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
                        Text("Guardar", color = textColor)
                    }
                    TextButton(
                        onClick = {
                            name = mode.name
                            editing = false
                        }
                    ) {
                        Text("Cancelar", color = metaColor)
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
        title = "Editar apps",
        name = mode.name,
        apps = apps,
        selected = selected,
        onSelectedChange = { selected = it },
        buttonLight = buttonLight,
        onDismiss = onDismiss,
        onPrimary = { onSave(selected) },
        primaryText = "Guardar apps"
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
        title = "Configurar modo",
        name = name,
        nameEditable = true,
        apps = apps,
        selected = selected,
        onNameChange = { name = it },
        onSelectedChange = { selected = it },
        buttonLight = buttonLight,
        onDismiss = onDismiss,
        onPrimary = { onCreate(name, selected) },
        primaryText = "Guardar modo"
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
                        label = { Text("Nombre") },
                        placeholder = { Text("Trabajo profundo") },
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
                Text(text = "Confirmación", color = BlankOnSurface, style = MaterialTheme.typography.labelLarge)
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = "Olvidar mi Blank.",
                    style = MaterialTheme.typography.headlineLarge,
                    color = BlankOnSurface,
                    textAlign = TextAlign.Center
                )
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = "Se desactivará Blank, se borrará la etiqueta NFC vinculada y volverás al onboarding para registrar una nueva.",
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
                            text = "Entiendo que tendré que vincular un Blank de nuevo.",
                            color = progressTextColor(buttonLight),
                            style = MaterialTheme.typography.bodyMedium
                        )
                    }
                }
            }
        }
        MainActionButton(
            text = "Sí, olvidar mi Blank",
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
                Text(text = "App bloqueada", style = MaterialTheme.typography.headlineLarge, color = BlankSurface, textAlign = TextAlign.Center)
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
        ScreenHeader(title = "Emergencia", onBack = onBack, dark = true)
        Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text(text = "Desbloqueo", color = BlankSurface.copy(alpha = 0.72f), style = MaterialTheme.typography.labelLarge)
                Spacer(modifier = Modifier.height(12.dp))
                Text(text = "Escribe la frase completa.", style = MaterialTheme.typography.headlineLarge, color = BlankSurface, textAlign = TextAlign.Center)
                Spacer(modifier = Modifier.height(12.dp))
                Text(
                    text = if (emergencyUnlocksRemaining > 0)
                        "Te quedan $emergencyUnlocksRemaining desbloqueos de emergencia esta semana."
                    else
                        "Ya has usado tus 3 desbloqueos de emergencia esta semana.",
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
    backLabel: String = "Volver",
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
    val estimated = stats.sessionsThisWeek * 15L * 60L * 1000L
    return estimated.coerceAtMost(stats.protectedMsThisWeek).coerceAtLeast(0L)
}

private fun savedTimeExplanation(stats: FocusStats): String {
    val saved = formatProtectedTime(estimatedSavedMs(stats))
    val protected = formatProtectedTime(stats.protectedMsThisWeek)
    return "Tiempo ahorrado: $saved estimados desde sesiones completadas, limitado a $protected reales en Blank."
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
    val weekStartOrdinal = startOrdinal(calendar, Calendar.DAY_OF_WEEK)
    val monthStartOrdinal = startOrdinal(calendar, Calendar.DAY_OF_MONTH)
    val yearStartOrdinal = calendar.get(Calendar.YEAR) * 400 + 1

    fun daysSince(startOrdinal: Int): List<FocusActivityDay> {
        return stats.activityDays.filter { day ->
            val ordinal = dayOrdinal(day.key) ?: return@filter false
            ordinal in startOrdinal..todayOrdinal
        }
    }

    return listOf(
        periodSummary("Hoy", daysSince(todayOrdinal)),
        ProgressPeriodSummary(
            label = "Semana",
            value = formatProtectedTime(stats.protectedMsThisWeek),
            caption = if (stats.sessionsThisWeek == 1) "1 sesión" else "${stats.sessionsThisWeek} sesiones"
        ),
        periodSummary("Mes", daysSince(monthStartOrdinal)),
        periodSummary("Año", daysSince(yearStartOrdinal))
    )
}

private fun periodSummary(label: String, days: List<FocusActivityDay>): ProgressPeriodSummary {
    val protectedMs = days.sumOf { it.protectedMs }
    val sessions = days.sumOf { it.sessions }
    return ProgressPeriodSummary(
        label = label,
        value = formatProtectedTime(protectedMs),
        caption = if (sessions == 1) "1 sesión" else "$sessions sesiones"
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
    return bestDay(days)?.let { dayName(it.dayOfWeek) } ?: "Sin datos"
}

private fun bestDayCaption(days: List<FocusActivityDay>): String {
    val day = bestDay(days) ?: return "Esta semana"
    val details = mutableListOf<String>()
    if (day.protectedMs > 0L) details += formatProtectedTime(day.protectedMs)
    if (day.blockedAttempts == 0) {
        details += "Sin impulsos"
    } else {
        details += "${day.blockedAttempts} impulsos frenados"
    }
    return details.joinToString(" · ")
}

private fun dayName(dayOfWeek: Int): String {
    return when (dayOfWeek) {
        Calendar.MONDAY -> "Lunes"
        Calendar.TUESDAY -> "Martes"
        Calendar.WEDNESDAY -> "Miércoles"
        Calendar.THURSDAY -> "Jueves"
        Calendar.FRIDAY -> "Viernes"
        Calendar.SATURDAY -> "Sábado"
        Calendar.SUNDAY -> "Domingo"
        else -> "Sin datos"
    }
}

private fun riskMomentValue(stats: FocusStats): String {
    val riskyDay = riskiestDay(stats.activityDays)
    return riskyDay?.let { dayName(it.dayOfWeek) } ?: "Sin patrón"
}

private fun riskMomentCaption(stats: FocusStats): String {
    val riskyDay = riskiestDay(stats.activityDays)
        ?: return "Con más datos aparecerá tu franja vulnerable"
    if (riskyDay.blockedAttempts > 0) {
        return "${riskyDay.blockedAttempts} impulsos frenados ese día"
    }
    if (riskyDay.sessions > 0) {
        return "Día donde más recurres a Blank"
    }
    return "Sin señales de riesgo todavía"
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
    if (stats.sessionsThisWeek <= 0) return "Completa una sesión para medirlo"
    val usedEmergencies = usedEmergencyUnlocks(emergencyUnlocksRemaining)
    return when {
        usedEmergencies == 0 && stats.blockedAttemptsThisWeek == 0 -> "Sesiones limpias, sin escapes ni impulsos"
        usedEmergencies == 0 -> "Hubo impulsos, pero no rompiste Blank"
        usedEmergencies < 3 -> "Mejorará al reducir emergencias"
        else -> "Semana frágil: ya usaste todas las emergencias"
    }
}

private fun controlRecoveryValue(stats: FocusStats, emergencyUnlocksRemaining: Int): String {
    val usedEmergencies = usedEmergencyUnlocks(emergencyUnlocksRemaining)
    return when {
        stats.blockedAttemptsThisWeek > 0 -> "${stats.blockedAttemptsThisWeek} pausas"
        usedEmergencies == 0 && stats.sessionsThisWeek > 0 -> "Estable"
        usedEmergencies < 3 -> "${3 - usedEmergencies} reservas"
        else -> "Límite"
    }
}

private fun controlRecoveryCaption(stats: FocusStats, emergencyUnlocksRemaining: Int): String {
    val usedEmergencies = usedEmergencyUnlocks(emergencyUnlocksRemaining)
    return when {
        stats.blockedAttemptsThisWeek > 0 && usedEmergencies == 0 -> "Impulsos frenados sin usar emergencias"
        stats.blockedAttemptsThisWeek > 0 -> "Blank hizo visible el impulso antes de actuar"
        usedEmergencies == 0 && stats.sessionsThisWeek > 0 -> "Todavía no necesitaste rescates esta semana"
        usedEmergencies < 3 -> "Emergencias restantes esta semana"
        else -> "Toca volver a depender del NFC"
    }
}

private fun usedEmergencyUnlocks(emergencyUnlocksRemaining: Int): Int {
    return (3 - emergencyUnlocksRemaining).coerceIn(0, 3)
}

private fun emergencyCaption(emergencyUnlocksRemaining: Int): String {
    val used = usedEmergencyUnlocks(emergencyUnlocksRemaining)
    return when {
        used == 0 -> "Sin rescates esta semana"
        emergencyUnlocksRemaining > 0 -> "$emergencyUnlocksRemaining disponibles todavía"
        else -> "Límite semanal alcanzado"
    }
}

private fun progressInsight(stats: FocusStats, savedMs: Long): String {
    return when {
        stats.sessionsThisWeek == 0 -> "Cuando completes tu primera sesión, Blank empezará a construir tu progreso semanal."
        protectionQualityScore(stats, 3) >= 90 -> "Tus sesiones están saliendo limpias: poco impulso y mucho tiempo protegido."
        stats.blockedAttemptsThisWeek >= 5 -> "Tu patrón ya es visible: Blank está interceptando varios impulsos antes de que manden ellos."
        savedMs >= 60L * 60L * 1000L -> "Ya has recuperado más de una hora de atención esta semana."
        stats.sessionsThisWeek >= 3 -> "La repetición empieza a contar: ya tienes varias sesiones completadas esta semana."
        stats.blockedAttemptsThisWeek > 0 -> "Blank ya ha interceptado impulsos automáticos. Esa fricción es el producto."
        else -> "Una sesión completada ya es una interrupción menos del piloto automático."
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
