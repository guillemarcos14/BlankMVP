package com.blanknfc.app.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable

private val LightColorScheme = lightColorScheme(
    primary = BlankOnSurface,
    secondary = BlankGray,
    background = BlankBackground,
    surface = BlankSurface,
    surfaceVariant = BlankPanel,
    onPrimary = BlankSurface,
    onSecondary = BlankOnSurface,
    onBackground = BlankOnSurface,
    onSurface = BlankOnSurface,
    outline = BlankLine
)

@Composable
fun BlankTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = LightColorScheme,
        typography = Typography,
        content = content
    )
}
