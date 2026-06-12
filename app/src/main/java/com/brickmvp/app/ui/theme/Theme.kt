package com.brickmvp.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

private val DarkColorScheme = darkColorScheme(
    primary = BrickRed,
    secondary = BrickGreen,
    background = BrickBackground,
    surface = BrickSurface,
    onPrimary = BrickOnSurface,
    onSecondary = BrickOnSurface,
    onBackground = BrickOnSurface,
    onSurface = BrickOnSurface
)

@Composable
fun BrickTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        typography = Typography,
        content = content
    )
}
