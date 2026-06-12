package com.brickmvp.app.ui.screens

import android.graphics.drawable.Drawable
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.graphics.drawable.toBitmap
import com.brickmvp.app.R
import com.brickmvp.app.data.SessionManager
import com.brickmvp.app.ui.theme.BrickGreen
import com.brickmvp.app.util.AppInfo
import com.brickmvp.app.util.PackageHelper

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppSelectorScreen(
    sessionManager: SessionManager,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val blockedPackages by sessionManager.blockedPackages.collectAsState()
    var selectedPackages by remember { mutableStateOf(blockedPackages) }
    var searchQuery by remember { mutableStateOf("") }

    val allApps = remember { PackageHelper.getInstalledApps(context) }
    val filteredApps = remember(searchQuery) {
        if (searchQuery.isBlank()) allApps
        else allApps.filter { it.label.contains(searchQuery, ignoreCase = true) }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = {
                    Text(stringResource(R.string.app_selector_title))
                },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    Text(
                        text = stringResource(R.string.app_selector_selected, selectedPackages.size),
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(end = 8.dp)
                    )
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background
                )
            )
        },
        bottomBar = {
            Surface(
                modifier = Modifier.fillMaxWidth(),
                color = MaterialTheme.colorScheme.surface
            ) {
                Button(
                    onClick = {
                        sessionManager.setBlockedPackages(selectedPackages)
                        onBack()
                    },
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = BrickGreen)
                ) {
                    Text(stringResource(R.string.app_selector_save))
                }
            }
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(padding)
        ) {
            // Search bar
            OutlinedTextField(
                value = searchQuery,
                onValueChange = { searchQuery = it },
                placeholder = { Text(stringResource(R.string.app_selector_search)) },
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                singleLine = true
            )

            LazyColumn {
                items(filteredApps, key = { it.packageName }) { appInfo ->
                    AppItem(
                        appInfo = appInfo,
                        isSelected = selectedPackages.contains(appInfo.packageName),
                        onToggle = { selected ->
                            selectedPackages = if (selected) {
                                selectedPackages + appInfo.packageName
                            } else {
                                selectedPackages - appInfo.packageName
                            }
                        }
                    )
                }
            }
        }
    }
}

@Composable
private fun AppItem(
    appInfo: AppInfo,
    isSelected: Boolean,
    onToggle: (Boolean) -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        val bitmap = remember(appInfo.icon) {
            appInfo.icon.toBitmap(48, 48).asImageBitmap()
        }
        Image(
            bitmap = bitmap,
            contentDescription = appInfo.label,
            modifier = Modifier.size(40.dp)
        )

        Spacer(modifier = Modifier.width(16.dp))

        Text(
            text = appInfo.label,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier.weight(1f)
        )

        Checkbox(
            checked = isSelected,
            onCheckedChange = onToggle
        )
    }
}
