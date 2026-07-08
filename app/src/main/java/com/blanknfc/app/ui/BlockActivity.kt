package com.blanknfc.app.ui

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.lifecycle.lifecycleScope
import com.blanknfc.app.BlankApp
import com.blanknfc.app.R
import com.blanknfc.app.ui.theme.BlankTheme
import kotlinx.coroutines.launch

class BlockActivity : ComponentActivity() {

    companion object {
        const val EXTRA_BLOCKED_PACKAGE = "blocked_package"
    }

    private var emergencyUnlocked = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }

        val sessionManager = BlankApp.get(this).container.sessionManager
        lifecycleScope.launch {
            sessionManager.isBlankActive.collect { isBlankActive ->
                if (!isBlankActive && !emergencyUnlocked) finish()
            }
        }

        setContent {
            BlankTheme {
                BlockScreen(
                    onEmergencyUnlock = {
                        emergencyUnlocked = true
                        sessionManager.deactivateForEmergency()
                    }
                )
            }
        }
    }

    @SuppressLint("MissingSuperCall")
    @Deprecated("Use OnBackPressedDispatcher")
    override fun onBackPressed() {
        // Stay on the blocking screen until the paired NFC tag ends the session.
    }
}

@Composable
private fun BlockScreen(onEmergencyUnlock: () -> Unit) {
    val context = LocalContext.current
    var emergencyMode by remember { mutableStateOf(false) }
    var emergencyDone by remember { mutableStateOf(false) }
    var typedPhrase by remember { mutableStateOf("") }
    val requiredPhrase = stringResource(R.string.emergency_phrase)

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = 24.dp, vertical = 42.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            if (emergencyDone) {
                Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
                    Text(
                        text = stringResource(R.string.emergency_done),
                        style = MaterialTheme.typography.headlineLarge,
                        color = Color.White,
                        textAlign = TextAlign.Center
                    )
                }
                return@Column
            }

            Box(modifier = Modifier.weight(1f), contentAlignment = Alignment.Center) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.Center
                ) {
                    Text(
                        text = if (emergencyMode)
                            "Escribe la frase completa."
                        else
                            stringResource(R.string.block_title),
                        style = MaterialTheme.typography.displayLarge,
                        color = Color.White,
                        textAlign = TextAlign.Center
                    )
                    Spacer(modifier = Modifier.height(18.dp))
                    Text(
                        text = if (emergencyMode)
                            stringResource(R.string.emergency_desc)
                        else
                            "Estás protegiendo el tiempo que querías recuperar.",
                        style = MaterialTheme.typography.bodyLarge,
                        color = Color.White.copy(alpha = 0.72f),
                        textAlign = TextAlign.Center
                    )
                    if (emergencyMode) {
                        Spacer(modifier = Modifier.height(24.dp))
                        Text(
                            text = requiredPhrase,
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color.White.copy(alpha = 0.72f),
                            textAlign = TextAlign.Center
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        OutlinedTextField(
                            value = typedPhrase,
                            onValueChange = { typedPhrase = it },
                            label = { Text(stringResource(R.string.emergency_phrase_label)) },
                            singleLine = false,
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedTextColor = Color.White,
                                unfocusedTextColor = Color.White,
                                focusedBorderColor = Color.White,
                                unfocusedBorderColor = Color.White.copy(alpha = 0.34f),
                                focusedLabelColor = Color.White,
                                unfocusedLabelColor = Color.White.copy(alpha = 0.64f)
                            ),
                            modifier = Modifier.fillMaxWidth()
                        )
                    }
                }
            }

            if (!emergencyMode) {
                TextButton(
                    onClick = {
                        val intent = Intent(Intent.ACTION_MAIN).apply {
                            addCategory(Intent.CATEGORY_HOME)
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK
                        }
                        context.startActivity(intent)
                        (context as? Activity)?.finish()
                    }
                ) {
                    Text("Volver al inicio", color = Color.White.copy(alpha = 0.64f))
                }
            } else {
                PrimaryBlockButton(
                    text = stringResource(R.string.emergency_unlock),
                    enabled = typedPhrase.trim() == requiredPhrase,
                    onClick = {
                        emergencyDone = true
                        onEmergencyUnlock()
                    }
                )
                TextButton(onClick = { emergencyMode = false }) {
                    Text(stringResource(R.string.nav_back), color = Color.White.copy(alpha = 0.64f))
                }
            }
        }
    }
}

@Composable
private fun PrimaryBlockButton(
    text: String,
    enabled: Boolean = true,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        shape = RoundedCornerShape(999.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = Color.White,
            contentColor = Color.Black,
            disabledContainerColor = Color.White.copy(alpha = 0.18f),
            disabledContentColor = Color.White.copy(alpha = 0.42f)
        ),
        modifier = Modifier
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
