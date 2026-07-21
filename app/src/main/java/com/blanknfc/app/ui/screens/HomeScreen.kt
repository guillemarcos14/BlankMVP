package com.blanknfc.app.ui.screens

import androidx.compose.animation.Crossfade
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.blanknfc.app.R
import com.blanknfc.app.data.SessionManager
import com.blanknfc.app.ui.theme.BlankGray
import com.blanknfc.app.ui.theme.BlankLine
import com.blanknfc.app.ui.theme.BlankOnSurface
import com.blanknfc.app.ui.theme.BlankSurface
import kotlinx.coroutines.delay
import java.util.Locale

private const val BackgroundImageAlpha = 0.72f

@Composable
fun HomeScreen(
    sessionManager: SessionManager,
    onEditApps: () -> Unit,
    onRelinkTag: () -> Unit,
    onForgetTag: () -> Unit
) {
    val isBlankActive by sessionManager.isBlankActive.collectAsState()
    val blankActiveSince by sessionManager.blankActiveSince.collectAsState()
    val blockedPackages by sessionManager.blockedPackages.collectAsState()
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var showSettings by remember { mutableStateOf(false) }
    var message by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(1000)
        }
    }

    HomeBackground(isBlankActive = isBlankActive) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 32.dp, vertical = 42.dp)
        ) {
            Text(
                text = "•••",
                style = MaterialTheme.typography.titleLarge,
                color = foregroundFor(isBlankActive).copy(alpha = 0.82f),
                modifier = Modifier
                    .align(Alignment.TopCenter)
                    .clickable { showSettings = true }
                    .padding(18.dp)
            )

            Column(
                modifier = Modifier.align(Alignment.Center),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                Text(
                    text = if (isBlankActive) "El teléfono seguirá ahí." else "Ya sé que solo querías\nmirar un par de stories.",
                    style = MaterialTheme.typography.headlineLarge,
                    color = foregroundFor(isBlankActive),
                    textAlign = TextAlign.Center
                )
            }

            Column(
                modifier = Modifier.align(Alignment.BottomCenter),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                if (isBlankActive && blankActiveSince > 0L) {
                    Text(
                        text = elapsedText(blankActiveSince, now),
                        style = MaterialTheme.typography.titleLarge.copy(fontWeight = FontWeight.Bold),
                        color = Color.White,
                        textAlign = TextAlign.Center
                    )
                    Spacer(modifier = Modifier.height(10.dp))
                }

                Button(
                    onClick = {
                        message = when {
                            isBlankActive -> "Escanea tu NFC vinculado para salir."
                            blockedPackages.isEmpty() -> {
                                onEditApps()
                                "Elige al menos una app para bloquear."
                            }
                            else -> {
                                sessionManager.activateBlank()
                                null
                            }
                        }
                    },
                    shape = RoundedCornerShape(999.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = if (isBlankActive) Color.White else Color(0xFF202124),
                        contentColor = if (isBlankActive) Color(0xFF202124) else Color.White
                    ),
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(54.dp)
                ) {
                    Text(
                        text = if (isBlankActive) "Escanear NFC para salir" else "Iniciar Blank",
                        style = MaterialTheme.typography.labelLarge
                    )
                }

                TextButton(onClick = { message = "Progreso estará disponible en Android en esta versión." }) {
                    Text(
                        text = "Progreso",
                        style = MaterialTheme.typography.bodyLarge,
                        color = foregroundFor(isBlankActive).copy(alpha = 0.56f)
                    )
                }

                if (message != null) {
                    Text(
                        text = message.orEmpty(),
                        style = MaterialTheme.typography.bodyMedium,
                        color = foregroundFor(isBlankActive).copy(alpha = 0.58f),
                        textAlign = TextAlign.Center
                    )
                }
            }

            if (showSettings) {
                SettingsSheet(
                    isBlankActive = isBlankActive,
                    blockedAppCount = blockedPackages.size,
                    onDismiss = { showSettings = false },
                    onEditApps = {
                        showSettings = false
                        onEditApps()
                    },
                    onRelinkTag = {
                        showSettings = false
                        onRelinkTag()
                    },
                    onForgetTag = {
                        showSettings = false
                        onForgetTag()
                    }
                )
            }
        }
    }
}

@Composable
private fun HomeBackground(
    isBlankActive: Boolean,
    content: @Composable () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(if (isBlankActive) Color.Black else Color(0xFFE7E7E2))
    ) {
        Crossfade(
            targetState = if (isBlankActive) R.drawable.bg_gray_2 else R.drawable.bg_gray_1,
            animationSpec = tween(durationMillis = 520),
            label = "blank_app_store_background"
        ) { backgroundResId ->
            Image(
                painter = painterResource(backgroundResId),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxSize()
                    .alpha(BackgroundImageAlpha)
            )
        }

        Canvas(modifier = Modifier.fillMaxSize()) {
            val dot = if (isBlankActive) {
                Color.White.copy(alpha = 0.08f)
            } else {
                Color(0xFF969690).copy(alpha = 0.18f)
            }
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

        content()
    }
}

@Composable
private fun SettingsSheet(
    isBlankActive: Boolean,
    blockedAppCount: Int,
    onDismiss: () -> Unit,
    onEditApps: () -> Unit,
    onRelinkTag: () -> Unit,
    onForgetTag: () -> Unit
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .clickable(onClick = onDismiss),
        contentAlignment = Alignment.BottomCenter
    ) {
        Surface(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 92.dp),
            color = if (isBlankActive) Color(0xE6292929) else Color(0xEAF5F5F5),
            shape = RoundedCornerShape(28.dp)
        ) {
            Column(modifier = Modifier.padding(horizontal = 18.dp, vertical = 24.dp)) {
                Text(
                    text = "Ajustes",
                    style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold),
                    color = foregroundFor(isBlankActive)
                )
                Spacer(modifier = Modifier.height(14.dp))
                SettingsRow("Modo", "Rutina diaria", isBlankActive, onEditApps)
                SettingsDivider(isBlankActive)
                SettingsRow("Apps protegidas", "$blockedAppCount", isBlankActive, onEditApps)
                SettingsDivider(isBlankActive)
                SettingsRow("Vincular nuevo NFC", "Etiqueta", isBlankActive, onRelinkTag)
                SettingsDivider(isBlankActive)
                SettingsRow("He olvidado mi Blank", "Reset", isBlankActive, onForgetTag)
                SettingsDivider(isBlankActive)
                SettingsRow("Emergencia", "Salida", isBlankActive, onDismiss, destructive = true)
            }
        }
    }
}

@Composable
private fun SettingsRow(
    label: String,
    value: String,
    isBlankActive: Boolean,
    onClick: () -> Unit,
    destructive: Boolean = false
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(44.dp)
            .clickable(onClick = onClick),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        val color = when {
            destructive -> Color(0xFFFF5C5C)
            else -> foregroundFor(isBlankActive)
        }
        Text(text = label, style = MaterialTheme.typography.bodyLarge, color = color)
        Text(text = value, style = MaterialTheme.typography.bodyLarge, color = color.copy(alpha = 0.82f))
    }
}

@Composable
private fun SettingsDivider(isBlankActive: Boolean) {
    HorizontalDivider(color = if (isBlankActive) Color.White.copy(alpha = 0.12f) else BlankLine)
}

private fun foregroundFor(isBlankActive: Boolean): Color {
    return if (isBlankActive) Color.White else BlankOnSurface
}

private fun elapsedText(sinceMillis: Long, nowMillis: Long): String {
    val elapsed = ((nowMillis - sinceMillis).coerceAtLeast(0L) / 1000L).toInt()
    val hours = elapsed / 3600
    val minutes = (elapsed % 3600) / 60
    val seconds = elapsed % 60
    return String.format(Locale.US, "%02d:%02d:%02d", hours, minutes, seconds)
}
