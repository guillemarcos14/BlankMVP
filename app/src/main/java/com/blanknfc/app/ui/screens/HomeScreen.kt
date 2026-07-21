package com.blanknfc.app.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material3.OutlinedButton
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
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.blanknfc.app.data.SessionManager
import com.blanknfc.app.ui.theme.BlankBackground
import com.blanknfc.app.ui.theme.BlankGray
import com.blanknfc.app.ui.theme.BlankGreen
import com.blanknfc.app.ui.theme.BlankOnSurface
import com.blanknfc.app.ui.theme.BlankRed
import com.blanknfc.app.ui.theme.BlankRedDark
import com.blanknfc.app.ui.theme.BlankSurface
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

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
    var message by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(Unit) {
        while (true) {
            now = System.currentTimeMillis()
            delay(1000)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(if (isBlankActive) BlankRedDark else BlankBackground)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Spacer(modifier = Modifier.weight(1f))

        Text(
            text = if (isBlankActive) "BLANKED" else "UNBLANKED",
            color = BlankOnSurface,
            fontSize = 46.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center
        )

        Spacer(modifier = Modifier.height(18.dp))

        Text(
            text = if (isBlankActive) {
                "Scan your NFC tag to deactivate Blank mode"
            } else {
                "Scan your NFC tag to activate Blank mode"
            },
            style = MaterialTheme.typography.bodyLarge,
            color = BlankGray,
            textAlign = TextAlign.Center
        )

        if (isBlankActive && blankActiveSince > 0L) {
            Spacer(modifier = Modifier.height(32.dp))
            Text(
                text = elapsedText(blankActiveSince, now),
                color = BlankOnSurface,
                fontSize = 34.sp,
                fontWeight = FontWeight.SemiBold,
                fontFamily = FontFamily.Monospace,
                textAlign = TextAlign.Center
            )
            Spacer(modifier = Modifier.height(10.dp))
            Text(
                text = "Blanked since ${timeText(blankActiveSince)}",
                style = MaterialTheme.typography.bodyMedium,
                color = BlankGray.copy(alpha = 0.7f),
                textAlign = TextAlign.Center
            )
        }

        if (blockedPackages.isNotEmpty()) {
            Spacer(modifier = Modifier.height(28.dp))
            Text(
                text = "${blockedPackages.size} selected",
                style = MaterialTheme.typography.bodyLarge,
                color = BlankGray,
                textAlign = TextAlign.Center
            )
        }

        Spacer(modifier = Modifier.height(18.dp))

        TextButton(onClick = { message = "Weekly report is not available on Android yet." }) {
            Text(
                text = "View weekly report",
                style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold),
                color = BlankGray
            )
        }

        Spacer(modifier = Modifier.height(22.dp))

        Button(
            onClick = {
                message = if (isBlankActive) {
                    "Hold your paired Blank tag near this phone."
                } else {
                    when (sessionManager.activateBlank()) {
                        SessionManager.NfcResult.BRICKED -> "Blank mode activated."
                        SessionManager.NfcResult.NO_APPS_SELECTED -> "Select at least one app to block first."
                        else -> "Hold your paired Blank tag near this phone."
                    }
                }
            },
            shape = RoundedCornerShape(8.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = if (isBlankActive) BlankRed else BlankGreen,
                contentColor = Color.White
            ),
            modifier = Modifier
                .fillMaxWidth()
                .height(54.dp)
        ) {
            Text("Scan NFC Tag", style = MaterialTheme.typography.labelLarge)
        }

        if (!isBlankActive) {
            Spacer(modifier = Modifier.height(12.dp))
            OutlinedButton(
                onClick = onEditApps,
                shape = RoundedCornerShape(8.dp),
                colors = ButtonDefaults.outlinedButtonColors(contentColor = BlankOnSurface),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(54.dp)
            ) {
                Text("Edit Apps", style = MaterialTheme.typography.labelLarge)
            }

            TextButton(onClick = onRelinkTag) {
                Text("Pair New NFC Tag", color = BlankGray)
            }

            TextButton(onClick = onForgetTag) {
                Text("Forget NFC Tag", color = BlankGray)
            }
        }

        if (message != null) {
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = message.orEmpty(),
                style = MaterialTheme.typography.bodyMedium,
                color = BlankGray,
                textAlign = TextAlign.Center
            )
        }

        Spacer(modifier = Modifier.weight(1f))
    }
}

private fun elapsedText(sinceMillis: Long, nowMillis: Long): String {
    val elapsed = ((nowMillis - sinceMillis).coerceAtLeast(0L) / 1000L).toInt()
    val hours = elapsed / 3600
    val minutes = (elapsed % 3600) / 60
    val seconds = elapsed % 60
    return String.format(Locale.US, "%02d:%02d:%02d", hours, minutes, seconds)
}

private fun timeText(millis: Long): String {
    return SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(millis))
}
