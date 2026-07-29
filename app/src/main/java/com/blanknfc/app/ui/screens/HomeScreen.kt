package com.blanknfc.app.ui.screens

import android.content.Intent
import android.graphics.BitmapFactory
import android.provider.Settings
import android.util.Base64
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
import androidx.compose.foundation.layout.aspectRatio
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
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
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
import androidx.compose.ui.graphics.asImageBitmap
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
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import com.blanknfc.app.R
import com.blanknfc.app.data.BlankMode
import com.blanknfc.app.data.SessionManager
import com.blanknfc.app.ui.theme.BlankBackground
import com.blanknfc.app.ui.theme.BlankGray
import com.blanknfc.app.ui.theme.BlankOnSurface
import com.blanknfc.app.ui.theme.BlankSurface
import com.blanknfc.app.util.AccessibilityHelper
import com.blanknfc.app.util.AppInfo
import com.blanknfc.app.util.BatteryHelper
import com.blanknfc.app.util.NfcHelper
import com.blanknfc.app.util.PackageHelper

private enum class HomePanel {
    HOME,
    SETTINGS,
    MODES,
    PRIVACY,
    RELINK,
    FORGET,
    BACKGROUND,
    BLOCK,
    EMERGENCY
}

private data class BackgroundTheme(
    val id: String,
    val label: String,
    val idleResId: Int,
    val activeResId: Int
)

private data class ConfigIssue(
    val title: String,
    val body: String,
    val action: String?,
    val onAction: () -> Unit = {}
)

private val BackgroundThemes = listOf(
    BackgroundTheme("blank", "Blank", R.string.bg_blank_home_1, R.string.bg_blank_home_2)
)

private const val HomeTagline = "¿Lo ves? Al final\nno era urgente,\nera costumbre."

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
    val backgroundThemeId by sessionManager.backgroundThemeId.collectAsState()
    val currentMode = modes.firstOrNull { it.id == currentModeId } ?: modes.first()
    val backgroundTheme = BackgroundThemes.firstOrNull { it.id == backgroundThemeId }
        ?: BackgroundThemes.first { it.id == SessionManager.DEFAULT_BACKGROUND_THEME_ID }
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
                    action = null
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
        isDark = panel == HomePanel.BLOCK || panel == HomePanel.EMERGENCY,
        backgroundTheme = backgroundTheme
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
                currentMode = currentMode,
                isBlankActive = isBlankActive,
                configIssues = configIssues,
                onModes = { panel = HomePanel.MODES },
                onSettings = { panel = HomePanel.SETTINGS },
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
                onPrivacy = {
                    panel = HomePanel.PRIVACY
                },
                onRelink = {
                    panel = HomePanel.RELINK
                },
                onForget = {
                    panel = HomePanel.FORGET
                },
                onBackground = {
                    panel = HomePanel.BACKGROUND
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

            HomePanel.PRIVACY -> TextPanel(
                title = "Privacidad",
                backLabel = "Volver",
                onBack = { panel = HomePanel.SETTINGS },
                blocks = listOf(
                    "Uso de Accesibilidad" to "Blank usa eventos de Accesibilidad para detectar cuando una app bloqueada pasa a primer plano y mostrar la pantalla de bloqueo.",
                    "Datos observados" to "No lee textos, contraseñas, mensajes, contactos, notificaciones ni contenido de pantalla.",
                    "Almacenamiento" to "La etiqueta NFC, apps protegidas y estado de Blank se guardan localmente en este dispositivo."
                )
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

            HomePanel.FORGET -> CenterActionPanel(
                topTitle = "Reset NFC",
                label = "Confirmación",
                title = "Olvidar la etiqueta NFC.",
                body = "Esto desactivará Blank y reiniciará el onboarding. Tus apps protegidas se mantienen.",
                action = "Confirmar reset",
                buttonLight = buttonLight,
                onBack = { panel = HomePanel.SETTINGS },
                onAction = onForgetTag
            )

            HomePanel.BACKGROUND -> BackgroundPanel(
                selectedThemeId = backgroundTheme.id,
                buttonLight = buttonLight,
                onBack = { panel = HomePanel.SETTINGS },
                onSelect = sessionManager::selectBackgroundTheme
            )

            HomePanel.BLOCK -> BlockPanel(
                onEmergency = { panel = HomePanel.EMERGENCY }
            )

            HomePanel.EMERGENCY -> EmergencyPanel(
                onBack = { panel = HomePanel.BLOCK },
                onUnlock = {
                    sessionManager.deactivateForEmergency()
                    panel = HomePanel.HOME
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
    backgroundTheme: BackgroundTheme,
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
                    modifier = Modifier.fillMaxSize()
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
private fun HomePanelContent(
    currentMode: BlankMode,
    isBlankActive: Boolean,
    configIssues: List<ConfigIssue>,
    onModes: () -> Unit,
    onSettings: () -> Unit,
    onMainAction: () -> Unit
) {
    Box(modifier = Modifier.fillMaxSize()) {
        TopBar(
            left = {
                ModeChipAligned(name = currentMode.name, onClick = onModes)
            },
            right = {
                IconDotsAligned(onClick = onSettings)
            },
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
            Column(
                modifier = Modifier.fillMaxWidth(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center
            ) {
                Text(
                    text = HomeTagline,
                    style = MaterialTheme.typography.titleLarge.copy(
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 38.sp,
                        lineHeight = 43.sp
                    ),
                    color = Color.White,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(24.dp))
                HomeBlankearButton(
                    text = if (active) "Escanear Blank para salir" else "Blankear",
                    enabled = !active,
                    modifier = Modifier.widthIn(max = if (active) 342.dp else 178.dp),
                    onClick = onMainAction
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
private fun IconDotsAligned(onClick: () -> Unit) {
    Box(
        modifier = Modifier
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
    onPrivacy: () -> Unit,
    onRelink: () -> Unit,
    onForget: () -> Unit,
    onBackground: () -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(title = "Ajustes", onBack = onBack)
        Spacer(modifier = Modifier.height(58.dp))
        Text(text = "Ajustes", style = MaterialTheme.typography.headlineLarge, color = BlankOnSurface)
        Spacer(modifier = Modifier.height(28.dp))
        val items = buildList {
            add(MenuItem("Privacidad", "Ver", onPrivacy))
            add(MenuItem("Vincular nueva etiqueta", "NFC", onRelink))
            add(MenuItem("Olvidar NFC", "Reset", onForget))
            add(MenuItem("Fondo de pantalla", "Color", onBackground))
        }
        MenuList(
            buttonLight = buttonLight,
            items = items
        )
    }
}

private data class MenuItem(val label: String, val meta: String, val action: () -> Unit)

@Composable
private fun BackgroundPanel(
    selectedThemeId: String,
    buttonLight: Boolean,
    onBack: () -> Unit,
    onSelect: (String) -> Unit
) {
    Column(modifier = Modifier.fillMaxSize()) {
        ScreenHeader(title = "Fondo", onBack = onBack)
        Spacer(modifier = Modifier.height(46.dp))
        Text(text = "Elige un fondo", style = MaterialTheme.typography.headlineLarge, color = BlankOnSurface)
        Spacer(modifier = Modifier.height(8.dp))
        Text(
            text = "Blank usarÃ¡ la variante clara en reposo y la variante intensa cuando estÃ© activo.",
            style = MaterialTheme.typography.bodyLarge,
            color = BlankOnSurface
        )
        Spacer(modifier = Modifier.height(24.dp))
        LazyColumn(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            items(BackgroundThemes, key = { it.id }) { theme ->
                BackgroundThemeRow(
                    theme = theme,
                    selected = theme.id == selectedThemeId,
                    buttonLight = buttonLight,
                    onSelect = { onSelect(theme.id) }
                )
            }
        }
    }
}

@Composable
private fun BackgroundThemeRow(
    theme: BackgroundTheme,
    selected: Boolean,
    buttonLight: Boolean,
    onSelect: () -> Unit
) {
    val buttonBackground = if (buttonLight) Color.White else Color.Black
    val buttonContent = if (buttonLight) Color.Black else Color.White
    val metaColor = buttonContent.copy(alpha = 0.72f)
    val border = if (selected) BorderStroke(2.dp, buttonContent) else null
    Surface(
        modifier = Modifier.fillMaxWidth(),
        color = buttonBackground,
        shape = RoundedCornerShape(22.dp),
        border = border,
        onClick = onSelect
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            BackgroundPreview(theme.idleResId)
            Spacer(modifier = Modifier.widthIn(min = 10.dp))
            BackgroundPreview(theme.activeResId)
            Column(
                modifier = Modifier
                    .weight(1f)
                    .padding(start = 14.dp)
            ) {
                Text(text = theme.label, color = buttonContent, style = MaterialTheme.typography.bodyLarge)
                Text(
                    text = if (selected) "Seleccionado" else "Disponible",
                    color = metaColor,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}

@Composable
private fun BackgroundPreview(resId: Int) {
    Surface(
        modifier = Modifier
            .widthIn(min = 44.dp, max = 44.dp)
            .aspectRatio(0.72f),
        shape = RoundedCornerShape(14.dp),
        color = BlankBackground
    ) {
        BackgroundImage(
            resId = resId,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize()
        )
    }
}

@Composable
private fun BackgroundImage(
    resId: Int,
    contentScale: ContentScale,
    modifier: Modifier = Modifier
) {
    val encoded = stringResource(resId)
    val imageBitmap = remember(encoded) {
        val bytes = Base64.decode(encoded.trim(), Base64.DEFAULT)
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size)?.asImageBitmap()
    }
    if (imageBitmap != null) {
        Image(
            bitmap = imageBitmap,
            contentDescription = null,
            contentScale = contentScale,
            modifier = modifier
        )
    }
}

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
                    Text(text = item.label, color = buttonContent, modifier = Modifier.weight(1f))
                    Text(text = item.meta, color = metaColor, style = MaterialTheme.typography.bodyMedium)
                }
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
private fun EmergencyPanel(onBack: () -> Unit, onUnlock: () -> Unit) {
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
            enabled = phrase.trim() == expected,
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
private fun HomeBlankearButton(
    text: String,
    enabled: Boolean = true,
    modifier: Modifier = Modifier,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(999.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = Color(0xFFB1B3B8).copy(alpha = 0.82f),
            contentColor = Color.White,
            disabledContainerColor = Color(0xFFB1B3B8).copy(alpha = 0.82f),
            disabledContentColor = Color.White
        ),
        modifier = modifier
            .fillMaxWidth()
            .height(48.dp)
            .shadow(
                elevation = 10.dp,
                shape = RoundedCornerShape(999.dp),
                ambientColor = Color.Black.copy(alpha = 0.06f),
                spotColor = Color.Black.copy(alpha = 0.06f)
            )
    ) {
        Text(text = text, style = MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold))
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
