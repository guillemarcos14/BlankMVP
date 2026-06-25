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
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.blanknfc.app.R
import com.blanknfc.app.ui.theme.BlankBackground
import com.blanknfc.app.ui.theme.BlankGray
import com.blanknfc.app.ui.theme.BlankOnSurface
import com.blanknfc.app.ui.theme.BlankPanel
import com.blanknfc.app.ui.theme.BlankSurface

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ForgetNfcScreen(
    onConfirm: () -> Unit,
    onBack: () -> Unit
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.home_forget_tag)) },
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
                        text = stringResource(R.string.home_forget_tag),
                        style = MaterialTheme.typography.headlineMedium,
                        color = BlankOnSurface,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.fillMaxWidth()
                    )
                    Spacer(modifier = Modifier.height(14.dp))
                    Text(
                        text = "Esto borrará la etiqueta NFC vinculada, desactivará Blank y reiniciará el onboarding. Tus apps bloqueadas se mantienen hasta que las cambies.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = BlankGray,
                        textAlign = TextAlign.Center
                    )
                    Spacer(modifier = Modifier.height(26.dp))
                    Button(
                        onClick = onConfirm,
                        shape = RoundedCornerShape(999.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = BlankOnSurface, contentColor = BlankSurface),
                        modifier = Modifier.fillMaxWidth().height(56.dp)
                    ) {
                        Text("Confirmar reset")
                    }
                    Spacer(modifier = Modifier.height(12.dp))
                    OutlinedButton(onClick = onBack, shape = RoundedCornerShape(999.dp), modifier = Modifier.fillMaxWidth().height(56.dp)) {
                        Text(stringResource(R.string.nav_back))
                    }
                }
            }
        }
    }
}
