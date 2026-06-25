package com.blanknfc.app.ui.screens

import android.content.pm.ApplicationInfo
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Checkbox
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.core.graphics.drawable.toBitmap
import com.blanknfc.app.ui.theme.BlankGray
import com.blanknfc.app.ui.theme.BlankOnSurface
import com.blanknfc.app.ui.theme.BlankPanel
import com.blanknfc.app.util.AppInfo

private enum class AppPickerCategory(val label: String) {
    ALL("Todas"),
    SOCIAL("Redes"),
    VIDEO("Vídeo"),
    GAMES("Juegos"),
    MESSAGING("Mensajes")
}

private val SocialPackages = listOf(
    "instagram",
    "tiktok",
    "facebook",
    "snapchat",
    "twitter",
    "x",
    "reddit",
    "pinterest",
    "threads",
    "bereal",
    "linkedin"
)

private val VideoPackages = listOf(
    "youtube",
    "netflix",
    "twitch",
    "primevideo",
    "disney",
    "hbo",
    "max",
    "crunchyroll",
    "vimeo"
)

private val MessagingPackages = listOf(
    "whatsapp",
    "telegram",
    "messenger",
    "discord",
    "slack",
    "signal",
    "snapchat",
    "teams"
)

@Composable
internal fun AppPickerContent(
    apps: List<AppInfo>,
    selected: Set<String>,
    onSelectedChange: (Set<String>) -> Unit,
    modifier: Modifier = Modifier,
    listMaxHeight: Dp? = null,
    rowColor: Color = Color.White.copy(alpha = 0.66f)
) {
    var searchQuery by remember { mutableStateOf("") }
    var category by remember { mutableStateOf(AppPickerCategory.ALL) }

    val commonDistractingPackages = remember(apps) {
        apps.filter(::isCommonDistraction).map { it.packageName }.toSet()
    }
    val filteredApps = remember(apps, searchQuery, category) {
        apps.filter { app ->
            val matchesSearch = searchQuery.isBlank() ||
                app.label.contains(searchQuery, ignoreCase = true) ||
                app.packageName.contains(searchQuery, ignoreCase = true)
            matchesSearch && matchesCategory(app, category)
        }
    }

    Column(modifier = modifier) {
        OutlinedTextField(
            value = searchQuery,
            onValueChange = { searchQuery = it },
            placeholder = { Text("Buscar apps...") },
            leadingIcon = {
                Icon(Icons.Default.Search, contentDescription = null)
            },
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(22.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = BlankOnSurface,
                unfocusedBorderColor = BlankGray.copy(alpha = 0.3f),
                focusedContainerColor = BlankPanel,
                unfocusedContainerColor = BlankPanel
            ),
            singleLine = true
        )

        Spacer(modifier = Modifier.height(10.dp))

        LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            items(AppPickerCategory.entries.toList(), key = { it.name }) { item ->
                CategoryPill(
                    label = item.label,
                    selected = category == item,
                    onClick = { category = item }
                )
            }
        }

        Spacer(modifier = Modifier.height(10.dp))

        OutlinedButton(
            onClick = {
                onSelectedChange(selected + commonDistractingPackages)
                category = AppPickerCategory.ALL
            },
            enabled = commonDistractingPackages.isNotEmpty(),
            shape = RoundedCornerShape(999.dp),
            colors = ButtonDefaults.outlinedButtonColors(contentColor = BlankOnSurface),
            modifier = Modifier.fillMaxWidth()
        ) {
            Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(18.dp))
            Spacer(modifier = Modifier.width(8.dp))
            Text("Seleccionar distracciones comunes")
        }

        Spacer(modifier = Modifier.height(12.dp))

        val listModifier = if (listMaxHeight != null) {
            Modifier.fillMaxWidth().heightIn(max = listMaxHeight)
        } else {
            Modifier.fillMaxWidth().weight(1f)
        }
        LazyColumn(
            modifier = listModifier,
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            items(filteredApps, key = { it.packageName }) { app ->
                AppPickerRow(
                    app = app,
                    checked = app.packageName in selected,
                    rowColor = rowColor,
                    onToggle = { checked ->
                        onSelectedChange(if (checked) selected + app.packageName else selected - app.packageName)
                    }
                )
            }
        }
    }
}

@Composable
private fun CategoryPill(label: String, selected: Boolean, onClick: () -> Unit) {
    val background = if (selected) BlankOnSurface else Color.White.copy(alpha = 0.66f)
    val content = if (selected) Color.White else BlankOnSurface
    Surface(
        color = background,
        shape = RoundedCornerShape(999.dp),
        modifier = Modifier.height(38.dp),
        onClick = onClick
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            if (selected) {
                Icon(Icons.Default.Check, contentDescription = null, modifier = Modifier.size(15.dp), tint = content)
                Spacer(modifier = Modifier.width(6.dp))
            }
            Text(text = label, color = content, style = MaterialTheme.typography.labelLarge)
        }
    }
}

@Composable
private fun AppPickerRow(
    app: AppInfo,
    checked: Boolean,
    rowColor: Color,
    onToggle: (Boolean) -> Unit
) {
    Surface(
        color = rowColor,
        shape = RoundedCornerShape(18.dp),
        modifier = Modifier.clickable { onToggle(!checked) }
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 14.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            val bitmap = remember(app.icon) {
                app.icon.toBitmap(48, 48).asImageBitmap()
            }
            Image(
                bitmap = bitmap,
                contentDescription = app.label,
                modifier = Modifier.size(36.dp)
            )
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(text = app.label, color = BlankOnSurface, style = MaterialTheme.typography.bodyLarge)
                Text(
                    text = categoryLabel(app),
                    color = BlankOnSurface.copy(alpha = 0.58f),
                    style = MaterialTheme.typography.bodySmall.copy(fontWeight = FontWeight.Medium)
                )
            }
            Checkbox(checked = checked, onCheckedChange = onToggle)
        }
    }
}

private fun matchesCategory(app: AppInfo, category: AppPickerCategory): Boolean {
    return when (category) {
        AppPickerCategory.ALL -> true
        AppPickerCategory.SOCIAL -> matchesAny(app, SocialPackages)
        AppPickerCategory.VIDEO -> matchesAny(app, VideoPackages)
        AppPickerCategory.GAMES -> app.category == ApplicationInfo.CATEGORY_GAME || matchesAny(app, listOf("game"))
        AppPickerCategory.MESSAGING -> matchesAny(app, MessagingPackages)
    }
}

private fun isCommonDistraction(app: AppInfo): Boolean {
    return matchesCategory(app, AppPickerCategory.SOCIAL) ||
        matchesCategory(app, AppPickerCategory.VIDEO) ||
        matchesCategory(app, AppPickerCategory.GAMES)
}

private fun matchesAny(app: AppInfo, needles: List<String>): Boolean {
    val haystack = "${app.packageName} ${app.label}".lowercase()
    return needles.any { needle -> haystack.contains(needle) }
}

private fun categoryLabel(app: AppInfo): String {
    return when {
        matchesCategory(app, AppPickerCategory.SOCIAL) -> "Red social"
        matchesCategory(app, AppPickerCategory.VIDEO) -> "Vídeo"
        matchesCategory(app, AppPickerCategory.GAMES) -> "Juego"
        matchesCategory(app, AppPickerCategory.MESSAGING) -> "Mensajería"
        else -> "App"
    }
}
