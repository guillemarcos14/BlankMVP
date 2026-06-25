package com.blanknfc.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.blanknfc.app.R
import com.blanknfc.app.data.SessionManager
import com.blanknfc.app.ui.theme.BlankBackground
import com.blanknfc.app.ui.theme.BlankGray
import com.blanknfc.app.ui.theme.BlankOnSurface
import com.blanknfc.app.ui.theme.BlankPanel
import com.blanknfc.app.ui.theme.BlankSurface

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RelinkNfcScreen(
    sessionManager: SessionManager,
    onBack: () -> Unit
) {
    val done by sessionManager.nfcRelinkCompleted.collectAsState()

    DisposableEffect(Unit) {
        sessionManager.startNfcRelink()
        onDispose {
            sessionManager.cancelNfcRelink()
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.relink_title)) },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = stringResource(R.string.nav_back))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = BlankBackground,
                    titleContentColor = BlankOnSurface,
                    navigationIconContentColor = BlankOnSurface
                )
            )
        }
    ) { padding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(BlankBackground)
                .padding(padding)
                .padding(24.dp)
        ) {
            Surface(color = BlankPanel, shape = RoundedCornerShape(34.dp), modifier = Modifier.fillMaxWidth()) {
                Column(modifier = Modifier.padding(24.dp)) {
                    Text(
                        text = if (done) stringResource(R.string.relink_done_title) else stringResource(R.string.relink_title),
                        style = MaterialTheme.typography.headlineMedium,
                        color = BlankOnSurface,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(modifier = Modifier.height(14.dp))
                    Text(
                        text = if (done) stringResource(R.string.relink_done_desc) else stringResource(R.string.relink_desc),
                        style = MaterialTheme.typography.bodyLarge,
                        color = BlankGray,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(modifier = Modifier.height(26.dp))
                    if (done) {
                        PrimaryButton(text = stringResource(R.string.nav_back), onClick = onBack)
                    } else {
                        Button(
                            onClick = {},
                            enabled = false,
                            shape = RoundedCornerShape(999.dp),
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(56.dp),
                            colors = ButtonDefaults.buttonColors(
                                disabledContainerColor = BlankSurface,
                                disabledContentColor = BlankGray
                            )
                        ) {
                            Text(stringResource(R.string.relink_waiting))
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun PrimaryButton(text: String, onClick: () -> Unit) {
    Button(
        onClick = onClick,
        shape = RoundedCornerShape(999.dp),
        colors = ButtonDefaults.buttonColors(containerColor = BlankOnSurface, contentColor = BlankSurface),
        modifier = Modifier
            .fillMaxWidth()
            .height(56.dp)
    ) {
        Text(text)
    }
}
