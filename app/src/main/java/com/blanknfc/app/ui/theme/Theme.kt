package com.blanknfc.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable

private val DarkColorScheme = darkColorScheme(
    primary = BlankGreen,
    secondary = BlankGray,
    background = BlankBackground,
    surface = BlankSurface,
    surfaceVariant = BlankPanel,
    onPrimary = BlankOnSurface,
    onSecondary = BlankOnSurface,
    onBackground = BlankOnSurface,
    onSurface = BlankOnSurface,
    outline = BlankLine,
    error = BlankRed
)

@Composable
fun BlankTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DarkColorScheme,
        typography = Typography,
        content = content
    )
}
