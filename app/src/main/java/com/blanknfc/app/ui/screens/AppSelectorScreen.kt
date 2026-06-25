package com.blanknfc.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.blanknfc.app.R
import com.blanknfc.app.data.SessionManager
import com.blanknfc.app.ui.theme.BlankBackground
import com.blanknfc.app.ui.theme.BlankOnSurface
import com.blanknfc.app.ui.theme.BlankSurface
import com.blanknfc.app.util.PackageHelper

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AppSelectorScreen(
    sessionManager: SessionManager,
    onBack: () -> Unit
) {
    val context = LocalContext.current
    val blockedPackages by sessionManager.blockedPackages.collectAsState()
    var selectedPackages by remember { mutableStateOf(blockedPackages) }

    val allApps = remember { PackageHelper.getInstalledApps(context) }

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
                    containerColor = BlankBackground,
                    titleContentColor = BlankOnSurface,
                    navigationIconContentColor = BlankOnSurface,
                    actionIconContentColor = BlankOnSurface
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
                    shape = RoundedCornerShape(999.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp)
                        .height(56.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = BlankOnSurface,
                        contentColor = BlankSurface
                    )
                ) {
                    Text(stringResource(R.string.app_selector_save))
                }
            }
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(BlankBackground)
                .padding(padding)
        ) {
            AppPickerContent(
                apps = allApps,
                selected = selectedPackages,
                onSelectedChange = { selectedPackages = it },
                modifier = Modifier
                    .fillMaxWidth()
                    .weight(1f)
                    .padding(horizontal = 16.dp, vertical = 8.dp)
            )
        }
    }
}
